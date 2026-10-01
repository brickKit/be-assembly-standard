# Task 8 外壳骨架（零成员）记录（含 V-03）

## 目标

1. 用 `brickkit new --shell` 生成 4 个外壳（`be/go-core`、`be/go-infra`、`be/go-backoffice`、`be/py-render`），改写成按 v1 写法的项目代码，零成员。
2. 先验证 `shell.members: []` 是否合法；合法则 `brickkit add` → `brickkit build` → `brickkit up`，4 个外壳零成员 healthy、`/healthz` 200。
3. V-03：在"一个外壳一个目录一个镜像"的标准布局下，`brickkit build` 是否顺利。
4. 退役旧的 `shells/go`、`shells/python` 两个 submodule。

## 环境

- brickKit CLI v1.0.1（`brickkit --version`：`BrickKit CLI v1.0.1`）
- go1.26.0 linux/amd64（go.mod 写 `go 1.25.11`，镜像用 `golang:1.25-alpine`）；本机 Python 3.14，验证 Python 外壳用 `uv venv -p 3.12`
- be-sdk-go v0.3.0、be-sdk-python v0.4.1（brief 写 v0.4.0，按派发说明用 v0.4.1）
- 基础资源：`be-postgres`、`be-nats`、`be-rustfs`、`be-traefik`、`be-casdoor` 已在运行（`Up 9 hours (healthy)`），没有再跑 `make up`
- 数据库里外壳登录角色已存在（`docker exec be-postgres psql -U postgres -d brickkit_db -tAc "select rolname from pg_roles where rolname like 'shell_%'"`）：`shell_py_render`、`shell_py_brain`、`shell_go_backoffice`、`shell_go_infra`、`shell_go_core`；`.env` 里有 `SHELL_GO_CORE_PASSWORD` 等 5 项

## 步骤

### 1. 查外壳端口：`grep -E "_shell-" registry/ports.tsv`

```
_shell-go-core	shell/go-core	8090	-	standalone	外壳自己的健康检查端口，不是任何成员的端口；成员的地址走 servedBy 网络别名，不走这个端口
_shell-go-backoffice	shell/go-backoffice	8116	-	standalone	同上
_shell-go-infra	shell/go-infra	8224	-	standalone	同上
_shell-py-render	shell/py-render	8402	-	standalone	同上
```

按裁定 R22 原地改了这 4 行（ID 列 `shell/<name>` → `be/<name>`，备注换成 v1 说法），分组标题行里的 servedBy 说法也一并改掉。改后：

```
# ===== 外壳自身（shell/be/<name>/ 下的 brickKit 外壳，项目代码；见 registry/README.md 规矩3b）=====
_shell-go-core	be/go-core	8090	-	standalone	外壳自己的 /healthz 端口（deployment.port），不是任何成员的端口；成员仍用自己的服务名和端口寻址，brickKit 把成员服务名设成外壳服务的网络别名
_shell-go-backoffice	be/go-backoffice	8116	-	standalone	同上
_shell-go-infra	be/go-infra	8224	-	standalone	同上
_shell-py-render	be/py-render	8402	-	standalone	同上
```

`make registry-check`：

```
✓ 端口册与 schema 册自洽（62 个组件 + 带外容器/外壳自身，端口两两不重复）
```

### 2. 生成骨架：`for n in go-core go-infra go-backoffice py-render; do brickkit new be/$n --shell; done`

```
✅ Component skeleton generated: be/go-core
   📄 shell/be/go-core/component.yaml
   📄 shell/be/go-core/BRICKKIT.md
   📄 shell/be/go-core/AGENTS.md
   📄 shell/be/go-core/CLAUDE.md
   📄 shell/be/go-core/README.md

Next steps:
  Fill in the TODOs in component.yaml and the docs (brickkit lint lists every one left)
  brickkit add --local     add it to brickkit.yaml (if the local install source can scan it)
  brickkit up --dry-run    check that it passes validation
```

（另外三个输出相同，只是名字不同。）生成的 `component.yaml` 里 `shell.members` 是一个占位成员 `example/member@0.1.0`，版本 `0.1.0`，端口 `8080`。

