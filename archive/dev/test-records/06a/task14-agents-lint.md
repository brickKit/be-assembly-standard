# Task 14 项目 AGENTS.md lint 记录（含 V-02）

## 目标
1. 确认项目 `AGENTS.md` 按 brickKit v1 四节结构写完后，项目层面没有 `DOC_*` / `AGENTS_BLOCK_MISSING` 警告。
2. V-02：弄清 `brickkit lint` 怎么对待 `AGENTS.zh.md`——项目层面与组件层面各一次。

## 环境
- brickkit CLI v1.0.1（`brickkit --version`：`BrickKit CLI v1.0.1`）
- 真实仓库：/home/zhijie/Desktop/github/be-assembly-standard，HEAD 43f8aa0 之上加本任务未提交的 AGENTS.md / AGENTS.zh.md / README.md / README.zh.md
- V-02 实验：scratchpad 里 `brickkit init proj --yes` + `brickkit new demo/widget` 生成的干净项目（不碰真实仓库）

## 步骤

### 1. 真实仓库：`brickkit lint 2>&1 | head -5`

```
✅ brickkit.yaml
✅ deploy.yaml
✅ cross-file: brickkit.yaml ↔ deploy.yaml ↔ config/
✅ ./ (docs)
❌ Error: component.yaml failed validation
```

`--strict` 同样：

```
✅ brickkit.yaml
✅ deploy.yaml
✅ cross-file: brickkit.yaml ↔ deploy.yaml ↔ config/
✅ ./ (docs)
❌ Error: component.yaml failed validation
```

`✅ ./ (docs)` 即项目层文档（AGENTS.md、CLAUDE.md）检查通过。之后的 ❌ 全部是 14 个旧组件的 `component.yaml`（`dependencies.resources` 未知字段），属 06b 迁移范围。

### 2. 真实仓库：`brickkit lint 2>&1 | grep -E "AGENTS|CLAUDE|DOC_|README"`（全量，142 行）

