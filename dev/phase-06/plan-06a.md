# 06a 地基 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把项目根目录、SDK、工具链、外壳骨架和项目级正式文档，全部按 brickKit v1.0.0 重新立起来，让 06b 可以开始逐个重建组件。

**Architecture:**
- 旧文件整体冻结进 `archive/pre-v1/`，然后由 `brickkit init` / `skills update` / `new` 重新生成项目三层文件、skill 和外壳骨架。
- SDK 改为从 `Config` 精确读取键名，连接信息改为普通配置项，依赖地址也从 `Config` 读。新增 shell 包：成员从 `BRICKKIT_SERVED_MEMBERS_CONFIG` 读取，迁移交给 brickKit。
- 文档的正式区和开发区之间，由 `make docs-boundary` 把关。

**Tech Stack:** brickKit CLI v1.0.0；Go 1.25（Gin、pgx、nats.go、errgroup）；Python 3.12（FastAPI、asyncpg、nats-py）；TypeScript（Node ≥ 24）；Bash；Python 3 标准库（用于检查脚本）。

**Spec:** [`spec.md`](spec.md)，总计划见 [`plan.md`](plan.md)。

## 检查点（停下汇报）

19 个 Task 分成 5 组，每组做完停一次，用户确认后再继续：

| 组 | Task | 做完后能看到什么 |
|---|---|---|
| ① 项目骨架 | 1–3 | v1 三层文件、5 个 skill、docs-boundary、配置约定 |
| ② SDK 与外壳 | 4–8 | 三个 SDK 已发布；4 个外壳以零成员跑起来 |
| ③ 工具链 | 9–11 | be-ops / be-acceptance 已发布；Makefile 和脚本跑通 |
| ④ 正式文档 | 12–15 | decisions、conventions、项目 AGENTS.md / README、version-bump-ship |
| ⑤ 06b 的输入 | 16–19 | 前端需求盘点、单组件闭环清单、路由题库、06a 总检查 |

## Global Constraints

- brickKit CLI 版本：v1.0.0（`brickkit version` 输出 `BrickKit CLI v1.0.0`）。
- 配置键：一律大写下划线，键名就是环境变量名。禁止使用以 `_ENDPOINT` 结尾的键，以及 `COMPONENT_ID`、`COMPONENT_VERSION`、`PORT`、`BRICKKIT_SERVED_MEMBERS`、`BRICKKIT_SERVED_MEMBERS_CONFIG`。
- 统一连接键：`PG_HOST`、`PG_PORT`、`PG_DATABASE`、`PG_USER`、`PG_PASSWORD`（`secret: true`）、`PG_SCHEMA`、`NATS_URL`、`S3_URL`、`OTEL_BASE_URL`、`AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL`。
- 外壳 ID：`be/go-core`、`be/go-infra`、`be/go-backoffice`、`be/py-render`，路径为 `shell/be/<name>/`。外壳是项目代码，放在本仓库，不建独立仓库。
- 版本：组件 2.0.0；外壳 1.0.0；be-sdk-go v0.3.0、be-sdk-python v0.4.0、be-sdk-ts v0.4.0、be-ops v0.2.0、be-acceptance v0.4.0。工具仓库用带注释的 `v` 前缀 tag 并推送。
- 正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接 `dev/` 或 `archive/`。
- 正式文档英文为主，同目录放 `.zh.md` 译本，`AGENTS.md` 也要有。与用户的对话用中文。
- 代码注释沿用现有风格（中文）。
- 提交信息：先写入文件，再用 `git commit -F <file>`；提交后先看一眼 `git log --oneline -1`，再打 tag。结尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 以最终目的为主：06a 期间，`components/` 下 14 个旧 `component.yaml` 会让根目录的 `brickkit lint` 报错，这是预期的，不处理。
- 新建或删除 GitHub 仓库前先提醒用户；镜像不推送。
- 知识缺口：从 Task 1 完成后开始，每次不得不去翻 brickKit 仓库（`/home/zhijie/Desktop/github/brickKit`）才能继续，就在 `dev/phase-06/to-verify.md` 的 V-04 表里追加一行。

## Review Focus

1. **`BRICKKIT_SERVED_MEMBERS_CONFIG` 的三种状态**：未设置、空字符串、`[]`。预期行为：未设置 → 报错（说明不是由 brickkit 作为外壳启动的）；空字符串 → 报错；`[]` → 零成员正常启动，不能退化成"启动全部编译进来的模块"。由 Task 5 的测试覆盖。
2. **含特殊字符的密钥穿过成员 JSON**：PEM 多行文本、`$`、引号、反斜杠。预期在模块的 `Config` 里拿到的值与原文逐字节一致。由 Task 5 的测试覆盖；端到端验证放在 06b 的 iam-casdoor。
3. **外壳成员的依赖地址只存在于 JSON 的 `config` 里，不在进程环境变量中**。预期 `Config.Endpoint` 从 `Config` 读取，进程环境变量里同名的值不应影响结果。由 Task 4 的测试覆盖。
4. **可选依赖缺失时键不存在（而不是空字符串）**。预期 `Endpoint` 返回 `ok=false`；键存在但值为空字符串时也返回 `ok=false`。由 Task 4（Go）、Task 6（Python）、Task 7（TS）的测试覆盖。
5. **数据库密码含 `@`、`:`、`/`、`%`**。预期拼出的 DSN 能被驱动正确解析，口令不被截断。由 Task 4、Task 6 的测试覆盖。

---

### Task 1: 归档旧文件，用 CLI 重新生成项目骨架

**Files:**
- Move: `docs/` → `archive/pre-v1/docs/`；`BrickEnterprise 设计书.md`、`AGENTS.md`、`AGENTS.zh.md` → `archive/pre-v1/`；`brickkit.yaml` → `archive/pre-v1/brickkit.yaml`
- Untrack + delete: `.brickkit/`
- Create (by CLI): `brickkit.yaml`、`deploy.yaml`、`config/vars.yaml`、`config/.gitkeep`、`AGENTS.md`、`shell/.gitkeep`、`.claude/skills/brickkit-*`
- Modify: `.gitignore`
- Create: `archive/pre-v1/README.md`

**Interfaces:**
- Produces: 一个只含 v1 三层文件、尚未声明任何组件的项目根目录；`AGENTS.md` 末尾带 `<!-- brickkit:managed:begin lang=en -->` 块。

- [ ] **Step 1: 确认工作区干净，并记录起点**

```bash
cd /home/zhijie/Desktop/github/be-assembly-standard
git status --short            # 期望：空
brickkit version              # 期望：BrickKit CLI v1.0.0
git log --oneline -1
```

- [ ] **Step 2: 归档旧文件**

```bash
mkdir -p archive/pre-v1
git mv docs archive/pre-v1/docs
git mv "BrickEnterprise 设计书.md" archive/pre-v1/
git mv AGENTS.md archive/pre-v1/AGENTS.md
git mv AGENTS.zh.md archive/pre-v1/AGENTS.zh.md
git mv brickkit.yaml archive/pre-v1/brickkit.yaml
git rm -r -q --cached .brickkit
rm -rf .brickkit
```

- [ ] **Step 3: 写归档说明 `archive/pre-v1/README.md`**

```markdown
# pre-v1 归档

brickKit v0.4.6 时代（阶段一至阶段五）的全部文档与项目配置，于 2026-10-01 阶段 06 开始时原样冻结。

- 只读，不维护；内部链接按原目录结构保留，但不保证都能点开。
- 正式文档（根目录 AGENTS.md、docs/、组件文档）不得链接这里。
- 内容：docs/（设计、计划、复盘、standards、ops、踩坑记录）、BrickEnterprise 设计书.md、AGENTS.md / AGENTS.zh.md、brickkit.yaml（v0.4 格式）。
```

- [ ] **Step 4: 用 CLI 补全项目目录**

```bash
brickkit init --yes --name be-assembly-standard 2>&1 | tee /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/1c264f6e-aaa4-4367-bc16-6601a194d7e7/scratchpad/init.log
brickkit skills update --lang en 2>&1 | tee -a /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/1c264f6e-aaa4-4367-bc16-6601a194d7e7/scratchpad/init.log
brickkit skills status
```

期望：
- `init` 创建了 `brickkit.yaml`、`deploy.yaml`、`config/vars.yaml`、`AGENTS.md`、`shell/.gitkeep`，并就 `.gitignore` 缺少的条目给出警告；`CLAUDE.md` 已经存在，保持不动。
- `skills status` 列出 5 个 skill（assemble、component、deploy、plan-change、troubleshoot），都是最新的。`version-bump-ship` 是项目自有的 skill，显示为不受管。
- `.brickkit/skills.lock` 不存在。

- [ ] **Step 5: 检查生成的 `brickkit.yaml` 的安装源**

```bash
cat brickkit.yaml
```

期望有两个本地源：`components/`（local-dev）和 `shell/`（local-shells）；`components:` 为空。如果名字或路径不一致，按以下内容改写：

```yaml
project: be-assembly-standard
sources:
  - name: local-dev
    type: local
    path: ./components
  - name: local-shells
    type: local
    path: ./shell
components: []
```

- [ ] **Step 6: 按 v1 要求重写 `.gitignore`**

整个文件替换为：

```gitignore
# brickKit v1：整个 .brickkit/ 都是本机缓存与生成物，不提交
.brickkit/
# 个人部署文件（brickkit local on 生成）
deploy.local.yaml
deploy.local.yaml.bak
# 密钥
.secrets/
.env
# brickkit remove 归档的组件配置
config/.archive/

# components/ 由 git submodule 跟踪（.gitmodules 是"组件 → 仓库 → 提交"的映射），
# 只忽略 brickkit sync 的归档区
components/.archived/

# 基础资源的密钥目录，永不提交
infra/**/secrets/
build/

# 与 brickKit 沟通用的反馈信箱，不进本仓库历史
/brickkit-feedback/
```

- [ ] **Step 7: 验证**

```bash
brickkit init --yes 2>&1 | grep -i "gitignore" || echo "无 .gitignore 警告"
brickkit lint 2>&1 | tail -20
```

期望：没有 `.gitignore` 警告。`lint` 的报错只来自 `components/*/*/component.yaml`（旧格式：`dependencies.resources` 等），`brickkit.yaml`、`deploy.yaml`、`AGENTS.md` 都没有报错。把 `lint` 的完整输出存为 `dev/test-records/06a/task1-lint.md`，按 spec §10 的格式写。

- [ ] **Step 8: 处理 pre-commit hook**

```bash
git config core.hooksPath          # 期望：.githooks
brickkit init --hooks 2>&1 | tee -a /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/1c264f6e-aaa4-4367-bc16-6601a194d7e7/scratchpad/init.log
```

预期 CLI 会把 `.githooks/pre-commit` 判定为"外来 hook"，并打印一段需要手工粘贴的片段。把 `.githooks/pre-commit` 整个替换为以下内容：

```bash
#!/usr/bin/env bash
# 提交前检查：brickKit 官方的 restore 判据（submodule 结构与 deploy.yaml 的 mode 一致）
# + 正式文档边界（Task 2 加入）。
set -euo pipefail
brickkit --log-level off restore --check
if [ -x infra/scripts/docs-boundary.py ]; then
  python3 infra/scripts/docs-boundary.py
fi
```

如果 CLI 打印的片段与上面第一条命令不一致，以 CLI 打印的为准。然后：

```bash
chmod +x .githooks/pre-commit
```

- [ ] **Step 9: 提交**

```bash
git add -A
git status --short | head -30
# 提交信息写入 scratchpad/msg.txt，第一行：
# chore(phase-06): 归档 v0.4 时代的全部文档与配置，用 brickkit v1 重新生成项目骨架
git commit -F /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/1c264f6e-aaa4-4367-bc16-6601a194d7e7/scratchpad/msg.txt
git log --oneline -1
```

---

### Task 2: 正式文档边界检查 `make docs-boundary`

**Files:**
- Create: `infra/scripts/docs-boundary.py`
- Create: `infra/scripts/tests/test_docs_boundary.py`
- Modify: `Makefile`（新增 `docs-boundary` 目标；在 `gates` 的依赖中加入 `docs-boundary`）

**Interfaces:**
- Produces: `python3 infra/scripts/docs-boundary.py [--root DIR]`。有违规时退出码为 1，每行输出 `<文件>:<行号>: 链接指向 <目标>（正式文档不得链接 dev/ 或 archive/）`；无违规时退出码为 0。

- [ ] **Step 1: 写失败测试**

`infra/scripts/tests/test_docs_boundary.py`:

```python
import importlib.util
import pathlib
import subprocess
import sys
import textwrap

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "docs-boundary.py"


def run(root: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root)],
                          capture_output=True, text=True)


def write(root: pathlib.Path, rel: str, body: str) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(textwrap.dedent(body), encoding="utf-8")


def test_clean_tree_passes(tmp_path):
    write(tmp_path, "AGENTS.md", "[ok](docs/decisions/0001-x.md)\n")
    write(tmp_path, "docs/decisions/0001-x.md", "# x\n")
    write(tmp_path, "dev/plan.md", "[可以链接任何地方](../archive/pre-v1/README.md)\n")
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr


def test_inline_link_into_dev_fails(tmp_path):
    write(tmp_path, "AGENTS.md", "see [plan](dev/phase-06/plan.md)\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "AGENTS.md:1" in r.stdout


def test_relative_parent_link_into_archive_fails(tmp_path):
    write(tmp_path, "docs/conventions/testing.md", "[old](../../archive/pre-v1/docs/x.md#a)\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "docs/conventions/testing.md:1" in r.stdout


def test_reference_style_and_angle_brackets_fail(tmp_path):
    write(tmp_path, "README.zh.md", "[a][r]\n\n[r]: dev/x.md\n<archive/pre-v1/README.md>\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "README.zh.md:3" in r.stdout
    assert "README.zh.md:4" in r.stdout


def test_component_docs_are_checked(tmp_path):
    write(tmp_path, "components/mdm/customer/BRICKKIT.md", "[x](../../../dev/a.md)\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "components/mdm/customer/BRICKKIT.md:1" in r.stdout


def test_code_blocks_and_absolute_urls_are_ignored(tmp_path):
    write(tmp_path, "AGENTS.md", "```\n[x](dev/a.md)\n```\n[gh](https://github.com/x/dev/a.md)\n`dev/a.md`\n")
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout
```

- [ ] **Step 2: 运行，确认失败**

```bash
python3 -m pytest infra/scripts/tests/test_docs_boundary.py -q
```

期望：全部 FAIL（脚本不存在）。

- [ ] **Step 3: 实现 `infra/scripts/docs-boundary.py`**