### 3. 改成零成员后验证 `shell.members: []`

按 brief Step 4 写 `shell/be/go-core/component.yaml`（`shell.members: []`），在外壳目录里跑 `brickkit lint`（向上找到项目的 `brickkit.yaml`，按项目场景检查）。与外壳相关的输出原文：

```
✅ ../go-backoffice/component.yaml
❌ Error: component.yaml failed validation
   File: component.yaml
   shell.members: a shell must list at least one component compiled into it
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
✅ ../go-infra/component.yaml
✅ ../py-render/component.yaml
```

（此时另外三个还是骨架里的占位成员，所以是 ✅。）其余 ❌ 全是 14 个旧组件 `component.yaml` 的 `dependencies.resources: unknown field`，属 06b 迁移范围。

再试 `brickkit add be/go-core --yes`，完整输出：

```
🔎 No version given for be/go-core; the latest is 1.0.0 (install source local-shells)
❌ Error: component.yaml failed validation
   File: local-shells (local): be/go-core@1.0.0
   shell.members: a shell must list at least one component compiled into it
   Component: be/go-core@1.0.0
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
{"time":"2026-10-01T22:30:19.766008717+02:00","level":"ERROR","message":"Command failed","command":"brickkit add","elapsed_ms":1,"error_code":"MANIFEST_INVALID","error":"MANIFEST_INVALID: Error: component.yaml failed validation; File=local-shells (local): be/go-core@1.0.0; shell.members=a shell must list at least one component compiled into it; Component=be/go-core@1.0.0","exit_code":1}
exit=1
```

`git status --short brickkit.yaml deploy.yaml config/` 无输出：失败的 `add` 没有留下任何改动。

`brickkit build be/go-core`（外壳不在项目里，无法单独构建）：

```
❌ Error: be/go-core is not in the project
   Versions in brickkit.yaml: (no such component)
   Suggestion: Check the component ID and version against components in brickkit.yaml
{"time":"2026-10-01T22:30:26.536369014+02:00","level":"ERROR","message":"Command failed","command":"brickkit build","elapsed_ms":0,"error_code":"COMPONENT_NOT_FOUND","error":"COMPONENT_NOT_FOUND: Error: be/go-core is not in the project; Versions in brickkit.yaml=(no such component)","exit_code":1}
exit=1
```

`brickkit up --dry-run`（确认本地源里放一份不合法的外壳清单不会把整个项目弄坏，其他人的命令照常可用）：

```
📋 The current project has no components
   Add all the components under components/ with brickkit add --local
   Or add one from an install source with brickkit add <component-id>
exit=0
```

结论：空列表被拒。按 brief 的条件分支，Task 8 退化为"生成骨架、能编译/能导入、不加入 `brickkit.yaml`"，跳过 Step 8 的 `add`/`build`/`up`，Step 9 退役 submodule 照做。

### 4. Go 外壳编译：`go mod tidy && go build ./...`（三个外壳各一次）

```
go: downloading github.com/brickKit/be-sdk-go v0.3.0
go-core build ok
go-backoffice build ok
go-infra build ok
```

`go.mod` 只直接 require `github.com/brickKit/be-sdk-go v0.3.0`，其余全是 `// indirect`。注意：单包模块里 `go build ./...` 会在目录里写出二进制（`go-core/go-core` 等），已删除；AGENTS.md 里写的是 `go build -o /dev/null ./...`，复跑：

```
go-core ok
go-infra ok
go-backoffice ok
```

### 5. Python 外壳导入

```bash
uv venv -q -p 3.12 <scratch>/venv
VIRTUAL_ENV=<scratch>/venv uv pip install -q .
<scratch>/venv/bin/python -c "import main, besdk.shell_runner as s; print('import ok', s.main)"
```

```
import ok <function main at 0x7e2d87253f60>
```

`pyproject.toml` 在 brief 的基础上补了 `[build-system]` 和 `[tool.setuptools] py-modules = ["main"]`，否则 `pip install .` 打包什么不明确；`besdk` 用 `@v0.4.1`。

### 6. 文档 lint

