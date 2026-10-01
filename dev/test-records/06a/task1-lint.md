# Task 1 lint 记录

## 目标
归档 v0.4 时代文件，用 brickkit v1.0.0 CLI 重新生成项目骨架，并确认 `brickkit lint` 对三层文件（brickkit.yaml / deploy.yaml / AGENTS.md）无错误。

## 环境
brickkit CLI v1.0.0；工作区干净起步（HEAD 82d3570）；`core.hooksPath` 起始值为 `.githooks`（Step 1 时 `git config` 输出显示 `.githooks` 出现在 ls 之前的位置为空，复查后确认为 `.githooks`）。

## 步骤
1. git mv docs / 设计书 / AGENTS*.md / brickkit.yaml 到 archive/pre-v1/；`.brickkit` 取消跟踪并删除。
2. `brickkit init --yes --name be-assembly-standard`：创建 brickkit.yaml、deploy.yaml、config/vars.yaml、config/.gitkeep、shell/.gitkeep、AGENTS.md；就 .gitignore 缺条目给出警告（预期）。
3. `brickkit skills update --lang en` / `skills status`：5 个 skill 均 up to date。
4. 重写 .gitignore；`brickkit init --yes | grep -i gitignore` -> 无警告。
5. `brickkit init --hooks`：报 CONFIG_CONFLICT（外来 hook），按 brief 把 .githooks/pre-commit 整体替换；之后 CLI 仍判定为外来 hook（预期，因不是 brickkit 写的）。
6. `brickkit lint`，完整输出如下。

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
❌ Error: component.yaml failed validation
   File: components/crm/opportunity/component.yaml
   dependencies.resources: unknown field (line 84). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/erp/finance/component.yaml
   dependencies.resources: unknown field (line 96). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/erp/inventory/component.yaml
   dependencies.resources: unknown field (line 100). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/erp/sales/component.yaml
   dependencies.resources: unknown field (line 136). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/frontend/standard/component.yaml
   dependencies.resources: unknown field (line 13). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/infra/authz/component.yaml
   dependencies.resources: unknown field (line 54). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/infra/bff-mobile/component.yaml
   dependencies.resources: unknown field (line 76). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/infra/iam-casdoor/component.yaml
   dependencies.resources: unknown field (line 73). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/infra/notification/component.yaml
   dependencies.resources: unknown field (line 43). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/infra/print/component.yaml
   dependencies.resources: unknown field (line 35). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/infra/workflow/component.yaml
   dependencies.resources: unknown field (line 41). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/integration/im-dingtalk/component.yaml
   dependencies.resources: unknown field (line 55). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/mdm/customer/component.yaml
   dependencies.resources: unknown field (line 47). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
❌ Error: component.yaml failed validation
   File: components/mdm/product/component.yaml
   dependencies.resources: unknown field (line 52). Fields available at this level: components
   Suggestion: Full field reference: docs/en/11-reference/01-component-yaml-schema.md (swap en for zh for the Chinese version)
⚠️ BRICKKIT.md is missing
   File: components/crm/opportunity/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/crm/opportunity/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/crm/opportunity/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/crm/opportunity/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/crm/opportunity/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/crm/opportunity/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/crm/opportunity/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/crm/opportunity/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/crm/opportunity/README.md
⚠️ the "Development" (开发) section is missing
   File: components/crm/opportunity/README.md
⚠️ BRICKKIT.md is missing
   File: components/erp/finance/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/erp/finance/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/erp/finance/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/erp/finance/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/erp/finance/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/erp/finance/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/erp/finance/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/erp/finance/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/erp/finance/README.md
⚠️ the "Development" (开发) section is missing
   File: components/erp/finance/README.md
⚠️ BRICKKIT.md is missing
   File: components/erp/inventory/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/erp/inventory/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/erp/inventory/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/erp/inventory/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/erp/inventory/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/erp/inventory/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/erp/inventory/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/erp/inventory/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/erp/inventory/README.md
⚠️ the "Development" (开发) section is missing
   File: components/erp/inventory/README.md
⚠️ BRICKKIT.md is missing
   File: components/erp/sales/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/erp/sales/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/erp/sales/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/erp/sales/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/erp/sales/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/erp/sales/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/erp/sales/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/erp/sales/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/erp/sales/README.md
⚠️ the "Development" (开发) section is missing
   File: components/erp/sales/README.md
⚠️ BRICKKIT.md is missing
   File: components/frontend/standard/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/frontend/standard/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/frontend/standard/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/frontend/standard/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/frontend/standard/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/frontend/standard/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/frontend/standard/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/frontend/standard/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/frontend/standard/README.md
⚠️ the "Development" (开发) section is missing
   File: components/frontend/standard/README.md
⚠️ BRICKKIT.md is missing
   File: components/infra/authz/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/infra/authz/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/infra/authz/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/infra/authz/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/infra/authz/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/infra/authz/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/authz/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/infra/authz/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/infra/authz/README.md
⚠️ the "Development" (开发) section is missing
   File: components/infra/authz/README.md
⚠️ BRICKKIT.md is missing
   File: components/infra/bff-mobile/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/infra/bff-mobile/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/infra/bff-mobile/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/infra/bff-mobile/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/infra/bff-mobile/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/infra/bff-mobile/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/bff-mobile/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the link ../../../docs/design/infra-bff-mobile.md leaves the component directory: projects that use the component do not have that file
   File: components/infra/bff-mobile/README.md
   Line: 64
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/infra/bff-mobile/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/infra/bff-mobile/README.md
⚠️ the "Development" (开发) section is missing
   File: components/infra/bff-mobile/README.md