```python
#!/usr/bin/env python3
"""正式文档边界检查：正式文档不得链接 dev/ 或 archive/。

正式文档 = 根目录 AGENTS*.md、README*.md，docs/ 下全部 .md，
components/<scope>/<name>/ 与 shell/<scope>/<name>/ 下的 .md（不含 node_modules 等）。
dev/ 与 archive/ 自己可以链接任何地方，不检查。
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

INLINE = re.compile(r"\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
REFDEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s|$)")
ANGLE = re.compile(r"<([^>\s]+\.md(?:#[^>\s]*)?)>")
FENCE = re.compile(r"^\s{0,3}(```|~~~)")
INLINE_CODE = re.compile(r"`[^`]*`")
SKIP_DIRS = {"node_modules", "dist", ".git", ".brickkit", "vendor", "__pycache__"}
FORBIDDEN = ("dev", "archive")


def formal_docs(root: pathlib.Path):
    for p in root.glob("AGENTS*.md"):
        yield p
    for p in root.glob("README*.md"):
        yield p
    for base in ("docs", "components", "shell"):
        d = root / base
        if not d.is_dir():
            continue
        for p in d.rglob("*.md"):
            rel_parts = p.relative_to(root).parts
            if any(part in SKIP_DIRS or part.startswith(".") for part in rel_parts):
                continue
            yield p


def targets(line: str):
    line = INLINE_CODE.sub("", line)
    for rx in (INLINE, REFDEF, ANGLE):
        for m in rx.finditer(line):
            yield m.group(1)


def violates(root: pathlib.Path, doc: pathlib.Path, target: str) -> bool:
    if "://" in target or target.startswith(("#", "mailto:")):
        return False
    path = target.split("#", 1)[0]
    if not path:
        return False
    resolved = (root / path.lstrip("/")) if path.startswith("/") else (doc.parent / path)
    try:
        rel = resolved.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return len(rel.parts) > 0 and rel.parts[0] in FORBIDDEN


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    root = pathlib.Path(ap.parse_args().root)
    bad = 0
    for doc in sorted(set(formal_docs(root))):
        in_fence = False
        for no, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            if FENCE.match(line):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for t in targets(line):
                if violates(root, doc, t):
                    print(f"{doc.relative_to(root)}:{no}: 链接指向 {t}（正式文档不得链接 dev/ 或 archive/）")
                    bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
```

```bash
chmod +x infra/scripts/docs-boundary.py
```

- [ ] **Step 4: 运行，确认通过**

```bash
python3 -m pytest infra/scripts/tests/test_docs_boundary.py -q
```

期望：6 passed。

- [ ] **Step 5: 接入 Makefile**

在 `Makefile` 的 `registry-check` 目标之后加入：

```makefile
docs-boundary:  ## 正式文档不得链接 dev/ 或 archive/
	@python3 infra/scripts/docs-boundary.py
```

并把 `gates:` 那一行的依赖加上 `docs-boundary`（如 `gates: docs-boundary`）。然后运行：

```bash
make docs-boundary; echo "exit=$?"
```

期望：`exit=0`。此时还没有正式文档，只有 CLI 生成的 `AGENTS.md`。

- [ ] **Step 6: 提交**

提交信息第一行：`feat(phase-06): make docs-boundary——正式文档不得链接 dev/ 与 archive/`

---

### Task 3: 配置约定与 `config/vars.yaml`

**Files:**
- Modify: `config/vars.yaml`
- Create: `docs/conventions/configuration.md`、`docs/conventions/configuration.zh.md`

**Interfaces:**
- Produces:
  - `config/vars.yaml` 中的共享变量名：`PG_HOST`、`PG_PORT`、`PG_DATABASE`、`NATS_URL`、`S3_URL`、`OTEL_BASE_URL`、`AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL`。06b 中各组件的 config 一律通过 `$var:<名>` 引用。
  - 组件自有键的命名规则：用 `<领域名词>_<含义>`，如 `DEFAULT_WAREHOUSE_ID`。

- [ ] **Step 1: 写 `config/vars.yaml`**

```yaml
# 全项目共享的配置值：多个组件重复用到的写在这里，组件的 config/<scope>-<name>.yaml
# 用 $var:<名> 引用。某个组件需要不同的值，就在它自己的文件里写字面量覆盖。
# 换环境 / 换拓扑：在对应部署文件（deploy.<env>.yaml）的 vars: 里覆盖，优先级高于本文件。

# PostgreSQL（make up 起的 be-postgres；组件容器通过 host-gateway 访问宿主机）
PG_HOST: host.docker.internal
PG_PORT: "5432"
PG_DATABASE: brickkit_db

# NATS（make up 起的 be-nats）
NATS_URL: nats://host.docker.internal:4222

# 对象存储（RustFS，S3 兼容；值是完整 URL）
S3_URL: http://host.docker.internal:9000

# 可观测性（未开 obs 时留空，SDK 视为关闭导出）
OTEL_BASE_URL: ""

# 权限与身份：两者都在 be/go-infra 外壳里；拆回独立部署时在 deploy.teardown.yaml 的 vars: 覆盖
AUTHZ_BUNDLE_URL: http://be-go-infra-1-0-0:8223/authz/bundle
IAM_JWKS_URL: http://be-go-infra-1-0-0:8200/.well-known/jwks.json
```

`8223` / `8200` 是 authz / iam-casdoor 在 `registry/ports.tsv` 中登记的 HTTP 端口，写入前先核对：

```bash
grep -E "infra-authz|infra-iam-casdoor" registry/ports.tsv
```

外壳服务名的格式为 `<scope>-<name>-<版本，点换成横线>`，06b 外壳发布 1.0.0 后用 `brickkit up --dry-run` 核对。

- [ ] **Step 2: 写 `docs/conventions/configuration.md`（英文，正式文档）**

只写结论，不写过程。章节如下：

```markdown
[English](configuration.md) · [中文](configuration.zh.md)

# Configuration conventions

## Key names
<!-- 规则：键名即环境变量名，大写下划线；禁用列表（Global Constraints 那一条原文）；组件自有键 <领域名词>_<含义> -->

## Shared connection keys
<!-- 表格：键 | 含义 | 值从哪来（$var / ${SECRET} / 字面量）| 是否 secret；共 11 个键（Global Constraints 列出的） -->

## Where values live
<!-- config/vars.yaml 放共享值；config/<scope>-<name>.yaml 放组件自己的值；deploy.<env>.yaml 的 vars: 按环境/拓扑覆盖；密钥只写 ${NAME}，值在 .env 或进程环境 -->

## Database roles
<!-- 每个组件一个登录角色 PG_USER=<schema 名>，密码 ${<SCOPE>_<NAME>_DB_PASSWORD}；外壳有自己的登录角色，通过 SET LOCAL ROLE 切到成员角色；schema 照抄 registry/schemas.tsv -->

## Dependency addresses
<!-- 强/弱依赖地址由 brickKit 注入 <ID>_ENDPOINT，代码用 rt.Config.Endpoint；authz/iam 不是依赖边，地址走 $var:AUTHZ_BUNDLE_URL / IAM_JWKS_URL，理由一句话：精确版本锁会让每次 authz 发版连带全部组件发版 -->
```

注意：注释里的提示在提交前必须全部换成正文，不得留下 HTML 注释。

- [ ] **Step 3: 写中文译本 `docs/conventions/configuration.zh.md`**

内容与英文版逐节对应：章节数相同，首行是 `[English](configuration.md) · [中文](configuration.zh.md)`。

- [ ] **Step 4: 验证并提交**

```bash
make docs-boundary
grep -c "^## " docs/conventions/configuration.md docs/conventions/configuration.zh.md   # 两个数字相同
grep -n "<!--" docs/conventions/configuration*.md && echo "还有占位注释" || echo ok
```

提交信息第一行：`docs(conventions): 配置键命名与共享变量约定，config/vars.yaml 初值`

---

### Task 4: be-sdk-go v0.3.0（第一部分）：精确键名、连接配置、依赖地址走 Config

**Files（仓库 `tools/be-sdk-go`）:**
- Modify: `runtime.go`（删除 `configEnvVarName`，`String` 改为精确匹配）
- Create: `connection.go`（`PGDSN`、`NATSURL`）
- Modify: `endpoint.go`（`Endpoint`、`MustEndpoint` 改为 `Config` 的方法；`StorageEndpoint` 改为 `Config.S3URL`）
- Modify: `standalone.go`（改用 `PGDSN(rt.Config)` / `NATSURL(rt.Config)`；删除 `buildPGDSN`、`buildNATSURL`）
- Modify: `shell.go`（删除 `BuildPGDSN`、`BuildNATSURL`）
- Test: `runtime_test.go`、`connection_test.go`（新）、`endpoint_test.go`、`standalone_test.go`

**Interfaces:**
- Produces:
  - `func (c Config) String(key string) (string, bool)`：键名精确匹配，不做任何转换。
  - `func PGDSN(cfg Config) (string, error)`
  - `func NATSURL(cfg Config) (string, error)`
  - `func (c Config) Endpoint(dep, extra string) (string, bool)`
  - `func (c Config) MustEndpoint(dep, extra string) string`
  - `func (c Config) S3URL() (string, bool)`
  - 已删除：包级 `Endpoint`、`MustEndpoint`、`StorageEndpoint`、`BuildPGDSN`、`BuildNATSURL`。

- [ ] **Step 1: 写失败测试：精确键名**

在 `runtime_test.go` 末尾追加：

```go
func TestConfigStringIsExactMatch(t *testing.T) {
	c := NewConfig(map[string]string{"PG_SCHEMA": "erp_sales"})
	if v, ok := c.String("PG_SCHEMA"); !ok || v != "erp_sales" {
		t.Fatalf("String(PG_SCHEMA) = %q,%v", v, ok)
	}
	// v1 起键名原样注入，不再有 camelCase → SNAKE 转换
	if _, ok := c.String("pgSchema"); ok {
		t.Fatal("String(pgSchema) 不应命中 PG_SCHEMA")
	}
}
```

删除 `runtime_test.go` 中所有测试 `configEnvVarName` 的用例：

```bash
cd tools/be-sdk-go && grep -n "configEnvVarName\|pgSchema\|camel" runtime_test.go
```

- [ ] **Step 2: 写失败测试：连接配置**

`connection_test.go`:

```go
package besdk

import (
	"net/url"
	"strings"
	"testing"
)

func pgCfg(over map[string]string) Config {
	m := map[string]string{
		"PG_HOST": "db", "PG_PORT": "5432", "PG_DATABASE": "brickkit_db",
		"PG_USER": "erp_sales", "PG_PASSWORD": "pw",
	}
	for k, v := range over {
		m[k] = v
	}
	return NewConfig(m)
}

func TestPGDSN(t *testing.T) {
	dsn, err := PGDSN(pgCfg(nil))
	if err != nil {
		t.Fatal(err)
	}
	if dsn != "postgres://erp_sales:pw@db:5432/brickkit_db" {
		t.Fatalf("dsn = %s", dsn)
	}
}

func TestPGDSNEscapesSpecialPassword(t *testing.T) {
	dsn, err := PGDSN(pgCfg(map[string]string{"PG_PASSWORD": "p@ss:w/rd%1"}))
	if err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(dsn)
	if err != nil {
		t.Fatal(err)
	}
	if pw, _ := u.User.Password(); pw != "p@ss:w/rd%1" {
		t.Fatalf("password round-trip = %q", pw)
	}
}

func TestPGDSNEmptyPasswordAllowedButKeyRequired(t *testing.T) {
	if _, err := PGDSN(pgCfg(map[string]string{"PG_PASSWORD": ""})); err != nil {
		t.Fatalf("空口令应允许（trust 认证）：%v", err)
	}
	c := NewConfig(map[string]string{"PG_HOST": "db", "PG_PORT": "5432", "PG_DATABASE": "d", "PG_USER": "u"})
	_, err := PGDSN(c)
	if err == nil || !strings.Contains(err.Error(), "PG_PASSWORD") {
		t.Fatalf("缺 PG_PASSWORD 应报错并点名，got %v", err)
	}
}

func TestPGDSNListsAllMissing(t *testing.T) {
	_, err := PGDSN(NewConfig(map[string]string{"PG_PASSWORD": "x"}))
	if err == nil {
		t.Fatal("应报错")
	}
	for _, k := range []string{"PG_HOST", "PG_PORT", "PG_DATABASE", "PG_USER"} {
		if !strings.Contains(err.Error(), k) {
			t.Fatalf("错误信息应点名 %s：%v", k, err)
		}
	}
}

func TestNATSURL(t *testing.T) {
	if v, err := NATSURL(NewConfig(map[string]string{"NATS_URL": "nats://n:4222"})); err != nil || v != "nats://n:4222" {
		t.Fatalf("NATSURL = %q,%v", v, err)
	}
	if _, err := NATSURL(NewConfig(nil)); err == nil {
		t.Fatal("缺 NATS_URL 应报错")
	}
}
```

- [ ] **Step 3: 写失败测试：依赖地址走 Config**

把 `endpoint_test.go` 整个替换为：

```go
package besdk

import "testing"

func TestEndpointFromConfigStripsScheme(t *testing.T) {
	c := NewConfig(map[string]string{
		"MDM_CUSTOMER_ENDPOINT":      "http://be-go-core-1-0-0:8101/",
		"MDM_CUSTOMER_GRPC_ENDPOINT": "http://be-go-core-1-0-0:9101",
	})
	if v, ok := c.Endpoint("mdm/customer", ""); !ok || v != "be-go-core-1-0-0:8101" {
		t.Fatalf("http = %q,%v", v, ok)
	}
	if v, ok := c.Endpoint("mdm/customer", "grpc"); !ok || v != "be-go-core-1-0-0:9101" {
		t.Fatalf("grpc = %q,%v", v, ok)
	}
}

func TestEndpointIgnoresProcessEnv(t *testing.T) {
	// 外壳成员的依赖地址只在成员 JSON 的 config 里；进程环境里的同名变量属于外壳自己，不能串进来
	t.Setenv("MDM_CUSTOMER_ENDPOINT", "http://wrong:1")
	if _, ok := NewConfig(nil).Endpoint("mdm/customer", ""); ok {
		t.Fatal("Config 里没有就必须是 ok=false，不能回落到进程环境")
	}
}

func TestEndpointAbsentAndEmptyAreBothMissing(t *testing.T) {
	if _, ok := NewConfig(nil).Endpoint("infra/workflow", ""); ok {
		t.Fatal("可选依赖缺失：键不存在 → ok=false")
	}
	if _, ok := NewConfig(map[string]string{"INFRA_WORKFLOW_ENDPOINT": ""}).Endpoint("infra/workflow", ""); ok {
		t.Fatal("键存在但为空 → ok=false")
	}
}