先在 scratch 里复制一份外壳目录（上面没有 `brickkit.yaml`，按"组件仓库"场景检查），`brickkit lint --strict`。第一轮（4 个外壳相同）：

```
⚠️ the link ../../../docs/decisions/0022-shells-are-project-code.md leaves the component directory: projects that use the component do not have that file
   File: AGENTS.md
   Line: 38
⚠️ the link ../../../docs/decisions/0022-shells-are-project-code.zh.md leaves the component directory: projects that use the component do not have that file
   File: AGENTS.zh.md
   Line: 38
⚠️ the "Purpose" (组件定位) section is missing
   File: BRICKKIT.zh.md
⚠️ the "Dependencies" (依赖说明) section is missing
   File: BRICKKIT.zh.md
⚠️ the "Configuration" (配置指南) section is missing
   File: BRICKKIT.zh.md
⚠️ the "Contracts" (契约索引) section is missing
   File: BRICKKIT.zh.md
```

修正：AGENTS 里指向项目决策 0022 的相对链接改成纯文字（链接跨出组件目录会报 `DOC_LINK_NOT_PORTABLE`，连 `AGENTS.md` 也查）；`BRICKKIT.zh.md` 的小节标题必须用 brickKit 规定的中文名：组件定位 / 依赖说明 / 配置指南 / 契约索引（"部署前准备""外壳声明"这两个我自己起的名字被接受了）。第二轮（4 个外壳相同）：

```
📦 Component repository (has component.yaml, no brickkit.yaml): component.yaml and the component's docs are checked
❌ Error: component.yaml failed validation
   File: component.yaml
   shell.members: a shell must list at least one component compiled into it
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
✅ ./ (docs)

📋 Checked 2 files: 1 with errors, 0 warnings
```

清单不合法时，`configSchema` 和 `DOC_OUT_OF_STEP` 这类依赖清单内容的检查是否还跑，看不出来。于是在 scratch 副本里临时把 `members` 改成 `[demo/probe@1.0.0]` 再 lint（4 个外壳相同）：

```
✅ component.yaml
⚠️ the shell compiles in demo/probe, but "Shell declaration" does not list it
⚠️ the shell compiles in demo/probe, but "外壳声明" does not list it
❌ Error: the structure check did not pass
```

只剩占位成员必然引起的"外壳声明没列它"两条，`configSchema`（含 py-render 多出的 `SHELL_HEALTH_PORT` 及其 `description`）、必填键在文档里是否提到等检查都通过。

真实仓库里项目级 `brickkit lint --strict` 中外壳相关的行：

```
❌ Error: component.yaml failed validation
   File: shell/be/go-backoffice/component.yaml
   shell.members: a shell must list at least one component compiled into it
❌ Error: component.yaml failed validation
   File: shell/be/go-core/component.yaml
   shell.members: a shell must list at least one component compiled into it
❌ Error: component.yaml failed validation
   File: shell/be/go-infra/component.yaml
   shell.members: a shell must list at least one component compiled into it
❌ Error: component.yaml failed validation
   File: shell/be/py-render/component.yaml
   shell.members: a shell must list at least one component compiled into it
...
✅ shell/be/go-backoffice/ (docs)
✅ shell/be/go-core/ (docs)
✅ shell/be/go-infra/ (docs)
✅ shell/be/py-render/ (docs)
```

（每条 ❌ 下还有一行 `Suggestion: Full field reference: ...`，与上面相同。）`make docs-boundary` 退出码 0。

### 7. 绕开 brickkit 的零成员运行验证（docker build + docker run）

`brickkit build`/`up` 用不了，改用 docker 直接构建每个外壳目录，模拟平台零成员时给的环境，检查能否启动、`/healthz` 是否 200。

`docker build -q -t task8-probe/be-<name>:1.0.0 shell/be/<name>`：

```
=== go-core
sha256:de2401a4e1629e369d0b7405c90d29e8372b97ed63e0c76111fa6ff9287e0bfe
exit=0
=== go-infra
sha256:6c40d51cdf415ff9af6e44a38af2eda36494be94ae29a07ea5b94e212a818a2b
exit=0
=== go-backoffice
sha256:dfb3b6e56c90cd536b16f6dba202df887764c8bca36d7524692cb896f783f479
exit=0
=== py-render
sha256:8b64aeed84f1ddd5dfbece8e53b5387e3370a55fb530dfc26e93ffacaa0610b9
exit=0
```

