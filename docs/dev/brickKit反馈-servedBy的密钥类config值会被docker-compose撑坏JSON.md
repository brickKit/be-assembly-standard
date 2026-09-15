# brickKit 反馈：`BRICKKIT_SERVED_MEMBERS_CONFIG` 承载密钥类 config 值时，会被 docker compose 自己的 `${VAR}` 全文本替换撑坏 JSON

> **这份文档是一次性的**：只针对这一个具体问题，看完可以直接删掉。完整
> 复现过程、两次尝试的修补方向（第一次治标不治本）、最终在我们自己这边
> 的兜底实现，都已经同步记在了我们自己 `docs/plans/04b-验证记录.md` 的
> "Task 0.6"一节，这里只摘要问题本身，方便你们判断。

## 先说结论

`BRICKKIT_SERVED_MEMBERS_CONFIG`（v0.4.2 新增，感谢这么快就做出来）在
**生成的那一刻是完全合法的 JSON**——但如果某个 servedBy 成员的某个
config 值在 `brickkit.yaml` 里是 `${VAR}` 占位符（最常见的场景：秘钥类
配置项，真实值不该提交进 git，只能靠占位符 + 真机注入），而这个变量在
`.env`/调用环境里真的有值、且这个值带着换行符（PEM 私钥是最典型的例
子），**docker compose 自己对整份生成好的 `docker-compose.yaml` 做全
文本 `${VAR}` 替换时，会直接把这个占位符替换成真实值，不管它是不是恰好
嵌在 `BRICKKIT_SERVED_MEMBERS_CONFIG` 这个 env 变量的 JSON 字符串内部**
——真实密钥的原始换行符替换进去，直接把这份 JSON 从中间断开。

症状：外壳容器 crash-loop，日志是
`解析 BRICKKIT_SERVED_MEMBERS_CONFIG 失败: invalid character '\n' in
string literal`（外壳自己用 `encoding/json`/`json.loads` 解析这个变量
时报错）。

这不是我们这边的用法有问题——**任何 brickKit 用户，只要有一个 servedBy
成员的某个 config 项是密钥类、且真实值带有换行符/双引号/反斜杠这类需要
JSON 转义的字符，都会 100% 踩到这个问题**，不是"可能"，是必然（PEM 私钥
是最常见的真实场景，几乎每个接第三方 OIDC/OAuth 的组件都会有这类配置
项）。

## 怎么复现的

1. 一个 servedBy 成员（比如我们的 `infra/iam-casdoor`）在 `brickkit.yaml`
   里声明 `config: { appTokenSigningKeyPem: "${APP_TOKEN_SIGNING_KEY_PEM}" }`。
2. `.env` 里 `APP_TOKEN_SIGNING_KEY_PEM` 是一份真实的多行 PEM 私钥（标准
   `-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----` 格式）。
3. `brickkit up --dry-run` 生成的 `docker-compose.yaml`，此时
   `BRICKKIT_SERVED_MEMBERS_CONFIG` 那一行还是合法的——占位符字符串
   `${APP_TOKEN_SIGNING_KEY_PEM}` 本身没有特殊字符，`json.Marshal`
   编码完全正常（`cat .brickkit/generated/docker-compose.yaml | grep
   BRICKKIT_SERVED_MEMBERS_CONFIG` 能看到这一点）。
4. `brickkit up`（不带 `--dry-run`，真的调 `docker compose ... up`）：
   `infra/iam-casdoor` 所在的外壳容器 crash-loop。`docker inspect` 看这个
   容器的 `BRICKKIT_SERVED_MEMBERS_CONFIG` 环境变量值，会看到它已经变成
   了断成多行的文本——`docker compose` 自己在读取 compose 文件、准备真正
   启动容器那一步，对整份文件按纯文本做了 `${VAR}` 替换，把真实 PEM 值
   拼进了这个本该是单行 JSON 的字符串里。

## 为什么这是 `BRICKKIT_SERVED_MEMBERS_CONFIG` 自己的问题，不是我们的用法问题

- brickKit 生成这份 JSON 时，`encoding/json` 保证输出合法（不会有未转义
  的控制字符）——**这一步本身没有问题**。
- 问题出在 brickKit 把"是否展开 `${VAR}`"这件事完全交给了 docker
  compose（生成阶段留着占位符，运行阶段才展开）——这个决定对**绝大多数**
  config 值都是对的（一个普通的顶层 `KEY=${VAR}` 标量赋值，docker
  compose 展开完全没问题），但对"这个占位符恰好是另一个 env 变量整段
  JSON 文本里的一个子串"这种情况，docker compose 的展开是**纯文本、无
  结构感知**的——它不知道也不可能知道自己正在往一段 JSON 字符串内部注入
  内容，更不知道往里面注入的值需要先做 JSON 转义才安全。
- 换句话说：**只要 servedBy 成员的 config 里还留着未展开的 `${VAR}`
  占位符，`BRICKKIT_SERVED_MEMBERS_CONFIG` 这个机制就没有真正做到"外壳
  拿到的是每个成员完整、可靠解析的 config"这个承诺**——密钥类的值，
  恰恰是最常见的、必须用 `${VAR}` 占位符表达的一类。

## 两个可能的修复方向（我们没有偏好，看你们判断）

- **方向一**：brickKit 自己在计算 `BRICKKIT_SERVED_MEMBERS_CONFIG` 这个
  JSON 之前，先对每个成员的 config 值做一次 `${VAR}` 展开（复用
  `internal/config/parse.go` 已有的展开逻辑），展开后再交给
  `encoding/json` 编码——`encoding/json` 会自动把真实值里的换行符/引号/
  反斜杠正确转义成 `\n`/`\"`/`\\`，docker compose 后续再对整份文件做
  `${VAR}` 替换时，因为这个 env 变量里已经不存在任何 `${VAR}` 语法了，
  不会再对它做二次替换，JSON 从生成到最终进容器全程保持合法。
- **方向二**：如果方向一涉及的改动面比预期大（比如展开时机牵扯到密钥
  管理的其它假设），至少在文档里明确写清楚"`BRICKKIT_SERVED_MEMBERS_
  CONFIG` 不保证密钥类 `${VAR}` 占位符的安全性，这类值需要外壳实现者
  自己在 JSON 解析前做转义修复"——我们自己这边的临时兜底实现是外壳
  启动器在 `json.Unmarshal`/`json.loads` 之前，跑一个只关心"现在在不在
  JSON 字符串里面"的最小状态机（遇到未转义的 `"` 切换状态，`\` 时跳过
  下一个字符防止转义序列被误判），把字符串**内部**的裸控制字符转义回
  `\n`/`\r`/`\t`——合法 JSON 字符串内部本来就不可能出现裸控制字符，见到
  了就一定是 docker compose 那次替换造成的，可以安全地统一转义、不需要
  先判断"这个 key 是不是密钥"。如果你们倾向于方向二，这段实现或许可以
  直接收进 `shell-implementers-guide` 文档，省得每个外壳实现者各自踩一遍
  这个坑。

我们自己这边已经按方向二的思路在两个外壳仓库（`be-shell-go`/
`be-shell-python`）里落地了兜底实现——这终归是下游兜底，不是修复，我们
更倾向于等你们那边看完再决定怎么处理。