func TestEndpointNameDerivation(t *testing.T) {
	c := NewConfig(map[string]string{"INTEGRATION_IM_DINGTALK_GRPC_ENDPOINT": "http://h:1"})
	if _, ok := c.Endpoint("integration/im-dingtalk", "grpc"); !ok {
		t.Fatal("ID 中的 / 与 - 都换成 _")
	}
}

func TestMustEndpointPanicsWithVarName(t *testing.T) {
	defer func() {
		r := recover()
		if r == nil {
			t.Fatal("应 panic")
		}
		if s, _ := r.(string); s == "" || !contains(s, "ERP_INVENTORY_GRPC_ENDPOINT") {
			t.Fatalf("panic 信息应点名变量：%v", r)
		}
	}()
	NewConfig(nil).MustEndpoint("erp/inventory", "grpc")
}

func TestS3URL(t *testing.T) {
	if v, ok := NewConfig(map[string]string{"S3_URL": "http://rustfs:9000"}).S3URL(); !ok || v != "http://rustfs:9000" {
		t.Fatalf("S3URL = %q,%v", v, ok)
	}
	if _, ok := NewConfig(nil).S3URL(); ok {
		t.Fatal("缺失 → ok=false")
	}
}

func contains(s, sub string) bool {
	return len(sub) == 0 || (len(s) >= len(sub) && (s == sub || indexOf(s, sub) >= 0))
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
```

如果 `testhelpers_test.go` 里已经有 `contains` 这类辅助函数，就删掉这里的重复定义，改用已有的。

- [ ] **Step 4: 运行，确认失败**

```bash
cd tools/be-sdk-go && go test ./... 2>&1 | tail -20
```

期望：编译失败，报 `undefined: PGDSN`、`c.Endpoint undefined` 等。

- [ ] **Step 5: 实现**

`runtime.go`：删除 `configEnvVarName` 函数及其上方整段注释，把 `String` 改为：

```go
// String 按键名精确取值。v1 起 configSchema 的键就是环境变量名，原样注入，
// 平台与 SDK 都不做任何大小写转换——调用方传的必须就是 component.yaml 里写的那个键。
func (c Config) String(key string) (string, bool) {
	v, ok := c.values[key]
	return v, ok
}
```

同时删除 `import` 中不再使用的 `strings`、`unicode`。

新建 `connection.go`：

```go
package besdk

import (
	"fmt"
	"net"
	"net/url"
	"strings"
)

// PGDSN 从统一连接键拼出 pgx 认得的 DSN。v1 起平台不再注入 DATABASE_* 资源变量，
// 连接信息是组件自己 configSchema 里的普通配置项（docs/conventions/configuration.md）。
//
// 口令用 url.UserPassword 编码——含 @ : / % 的口令原样拼进去会把 DSN 截断。
// PG_PASSWORD 允许为空字符串（trust 认证），但键必须存在：缺键说明 config 漏写，不是"没有密码"。
func PGDSN(cfg Config) (string, error) {
	var missing []string
	need := func(k string) string {
		v, ok := cfg.String(k)
		if !ok || v == "" {
			missing = append(missing, k)
		}
		return v
	}
	host, port, db, user := need("PG_HOST"), need("PG_PORT"), need("PG_DATABASE"), need("PG_USER")
	pw, ok := cfg.String("PG_PASSWORD")
	if !ok {
		missing = append(missing, "PG_PASSWORD")
	}
	if len(missing) > 0 {
		return "", fmt.Errorf("缺少数据库连接配置：%s", strings.Join(missing, ", "))
	}
	u := url.URL{Scheme: "postgres", User: url.UserPassword(user, pw), Host: net.JoinHostPort(host, port), Path: "/" + db}
	return u.String(), nil
}

// NATSURL 读 NATS_URL（完整 URL，可含凭据）。
func NATSURL(cfg Config) (string, error) {
	v, ok := cfg.String("NATS_URL")
	if !ok || v == "" {
		return "", fmt.Errorf("缺少 NATS_URL")
	}
	return v, nil
}
```

把 `endpoint.go` 中 `envName` 以下的部分替换为：

```go
// Endpoint 从 Config 读 <ID>[_<PORT>]_ENDPOINT 并剥掉 scheme。
//
// ⚠️ 读 Config 而不是进程环境：外壳里每个成员的依赖地址只存在于
// BRICKKIT_SERVED_MEMBERS_CONFIG 里它自己那一项的 config 中，进程环境属于外壳本身。
// 单跑时 RunStandalone 把进程环境整份灌进 Config，所以两种形态走的是同一个入口。
//
// ⚠️ 平台注入的值恒为 http:// 开头，额外端口也一样；grpc 拨号前必须剥掉。
// 可选依赖缺失时键不存在（不是空字符串）；空字符串同样当作缺失。
func (c Config) Endpoint(dep, extra string) (string, bool) {
	v, ok := c.String(envName(dep, extra))
	if !ok || v == "" {
		return "", false
	}
	v = strings.TrimPrefix(v, "http://")
	v = strings.TrimPrefix(v, "https://")
	return strings.TrimSuffix(v, "/"), true
}

// MustEndpoint 用于强依赖：缺失即 panic（强依赖缺失时平台本来就会阻断启动）。
func (c Config) MustEndpoint(dep, extra string) string {
	v, ok := c.Endpoint(dep, extra)
	if !ok {
		panic("强依赖 " + dep + " 的 " + envName(dep, extra) + " 未注入")
	}
	return v
}

// S3URL 读 S3_URL（完整 URL，原样返回）。v1 起 STORAGE_ENDPOINT 不再由平台注入，
// 而且 *_ENDPOINT 后缀是保留名，不能作为配置键。
func (c Config) S3URL() (string, bool) {
	v, ok := c.String("S3_URL")
	if !ok || v == "" {
		return "", false
	}
	return v, true
}
```

并删除 `endpoint.go` 中的 `import "os"`。

`standalone.go`：
1. 删除 `buildPGDSN`、`buildNATSURL` 两个函数及其注释。
2. 先构造 `cfg := NewConfig(envSnapshot())`，然后：

```go
	cfg := NewConfig(envSnapshot())

	shutdownOTel, err := Bootstrap(ctx, componentID, cfg.StringOr("OTEL_BASE_URL", ""))
	if err != nil {
		exitf(componentID, "Bootstrap 失败：%v", err)
	}
	defer func() { _ = shutdownOTel(context.Background()) }()

	pgDSN, err := PGDSN(cfg)
	if err != nil {
		exitf(componentID, "拼数据库连接串失败：%v", err)
	}
	db, err := sql.Open("pgx", pgDSN)
	if err != nil {
		exitf(componentID, "打开数据库连接池失败：%v", err)
	}
	defer func() { _ = db.Close() }()

	natsURL, err := NATSURL(cfg)
	if err != nil {
		exitf(componentID, "%v", err)
	}
	nc, err := nats.Connect(natsURL)
	if err != nil {
		exitf(componentID, "连接 NATS 失败：%v", err)
	}
	defer nc.Close()
```

3. `rt := &Runtime{... Config: cfg, ...}`（原来的 `NewConfig(envSnapshot())` 改为 `cfg`）。

`shell.go`：删除 `BuildPGDSN`、`BuildNATSURL` 及其注释。

`authz.go`：查找 `setupAuthzRuntime` 读取 `iamJwksUrl` / `authzBundleUrl` 的地方，改为读 `IAM_JWKS_URL` / `AUTHZ_BUNDLE_URL`：

```bash
grep -n '"iamJwksUrl"\|"authzBundleUrl"\|"[a-z][a-zA-Z]*Url"\|"[a-z][a-zA-Z]*Schema"' *.go
```

所有命中的驼峰键都改成对应的大写下划线键。

- [ ] **Step 6: 修 `standalone_test.go` 中依赖 `DATABASE_*` / `MQ_*` 的用例**

```bash
grep -n "DATABASE_\|MQ_\|buildPGDSN\|buildNATSURL\|StorageEndpoint\|STORAGE_ENDPOINT" *_test.go
```

把每个命中的用例改为通过 `NewConfig(map...)` 给出 `PG_*` / `NATS_URL`，或者删除（`connection_test.go` 已经覆盖了的就删）。

- [ ] **Step 7: 运行全部测试，确认通过**

```bash
go vet ./... && go test ./... 2>&1 | tail -20
grep -rn "os.Getenv\|os.LookupEnv" --include=*.go . | grep -v _test.go
```

期望：全部 PASS。`os.Getenv` / `os.LookupEnv` 只出现在 `standalone.go`（`mustGetenv`、`envSnapshot`）中。

- [ ] **Step 8: 提交（暂不打 tag，Task 5 完成后一起发布）**

提交信息第一行：`feat!: v1 配置契约——键名精确匹配、PG_*/NATS_URL 连接配置、依赖地址从 Config 读`

---

### Task 5: be-sdk-go v0.3.0（第二部分）：shell 包与最小复现，发布

**Files（仓库 `tools/be-sdk-go`）:**
- Create: `shell/members.go`（`ServedMember`、`ParseServedMembers`）
- Create: `shell/run.go`（`Registry`、`Main`、`Run`；移植自 `shells/go/internal/shell/shell.go`，去掉迁移逻辑）
- Test: `shell/members_test.go`、`shell/run_test.go`（移植自 `shells/go/internal/shell/shell_test.go`）
- Modify: `README.md`（新增 "Shell" 一节；更新配置键说明）

**Interfaces:**
- Consumes: Task 4 的 `besdk.Config`、`PGDSN`、`NATSURL`；现有的 `besdk.NewShellRuntime`、`InitShellAuthz`、`ServeHTTP`、`ServeExtraPort`、`Bootstrap`、`NewLogger`。
- Produces:
  - `package shell`（import 路径 `github.com/brickKit/be-sdk-go/shell`）
  - `type ServedMember struct { ComponentID string; Version string; HTTPPort int; ExtraPorts []ExtraPort; Config map[string]string }`
  - `type ExtraPort struct { Name string; Port int }`
  - `func ParseServedMembers(raw string, present bool) ([]ServedMember, error)`
  - `type Constructor = func(context.Context, *besdk.Runtime) (*besdk.Module, error)`
  - `type Registry map[string]Constructor`
  - `func Main(shellName string, registry Registry)`：外壳 `main.go` 唯一的一行。
  - `func Run(ctx context.Context, cfg Config, members []ServedMember, registry Registry, logger *slog.Logger) error`
  - `type Config struct { ShellName string; ShellConfig besdk.Config; HTTPPort int }`

- [ ] **Step 1: 先读要移植的源码**

```bash
cd /home/zhijie/Desktop/github/be-assembly-standard
sed -n 1,308p shells/go/internal/shell/shell.go
sed -n 1,304p shells/go/internal/shell/shell_test.go
sed -n 1,140p shells/go/cmd/shell/main.go
```

记下需要保留的四样东西：
1. 共享 DB 池与 NATS 连接；
2. `InitShellAuthz` 只调用一次；
3. 每个模块的 HTTP 端口与额外端口各自监听；
4. 单个模块 `Start` panic 时不拖垮其它模块（panic 隔离）。

要删除的有三样：`runMigrations` 及其 iofs 依赖（v1 由 brickKit 用成员自己的镜像先跑迁移）、`sanitizeServedMembersConfig`（v1 的 JSON 由平台以 0600 env 文件送达，不再经过 compose 的 `${}` 替换）、`configEnvVarName`。

- [ ] **Step 2: 写失败测试 `shell/members_test.go`**

```go
package shell

import (
	"strings"
	"testing"
)

func TestParseServedMembersUnsetIsError(t *testing.T) {
	_, err := ParseServedMembers("", false)
	if err == nil || !strings.Contains(err.Error(), "未设置") {
		t.Fatalf("未设置应报错：%v", err)
	}
}

func TestParseServedMembersEmptyStringIsError(t *testing.T) {
	if _, err := ParseServedMembers("  ", true); err == nil {
		t.Fatal("空字符串应报错：零成员时平台给的是 []")
	}
}

func TestParseServedMembersZeroMembers(t *testing.T) {
	ms, err := ParseServedMembers("[]", true)
	if err != nil {
		t.Fatal(err)
	}
	if ms == nil || len(ms) != 0 {
		t.Fatalf("零成员应得到非 nil 的空切片，got %#v", ms)
	}
}

func TestParseServedMembersFields(t *testing.T) {
	raw := `[{"componentId":"mdm/customer","version":"2.0.0","httpPort":8101,
	  "extraPorts":[{"name":"grpc","port":9101}],
	  "config":{"PG_SCHEMA":"mdm_customer","INFRA_AUTHZ_ENDPOINT":"http://be-go-infra-1-0-0:8223"}}]`
	ms, err := ParseServedMembers(raw, true)
	if err != nil {
		t.Fatal(err)
	}
	m := ms[0]
	if m.ComponentID != "mdm/customer" || m.Version != "2.0.0" || m.HTTPPort != 8101 {
		t.Fatalf("%#v", m)
	}
	if len(m.ExtraPorts) != 1 || m.ExtraPorts[0].Name != "grpc" || m.ExtraPorts[0].Port != 9101 {
		t.Fatalf("extraPorts %#v", m.ExtraPorts)
	}
	if m.Config["PG_SCHEMA"] != "mdm_customer" {
		t.Fatalf("config %#v", m.Config)
	}
}

func TestParseServedMembersSecretsSurviveVerbatim(t *testing.T) {
	pem := "-----BEGIN PRIVATE KEY-----\nMIIB$abc\"q\\x\n-----END PRIVATE KEY-----\n"
	raw := `[{"componentId":"infra/iam-casdoor","version":"2.0.0","httpPort":8200,"extraPorts":[],
	  "config":{"APP_TOKEN_SIGNING_KEY_PEM":"-----BEGIN PRIVATE KEY-----\nMIIB$abc\"q\\x\n-----END PRIVATE KEY-----\n"}}]`
	ms, err := ParseServedMembers(raw, true)
	if err != nil {
		t.Fatal(err)
	}
	if got := ms[0].Config["APP_TOKEN_SIGNING_KEY_PEM"]; got != pem {
		t.Fatalf("PEM 未逐字节保留：%q", got)
	}
}

func TestParseServedMembersMalformedJSON(t *testing.T) {
	if _, err := ParseServedMembers(`[{"componentId":`, true); err == nil {
		t.Fatal("坏 JSON 应报错")
	}
}
```

- [ ] **Step 3: 运行，确认失败**

```bash
cd tools/be-sdk-go && go test ./shell/ 2>&1 | tail -5
```

期望：编译失败，`undefined: ParseServedMembers`。

- [ ] **Step 4: 实现 `shell/members.go`**

```go
// Package shell 是外壳进程的全部装配：把 RunStandalone 的"1 模块"形状推广到"N 模块"。
// 外壳的 main.go 只有一行：shell.Main("<外壳名>", shell.Registry{...})。
package shell

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// ExtraPort 是成员 component.yaml 里的一条 extraPorts。
type ExtraPort struct {
	Name string `json:"name"`
	Port int    `json:"port"`
}

// ServedMember 是 BRICKKIT_SERVED_MEMBERS_CONFIG 数组的一项。Config 是这个成员独立部署时
// 会拿到的全部环境变量（已求值：$var:、${}、file:// 都已替换，*_ENDPOINT 也在里面），
// 不含 COMPONENT_ID / COMPONENT_VERSION（那两个就是 ComponentID / Version）。
type ServedMember struct {
	ComponentID string            `json:"componentId"`
	Version     string            `json:"version"`
	HTTPPort    int               `json:"httpPort"`
	ExtraPorts  []ExtraPort       `json:"extraPorts"`
	Config      map[string]string `json:"config"`
}

// ParseServedMembers 解析平台注入的成员清单。present 是 os.LookupEnv 的第二个返回值。
//
// ⚠️ 三种状态含义相反，不能混为一谈：
//   - 未设置：这个进程不是 brickkit 作为外壳启动的（比如手工 docker run），报错；
//   - "[]"：这次部署所有成员都被移出外壳，零成员正常启动；
//   - 空字符串：平台从不这样给，视为数据损坏，报错。
// 绝不能把"没有成员"退化成"启动全部编译进来的模块"。
func ParseServedMembers(raw string, present bool) ([]ServedMember, error) {
	if !present {
		return nil, errors.New("BRICKKIT_SERVED_MEMBERS_CONFIG 未设置：这个进程看起来不是由 brickkit 作为外壳启动的")
	}
	if strings.TrimSpace(raw) == "" {
		return nil, errors.New("BRICKKIT_SERVED_MEMBERS_CONFIG 为空字符串：零成员时平台给的是 []，空串说明数据在传递中损坏")
	}
	var ms []ServedMember
	if err := json.Unmarshal([]byte(raw), &ms); err != nil {
		return nil, fmt.Errorf("解析 BRICKKIT_SERVED_MEMBERS_CONFIG 失败：%w", err)
	}
	if ms == nil {
		ms = []ServedMember{}
	}
	return ms, nil
}
```

- [ ] **Step 5: 运行，确认通过**

```bash
go test ./shell/ -run ParseServedMembers -v 2>&1 | tail -15
```

期望：6 个用例全部 PASS。

- [ ] **Step 6: 移植运行测试 `shell/run_test.go`**

```bash
cp ../../shells/go/internal/shell/shell_test.go shell/run_test.go
```

然后改动三处：
1. 删除所有与迁移相关的用例和断言（`runMigrations`、`Schema` 字段、`x-migrations-table`）。
2. 把测试里构造 `ModuleSpec` 的写法改成构造 `[]ServedMember` 加 `Registry`：模块构造函数放进 `Registry{"test/a": ctorA}`，`ServedMember{ComponentID: "test/a", HTTPPort: <空闲端口>, Config: map[string]string{...}}`。
3. 外壳级配置改为 `Config{ShellName: "test-shell", ShellConfig: besdk.NewConfig(map[string]string{"PG_HOST":..., "NATS_URL":...}), HTTPPort: <空闲端口>}`。连接参数从 `TEST_PG_DSN` / `TEST_NATS_URL` 解析；这两个变量缺失时 `t.Skip`，与原测试保持一致。

另外追加两个用例：

```go
func TestRunRejectsMemberWithoutConstructor(t *testing.T) {
	err := buildModulesForTest(t, []ServedMember{{ComponentID: "x/unknown", HTTPPort: 1}}, Registry{})
	if err == nil || !strings.Contains(err.Error(), "x/unknown") {
		t.Fatalf("未登记构造函数的成员应报错并点名：%v", err)
	}
}

func TestRunZeroMembersServesOnlyShellHealth(t *testing.T) {
	// 零成员：只起外壳自己的 /healthz，200；不调用 Registry 里的任何构造函数
	called := false
	reg := Registry{"test/a": func(context.Context, *besdk.Runtime) (*besdk.Module, error) { called = true; return nil, nil }}
	port := freePort(t)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, testShellConfig(t, port), []ServedMember{}, reg, besdk.NewLogger("test-shell")) }()
	waitHealthy(t, port)
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if called {
		t.Fatal("零成员时不应构造任何模块")
	}
}
```

`buildModulesForTest`、`freePort`、`waitHealthy`、`testShellConfig` 写在 `run_test.go` 里。原测试里已经有同类辅助函数的就改名复用；没有的按以下实现：

```go
func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func waitHealthy(t *testing.T, port int) {
	t.Helper()
	url := fmt.Sprintf("http://127.0.0.1:%d/healthz", port)
	for i := 0; i < 50; i++ {
		if resp, err := http.Get(url); err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				return
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("%s 5 秒内未就绪", url)
}

func testShellConfig(t *testing.T, port int) Config {
	t.Helper()
	dsn, nurl := os.Getenv("TEST_PG_DSN"), os.Getenv("TEST_NATS_URL")
	if dsn == "" || nurl == "" {
		t.Skip("需要 TEST_PG_DSN 与 TEST_NATS_URL")
	}
	u, err := neturl.Parse(dsn)
	if err != nil {
		t.Fatal(err)
	}
	pw, _ := u.User.Password()
	return Config{ShellName: "test-shell", HTTPPort: port, ShellConfig: besdk.NewConfig(map[string]string{
		"PG_HOST": u.Hostname(), "PG_PORT": u.Port(), "PG_DATABASE": strings.TrimPrefix(u.Path, "/"),
		"PG_USER": u.User.Username(), "PG_PASSWORD": pw, "NATS_URL": nurl,
	})}
}

func buildModulesForTest(t *testing.T, ms []ServedMember, reg Registry) error {
	t.Helper()
	_, err := buildModules(context.Background(), ms, reg, nil, nil)
	return err
}
```

（`neturl` 是 `net/url` 的别名导入，用来避免和局部变量 `url` 冲突。）

- [ ] **Step 7: 实现 `shell/run.go`**

```bash
cp ../../shells/go/internal/shell/shell.go shell/run.go
```

然后按下面的结构改写，保留原文件里 Listen、errgroup 和 panic 隔离的实现（`builtModule`、逐模块 `ServeHTTP` / `ServeExtraPort`、`Start` 的 recover 包装）：

```go
package shell

// Constructor 是组件 backend/module.New 的签名。
type Constructor = func(context.Context, *besdk.Runtime) (*besdk.Module, error)

// Registry 把成员 ID 映射到编译进本外壳的构造函数。它必须与外壳 component.yaml 的
// shell.members 一一对应：镜像里编进了谁，由 main.go 的静态 import 决定。
type Registry map[string]Constructor

// Config 是外壳进程级的输入。ShellConfig 是外壳**自己的**配置（它自己 configSchema 的
// PG_*/NATS_URL/OTEL_BASE_URL/AUTHZ_BUNDLE_URL/IAM_JWKS_URL），不是任何成员的。
type Config struct {
	ShellName   string
	ShellConfig besdk.Config
	HTTPPort    int // 外壳自己 component.yaml 的 deployment.port，只答 /healthz
}

// Main 是外壳 main.go 的唯一一行。它读外壳自己的环境（外壳进程级，允许），
// 读自己的 component.yaml 拿端口，解析成员清单，然后调 Run。任何错误都打印后以 1 退出——
// 这是外壳进程本身的入口，不是模块，所以这里可以退出进程。
func Main(shellName string, registry Registry) {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	logger := besdk.NewLogger(shellName)
	raw, present := os.LookupEnv("BRICKKIT_SERVED_MEMBERS_CONFIG")
	members, err := ParseServedMembers(raw, present)
	if err != nil {
		logger.Error("外壳启动失败", "err", err)
		os.Exit(1)
	}
	port, err := ownHTTPPort("component.yaml")
	if err != nil {
		logger.Error("读外壳自己的 component.yaml 失败", "err", err)
		os.Exit(1)
	}
	cfg := Config{ShellName: shellName, ShellConfig: besdk.NewConfig(envSnapshot()), HTTPPort: port}
	if err := Run(ctx, cfg, members, registry, logger); err != nil {
		logger.Error("外壳异常退出", "err", err)
		os.Exit(1)
	}
}

// Run：Bootstrap 一次 → 用外壳自己的 PG_*/NATS_URL 开一个共享池和一条 NATS 连接 →
// InitShellAuthz 一次 → 逐个成员用它自己的 Config 构造 Runtime 并调用构造函数 →
// errgroup 一起 Listen（外壳 /healthz + 每个成员的端口）→ ctx 取消或任一失败时全部优雅退出。
// 成员迁移不在这里跑：v1 由 brickKit 在外壳启动前用每个成员自己的镜像和配置跑完。
func Run(ctx context.Context, cfg Config, members []ServedMember, registry Registry, logger *slog.Logger) error {
	// 1. shutdown, err := besdk.Bootstrap(ctx, cfg.ShellName, cfg.ShellConfig.StringOr("OTEL_BASE_URL", ""))
	// 2. dsn, err := besdk.PGDSN(cfg.ShellConfig)；db := sql.Open("pgx", dsn)
	// 3. nurl, err := besdk.NATSURL(cfg.ShellConfig)；nc := nats.Connect(nurl)
	// 4. besdk.InitShellAuthz(ctx, cfg.ShellConfig, logger)
	// 5. built, err := buildModules(ctx, members, registry, db, nc)
	// 6. errgroup：外壳 /healthz（cfg.HTTPPort，只答 200，不查任何依赖）+ 原文件里每个 builtModule 的 Serve 与 Start
	// 以上 6 步沿用原 shell.go 中 Run 的实现，只替换输入来源；删除第 5 步之后的 runMigrations 调用。
}

// buildModules 为每个成员构造 Runtime（Env 用成员 JSON 里的 Config，绝不用外壳进程环境）并调用构造函数。
func buildModules(ctx context.Context, members []ServedMember, registry Registry, db *sql.DB, nc *nats.Conn) ([]builtModule, error) {
	out := make([]builtModule, 0, len(members))
	for _, m := range members {
		ctor, ok := registry[m.ComponentID]
		if !ok {
			return nil, fmt.Errorf("成员 %s 在 BRICKKIT_SERVED_MEMBERS_CONFIG 里，但本外壳没有编译它（Registry 未登记）——检查外壳 component.yaml 的 shell.members 与 main.go 的 import", m.ComponentID)
		}
		extra := make(map[string]int, len(m.ExtraPorts))
		for _, p := range m.ExtraPorts {
			extra[p.Name] = p.Port
		}
		rt := besdk.NewShellRuntime(besdk.ShellModuleConfig{
			ComponentID: m.ComponentID, ComponentVersion: m.Version,
			Env: m.Config, HTTPPort: m.HTTPPort, ExtraPorts: extra,
		}, db, nc)
		mod, err := ctor(ctx, rt)
		if err != nil {
			return nil, fmt.Errorf("成员 %s 初始化失败：%w", m.ComponentID, err)
		}
		out = append(out, builtModule{id: m.ComponentID, rt: rt, mod: mod})
	}
	return out, nil
}
```

原文件的 `builtModule` 结构体（字段 `spec ModuleSpec`）改为 `type builtModule struct { id string; rt *besdk.Runtime; mod *besdk.Module }`，原来引用 `b.spec.ComponentID` 的地方改为 `b.id`，引用 `b.spec.HTTPPort` / `ExtraPorts` 的地方改为 `b.rt.HTTPPort` / `b.rt.ExtraPorts`。

`Run` 中第 1–6 步的注释是移植指引：每一步都要用原 `shell.go` 里对应的真实代码替换，提交前 `run.go` 里不得残留这些步骤注释。

`ownHTTPPort` 与 `envSnapshot` 在 be-sdk-go 根包里已有等价实现（`loadOwnPorts`、`envSnapshot`），但都没有导出。在根包新建 `export_shell.go` 导出它们：

```go
package besdk

// LoadOwnHTTPPort 供 shell 包读外壳自己的 component.yaml。
func LoadOwnHTTPPort(path string) (int, error) {
	p, err := loadOwnPorts(path)
	return p.HTTPPort, err
}

// EnvSnapshot 供 shell 包读外壳进程自己的环境（外壳进程级，不属于任何模块）。
func EnvSnapshot() map[string]string { return envSnapshot() }
```

`run.go` 中用 `besdk.LoadOwnHTTPPort` 和 `besdk.EnvSnapshot()` 替换 `ownHTTPPort` 和 `envSnapshot()`。

- [ ] **Step 8: 运行全部测试**

```bash
make -C ../.. test-db-init >/dev/null 2>&1 || true
export TEST_PG_DSN=$(grep -h TEST_PG_DSN ../../.env 2>/dev/null | cut -d= -f2-)
export TEST_NATS_URL=${TEST_NATS_URL:-nats://localhost:4222}
go vet ./... && go test ./... 2>&1 | tail -20
```

期望：全部 PASS。panic 隔离用例在有 `TEST_PG_DSN` 时必须真正执行，不能被 Skip（看 `-v` 输出确认）。

- [ ] **Step 9: README 与发布**

`README.md` 新增 `## Shell` 一节，内容包括：外壳 `main.go` 的一行写法；`Registry` 必须与 `shell.members` 一致；成员迁移由 brickKit 负责；`BRICKKIT_SERVED_MEMBERS_CONFIG` 三种状态的含义。同时更新配置相关章节：精确键名、`PGDSN` / `NATSURL`、`Config.Endpoint`、`S3URL`。

```bash
git add -A && git commit -F <msg 文件>   # 第一行：feat!: shell 包——外壳装配下沉到 SDK，成员从 v1 JSON 读取，迁移交给 brickKit
git log --oneline -1
git tag -a v0.3.0 -F <notes 文件>        # notes：破坏性变更清单（Task 4 + 5 的已删除接口与替代写法）
git push origin HEAD --follow-tags
```

然后在父仓库更新 submodule 指针：

```bash
cd ../.. && git add tools/be-sdk-go && git commit -F <msg>   # chore: be-sdk-go → v0.3.0
```

---

### Task 6: be-sdk-python v0.4.0

**Files（仓库 `tools/be-sdk-python`）:**
- Modify: `besdk/runtime.py`（删除 `_config_env_var_name`，`string` 改为精确匹配）
- Create: `besdk/connection.py`（`pg_dsn`、`nats_url`）
- Modify: `besdk/endpoint.py`（`endpoint` / `must_endpoint` 改为 `Config` 的方法；`storage_endpoint` → `Config.s3_url`）
- Modify: `besdk/standalone.py`（改用 `pg_dsn(cfg)` / `nats_url(cfg)`）
- Create: `besdk/shell_runner.py`（`parse_served_members`、`main`、`run`；移植自 `shells/python/shell/run.py`，去掉迁移）
- Test: `tests/test_connection.py`、`tests/test_endpoint.py`、`tests/test_shell_runner.py`；修改 `tests/test_runtime.py`

**Interfaces:**
- Produces:
  - `Config.string(key) -> tuple[str, bool]`：精确匹配。
  - `pg_dsn(cfg: Config) -> str`：缺键时抛 `ValueError`，错误信息点名全部缺失的键。
  - `nats_url(cfg: Config) -> str`
  - `Config.endpoint(dep: str, extra: str = "") -> tuple[str, bool]`、`Config.must_endpoint(dep, extra="") -> str`、`Config.s3_url() -> tuple[str, bool]`
  - `besdk.shell_runner.ServedMember`（dataclass，字段：`component_id`、`version`、`http_port`、`extra_ports: dict[str,int]`、`config: dict[str,str]`）
  - `parse_served_members(raw: str | None) -> list[ServedMember]`
  - `main(shell_name: str, registry: dict[str, Callable])`

- [ ] **Step 1: 写失败测试**

`tests/test_connection.py`:

```python
import urllib.parse

import pytest

from besdk.connection import nats_url, pg_dsn
from besdk.runtime import Config

BASE = {"PG_HOST": "db", "PG_PORT": "5432", "PG_DATABASE": "brickkit_db", "PG_USER": "infra_print", "PG_PASSWORD": "pw"}


def test_pg_dsn():
    assert pg_dsn(Config(BASE)) == "postgresql://infra_print:pw@db:5432/brickkit_db"


def test_pg_dsn_escapes_password():
    dsn = pg_dsn(Config({**BASE, "PG_PASSWORD": "p@ss:w/rd%1"}))
    assert urllib.parse.unquote(urllib.parse.urlsplit(dsn).password) == "p@ss:w/rd%1"


def test_pg_dsn_lists_all_missing():
    with pytest.raises(ValueError) as e:
        pg_dsn(Config({"PG_PASSWORD": "x"}))
    for k in ("PG_HOST", "PG_PORT", "PG_DATABASE", "PG_USER"):
        assert k in str(e.value)


def test_pg_dsn_empty_password_allowed_but_key_required():
    pg_dsn(Config({**BASE, "PG_PASSWORD": ""}))
    with pytest.raises(ValueError, match="PG_PASSWORD"):
        pg_dsn(Config({k: v for k, v in BASE.items() if k != "PG_PASSWORD"}))


def test_nats_url():
    assert nats_url(Config({"NATS_URL": "nats://n:4222"})) == "nats://n:4222"
    with pytest.raises(ValueError):
        nats_url(Config({}))
```

`tests/test_endpoint.py`（整个替换）:

```python
import pytest

from besdk.runtime import Config


def test_endpoint_strips_scheme():
    c = Config({"MDM_CUSTOMER_ENDPOINT": "http://be-go-core-1-0-0:8101/"})
    assert c.endpoint("mdm/customer") == ("be-go-core-1-0-0:8101", True)


def test_endpoint_ignores_process_env(monkeypatch):
    monkeypatch.setenv("MDM_CUSTOMER_ENDPOINT", "http://wrong:1")
    assert Config({}).endpoint("mdm/customer") == ("", False)


def test_endpoint_absent_and_empty_are_missing():
    assert Config({}).endpoint("infra/workflow") == ("", False)
    assert Config({"INFRA_WORKFLOW_ENDPOINT": ""}).endpoint("infra/workflow") == ("", False)


def test_must_endpoint_names_variable():
    with pytest.raises(RuntimeError, match="ERP_INVENTORY_GRPC_ENDPOINT"):
        Config({}).must_endpoint("erp/inventory", "grpc")


def test_s3_url():
    assert Config({"S3_URL": "http://rustfs:9000"}).s3_url() == ("http://rustfs:9000", True)
    assert Config({}).s3_url() == ("", False)
```

`tests/test_shell_runner.py`:

```python
import pytest

from besdk.shell_runner import parse_served_members

PEM = "-----BEGIN PRIVATE KEY-----\nMIIB$abc\"q\\x\n-----END PRIVATE KEY-----\n"


def test_unset_is_error():
    with pytest.raises(RuntimeError, match="未设置"):
        parse_served_members(None)


def test_empty_string_is_error():
    with pytest.raises(RuntimeError):
        parse_served_members("  ")


def test_zero_members():
    assert parse_served_members("[]") == []


def test_fields_and_secret_verbatim():
    raw = ('[{"componentId":"infra/print","version":"2.0.0","httpPort":8402,'
           '"extraPorts":[{"name":"grpc","port":9402}],'
           '"config":{"PG_SCHEMA":"infra_print","K":"-----BEGIN PRIVATE KEY-----\\nMIIB$abc\\"q\\\\x\\n-----END PRIVATE KEY-----\\n"}}]')
    [m] = parse_served_members(raw)
    assert (m.component_id, m.version, m.http_port) == ("infra/print", "2.0.0", 8402)
    assert m.extra_ports == {"grpc": 9402}
    assert m.config["PG_SCHEMA"] == "infra_print"
    assert m.config["K"] == PEM
```

在 `tests/test_runtime.py` 中删除测试 `_config_env_var_name` 的用例，追加：

```python
def test_config_string_is_exact_match():
    c = Config({"PG_SCHEMA": "infra_print"})
    assert c.string("PG_SCHEMA") == ("infra_print", True)
    assert c.string("pgSchema") == ("", False)
```

- [ ] **Step 2: 运行，确认失败**

```bash
cd tools/be-sdk-python && python -m pytest -q 2>&1 | tail -15
```

期望：多个用例失败或报导入错误。

- [ ] **Step 3: 实现**

`besdk/runtime.py`：删除 `_config_env_var_name` 及其文档字符串；`string` 改为：

```python
    def string(self, key: str) -> tuple[str, bool]:
        """按键名精确取值。v1 起键名即环境变量名，原样注入，不做任何转换。"""
        v = self._values.get(key)
        if v is None:
            return "", False
        return v, True
```

并在 `Config` 类中加入：

```python
    def endpoint(self, dep: str, extra: str = "") -> tuple[str, bool]:
        """从 Config 读 <ID>[_<PORT>]_ENDPOINT 并剥掉 scheme。外壳成员的依赖地址只在它
        自己的成员 config 里，绝不回落到进程环境。键不存在或值为空都视为缺失。"""
        from besdk.endpoint import env_name

        v, ok = self.string(env_name(dep, extra))
        if not ok or v == "":
            return "", False
        for p in ("http://", "https://"):
            if v.startswith(p):
                v = v[len(p):]
        return v.rstrip("/"), True

    def must_endpoint(self, dep: str, extra: str = "") -> str:
        from besdk.endpoint import env_name

        v, ok = self.endpoint(dep, extra)
        if not ok:
            raise RuntimeError(f"强依赖 {dep} 的 {env_name(dep, extra)} 未注入")
        return v

    def s3_url(self) -> tuple[str, bool]:
        v, ok = self.string("S3_URL")
        return (v, True) if ok and v else ("", False)
```

`besdk/endpoint.py`：只保留名字推导函数，并重命名为公开名：

```python
"""依赖地址变量名推导。取值走 Config.endpoint（besdk/runtime.py）。"""


def env_name(dep: str, extra: str = "") -> str:
    """"mdm/customer" -> MDM_CUSTOMER_ENDPOINT；("integration/im-dingtalk","grpc") -> INTEGRATION_IM_DINGTALK_GRPC_ENDPOINT"""
    p = dep.replace("/", "_").replace("-", "_").upper()
    return f"{p}_ENDPOINT" if not extra else f"{p}_{extra.upper()}_ENDPOINT"
```

然后检查其它模块是否引用了旧函数名：

```bash
grep -rn "_env_name\|storage_endpoint\|from besdk.endpoint import\|besdk.endpoint\." besdk/ tests/
```

把所有命中改为 `env_name`，或改用 `Config` 上的方法。

`besdk/connection.py`:

```python
"""统一连接键 → 驱动连接串。v1 起平台不再注入 DATABASE_*/MQ_*，连接信息是组件
configSchema 里的普通配置项（docs/conventions/configuration.md）。"""
from __future__ import annotations

import urllib.parse

from besdk.runtime import Config


def pg_dsn(cfg: Config) -> str:
    missing: list[str] = []

    def need(k: str) -> str:
        v, ok = cfg.string(k)
        if not ok or v == "":
            missing.append(k)
        return v

    host, port, db, user = need("PG_HOST"), need("PG_PORT"), need("PG_DATABASE"), need("PG_USER")
    pw, ok = cfg.string("PG_PASSWORD")
    if not ok:
        missing.append("PG_PASSWORD")
    if missing:
        raise ValueError("缺少数据库连接配置：" + ", ".join(missing))
    q = urllib.parse.quote
    return f"postgresql://{q(user, safe='')}:{q(pw, safe='')}@{host}:{port}/{q(db, safe='')}"


def nats_url(cfg: Config) -> str:
    v, ok = cfg.string("NATS_URL")
    if not ok or not v:
        raise ValueError("缺少 NATS_URL")
    return v
```

`besdk/standalone.py`：删除拼接 `DATABASE_*` / `MQ_*` 的两个函数，构造 `cfg = Config(_env_snapshot())` 后，改用 `pg_dsn(cfg)`、`nats_url(cfg)`、`cfg.string_or("OTEL_BASE_URL", "")`。

`besdk/shell_runner.py`：

```bash
cp ../../shells/python/shell/run.py besdk/shell_runner.py
sed -n 1,249p besdk/shell_runner.py
```

改写要点：
1. 文件顶部新增下面的 `ServedMember` 和 `parse_served_members`。
2. 外壳级连接改用 `pg_dsn(shell_cfg)` / `nats_url(shell_cfg)`，其中 `shell_cfg = Config(dict(os.environ))`。
3. 每个成员的 `Runtime` 使用 `Config(m.config)`。
4. 删除迁移调用、`yoyo` 导入、驼峰转换。
5. 保留共享 asyncpg 池、`InitShellAuthz` 的等价调用、逐成员监听、panic 隔离。

```python
@dataclass
class ServedMember:
    component_id: str
    version: str
    http_port: int
    extra_ports: dict[str, int]
    config: dict[str, str]


def parse_served_members(raw: str | None) -> list[ServedMember]:
    """raw 是 os.environ.get("BRICKKIT_SERVED_MEMBERS_CONFIG")。
    None（未设置）与空串都报错；"[]" 是零成员。绝不退化成"启动全部编译进来的模块"。"""
    if raw is None:
        raise RuntimeError("BRICKKIT_SERVED_MEMBERS_CONFIG 未设置：这个进程看起来不是由 brickkit 作为外壳启动的")
    if raw.strip() == "":
        raise RuntimeError("BRICKKIT_SERVED_MEMBERS_CONFIG 为空字符串：零成员时平台给的是 []")
    try:
        items = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"解析 BRICKKIT_SERVED_MEMBERS_CONFIG 失败：{e}") from e
    return [
        ServedMember(
            component_id=i["componentId"], version=i["version"], http_port=int(i["httpPort"]),
            extra_ports={p["name"]: int(p["port"]) for p in i.get("extraPorts") or []},
            config={k: str(v) for k, v in (i.get("config") or {}).items()},
        )
        for i in items
    ]
```

- [ ] **Step 4: 运行全部测试，确认通过**

```bash
python -m pytest -q 2>&1 | tail -10
grep -rn "os.environ" besdk/ | grep -v "standalone.py\|shell_runner.py"
```

期望：全部 PASS；`os.environ` 只出现在 `standalone.py` 与 `shell_runner.py`。

- [ ] **Step 5: 发布**

更新 `README.md` 的配置与外壳章节（内容同 Go 版 Task 5 Step 9）。

```bash
git add -A && git commit -F <msg>      # feat!: v1 配置契约 + shell_runner（成员从 v1 JSON 读取，迁移交给 brickKit）
git log --oneline -1
git tag -a v0.4.0 -F <notes> && git push origin HEAD --follow-tags
cd ../.. && git add tools/be-sdk-python && git commit -F <msg>   # chore: be-sdk-python → v0.4.0
```

---

### Task 7: be-sdk-ts v0.4.0

**Files（仓库 `tools/be-sdk-ts`）:**
- Modify: `src/config.ts`（删除驼峰转换；新增 `endpoint`、`mustEndpoint`、`s3Url` 方法）
- Modify: `src/endpoint.ts`（只保留 `envName`）
- Modify: `src/standalone.ts`（`OTEL_BASE_URL` 改从 Config 读）
- Test: `test/config.test.ts`、`test/endpoint.test.ts`（按仓库现有的测试目录与框架放置）

**Interfaces:**
- Produces:
  - `config.string(key): [string, boolean]`：精确匹配。
  - `config.endpoint(dep: string, extra?: string): [string, boolean]`
  - `config.mustEndpoint(dep, extra?): string`
  - `config.s3Url(): [string, boolean]`
  - `envName(dep, extra?)`
  - 已删除：包级 `endpoint`、`mustEndpoint`、`storageEndpoint`。

- [ ] **Step 1: 确认测试框架与现有 API 名称**

```bash
cd tools/be-sdk-ts && cat package.json | sed -n 1,40p && ls test* tests* 2>/dev/null; sed -n 1,80p src/config.ts; sed -n 1,70p src/endpoint.ts
```

下面的测试按 vitest 写。如果仓库用的是 node:test，就把 `describe/it/expect` 换成 `test` 与 `assert.deepStrictEqual`，断言内容不变。方法名以 `src/config.ts` 现有的命名风格为准（如果现有方法是 `string()` 返回元组，就照此写）。

- [ ] **Step 2: 写失败测试**

```ts
import { describe, expect, it } from "vitest";
import { Config } from "../src/config";

describe("Config v1", () => {
  it("exact key match, no camelCase conversion", () => {
    const c = new Config({ PG_SCHEMA: "x" });
    expect(c.string("PG_SCHEMA")).toEqual(["x", true]);
    expect(c.string("pgSchema")).toEqual(["", false]);
  });
  it("endpoint strips scheme and trailing slash", () => {
    const c = new Config({ ERP_SALES_ENDPOINT: "http://be-go-core-1-0-0:8084/" });
    expect(c.endpoint("erp/sales")).toEqual(["be-go-core-1-0-0:8084", true]);
  });
  it("endpoint ignores process.env", () => {
    process.env.ERP_SALES_ENDPOINT = "http://wrong:1";
    try {
      expect(new Config({}).endpoint("erp/sales")).toEqual(["", false]);
    } finally {
      delete process.env.ERP_SALES_ENDPOINT;
    }
  });
  it("absent and empty are both missing", () => {
    expect(new Config({}).endpoint("infra/workflow")).toEqual(["", false]);
    expect(new Config({ INFRA_WORKFLOW_ENDPOINT: "" }).endpoint("infra/workflow")).toEqual(["", false]);
  });
  it("mustEndpoint names the variable", () => {
    expect(() => new Config({}).mustEndpoint("erp/inventory", "grpc")).toThrow(/ERP_INVENTORY_GRPC_ENDPOINT/);
  });
  it("s3Url", () => {
    expect(new Config({ S3_URL: "http://rustfs:9000" }).s3Url()).toEqual(["http://rustfs:9000", true]);
    expect(new Config({}).s3Url()).toEqual(["", false]);
  });
});
```

- [ ] **Step 3: 运行，确认失败**

```bash
npm test 2>&1 | tail -15
```

- [ ] **Step 4: 实现**

`src/config.ts`：删除驼峰转换函数及其注释；`string(key)` 改为直接读 `this.values[key]`。新增：

```ts
  /** 从 Config 读 <ID>[_<PORT>]_ENDPOINT 并剥掉 scheme。绝不回落到 process.env；键缺失或为空都视为缺失。 */
  endpoint(dep: string, extra = ""): [string, boolean] {
    const [v, ok] = this.string(envName(dep, extra));
    if (!ok || v === "") return ["", false];
    return [v.replace(/^https?:\/\//, "").replace(/\/$/, ""), true];
  }

  mustEndpoint(dep: string, extra = ""): string {
    const [v, ok] = this.endpoint(dep, extra);
    if (!ok) throw new Error(`强依赖 ${dep} 的 ${envName(dep, extra)} 未注入`);
    return v;
  }

  s3Url(): [string, boolean] {
    const [v, ok] = this.string("S3_URL");
    return ok && v !== "" ? [v, true] : ["", false];
  }
```

`src/endpoint.ts` 只保留并导出 `envName`。`src/index.ts` 删除对已移除函数的导出。`src/standalone.ts` 中 `process.env.OTEL_BASE_URL` 改为 `config.stringOr("OTEL_BASE_URL", "")`（构造 Config 之后再读；方法名以现有 API 为准）。

```bash
grep -rn "process.env" src/ | grep -v standalone.ts
```

期望：无输出。

- [ ] **Step 5: 运行测试、构建、发布**

```bash
npm test && npm run build
git add -A && git commit -F <msg>    # feat!: v1 配置契约——精确键名，依赖地址从 Config 读
git log --oneline -1
git tag -a v0.4.0 -F <notes> && git push origin HEAD --follow-tags
cd ../.. && git add tools/be-sdk-ts && git commit -F <msg>
```

---

### Task 8: 外壳骨架（零成员）与退役旧外壳仓库

**Files:**
- Create（CLI 生成后改写）: `shell/be/{go-core,go-infra,go-backoffice}/{component.yaml,main.go,go.mod,Dockerfile,BRICKKIT.md,AGENTS.md,CLAUDE.md,README.md}`
- Create: `shell/be/py-render/{component.yaml,main.py,pyproject.toml,Dockerfile,BRICKKIT.md,AGENTS.md,CLAUDE.md,README.md}`
- Delete（submodule）: `shells/go`、`shells/python`；`shells/README.md`
- Modify: `.gitmodules`

**Interfaces:**
- Consumes: be-sdk-go v0.3.0 的 `shell.Main`；be-sdk-python v0.4.0 的 `besdk.shell_runner.main`。
- Produces: 4 个能用 `brickkit build` 构建、以零成员正常启动并在 `/healthz` 返回 200 的外壳。06b 只需往 `shell.members`、`main.go` 的 Registry、`go.mod` 中加入成员。

- [ ] **Step 1: 提醒用户（不需要等回复，继续执行）**

在当轮回复中告知用户：`shells/go`、`shells/python` 两个 submodule 将从本仓库移除；GitHub 上的 `be-shell-go`、`be-shell-python` 仓库是否归档（Archive），由用户决定。

- [ ] **Step 2: 查外壳端口**

```bash
grep -E "_shell-" registry/ports.tsv
```

记下 go-core / go-infra / go-backoffice / py-render 的 HTTP 端口（现值分别为 8090 / 8224 / 8116 / 8402，以 tsv 为准）。

- [ ] **Step 3: 生成骨架**

```bash
for n in go-core go-infra go-backoffice py-render; do brickkit new be/$n --shell; done
ls shell/be/*
```

- [ ] **Step 4: 改写 Go 外壳的 `component.yaml`（以 go-core 为例，另外两个只改 id、name、description、端口）**

```yaml
apiVersion: brickkit/v1
kind: Component
metadata:
  id: be/go-core
  name: Go core shell
  version: 1.0.0
  description: Runs the MDM and ERP Go components in one process to save memory and CPU.
  repository: https://github.com/brickKit/be-assembly-standard
  license: Apache-2.0
  vendor: brickKit
shell:
  members: []
dependencies:
  components: []
configSchema:
  type: object
  properties:
    PG_HOST: {type: string}
    PG_PORT: {type: string, default: "5432"}
    PG_DATABASE: {type: string}
    PG_USER: {type: string}
    PG_PASSWORD: {type: string, secret: true}
    NATS_URL: {type: string}
    OTEL_BASE_URL: {type: string, default: ""}
    AUTHZ_BUNDLE_URL: {type: string}
    IAM_JWKS_URL: {type: string}
  required: [PG_HOST, PG_DATABASE, PG_USER, PG_PASSWORD, NATS_URL]
deployment:
  type: container
  build:
    context: .
    dockerfile: Dockerfile
  port: 8090
  resources:
    requests: {cpu: "200m", memory: "256Mi"}
  labels:
    prometheus.io/scrape: "true"
    prometheus.io/path: /metrics
    prometheus.io/port: "8090"
healthCheck:
  type: http
  path: /healthz
  startPeriodSeconds: 300
```

先验证 `shell.members: []` 是否合法：

```bash
brickkit lint 2>&1 | grep -A3 "shell/be/go-core" | head
```

- 如果空列表被拒绝（报错信息说 `shell.members` 至少要一项），这就是 V-03 的新事实：把结论记进 `to-verify.md`，Task 8 退化为"只生成骨架、`go build` 能通过、不加入 `brickkit.yaml`"，跳过 Step 8 和 Step 9，06b 中加入第一个成员后再接入。
- 如果合法，继续执行。

- [ ] **Step 5: Go 外壳的代码文件**

`shell/be/go-core/main.go`：

```go
// be/go-core 外壳：成员由 shell.members 声明，这里的 Registry 必须与之一一对应。
package main

import "github.com/brickKit/be-sdk-go/shell"

func main() {
	shell.Main("be-go-core", shell.Registry{})
}
```

`shell/be/go-core/go.mod`：

```
module github.com/brickKit/be-assembly-standard/shell/be/go-core

go 1.25.11

require github.com/brickKit/be-sdk-go v0.3.0
```

```bash
cd shell/be/go-core && go mod tidy && go build ./... && cd -
```

`shell/be/go-core/Dockerfile`：

```dockerfile
FROM golang:1.25-alpine AS build
WORKDIR /src
RUN apk add --no-cache git
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/shell .

# 基底必须带 /bin/sh 与 wget：平台健康检查是 CMD-SHELL
FROM alpine:3.20
RUN apk add --no-cache wget ca-certificates tzdata
WORKDIR /app
COPY --from=build /out/shell /app/shell
COPY component.yaml /app/component.yaml
ENTRYPOINT ["/app/shell"]
```

go-infra、go-backoffice 照此各写一份：`main.go` 中名字分别为 `be-go-infra`、`be-go-backoffice`，`go.mod` 的 module 路径相应修改。

- [ ] **Step 6: Python 外壳 `shell/be/py-render`**

`component.yaml` 与 Go 版相同，只改 id `be/py-render`、端口（Step 2 查到的值）、`startPeriodSeconds: 300`。

`main.py`：

```python
"""be/py-render 外壳：成员由 shell.members 声明，registry 必须与之一一对应。"""
from besdk.shell_runner import main

if __name__ == "__main__":
    main("be-py-render", {})
```

`pyproject.toml`：

```toml
[project]
name = "be-py-render"
version = "1.0.0"
requires-python = ">=3.12"
dependencies = ["besdk @ git+https://github.com/brickKit/be-sdk-python.git@v0.4.0"]
```

`Dockerfile`：

```dockerfile
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends wget git && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY pyproject.toml ./
RUN pip install --no-cache-dir .
COPY . .
ENTRYPOINT ["python", "main.py"]
```

- [ ] **Step 7: 外壳文档**

四个外壳的 `BRICKKIT.md` 与 `AGENTS.md`（含 `.zh.md`）按 v1 骨架填写，只写当前事实：
- **Purpose**：这个外壳要编译哪些成员（写目标成员名单，并说明当前为零成员、06b 起逐个加入）。用 Owns / Does not own 区分：它只负责进程合并，业务逻辑归成员组件。
- **Before you deploy**：外壳自己的数据库登录角色，以及它对各成员角色的 `GRANT`（由 `make db-init` 建立）。
- **Shell declaration**：列出 `shell.members`。
- **AGENTS.md 的 Code map**：`main.go`、`go.mod`、`Dockerfile`、`component.yaml`。
- **Pitfalls**：Registry 与 `shell.members` 不一致时启动会失败；零成员是合法状态。

运行：

```bash
for n in go-core go-infra go-backoffice py-render; do (cd shell/be/$n && brickkit lint --strict) ; done
```

期望：零警告。如果某条文档警告的含义看不懂、需要去翻 brickKit 仓库，记一条 V-04。

- [ ] **Step 8: 加入项目、构建、零成员启动**

```bash
make up                       # 基础资源（postgres/nats/...）
for n in go-core go-infra go-backoffice py-render; do brickkit add be/$n --yes; done   # 逐个显式加：--local 会扫到 components/ 下的旧 manifest
cat brickkit.yaml deploy.yaml; ls config/
```

为 4 个外壳填写 `config/be-<name>.yaml`：

```yaml
PG_HOST: $var:PG_HOST
PG_PORT: $var:PG_PORT
PG_DATABASE: $var:PG_DATABASE
PG_USER: shell_go_core          # 外壳登录角色，与 be-ops db-script 一致
PG_PASSWORD: ${SHELL_GO_CORE_PASSWORD}
NATS_URL: $var:NATS_URL
AUTHZ_BUNDLE_URL: $var:AUTHZ_BUNDLE_URL
IAM_JWKS_URL: $var:IAM_JWKS_URL
```

```bash
grep -n "shell_go_core\|SHELL_GO_CORE" tools/be-ops/internal/dbscript/gen.go .env 2>/dev/null | head   # 核对角色名与密码变量名
brickkit build 2>&1 | tail -20
brickkit up 2>&1 | tail -30
brickkit status
for p in 8090 8224 8116 8402; do curl -fsS -o /dev/null -w "%{http_code} $p\n" http://localhost:$p/healthz || echo "fail $p"; done
```

期望：4 个外壳的镜像都带 `io.brickkit.build=local` 标签；`up` 没有报 `IMAGE_*` 错误；4 个外壳都 healthy。如果 `curl` 不通是因为端口没暴露到宿主机，就改为在 `deploy.yaml` 中给外壳加 `expose: true` 和 `exposePort`，或者用 `docker exec` 进容器检查，并在记录中写明。

整个过程按 spec §10 写入 `dev/test-records/06a/task8-shells-zero-members.md`，包括 V-03 的结论（单外壳单目录布局下，`build` 是否顺利）。

```bash
brickkit down
```

- [ ] **Step 9: 退役旧外壳 submodule**

```bash
git submodule deinit -f shells/go shells/python
git rm -q shells/go shells/python
git rm -q shells/README.md 2>/dev/null || true
rm -rf .git/modules/shells
git status --short | head
```

- [ ] **Step 10: 提交**

提交信息第一行：`feat(shell): 4 个外壳按 v1 重建为项目代码（零成员），退役 shells/go 与 shells/python`

---

### Task 9: be-ops v0.2.0

**Files（仓库 `tools/be-ops`）:**
- Delete: `internal/genyaml/`；`cmd/be-ops/main.go` 中的 `gen` 子命令、`runGen` 及其帮助文本
- Modify: `internal/registry/check.go`（如有对 `_shell-` 行与新外壳 ID 的假设，同步修改）
- Modify: `internal/dbscript/gen.go`（外壳登录角色名与 `be/<name>` 外壳一一对应）
- Modify: `README.md`

**Interfaces:**
- Produces: `be-ops registry`、`be-ops db-script`、`be-ops permissions`、`be-ops data-scopes` 照旧可用；`be-ops gen` 已删除（由 `brickkit add` 取代）。

- [ ] **Step 1: 删除 genyaml，运行测试**

```bash
cd tools/be-ops
git rm -r -q internal/genyaml
grep -n "gen\b\|runGen\|genyaml" cmd/be-ops/*.go
```

删除 `subcommands` 表中的 `"gen"` 项、`case "gen":` 分支以及 `runGen` 函数。

```bash
go build ./... && go test ./...
```

- [ ] **Step 2: 写失败测试：外壳登录角色**

```bash
sed -n 1,140p internal/dbscript/gen.go
grep -n "shell" internal/dbscript/gen_test.go | head
```

在 `gen_test.go` 中追加用例：输入的 Row 包含 `_shell-go-core` 这一行时，输出包含 `CREATE ROLE shell_go_core LOGIN`，并且对 go-core 的每个目标成员角色都有 `GRANT <成员角色> TO shell_go_core`。

成员清单如何传入 `Gen`，以现有实现为准。如果现在是硬编码的，改为从各外壳的 `shell/be/<name>/component.yaml` 的 `shell.members` 读取（06a 时为空，只建登录角色；06b 加入成员后 GRANT 会自动出现）。

- [ ] **Step 3: 实现并通过测试**

```bash
go test ./internal/dbscript/ -v 2>&1 | tail -15
```

- [ ] **Step 4: 端到端：生成建库脚本并执行**

```bash
cd ../.. && make db-init 2>&1 | tail -10
```

期望：成功；`psql` 中能看到 4 个外壳登录角色。

- [ ] **Step 5: README 与发布**

README 删去 `gen` 相关内容，说明 `brickkit.yaml` / `deploy.yaml` / `config/` 由 `brickkit add` 维护。

```bash
cd tools/be-ops && git add -A && git commit -F <msg> && git log --oneline -1
git tag -a v0.2.0 -F <notes> && git push origin HEAD --follow-tags
cd ../.. && git add tools/be-ops && git commit -F <msg>
```

---

### Task 10: be-acceptance v0.4.0

**Files（仓库 `tools/be-acceptance`）:**
- Keep: `gates/{importscan,systemclientscan,bareginscan,eventsbreaking,datascopetestscan}.go`
- Decide by experiment: `gates/dependencyversionscan.go`、`versionbump/`
- Delete: `platform/`（v0.4 的平台断言；06f 按 v1 重写）
- Modify: `closedloop/tier0_test.go`（拆回改用 `brickkit up --ignore-shells`，删除对 `patch-teardown-bindings.py` 的调用）
- Record: `dev/test-records/06a/task10-version-checks-experiment.md`（父仓库）

**Interfaces:**
- Produces: `be-acceptance gates`（保留的 gate）；`be-acceptance bump-version`（按实验结论保留或缩减）。

- [ ] **Step 1: 实验——v1 本身能拦住哪些版本漂移**

在 scratchpad 里用 `brickkit new` 造两个组件 `t/a`、`t/b`（b 依赖 `t/a@0.1.0`），然后依次制造以下三种漂移，每次都跑 `brickkit lint` 和 `brickkit up --dry-run`，把完整输出存下来：
1. a 升到 0.2.0，b 仍依赖 0.1.0；
2. `brickkit.yaml` 中 a 的版本与 `component.yaml` 不一致；
3. 外壳 `shell.members` 写的是 `t/a@0.1.0`，而项目中 a 是 0.2.0。

```bash
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/1c264f6e-aaa4-4367-bc16-6601a194d7e7/scratchpad/ver-exp
rm -rf $S && mkdir -p $S && cd $S && brickkit init --yes --name verexp
brickkit new t/a && brickkit new t/b
# 编辑 components/t/b/component.yaml：dependencies.components: [t/a@0.1.0]
brickkit add --local --yes && brickkit lint; brickkit up --dry-run 2>&1 | tail -20
# 漂移 1：把 components/t/a/component.yaml 的 version 改为 0.2.0
brickkit lint 2>&1 | tail -20; brickkit up --dry-run 2>&1 | tail -20
```

逐条记录：v1 有没有报错、错误码是什么、提示是否告诉人下一步该做什么。

- [ ] **Step 2: 按实验结论决定**

| 实验结果 | 决定 |
|---|---|
| 漂移 1、2、3 都被 `lint` 或 `up --dry-run` 拦下 | 删除 `dependency-version-scan` gate；`make gates` 改为同时跑 `brickkit up --dry-run`（零启动成本） |
| 部分被拦下 | gate 只保留 v1 拦不住的那几类，删除其余检查代码及对应测试 |
| `bump-version` 中"改 `brickkit.yaml` 版本号、改 `config:` 主机名字面量、改 AGENTS 名册"这三项 | 删除：分别由 `brickkit upgrade`、`$var:` 和 CLI 维护块取代 |
| `bump-version` 中"改下游组件 `component.yaml` 的依赖版本、改外壳 `shell.members`、改外壳 `go.mod`" | 保留并改为 v1 路径：外壳在 `shell/be/<name>/`，`go.mod` 的 require 写 `/v2` 模块路径 |

把决定写进实验记录的"结论"一节。

- [ ] **Step 3: 按决定修改代码，先改测试**

被保留部分的测试 fixture 全部换成 v1 布局（`shell/be/<name>/component.yaml` 的 `shell.members`；组件的 `dependencies.components` 写 `id@2.0.0`）。

```bash
cd tools/be-acceptance && go test ./gates/ ./versionbump/ 2>&1 | tail -20
```

先让测试按新 fixture 失败，再改实现直到通过。

- [ ] **Step 4: 删除 `platform/`，修改 `closedloop/tier0_test.go`**

```bash
git rm -r -q platform
grep -n "ignore-served-by\|patch-teardown\|servedBy\|local: true" closedloop/*.go
```

把 `--ignore-served-by` 换成 `--ignore-shells`，并删除修改 `brickkit.yaml` 的步骤。

```bash
go vet ./... && go test ./... 2>&1 | tail -10
```

- [ ] **Step 5: 发布**

```bash
git add -A && git commit -F <msg> && git log --oneline -1
git tag -a v0.4.0 -F <notes> && git push origin HEAD --follow-tags
cd ../.. && git add tools/be-acceptance dev/test-records/06a && git commit -F <msg>
```

---

### Task 11: Makefile 与 `infra/scripts` 按 v1 重写

**Files:**
- Delete: `infra/scripts/patch-teardown-bindings.py`、`infra/scripts/arsenal.sh`、`infra/scripts/weekly-teardown-gate.sh`、`infra/scripts/docs-check.sh`
- Create: `deploy.teardown.yaml`
- Modify: `Makefile`、`infra/scripts/lib/seed-net.sh`、`infra/scripts/test-cross.sh`、`infra/scripts/version-check.sh`、`infra/scripts/optional.sh`

**Interfaces:**
- Produces（make 目标）:
  - `teardown-up`：`brickkit up -f deploy.teardown.yaml --ignore-shells`
  - `teardown-down`：`brickkit down -f deploy.teardown.yaml`
  - `docs-check ID=<scope>/<name>`：`cd components/<ID> && brickkit lint --strict`（参数从旧的 REPO= 改为 ID=）
  - `lint`：`brickkit lint --strict`
  - 删除：`arsenal-check`、`arsenal-restore`（由 `brickkit restore` 与 pre-commit 取代）
- Produces（脚本）: `seed-net.sh` 与 `test-cross.sh` 读取 `.brickkit/generated/compose.yaml`。

- [ ] **Step 1: 列出所有引用**

```bash
grep -n "arsenal\|teardown\|ignore-served-by\|docker-compose.yaml\|docs-check\|servedBy\|resources\[\]\|\.archived" Makefile infra/scripts/*.sh infra/scripts/lib/*.sh
```

- [ ] **Step 2: `deploy.teardown.yaml`**

```yaml
# 拆回验证专用部署文件：配合 --ignore-shells 使用，所有成员都按独立组件部署。
# authz / iam 的地址从外壳服务名换成它们自己的服务名（06b 两者发布 2.0.0 后核对）。
target: docker
vars:
  AUTHZ_BUNDLE_URL: http://infra-authz-2-0-0:8223/authz/bundle
  IAM_JWKS_URL: http://infra-iam-casdoor-2-0-0:8200/.well-known/jwks.json
components: []
```

`components:` 的条目由 06b 中各组件 `brickkit add` 之后再补齐（每个组件 `expose: true`，便于 tier0 从宿主机 curl）。06a 先不填。

- [ ] **Step 3: 改 Makefile**

把 `arsenal-check`、`arsenal-restore`、`teardown-up`、`teardown-down`、`docs-check` 五个目标整体替换为：

```makefile
lint:  ## brickKit 自身的三层 + 文档检查（严格模式）
	@brickkit lint --strict

docs-check:  ## 检查某个组件的四件套：make docs-check ID=mdm/customer
	@test -n "$(ID)" || (echo "用法：make docs-check ID=<scope>/<name>"; exit 2)
	@cd components/$(ID) && brickkit lint --strict

teardown-up:  ## 拆回验证：所有成员按独立组件部署（--ignore-shells + deploy.teardown.yaml）
	@brickkit up -f deploy.teardown.yaml --ignore-shells

teardown-down:  ## 停掉拆回验证的容器
	@brickkit down -f deploy.teardown.yaml
```

然后删除文件：

```bash
git rm -q infra/scripts/patch-teardown-bindings.py infra/scripts/arsenal.sh infra/scripts/weekly-teardown-gate.sh infra/scripts/docs-check.sh
```

- [ ] **Step 4: 改 `seed-net.sh` 与 `test-cross.sh`**

```bash
sed -n 1,149p infra/scripts/lib/seed-net.sh
sed -n 1,90p infra/scripts/test-cross.sh
```

修改规则：
1. 读组件版本：从 `brickkit.yaml` 的 `components[]` 读，v1 的格式是 `- id: x` 下一行跟 `version:`，与旧格式相同，awk 逻辑可以沿用，但要加一个测试：用 v1 的 `brickkit.yaml` 片段跑一遍。
2. 生成目录：`.brickkit/generated/docker-compose.yaml` → `.brickkit/generated/compose.yaml`。
3. 服务寻址：成员在外壳内时，目标主机名是外壳服务名。改为从 `brickkit up --dry-run` 的输出（或 `compose.yaml`）中查出组件实际所在的服务，不再自己按规则拼接。
4. 网络名：`brickkit-<project>-net` 不变。

验证：

```bash
bash -n infra/scripts/lib/seed-net.sh infra/scripts/test-cross.sh
source infra/scripts/lib/seed-net.sh && component_version be/go-core   # 期望输出 1.0.0
```

- [ ] **Step 5: `version-check.sh` 与 `optional.sh`**

`version-check.sh`：tag 比较同时兼容 `2.0.0` 与 `v2.0.0` 两种格式（V-06 的双 tag）；外壳的 tag 是父仓库中的 `be-<name>/<ver>`，改为在父仓库里查。`optional.sh` 第 41 行附近关于 `resources[].engine` 的注释和逻辑，改为指向 `config/vars.yaml`。

```bash
bash infra/scripts/version-check.sh 2>&1 | tail -20
```

期望能跑完。旧组件版本落后于 tag 之类的报警可以出现，那是 06b 要处理的。

- [ ] **Step 6: 验证与提交**

```bash
make help | head -50
make lint 2>&1 | tail -5         # 预期只因 components/ 下的旧 manifest 报错
make docs-boundary && make registry-check
```

提交信息第一行：`refactor(make): Makefile 与 infra/scripts 按 brickKit v1 重写，删除 v0.4 专用脚本`

---

### Task 12: `docs/decisions/` 大决策

**Files:**
- Create: `docs/decisions/README.md`（+ `.zh.md`）——编号规则与索引表
- Create: `docs/decisions/NNNN-<slug>.md`（+ `.zh.md`），15–25 条

**Interfaces:**
- Produces: 决策编号（0001 起，编号一经分配不重排）；项目 `AGENTS.md` 的"查找路由"和 06d 的题库会按编号引用。

- [ ] **Step 1: 筛选决策**

从以下来源挑选"约束未来改动"的决策：
- `archive/pre-v1/AGENTS.md` 中"不要提议"那张表；
- `archive/pre-v1/BrickEnterprise 设计书.md` 中的"决策 N"；
- 设计书 §13.3 的铁律。

筛选标准：将来有人提需求时可能撞上它，而且推翻它需要人来拍板。

候选清单（执行时逐条核对原文，确认在 v1 下仍然成立）：
1. 组件之间禁止 import，仅有两类白名单（SDK、生成的契约包）
2. 每个组件独立 schema，迁移状态表放在自己的 schema 里
3. 技术栈逐格锁定（Go = Gin + pgx + golang-migrate；Python = FastAPI + asyncpg + yoyo；不用 ORM）
4. 不引入 Redis
5. 权限采用 OPA 式本地 PDP（bundle 拉进内存 map），组件不持有权限表
6. JWT 只承载身份，不携带权限键
7. 权限是纯并集，没有 Deny
8. 数据范围随版本发布，不做运行时可配置界面
9. 数据范围不用 PostgreSQL RLS，不做通用记录共享引擎
10. 金额字段一律用字符串编码的十进制；`List` 接口不接受 offset
11. 契约只做加法（proto 与事件）
12. 多种合理实现并存时，是新增槽位族的信号，而不是加配置开关
13. 前端技术栈：Vue 3；PC 用 AntDV + vxe-table；移动端用 wot-design-uni；两端只共享设计令牌
14. 第三方 UI 组件只能出现在 ui-kit 中
15. PC 骨架采用 AWS 控制台式两层导航 + 应用内标签页
16. 用户偏好只有四项（收藏、亮/暗、密度、语言）
17. 设计令牌是运行时 CSS 变量
18. 不用 Java / C#
19. 事件总线、对象存储、网关、可观测性不包装成组件
20. 测试账号不写进迁移；首个管理员通过 `bootstrapAdminSub` 配置
21. authz / iam 地址走共享变量，不走依赖边（本阶段新定）
22. 外壳是项目代码，一个外壳对应一个镜像（本阶段新定）

- [ ] **Step 2: 写每一条决策**

每个文件的结构（英文主文件，`.zh.md` 逐节对应，首行放语言互链）：

```markdown
[English](0004-no-redis.md) · [中文](0004-no-redis.zh.md)

# 0004 No Redis

## Decision
<!-- 一句话结论 -->

## Why
<!-- 两三句理由；不写讨论过程，不写"阶段 N 发现" -->

## What this rules out
<!-- 会被这条决策挡下的典型需求，用请求者会搜索的词写 -->

## Revisit only if
<!-- 什么条件下值得重新讨论 -->
```

提交前所有 `<!-- -->` 注释必须换成正文。

- [ ] **Step 3: 写索引 `docs/decisions/README.md`（+ `.zh.md`）**

索引表格式为 `| No. | Decision | Rules out |`。另写一句规则：编号一经分配不重排；被推翻的决策在原文件顶部标注 `Superseded by NNNN`，文件保留。

- [ ] **Step 4: 验证并提交**

```bash
make docs-boundary
for f in docs/decisions/*[0-9]-*.md; do case $f in *.zh.md) continue;; esac; z=${f%.md}.zh.md; test -f $z || echo "缺译本 $z"; [ "$(grep -c '^## ' $f)" = "$(grep -c '^## ' $z)" ] || echo "章节数不一致 $f"; done
grep -rn "<!--\|阶段[一二三四五]\|Phase [1-5]\|v0\.4" docs/decisions/ && echo "有残留" || echo ok
```

提交信息第一行：`docs(decisions): 约束未来改动的 N 条大决策（结论 + 理由 + 挡下什么）`

---

### Task 13: `docs/conventions/` 其余约定

**Files（每个都配 `.zh.md`）:**
- Create: `docs/conventions/README.md`（索引）
- Create: `docs/conventions/development-workflow.md`（由总纲 SOP-W 改写：七步循环、红绿节奏、一次会话做多少、版本号规则含 V-06 的双 tag）
- Create: `docs/conventions/testing.md`（由 `archive/pre-v1/docs/standards/en/04-testing-standard.md` 改写：L1–L4 判据、三种运行粒度、卡住时的三条出路与禁令、跨组件测试、前端 FE-1 到 FE-4）
- Create: `docs/conventions/data.md`（由 05-data-construction-standard 改写：测试库与演示库物理分离、种子数据归属与丰富度、缺数据先补依赖方）
- Create: `docs/conventions/documentation.md`（本项目的文档体系：正式区与开发区、语言规则、四件套、决策只收大决策、`docs-boundary`）
- Create: `docs/conventions/ai-development.md`（由 03 改写：模式取舍、文件和函数长度信号）
- Create: `docs/conventions/reference-implementations.md`（由 02 + 总纲 SOP-R 改写：三步法、R-2 参考项目表、槽位族信号）
- Create: `docs/conventions/backend.md`（模块入口契约 `module.New`、`rt` 是唯一入口、合并安全三问、健康检查禁令、`SystemClient` 限制、权限键注册方式）
- Create: `docs/conventions/registries.md`（`registry/` 四张表只追加；端口与 schema 的取用方法；`1xxxx` / `2xxxx` 端口段的划分）
- Create: `docs/seed-data.md`（由 `archive/pre-v1/docs/dev/种子数据一览.md` 改写）

**Interfaces:**
- Consumes: Task 3 的 `configuration.md`；Task 4–7 的 SDK API 名称（`rt.Config.Endpoint`、`besdk.PGDSN`、`shell.Main`）。
- Produces: 项目 `AGENTS.md` 的"项目约定"一节会逐条链接到这里。

- [ ] **Step 1: 逐份改写**

每份的规则如下：
- 只写结论。
- 删除阶段叙事、版本号历史、"踩坑过程"。
- 与 brickKit 09-patterns 重复的内容保留，但要以"本项目怎么做"的口吻来写。
- v1 下已经失效的规则直接删除，例如 `servedBy`、`local: true`、资源绑定、`STORAGE_ENDPOINT`、驼峰键、`labels` 合并冲突。
- 引用 SDK API 时用 Task 4–7 的新名字。

写之前先对每份旧文档列出"保留 / 改写 / 删除"三栏清单，存到 scratchpad，避免遗漏。

- [ ] **Step 2: 验证并提交**

```bash
make docs-boundary
grep -rln "servedBy\|local: true\|STORAGE_ENDPOINT\|dependencies.resources\|pgSchema\|authzBundleUrl\|阶段[一二三四五]" docs/ && echo "有残留" || echo ok
for f in $(ls docs/conventions/*.md docs/seed-data.md | grep -v '\.zh\.md$'); do z=${f%.md}.zh.md; test -f $z || echo "缺译本 $z"; done
```

提交信息第一行：`docs(conventions): 项目约定细则——由旧 standards 与总纲改写，只留 v1 下成立的结论`

---

### Task 14: 项目 `AGENTS.md`（+ `.zh.md`）与 `README.md`（+ `.zh.md`）

**Files:**
- Modify: `AGENTS.md`（Task 1 由 CLI 生成，保留末尾的维护块）
- Create: `AGENTS.zh.md`、`README.md`、`README.zh.md`

**Interfaces:**
- Consumes: Task 12、13 的文件路径与决策编号。
- Produces: 06d 题库中"期望阅读路径"的起点。

- [ ] **Step 1: 写 `AGENTS.md` 的四节（英文，维护块之上）**

开头一句沿用 CLI 骨架原句。接着加一段语言规则（原文保留旧 AGENTS.md 顶部的"文档语言 ≠ 对话语言"警示，并精简为 3 句）。然后：

- `## Overview`：项目是什么（ERP/CRM 组件库与标准组装模板，验证 brickKit）；九个领域；三类中枢组件；组件、外壳、工具三类仓库各自在哪；两条不可违背的原则（每个组件都是纯 brickKit 组件、能单独运行；合并只发生在部署层）。
- `## Conventions`：每条一行，加链接，覆盖 `docs/conventions/` 每份文件和 `config/vars.yaml` 规则；登记表只追加；版本与双 tag。
- `## Where to look`：表格 `| What you are doing (words you'd search for) | Read first |`，约 25 行。用请求者的说法写，比如"加一个接口 / 谁能调用它"→ `docs/conventions/backend.md#permissions`；"让表只显示某些行"→ ……；"想加缓存 / Redis"→ `docs/decisions/0004-no-redis.md`；"怎么部署 / 谁建数据库"→ `docs/ops/`（06e 前先写"见各组件 BRICKKIT.md 的 Before you deploy"）。最后一行照 CLI 骨架原句："not here? the component table below, then the component's AGENTS.md"。
- `## Pitfalls`：表格 `| Never | Symptom | Why |`，从旧"23 条易错"中挑出 v1 下仍然成立的条目（例如 `SET` 不带 `LOCAL`、组件互相 import、模块里读 `os.Getenv`、进程级初始化、`log.Fatal`、`/healthz` 查依赖、`FROM scratch`、`SystemClient` 用在用户请求路径上、改已发布的权限键、前端只查 features 不查 permissions、省略 `data_scopes`），再补上本阶段新增的条目（外壳 Registry 与 `shell.members` 不一致；`deploy.local.yaml` 被整份替换而不是合并；Go v2 模块路径）。

- [ ] **Step 2: 写 `AGENTS.zh.md`**

逐节对应英文版；末尾不放维护块（维护块只在主文件里）。首行放互链：`[English](AGENTS.md) · [中文](AGENTS.zh.md)`。英文主文件顶部也加同样一行。

- [ ] **Step 3: 写 `README.md` / `README.zh.md`**

给人看的入口：一句话介绍项目；快速开始（`make up`、`brickkit up`、`make seed-data`）；文档导航表（指向 `AGENTS.md`、`docs/conventions/`、`docs/decisions/`、`docs/ops/`）；仓库结构。

- [ ] **Step 4: 验证（含 V-02）**

```bash
brickkit lint 2>&1 | grep -E "AGENTS|CLAUDE|DOC_" | head -20
brickkit skills status
make docs-boundary
```

期望：项目层面没有 `DOC_*` 或 `AGENTS_BLOCK_MISSING` 警告。记录 lint 对 `AGENTS.zh.md` 的反应（无反应 / 警告 / 报错），写进 `to-verify.md` 的 V-02 结论栏；如果有警告，把原文贴进 `dev/test-records/06a/task14-agents-lint.md`。

- [ ] **Step 5: 提交**

提交信息第一行：`docs: 项目 AGENTS.md / README.md 按 brickKit v1 四节结构重写（含中文版）`

---

### Task 15: 项目 skill `version-bump-ship` 按 v1 重写

**Files:**
- Modify: `.claude/skills/version-bump-ship/SKILL.md`

**Interfaces:**
- Consumes: Task 10 的 `bump-version` 保留范围；V-06 的双 tag 规则。

- [ ] **Step 1: 读旧 skill，列出要改的地方**

```bash
cat .claude/skills/version-bump-ship/SKILL.md
```

- [ ] **Step 2: 重写**

保留原 skill 的整体链路（确认改动 → 传播版本号 → 逐组件测试、提交、tag、构建 → 更新组装仓库 → 真机验证），以及"何时停下来问人"那一段。逐处替换：
- 版本传播：下游 `component.yaml` 的依赖版本与外壳的 `shell.members` / `go.mod` 用 `make bump-version`（Task 10 缩减后的版本）；项目侧用 `brickkit upgrade <id>@<ver> --dry-run`，确认后再去掉 `--dry-run`。
- 发布：`brickkit release --notes-file <file>`，Go 组件再执行 `git tag -a v<ver> -m <同一份说明> && git push origin v<ver>`。
- 构建：`brickkit build <id>`，不推送镜像。
- 验证：`brickkit up --focus <id>`，再跑 `make test-cross`。
- 删除：所有 `servedBy`、`brickkit.yaml` 中的 `config:` 字面量同步、AGENTS 名册同步相关的步骤。

- [ ] **Step 3: 验证并提交**

```bash
grep -n "servedBy\|config: 字面量\|名册\|docker push" .claude/skills/version-bump-ship/SKILL.md && echo 有残留 || echo ok
```

提交信息第一行：`docs(skill): version-bump-ship 按 brickKit v1 重写（release/upgrade/build，Go 双 tag）`

---

### Task 16: 前端需求盘点

**Files:**
- Create: `dev/phase-06/frontend-needs.md`

**Interfaces:**
- Produces: 06b 各组件"需要补的接口"清单。06b 计划会按组件引用这份表。

- [ ] **Step 1: 盘点现有页面和接口**

```bash
cd components/frontend/standard
ls apps/pc/src/views apps/pc/src/pages 2>/dev/null; ls apps/mobile/src/pages
grep -rn "fetch\|request(\|api\." apps/pc/src --include=*.ts --include=*.vue | grep -o "/api/[a-zA-Z0-9/_{}:-]*" | sort -u
cd ../../..
for f in components/*/*/contracts/*.openapi.yaml; do echo "== $f"; grep -E "^  /" $f; done
```

- [ ] **Step 2: 写对照表**

`dev/phase-06/frontend-needs.md` 包含三张表：
1. `| 端 | 页面 | 操作 | 组件 | 接口（方法 路径）| 现状：已有 / 缺失 / 需改 |`：覆盖 spec §6 列出的全部页面和操作。
2. 按组件汇总的"06b 需要补的接口"：每个接口写清请求和响应字段的要点、需要的权限键（新键要追加到 `registry/permissions.tsv`）、数据范围维度。
3. 菜单：每个组件 `assembly.yaml` 中 `menus` 的现状，以及 06c 需要补的部分。

- [ ] **Step 3: 提交**

提交信息第一行：`docs(phase-06): 前端需求盘点——页面/操作 → 接口 → 现状，06b 按此补接口`

---

### Task 17: 单组件闭环清单

**Files:**
- Create: `dev/phase-06/component-loop.md`

**Interfaces:**
- Consumes: Task 3、4–7、12–15 的全部产出。
- Produces: 06b 每个组件执行时逐项勾选的清单。

- [ ] **Step 1: 写清单**

把 spec §5 的 9 步展开成可勾选的命令级清单。每一步都写出具体命令和判定标准：
- 第 2 步：`brickkit new <id> --path <scratch>/<repo>`，生成后用 `diff` 对照现有组件仓库的文件，决定哪些文件替换、哪些合并。
- 第 3 步：`component.yaml` 改写对照表，逐个列出旧键 → 新键，例如 `pgSchema` → `PG_SCHEMA`、`iamJwksUrl` → `IAM_JWKS_URL`、`authzBundleUrl` → `AUTHZ_BUNDLE_URL`、`otelBaseUrl` → `OTEL_BASE_URL`、`defaultWarehouseId` → `DEFAULT_WAREHOUSE_ID`，以及新增的 `PG_HOST`、`PG_PORT`、`PG_DATABASE`、`PG_USER`、`PG_PASSWORD`、`NATS_URL`。
- 第 4 步：代码迁移检查——`grep` 驼峰键名、`besdk.Endpoint(`、`StorageEndpoint`、`DATABASE_`；Go 组件的模块路径改为 `/v2`（`go mod edit -module`，再全仓库替换 import 路径）。
- 第 5 步：四件套的写作要点（不写历史、Owns / Does not own、Before you deploy 写建库与角色、Configuration 覆盖全部 required 键）。
- 第 6 步：`brickkit lint --strict` 零警告。
- 第 7 步：`brickkit add` 之后 `config/<id>.yaml` 的标准写法（引用 `$var:`），以及 `brickkit build`、`brickkit up --focus`、`make test-cross`。
- 第 8 步：`brickkit release --notes-file`，再为 Go 组件补打 `v` tag。
- 第 9 步：记录模板（spec §10）。

最后附上"停下汇报"条件：试点组件 mdm/customer 完成后；每个批次完成后；遇到需要用户拍板的情况（边界变化、破坏性契约变化、推翻已有决策）。

- [ ] **Step 2: 提交**

提交信息第一行：`docs(phase-06): 06b 单组件闭环清单`

---

### Task 18: AI 路由题库

**Files:**
- Create: `dev/routing-tests/README.md`（考法、评分规则、过关线）
- Create: `dev/routing-tests/questions.md`

**Interfaces:**
- Consumes: Task 12–14 的文件路径与决策编号。
- Produces: 06d 的考试输入。

- [ ] **Step 1: 写考法与评分（`README.md`）**

内容来自 spec §7：零上下文子 agent，只给项目路径；三档模型；路径、结论、答案三个维度；总分 ≥ 90%、冲突类 100%；禁止阅读的范围；作答时按顺序记录读过的文件。

- [ ] **Step 2: 写约 30 道题（`questions.md`）**

每题格式：

```markdown
### Q07 想给权限判定加一层 Redis 缓存，减少延迟
- 类别：与已有决策冲突
- 期望路径：AGENTS.md → Where to look「缓存 / Redis」→ docs/decisions/0004-no-redis.md
- 期望结论：Conflicts（停下来交给人，并引用 0004 的 Decision 与 Why）
- 标准答案要点：不引入 Redis；权限判定是进程内 map 查找，加 Redis 反而更慢；如确有性能问题，应先给出数据
- 禁止：读 archive/、dev/、组件源码
```

各类题量：只改一个组件 6、需要先改上游 5、需要新组件 4、与已有决策冲突 5、部署与配置 5、排障 3、外部使用者视角（只给一份 `BRICKKIT.md`）3。

出题的措辞要用请求者的说法，不要照抄文档标题，否则测不出路由能力。06b 尚未完成时，组件层面的期望路径先写到"该组件的 `BRICKKIT.md` 的哪一节"，06d 开考前再核对一遍文件是否真的存在。

- [ ] **Step 3: 提交**

提交信息第一行：`test(phase-06): AI 路由题库 30 题与评分规则`

---

### Task 19: 06a 收尾与检查点

**Files:**
- Create: `dev/phase-06/batches/06a.md`（06a 执行记录摘要）
- Modify: `dev/phase-06/to-verify.md`（V-02、V-03 结论；V-04 缺口记录）

- [ ] **Step 1: 全量检查**

```bash
cd /home/zhijie/Desktop/github/be-assembly-standard
make docs-boundary && make registry-check && make gates 2>&1 | tail -20
brickkit skills status
brickkit lint 2>&1 | grep -v "components/" | tail -20      # 除旧组件 manifest 外不应有错误
git submodule status | grep -E "tools/" ; for t in be-sdk-go be-sdk-python be-sdk-ts be-ops be-acceptance; do git -C tools/$t describe --tags; done
python3 -m pytest infra/scripts/tests -q
```

期望：5 个工具仓库分别位于 v0.3.0 / v0.4.0 / v0.4.0 / v0.2.0 / v0.4.0；其余检查全部通过。

- [ ] **Step 2: 写 `batches/06a.md`**

内容包括：每个 Task 的结果；偏离计划的地方及原因；新增的待验证项；知识缺口条数；给 06b 计划的输入（SDK 实际 API、外壳 ID 与服务名、`frontend-needs.md` 中按组件统计的缺口数）。

- [ ] **Step 3: 提交并停下汇报**

```bash
git add -A && git commit -F <msg> && git log --oneline -3
```

停下，向用户汇报 06a 结果，并请求开始编写 `plan-06b.md`。