镜像大小：3 个 Go 外壳各 58.4MB，py-render 517MB。

`docker run -d --add-host=host.docker.internal:host-gateway --env-file <scratch>/<name>.env -p 2980<i>:<端口> ...`。env 文件内容：`PG_HOST=host.docker.internal`、`PG_PORT=5432`、`PG_DATABASE=brickkit_db`、`PG_USER=shell_<name>`、`PG_PASSWORD=<取自 .env 的 SHELL_<NAME>_PASSWORD>`、`NATS_URL=nats://host.docker.internal:4222`、`OTEL_BASE_URL=`、`AUTHZ_BUNDLE_URL`/`IAM_JWKS_URL` 取 `config/vars.yaml` 的值、`BRICKKIT_SERVED_MEMBERS=`、`BRICKKIT_SERVED_MEMBERS_CONFIG=[]`；py-render 另加 `SHELL_HEALTH_PORT=8402`（模拟 configSchema 默认值被注入）。宿主机端口 29801–29804 是临时选的空闲端口，验证完即删。

宿主机 `curl` 与容器内 `wget`：

```
200 host:29801
200 host:29802
200 host:29803
200 host:29804
=== go-core: running exit=0
 <- wget in container exit=0
2026/10/01 20:38:59 ERROR Failed to refresh HTTP JWK Set from remote HTTP resource. error="failed to perform HTTP request for JWK Set refresh: Get \"http://be-go-infra-1-0-0:8200/.well-known/jwks.json\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host" url=http://be-go-infra-1-0-0:8200/.well-known/jwks.json
{"time":"2026-10-01T20:38:59.189928284Z","level":"WARN","msg":"拉取 authz bundle 失败，沿用内存里已有的旧版本","component_id":"be-go-core","error":"Get \"http://be-go-infra-1-0-0:8223/authz/bundle\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host"}
{"time":"2026-10-01T20:39:14.251718824Z","level":"WARN","msg":"拉取 authz bundle 失败，沿用内存里已有的旧版本","component_id":"be-go-core","error":"Get \"http://be-go-infra-1-0-0:8223/authz/bundle\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host"}
=== go-infra: running exit=0
 <- wget in container exit=0
2026/10/01 20:38:59 ERROR Failed to refresh HTTP JWK Set from remote HTTP resource. error="failed to perform HTTP request for JWK Set refresh: Get \"http://be-go-infra-1-0-0:8200/.well-known/jwks.json\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host" url=http://be-go-infra-1-0-0:8200/.well-known/jwks.json
{"time":"2026-10-01T20:38:59.416058524Z","level":"WARN","msg":"拉取 authz bundle 失败，沿用内存里已有的旧版本","component_id":"be-go-infra","error":"Get \"http://be-go-infra-1-0-0:8223/authz/bundle\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host"}
{"time":"2026-10-01T20:39:14.45465682Z","level":"WARN","msg":"拉取 authz bundle 失败，沿用内存里已有的旧版本","component_id":"be-go-infra","error":"Get \"http://be-go-infra-1-0-0:8223/authz/bundle\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host"}
=== go-backoffice: running exit=0
 <- wget in container exit=0
2026/10/01 20:38:59 ERROR Failed to refresh HTTP JWK Set from remote HTTP resource. error="failed to perform HTTP request for JWK Set refresh: Get \"http://be-go-infra-1-0-0:8200/.well-known/jwks.json\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host" url=http://be-go-infra-1-0-0:8200/.well-known/jwks.json
{"time":"2026-10-01T20:38:59.631969625Z","level":"WARN","msg":"拉取 authz bundle 失败，沿用内存里已有的旧版本","component_id":"be-go-backoffice","error":"Get \"http://be-go-infra-1-0-0:8223/authz/bundle\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host"}
{"time":"2026-10-01T20:39:14.642210887Z","level":"WARN","msg":"拉取 authz bundle 失败，沿用内存里已有的旧版本","component_id":"be-go-backoffice","error":"Get \"http://be-go-infra-1-0-0:8223/authz/bundle\": dial tcp: lookup be-go-infra-1-0-0 on 8.8.8.8:53: no such host"}
=== py-render: running exit=0
{"ok":true} <- wget in container exit=0
拉取 authz bundle 失败，沿用内存里已有的旧版本: [Errno -2] Name or service not known
```