```
   File: components/crm/opportunity/AGENTS.md
   File: components/crm/opportunity/AGENTS.md
   File: components/crm/opportunity/AGENTS.md
   File: components/crm/opportunity/AGENTS.md
   File: components/crm/opportunity/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/crm/opportunity/AGENTS.md
   File: components/crm/opportunity/README.md
   File: components/crm/opportunity/README.md
   File: components/crm/opportunity/README.md
   File: components/erp/finance/AGENTS.md
   File: components/erp/finance/AGENTS.md
   File: components/erp/finance/AGENTS.md
   File: components/erp/finance/AGENTS.md
   File: components/erp/finance/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/erp/finance/AGENTS.md
   File: components/erp/finance/README.md
   File: components/erp/finance/README.md
   File: components/erp/finance/README.md
   File: components/erp/inventory/AGENTS.md
   File: components/erp/inventory/AGENTS.md
   File: components/erp/inventory/AGENTS.md
   File: components/erp/inventory/AGENTS.md
   File: components/erp/inventory/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/erp/inventory/AGENTS.md
   File: components/erp/inventory/README.md
   File: components/erp/inventory/README.md
   File: components/erp/inventory/README.md
   File: components/erp/sales/AGENTS.md
   File: components/erp/sales/AGENTS.md
   File: components/erp/sales/AGENTS.md
   File: components/erp/sales/AGENTS.md
   File: components/erp/sales/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/erp/sales/AGENTS.md
   File: components/erp/sales/README.md
   File: components/erp/sales/README.md
   File: components/erp/sales/README.md
   File: components/frontend/standard/AGENTS.md
   File: components/frontend/standard/AGENTS.md
   File: components/frontend/standard/AGENTS.md
   File: components/frontend/standard/AGENTS.md
   File: components/frontend/standard/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/frontend/standard/AGENTS.md
   File: components/frontend/standard/README.md
   File: components/frontend/standard/README.md
   File: components/frontend/standard/README.md
   File: components/infra/authz/AGENTS.md
   File: components/infra/authz/AGENTS.md
   File: components/infra/authz/AGENTS.md
   File: components/infra/authz/AGENTS.md
   File: components/infra/authz/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/authz/AGENTS.md
   File: components/infra/authz/README.md
   File: components/infra/authz/README.md
   File: components/infra/authz/README.md
   File: components/infra/bff-mobile/AGENTS.md
   File: components/infra/bff-mobile/AGENTS.md
   File: components/infra/bff-mobile/AGENTS.md
   File: components/infra/bff-mobile/AGENTS.md
   File: components/infra/bff-mobile/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/bff-mobile/AGENTS.md
   File: components/infra/bff-mobile/README.md
   File: components/infra/bff-mobile/README.md
   File: components/infra/bff-mobile/README.md
   File: components/infra/bff-mobile/README.md
   File: components/infra/iam-casdoor/AGENTS.md
   File: components/infra/iam-casdoor/AGENTS.md
   File: components/infra/iam-casdoor/AGENTS.md
   File: components/infra/iam-casdoor/AGENTS.md
   File: components/infra/iam-casdoor/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/iam-casdoor/AGENTS.md
   File: components/infra/iam-casdoor/README.md
   File: components/infra/iam-casdoor/README.md
   File: components/infra/iam-casdoor/README.md
   File: components/infra/notification/AGENTS.md
   File: components/infra/notification/AGENTS.md
   File: components/infra/notification/AGENTS.md
   File: components/infra/notification/AGENTS.md
   File: components/infra/notification/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/notification/AGENTS.md
   File: components/infra/notification/README.md
   File: components/infra/notification/README.md
   File: components/infra/notification/README.md
   File: components/infra/print/AGENTS.md
   File: components/infra/print/AGENTS.md
   File: components/infra/print/AGENTS.md
   File: components/infra/print/AGENTS.md
   File: components/infra/print/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/print/AGENTS.md
   File: components/infra/print/README.md
   File: components/infra/print/README.md
   File: components/infra/print/README.md
   File: components/infra/print/README.md
   File: components/infra/workflow/AGENTS.md
   File: components/infra/workflow/AGENTS.md
   File: components/infra/workflow/AGENTS.md
   File: components/infra/workflow/AGENTS.md
   File: components/infra/workflow/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/workflow/AGENTS.md
   File: components/infra/workflow/README.md
   File: components/infra/workflow/README.md
   File: components/infra/workflow/README.md
   File: components/integration/im-dingtalk/AGENTS.md
   File: components/integration/im-dingtalk/AGENTS.md
   File: components/integration/im-dingtalk/AGENTS.md
   File: components/integration/im-dingtalk/AGENTS.md
   File: components/integration/im-dingtalk/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/integration/im-dingtalk/AGENTS.md
   File: components/integration/im-dingtalk/README.md
   File: components/integration/im-dingtalk/README.md
   File: components/integration/im-dingtalk/README.md
   File: components/mdm/customer/AGENTS.md
   File: components/mdm/customer/AGENTS.md
   File: components/mdm/customer/AGENTS.md
   File: components/mdm/customer/AGENTS.md
   File: components/mdm/customer/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/mdm/customer/AGENTS.md
   File: components/mdm/customer/README.md
   File: components/mdm/customer/README.md
   File: components/mdm/customer/README.md
   File: components/mdm/product/AGENTS.md
   File: components/mdm/product/AGENTS.md
   File: components/mdm/product/AGENTS.md
   File: components/mdm/product/AGENTS.md
   File: components/mdm/product/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/mdm/product/AGENTS.md
   File: components/mdm/product/README.md
   File: components/mdm/product/README.md
   File: components/mdm/product/README.md
```