⚠️ BRICKKIT.md is missing
   File: components/infra/iam-casdoor/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/infra/iam-casdoor/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/infra/iam-casdoor/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/infra/iam-casdoor/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/infra/iam-casdoor/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/infra/iam-casdoor/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/iam-casdoor/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/infra/iam-casdoor/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/infra/iam-casdoor/README.md
⚠️ the "Development" (开发) section is missing
   File: components/infra/iam-casdoor/README.md
⚠️ BRICKKIT.md is missing
   File: components/infra/notification/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/infra/notification/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/infra/notification/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/infra/notification/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/infra/notification/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/infra/notification/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/notification/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/infra/notification/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/infra/notification/README.md
⚠️ the "Development" (开发) section is missing
   File: components/infra/notification/README.md
⚠️ BRICKKIT.md is missing
   File: components/infra/print/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/infra/print/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/infra/print/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/infra/print/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/infra/print/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/infra/print/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/print/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the link ../../../docs/design/infra-print.md leaves the component directory: projects that use the component do not have that file
   File: components/infra/print/README.md
   Line: 89
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/infra/print/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/infra/print/README.md
⚠️ the "Development" (开发) section is missing
   File: components/infra/print/README.md
⚠️ the link ../../../../docs/design/infra-print.md leaves the component directory: projects that use the component do not have that file
   File: components/infra/print/docs/手册.md
   Line: 70
⚠️ BRICKKIT.md is missing
   File: components/infra/workflow/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/infra/workflow/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/infra/workflow/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/infra/workflow/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/infra/workflow/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/infra/workflow/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/infra/workflow/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/infra/workflow/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/infra/workflow/README.md
⚠️ the "Development" (开发) section is missing
   File: components/infra/workflow/README.md
⚠️ BRICKKIT.md is missing
   File: components/integration/im-dingtalk/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/integration/im-dingtalk/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/integration/im-dingtalk/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/integration/im-dingtalk/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/integration/im-dingtalk/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/integration/im-dingtalk/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/integration/im-dingtalk/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/integration/im-dingtalk/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/integration/im-dingtalk/README.md
⚠️ the "Development" (开发) section is missing
   File: components/integration/im-dingtalk/README.md
⚠️ BRICKKIT.md is missing
   File: components/mdm/customer/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/mdm/customer/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/mdm/customer/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/mdm/customer/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/mdm/customer/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/mdm/customer/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/mdm/customer/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/mdm/customer/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/mdm/customer/README.md
⚠️ the "Development" (开发) section is missing
   File: components/mdm/customer/README.md
⚠️ BRICKKIT.md is missing
   File: components/mdm/product/BRICKKIT.md
⚠️ the "Code map" (代码地图) section is missing
   File: components/mdm/product/AGENTS.md
⚠️ the "Build and test" (构建与测试) section is missing
   File: components/mdm/product/AGENTS.md
⚠️ the "Design decisions" (设计取舍) section is missing
   File: components/mdm/product/AGENTS.md
⚠️ the "Pitfalls" (易错点) section is missing
   File: components/mdm/product/AGENTS.md
⚠️ the "Before changing code" (改代码前自查) section is missing
   File: components/mdm/product/AGENTS.md
⚠️ AGENTS.md has no usable block maintained by brickkit: there is no block maintained by brickkit
   File: components/mdm/product/AGENTS.md
   Suggestion: Run brickkit skills update to add it (an explicit request: no other command changes your file)
⚠️ the "Use it in a project" (在项目里使用) section is missing
   File: components/mdm/product/README.md
⚠️ the "Documentation" (文档) section is missing
   File: components/mdm/product/README.md
⚠️ the "Development" (开发) section is missing
   File: components/mdm/product/README.md

📋 Checked 32 files: 14 with errors, 147 warnings
❌ Error: the structure check did not pass
   Checked: 32 files
   With errors: 14 files
   Suggestion: Fix them at the locations listed above, then run brickkit lint again
{"time":"2026-10-01T21:31:08.238073724+02:00","level":"ERROR","message":"Command failed","command":"brickkit lint","elapsed_ms":69,"error_code":"LINT_FAILED","error":"LINT_FAILED: Error: the structure check did not pass; Checked=32 files; With errors=14 files","exit_code":1}
```

## 现象
- brickkit.yaml、deploy.yaml、cross-file 均通过。
- AGENTS.md 有 4 条 `placeholder (TODO)` 警告（第 7/11/15/19 行）：CLI 生成的模板里留了待填项，属于后续任务填写，非错误。
- 14 个 components/*/*/component.yaml 报旧格式错误（`dependencies.resources: unknown field`），预期的过渡性报错，由后续任务迁移。
- `skills update` 之后 `.brickkit/`（artifacts/generated/manifests）又被重新创建了；已被新 .gitignore 忽略，未提交。
- skills 里多出 `brickkit-plan-change`（v1 新增）。

## 卡点与绕过
`init --hooks` 无法接管外来 hook；按 brief 手工替换 .githooks/pre-commit 内容，与 CLI 打印的片段第一条命令（restore --check）等价（用裸 `brickkit` 而非绝对路径）。

## 结论
三层文件无错误，lint 错误仅来自旧格式组件清单；符合预期。

## 反馈候选
- `brickkit init --hooks` 在 hook 已手工包含 `restore --check` 时仍报 CONFIG_CONFLICT，可考虑识别"已含 restore --check"为已安装。
- init 生成的 AGENTS.md 带 TODO 占位，lint 以警告提示（可能是设计如此）。