（Go 的 `/healthz` 只回状态码、没有响应体，所以 `wget -O-` 前面是空的。）authz/JWKS 拉取失败是预期内的：这个临时容器不在 brickKit 网络里，`be-go-infra-1-0-0` 不存在；只打日志，不影响进程和 `/healthz`。

两个对照：

py-render 不设 `SHELL_HEALTH_PORT`（等于 configSchema 没给默认值）：

```
 8402 exit=4
{"ok":true} 18889 exit=0
```

即 be-sdk-python 的外壳 `/healthz` 不读 `deployment.port`，没有 `SHELL_HEALTH_PORT` 时落在它自己的兜底端口 18889，平台探 8402 会永远不健康。所以 py-render 的 configSchema 加了 `SHELL_HEALTH_PORT`，默认 `"8402"`。

go-core 不设 `BRICKKIT_SERVED_MEMBERS_CONFIG`：

```
{"time":"2026-10-01T20:39:29.647214218Z","level":"ERROR","msg":"外壳启动失败","component_id":"be-go-core","err":"BRICKKIT_SERVED_MEMBERS_CONFIG 未设置：这个进程看起来不是由 brickkit 作为外壳启动的"}
exit=1
```

与 SDK 的约定一致（未设置报错，`[]` 才是零成员）。验证完删除了 4 个容器、4 个镜像和含密码的 env 文件。

### 8. 退役旧 submodule

先确认两边没有未推送的东西：

```
== shells/go
f1607e8 docs: README.md 删掉指向父仓库已删除文档的失效链接
* main f1607e8 [origin/main] docs: README.md 删掉指向父仓库已删除文档的失效链接
== shells/python
2310325 fix: 外壳自己的 component.yaml 版本号追平到 v0.3.5
* main 2310325 [origin/main] fix: 外壳自己的 component.yaml 版本号追平到 v0.3.5
 f1607e8fcb74763855977bc4711fc8e70311abf3 shells/go (v0.5.9)
 231032577aee4cddf89c1449b7c03b34f7fe7431 shells/python (v0.3.5)
```

`git submodule deinit -f shells/go shells/python && git rm -q shells/go shells/python && git rm -q shells/README.md; rm -rf .git/modules/shells`：

```
warning: Submodule work tree 'shells/go' contains a .git directory. This will be replaced with a .git file by using absorbgitdirs.
Migrating git directory of 'shells/go' from
'/home/zhijie/Desktop/github/be-assembly-standard/shells/go/.git' to
'/home/zhijie/Desktop/github/be-assembly-standard/.git/modules/shells/go'
Cleared directory 'shells/go'
warning: Submodule work tree 'shells/python' contains a .git directory. This will be replaced with a .git file by using absorbgitdirs.
Migrating git directory of 'shells/python' from
'/home/zhijie/Desktop/github/be-assembly-standard/shells/python/.git' to
'/home/zhijie/Desktop/github/be-assembly-standard/.git/modules/shells/python'
Submodule 'shells/go' (git@github.com:brickKit/be-shell-go.git) unregistered for path 'shells/go'
Cleared directory 'shells/python'
Submodule 'shells/python' (git@github.com:brickKit/be-shell-python.git) unregistered for path 'shells/python'
```

之后 `shells/` 目录不存在，`.gitmodules` 里不再有 shells 条目，`git config --get-regexp '^submodule\.shells'` 无结果；`git grep "shells/\|be-shell-go\|be-shell-python"`（排除 dev/、archive/、components/、tools/）无结果。GitHub 上的 `be-shell-go`、`be-shell-python` 没动。

## 现象