其中 14 条 `AGENTS.md has no usable block maintained by brickkit` 逐条核对过紧随其后的 `File:` 行，全部是 `components/*/AGENTS.md`（`brickkit lint 2>&1 | grep -A1 "no usable block" | grep -c "File: components"` → 14）。项目根的 `AGENTS.md` / `CLAUDE.md` / `README.md` 零条。

### 3. 真实仓库：`brickkit skills status`

```
Skill language: en (recorded in AGENTS.md, in the block maintained by brickkit; brickkit skills update --lang to change it)
   ┌───────────────────────────────────────────────┬────────────────────────────────────────────────┐
   │ File                                          │ Status                                         │
   ├───────────────────────────────────────────────┼────────────────────────────────────────────────┤
   │ .claude/skills/brickkit-assemble/SKILL.md     │ up to date                                     │
   │ .claude/skills/brickkit-component/SKILL.md    │ up to date                                     │
   │ .claude/skills/brickkit-deploy/SKILL.md       │ up to date                                     │
   │ .claude/skills/brickkit-plan-change/SKILL.md  │ up to date                                     │
   │ .claude/skills/brickkit-troubleshoot/SKILL.md │ outdated (v1.0.0 → v1.0.1)                     │
   │ AGENTS.md                                     │ block maintained by brickkit present (lang=en) │
   └───────────────────────────────────────────────┴────────────────────────────────────────────────┘

1 file needs refreshing: brickkit skills update
```

### 4. V-02 实验一：项目根与组件各放一份"故意写坏"的 `AGENTS.zh.md`

两份内容相同：首行互链、一个 `<!-- TODO: 占位 -->`、一个指向不存在文件的链接 `[坏链接](no-such-file.md)`、没有任何 `##` 小节。组件的 `AGENTS.md` 首行没有链 `AGENTS.zh.md`。`brickkit lint --strict` 全量输出：

```
✅ brickkit.yaml
✅ deploy.yaml
✅ cross-file: brickkit.yaml ↔ deploy.yaml ↔ config/
⚠️ a placeholder (TODO) is still in the text
   File: AGENTS.md
   Line: 7
⚠️ a placeholder (TODO) is still in the text
   File: AGENTS.md
   Line: 11
⚠️ a placeholder (TODO) is still in the text
   File: AGENTS.md
   Line: 15
⚠️ a placeholder (TODO) is still in the text
   File: AGENTS.md
   Line: 19
✅ components/demo/widget/component.yaml
⚠️ AGENTS.md does not link AGENTS.zh.md: a file with translations links every language version near the top
   File: components/demo/widget/AGENTS.md
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/AGENTS.md
   Line: 7
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/AGENTS.md
   Line: 11
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/AGENTS.md
   Line: 15
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/AGENTS.md
   Line: 19
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/AGENTS.md
   Line: 23
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/AGENTS.zh.md
   Line: 5
⚠️ the link no-such-file.md points at a file that does not exist
   File: components/demo/widget/AGENTS.zh.md
   Line: 7
⚠️ this translation has 0 sections, its primary AGENTS.md has 6
   File: components/demo/widget/AGENTS.zh.md
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/BRICKKIT.md
   Line: 5
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/BRICKKIT.md
   Line: 9
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/BRICKKIT.md
   Line: 13
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/BRICKKIT.md
   Line: 19
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/BRICKKIT.md
   Line: 23
⚠️ a placeholder (TODO) is still in the text
   File: components/demo/widget/README.md
   Line: 3

📋 Checked 6 files: 0 with errors, 19 warnings
❌ Error: the structure check did not pass
   Checked: 6 files
   Warnings: 19 (--strict: warnings count as failures)
   Suggestion: Fix them at the locations listed above, then run brickkit lint again
{"time":"2026-10-01T22:08:55.749236194+02:00","level":"ERROR","message":"Command failed","command":"brickkit lint","elapsed_ms":2,"error_code":"LINT_FAILED","error":"LINT_FAILED: Error: the structure check did not pass; Checked=6 files; Warnings=19 (--strict: warnings count as failures)","exit_code":1}
```