- `shell.members: []` 被 `lint` 和 `add` 判为不合法清单（`MANIFEST_INVALID`）；外壳因此加不进 `brickkit.yaml`，`brickkit build <id>` 只认项目里的组件，所以也构建不了。
- 同一份清单放在本地源里，不影响 `brickkit up --dry-run` 等其他命令。
- 运行期零成员完全正常：4 个镜像都能构建，`BRICKKIT_SERVED_MEMBERS_CONFIG=[]` 时 4 个外壳都启动、`/healthz` 200，下游 authz/JWKS 不可达只打日志。
- be-sdk-python 外壳的 `/healthz` 端口来自 `SHELL_HEALTH_PORT`（兜底 18889），不是 `deployment.port`；Go 外壳则从 `./component.yaml` 读 `deployment.port`。
- 外壳自己的端口只提供 `/healthz`，没有 `/metrics`（Go 用裸 `ServeMux` 只挂了 `/healthz`，Python 的健康检查 app 也只有 `/healthz`），所以 brief 里的 `prometheus.io/*` 标签会让抓取打到 404，已从 4 份 `component.yaml` 去掉。

## 卡点与绕过

- 卡点：空 `shell.members` 被拒 → 无法 `add` / `brickkit build` / `brickkit up`。绕过：按 brief 的条件分支不加入项目；改用 `docker build` + `docker run` 验证镜像能构建、零成员能启动。`brickkit build` 是否给外壳镜像打上成员版本标签、`up` 的镜像核对，要等 06b 第一个成员加入后才能验。
- 没有写 `config/be-<name>.yaml`：外壳不在 `brickkit.yaml` 里时，lint 会报 `⚠️ config/be-go-core.yaml belongs to no component in brickkit.yaml and is ignored`（试写过一次再删掉了）。等 06b `brickkit add` 生成骨架后再填。
- 没有读 brickKit 源码。

## 结论

- **V-03**：标准布局（`brickkit new --shell`，一个外壳一个目录、一个镜像、一份成员清单）下，旧的"一个仓库一个镜像、部署成多个外壳实例"需求不存在了，构建上下文就是外壳自己的目录，不需要越出去；4 个外壳目录用 `docker build` 都能直接构建。但 brickKit v1.0.1 不接受 `shell.members: []`（`MANIFEST_INVALID`："a shell must list at least one component compiled into it"），所以零成员的外壳加不进项目，`brickkit build` 本身这次没法跑。`brickkit build` 是否顺利，改到 06b 第一个成员加入时再验。
- 4 个外壳的骨架、代码和文档都已完成：Go 外壳 `go build` 通过，Python 外壳在 3.12 下能导入，文档 `lint --strict` 零警告（唯一的错误是空成员）。
- 旧 submodule 已退役。

## 反馈候选

1. （brickKit）一个外壳零成员在运行期是合法的（SDK 拿到 `[]`；部署文件也可以一个成员都不托管），但清单层面必须至少列一个成员。后果是先建外壳骨架、再逐个迁入成员这种做法走不通：第一个成员加入之前，外壳既不能 `add` 也不能 `build`；放在本地源里还会让项目的 `lint` 一直报错。可以问一下是有意设计还是可以放宽（比如零成员只给警告）。
2. （brickKit 文档）`BRICKKIT.zh.md` 的小节必须用固定的中文标题（组件定位 / 依赖说明 / 配置指南 / 契约索引），但已安装的 skill 里没写这几个名字，只能 lint 报错之后才知道。另外 `AGENTS.md` 里的相对链接只要跨出组件目录也会报 `DOC_LINK_NOT_PORTABLE`，而 skill 只说了 `BRICKKIT.md` 不能用相对链接。
3. （项目内 SDK，不是 brickKit 的问题）be-sdk-python 的外壳 `/healthz` 端口应该和 Go 一样从自己的 `component.yaml` 读 `deployment.port`，而不是靠 `SHELL_HEALTH_PORT`/18889 兜底；目前靠 py-render 在 configSchema 里声明默认值 8402 来补。

## 追加：裁定 R23（be-sdk-python v0.4.2）后的 py-render 复验