### 5. V-02 实验二：组件 `AGENTS.zh.md` 改成与 `AGENTS.md` 自己的 5 节一一对应（不含维护块），组件 `AGENTS.md` 首行补上互链

```
⚠️ this translation has 5 sections, its primary AGENTS.md has 6
   File: components/demo/widget/AGENTS.zh.md
```

组件 `AGENTS.md` 的 6 个 `##`：`Code map`、`Build and test`、`Design decisions`、`Pitfalls`、`Before changing code`，加维护块里的 `## BrickKit`。

### 6. V-02 实验三：在组件 `AGENTS.zh.md` 末尾再加一节 `## BrickKit`（一句"见英文版末尾的维护块"）

`brickkit lint --strict 2>&1 | grep -B1 -A2 "zh\|translation"` 无输出：关于 zh 的警告全部消失。

## 现象
- 项目根 `AGENTS.zh.md`：**完全不检查**。故意放的 TODO 与断链都没有警告，也不要求 `AGENTS.md` 链接它（实验一里项目层只有 `AGENTS.md` 骨架原有的 4 条 TODO）。项目根 `README.md` / `README.zh.md` 同样不在检查范围内。
- 组件 `AGENTS.zh.md`：**当作 `AGENTS.md` 的译文检查**，和 BRICKKIT/README 的译文一样：
  - `DOC_PLACEHOLDER`、`DOC_LINK_BROKEN` 照查；
  - 要求 `AGENTS.md` 顶部链接 `AGENTS.zh.md`（"a file with translations links every language version near the top"）；
  - `DOC_TRANSLATION_DRIFT` 比较 `##` 小节数时**把维护块里的 `## BrickKit` 也算进主文件**，所以不带维护块的译文永远差一节，必须补一个 `## BrickKit` 小节才能过 `--strict`。
- 真实仓库项目层面：零 `DOC_*`、零 `AGENTS_BLOCK_MISSING`；`make docs-boundary` 退出码 0；本文档链接与锚点自检（scratchpad 脚本按 GitHub 锚点规则解析）0 处失效。
- `skills status`：`brickkit-troubleshoot` 显示 outdated（v1.0.0 → v1.0.1），是 CLI 从 1.0.0 升到 1.0.1 引起的，与本任务无关，未执行 `skills update`。

## 卡点与绕过
无卡点。V-02 的组件一半用 scratchpad 里新生成的组件做，没有动真实组件仓库（真实组件的 AGENTS.md 要到 06b 才按 v1 重写）。

## 结论
- 项目层：`AGENTS.zh.md` 不被 lint 识别，中英文一致只能靠 `documentation.md` 的约定和人工/AI 自查。
- 组件层：`AGENTS.zh.md` 被当作译文检查，并且小节数要算上维护块的 `## BrickKit`。06b 写组件 `AGENTS.zh.md` 时末尾要放一节 `## BrickKit`（指向英文版维护块），否则 `make docs-check` 的 `--strict` 会报 `DOC_TRANSLATION_DRIFT`。
- brickkit-component skill 写的是"`AGENTS.md` is not translated"，而 lint 实际会检查组件的 `AGENTS.zh.md`——行为与 skill 措辞不一致。

## 反馈候选
1. skill 说 AGENTS.md 不翻译，lint 却把组件 `AGENTS.zh.md` 当译文检查；要么 skill 写明"可以翻译，翻译时规则是……"，要么 lint 不查。
2. 译文小节数把维护块的 `## BrickKit` 算进主文件，而维护块只存在于主文件，导致所有组件 `AGENTS.<lang>.md` 都得手写一个占位小节。建议计数时排除维护块里的小节。
3. 项目层与组件层对 `AGENTS.<lang>.md` 的处理不一致（前者完全不查）。