### 目标

be-sdk-python v0.4.2 的外壳改为在自己 `./component.yaml` 的 `deployment.port` 上提供 `/healthz`，不再读 `SHELL_HEALTH_PORT`。py-render 去掉这个键，依赖升到 `@v0.4.2`，然后复验：不设 `SHELL_HEALTH_PORT` 时零成员 `/healthz` 在 8402 返回 200。

### 环境

同上。v0.4.2 的实现看的是本地 `tools/be-sdk-python` 里 `git show v0.4.2:besdk/shell_runner.py` 和 `besdk/manifest.py`：`health_port=load_own_http_port(component_yaml)`；文件缺失，或端口缺失、非法、为 0，都直接报错，没有兜底端口。

### 步骤

1. 改动：`component.yaml` 删掉 `SHELL_HEALTH_PORT` 这条 configSchema；`pyproject.toml` 改成 `besdk @ git+https://github.com/brickKit/be-sdk-python.git@v0.4.2`；`BRICKKIT.md`/`.zh.md` 的配置表删掉这一行；`AGENTS.md`/`.zh.md` 易错点里关于 `SHELL_HEALTH_PORT` 的一行，换成"镜像工作目录里没有 `component.yaml` 时启动即退出"。`grep -rn "SHELL_HEALTH_PORT\|18889" shell/be` 无结果。3 个 Go 外壳的 `component.yaml` 里 `grep -n HEALTH` 也无结果：它们没有类似的键，一直从 `./component.yaml` 读端口。

2. `docker build -q --no-cache -t task8-probe/be-py-render:1.0.0 shell/be/py-render`：

```
sha256:92077d1e2ea1f303f1942be90a715f35cd71b47dcf25af5469b289573866374c
build exit=0
```

3. `docker run -d --add-host=host.docker.internal:host-gateway --env-file <scratch>/py-r23.env -p 29804:8402 ...`。env 文件与上次相同，只是没有 `SHELL_HEALTH_PORT`：`PG_*`（`shell_py_render`，密码取自 `.env`）、`NATS_URL`、`OTEL_BASE_URL=`、`AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL`、`BRICKKIT_SERVED_MEMBERS=`、`BRICKKIT_SERVED_MEMBERS_CONFIG=[]`。

```
200 host:29804
running exit=0
{"ok":true} 8402 exit=0
 18889 exit=4
Version: 0.4.2
拉取 authz bundle 失败，沿用内存里已有的旧版本: [Errno -2] Name or service not known
```

（后三行分别是容器内 `wget` 8402、`wget` 18889、`pip show besdk`；最后一行是容器日志，authz 不可达是预期内的，原因同上。）

4. 对照：工作目录换成 `/tmp`（找不到 `component.yaml`），`docker run --rm ... -w /tmp --entrypoint python ... /app/main.py`：

```
[be-py-render] 读自己的 component.yaml 失败：[Errno 2] No such file or directory: 'component.yaml'
exit=1
```

5. `cd shell/be/py-render && brickkit lint --strict`（项目场景）里与 py-render 相关的只有：

```
   File: component.yaml
   shell.members: a shell must list at least one component compiled into it
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
...
✅ ./ (docs)
```

scratch 副本（组件场景）：

```
📦 Component repository (has component.yaml, no brickkit.yaml): component.yaml and the component's docs are checked
❌ Error: component.yaml failed validation
   File: component.yaml
   shell.members: a shell must list at least one component compiled into it
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
✅ ./ (docs)

📋 Checked 2 files: 1 with errors, 0 warnings
```

6. 删除了探针容器 `task8-probe-py-r23`、镜像 `task8-probe/be-py-render:1.0.0` 和含密码的 env 文件；`docker ps -a`、`docker images` 里都没有 task8 相关的残留。

### 结论

v0.4.2 之后 py-render 不再需要 `SHELL_HEALTH_PORT`：零成员时 `/healthz` 在 `deployment.port` 8402 返回 200，18889 不再监听；缺少 `component.yaml` 时会响亮退出。前文反馈候选 3 已在 SDK 侧解决。lint 只剩空成员这一条错误。
