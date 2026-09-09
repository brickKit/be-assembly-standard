# infra-print · 打印渲染中心 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `infra/print` |
| 仓库名 | `infra-print` |
| 端口 | HTTP `8400` / gRPC `9400` ← 抄 `registry/ports.tsv` |
| schema / role | `infra_print` / `infra_print_rw`（归档 `infra_print_archive`） |
| 语言 | **Python**（全系统第一个） |
| 框架栈 | **FastAPI + uvicorn + `grpc.aio` + `asyncpg` + `yoyo-migrations`**（设计书 §12.4，逐格抄，不许自选） |
| 合并部署时进 | **外壳五 `py-render`** |
| 装配角色 | `default` |
| 阶段 | 第三阶段 |

> 规范源是设计书 **§6.11**。
> ⚠️ **选它进阶段三切片的理由不是业务，是阶段四要靠它验 Python 外壳**（§9.6.1 档 3）——所以本组件的
> 价值有一半在"证明 `be-sdk-python` 与 Python 外壳形态成立"，业务上只要能渲染出送货单就够了。

## 1. 边界

**归我：**

- **模板的存储与版本管理**：上传、预览、回滚（§6.11 明确要求）。
- **渲染**：`template_id` + 数据（JSON）→ PDF 字节流 或 打印机指令流。
- **两条完全不同的渲染路径**：HTML→PDF（A4 单据）与 模板→ZPL（斑马条码标签），见 §3.2。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| **"要不要打印"、"什么时候打印"** | 业务组件 | §6.11 原文点名：**严禁包含任何业务逻辑**（如"订单金额大于 10 万才打印"）。我收到请求就渲染 |
| **数据从哪来** | 业务组件 | 它把渲染所需的 JSON 整个传给我。**我不查任何业务库**——我连它是不是一张真订单都不知道 |
| 打印机、驱动、纸张 | 客户端 / 前端 | 我产出字节流，谁把它送到打印机不归我 |
| 文件的长期存储 | `infra-storage` / `infra-attachment`（阶段五） | 本阶段直接返回字节流，不落盘（§9 第 2 条） |

**`data_scopes: none`** ——模板是全局资产（一个客户就一套送货单模板），不做行级过滤。⚠️ **但渲染出来的
内容里有业务数据**，所以访问控制靠**调用方**：业务组件在自己那边判完权限才来调我。

### 1.1 ⚠️ 本组件是"纯函数"，这一点决定了很多设计

同样的 `template_id` + 同样的数据 = 同样的输出。由此：

| 推论 | 说明 |
|---|---|
| **不需要 `idempotency_key`** | 全系统写命令都要幂等键（§4.4.2），**我是唯一的例外**——重复调用没有副作用，重算一遍就是了 |
| 不需要 Outbox 参与业务事务 | 我不改任何业务状态 |
| 可以随便重试 | 调用方超时了直接重发，不用先查状态（没有"薛定谔的超时"问题） |
| 容易横向扩展 | 无状态（模板是只读缓存），K8s 下可以多副本 |

⚠️ **写 `AGENTS.md` 时要点明这一条**——否则下一个人会照着别的组件的模板给我加一张 `command_idempotency` 表，而那张表在这里永远是空的。

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `print_templates` | 不分区 | — | 模板的**当前版本**：`template_id`、类型（`pdf`/`zpl`）、内容、`version`、启用状态 |
| `print_template_versions` | 不分区 | — | 历史版本，**只增不改**。回滚 = 把某个历史版本复制成新的当前版本，**不是删掉新版本** |
| `print_jobs` | `created_at` | 月 | 渲染记录：谁、什么时候、渲染了哪个模板、成功与否、耗时。**纯审计与排障，不存渲染结果** |

强制字段全部符合 §11.2.1。**没有 `command_idempotency`**（理由见 §1.1）。

**终态列表**：`print_jobs` 写入即终态；`print_template_versions` 写入即终态。

⚠️ **模板存数据库不存文件**：§6.11 要求"上传、预览、版本回滚"，都是运行时行为；而平台的 Manifest
**没有 volumes 字段**（§6.3），文件挂不进容器。**这两条加起来只剩数据库一条路。**

⚠️ **`print_jobs` 记录"谁打印了什么"是有审计价值的**——打印发票、打印含成本价的单据在 ERP 里都是敏感动作。
但**不存渲染出来的字节**（那是几百 KB × 每次打印），只存元数据。

## 3. 契约面

**gRPC（`infra.print.v1.PrintService`）：**

| rpc | 类型 | 幂等键 | 说明 |
|---|---|---|---|
| `Render` | 命令（**无副作用**） | **不需要**（§1.1） | `template_id` + `data`(JSON) → 字节流 + `content_type` |
| `BatchGetTemplates` | 读 | — | §3.8 强制的 `batchGet` |
| `ListTemplates` | 读 | — | 模板清单，给管理界面 |

**对外 REST 路径前缀：** `/infra/print/**`

| 路径 | 权限键 | 说明 |
|---|---|---|
| `POST /render` | `infra.print.render` | 前端直接要预览时用 |
| `GET /templates` / `GET /templates/{id}` | `infra.print.template.view` | 模板管理 |
| `PUT /templates/{id}` | `infra.print.template.edit` | 上传新版本 |
| `POST /templates/{id}/rollback` | `infra.print.template.edit` | 回滚到指定历史版本 |
| `POST /templates/{id}/preview` | `infra.print.template.view` | 用样例数据预览，**不写 `print_jobs`** |

⚠️ **返回的是字节流，注意 gRPC 的消息大小上限**（默认 4MB）。A4 送货单 PDF 通常 100KB 量级，够用；
但**批量打印 200 张标签**会撞上限。本阶段的对策是**调用方分批**，长期方案见 §9 第 2 条。

### 3.2 ⭐ 两条渲染路径，共用一个接口但内部完全不同

§6.11 要求同时支持 **A4 单据（PDF）** 和 **斑马打印机条码标签（ZPL 指令）**。这两件事**只有入口相同**：

| | A4 单据 | 条码标签 |
|---|---|---|
| 模板是什么 | HTML + CSS（Paged Media） | **ZPL 指令文本模板**（`^XA...^XZ`），不是 HTML |
| 渲染成什么 | PDF 字节流 | **纯文本指令**，直接喂给打印机 |
| 引擎 | WeasyPrint（§3.3） | 纯字符串模板替换，**不需要任何渲染引擎** |
| 出错长什么样 | 版式跑偏 | 打印机吐白纸或乱码 |

⚠️ **不许试图用"HTML → 图片 → ZPL"把两条路合成一条。** 那会让标签打印依赖整个 HTML 渲染栈，
而条码标签恰恰是**最不能出错、最需要精确到点**的东西（扫不出来的条码等于没打）。ZPL 就是为此设计的指令集，
直接生成它是正解。

### 3.3 ⭐ 渲染引擎必须是内部可替换接口——这条来自真实调研

**选定 WeasyPrint** 作为 HTML→PDF 的默认实现（纯 Python、pip 装完即用、镜像小，符合"客户本地单机部署"的形态）。

**但引擎本身必须藏在一个内部接口后面**，理由是调研发现的一个事实：

> **两家主流开源 ERP 的默认渲染引擎正在被换掉。** ERPNext/Frappe 与 Odoo 长期用 `wkhtmltopdf`，
> 而它**已经多年没有实质更新、跟不上现代 CSS（Flexbox/Grid/CSS 变量）**；ERPNext 已经在往
> **Chromium** 迁移（`print_designer` 从 v1.5.0 起可选 Chrome 引擎）。

**"渲染引擎会换"是被现实验证过的事，不是假设。** 所以：

```
业务代码只认这一个接口：   render(template, data) -> bytes
                              ├── WeasyPrintRenderer   ← 阶段三的默认实现
                              ├── ChromiumRenderer     ← 版式要求高时的 Fork 点
                              └── ZplRenderer          ← §3.2 的第二条路径
```

⚠️ **换引擎不该是"改 40 处调用"**，同 `be-sdk-*` 与 `ui-kit` 那条"第三方只出现在一个地方"的道理
（决策 111、§12.6.6）。这个接口本身要写进 `AGENTS.md` 的禁令：**业务代码里不许直接 import WeasyPrint**。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `infra.print.rendered.v1` | 旁路 | 一次渲染完成 | `template_id`、`actor`、来源单据引用、成功与否。**仅供 `infra-audit`（阶段五）** |

⚠️ **只有这一条，而且是旁路。** 打印本身不改变任何业务状态，没有下游需要靠它推进流程。

**消费：** **无。**

⚠️ 与 `infra-workflow` 同理：消费任何业务事件都意味着我要理解业务语义，而 §6.11 明令禁止。

## 5. 依赖

**强依赖**：无。
**弱依赖**：无。

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| **所有业务组件** | 数据由调用方**整个传进来**。我去回查等于同时违反"严禁业务逻辑"和"要认识业务库结构" |
| `infra-storage` / `infra-attachment` | 阶段五才有。本阶段直接返回字节流（§9 第 2 条） |
| `infra-authz` | 同所有组件：`authzBundleUrl` 配置项，不是依赖边 |

**零出边。**

**谁依赖我**（入边）：

| 谁 | 强/弱 | 调什么 |
|---|---|---|
| `erp-sales` | 强依赖（阶段三新增） | `Render`——打印送货单。⚠️ **这条边是本组件不能做成 slot 的原因**（§8） |
| 未来的 `erp-purchase`/`erp-inventory` 等 | 强依赖 | 打印采购单、拣货单、库存标签 |

## 6. 在同步图与三枢纽里的位置

**零出边，只有入边**——形态与 `erp-inventory`（物理命令枢纽）、`infra-workflow` 同类：被调用，自己不指向任何人，**不可能引入环**。

与 §1.4 的"CRM 与 ERP 零同步边"无关（我是 infra 层）。与三枢纽无业务关系。

⚠️ **我是阶段四的关键角色**：档 3 要把 14 个组件合成 2 个外壳，**Python 外壳里只有我一个模块**（§9.6.1）。
所以本组件的 `module.py` 入口签名、`be-sdk-python` 的 `Runtime` 形状对不对，**要到阶段四合外壳时才真正被验**——
本阶段先按 §12.5 的模块入口契约写对，别留"反正现在单跑没问题"的东西（§13.3 铁律七）。

⚠️ **本组件也是全项目第一个真的落地 `backend/app/http`/`backend/app/grpc` 目录约定的组件**（总纲 SOP-B、阶段三
Task 3 补记）——REST handler 放 `backend/app/http/`，这是 `make gates` 的 `SystemClient` 误用扫描与裸路由扫描
认的目录，写渲染接口的 handler 时直接落在这里，不要另起别的名字。

## 7. 分区与归档策略

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `print_templates` | 永远热 | 不归档 | — |
| `print_template_versions` | 永远热 | 不归档（模板历史要能一直回滚） | — |
| `print_jobs` | 最近 **3 个月** | 超过 3 个月的整月分区 | `infra_print_archive` |

⚠️ **`print_jobs` 要归档不要删**：它是"谁打印过发票"的审计线索，在合规场景下要求保留数年（§11.7 对
`infra-audit` 的口径）。**归档到冷 schema，不是清理掉。**

## 8. 参考实现

> 完整调研过程见 [`_调研记录/03-阶段三.md`](./_调研记录/03-阶段三.md) 的「infra-print」一节。
> ⚠️ 本组件的调研是**真查了的**（阶段三少数几处 🔍 转 ✅ 的），因为"市场上到底用 HTML 还是别的"直接决定 §3.3 的选型。

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| ERPNext / Frappe | 📋 开工前填 | Print Format（Jinja HTML 模板）+ PDF 生成后端 | ✅ **查证确认走 HTML 模板**；更值钱的是它**正在把 wkhtmltopdf 换成 Chromium** 这件事——直接推出了 §3.3"引擎必须可换"的结论 | GPL-3 | 借鉴逻辑 |
| Odoo | 📋 开工前填 | QWeb 报表 → wkhtmltopdf | ✅ 同样是 HTML 模板。**两家主流都用 HTML**，佐证 §6.11 的选择 | LGPL-3 | 借鉴逻辑 |
| OCA `report_py3o` / Tryton `relatorio` | — | ODT（LibreOffice）模板路线 | **第二流派的存在证明**：模板是 ODT，业务人员用 LibreOffice 所见即所得地改，不需要开发者。→ §8 末尾的 Fork 点 | AGPL-3 / GPL-3（**只读文档，不看源码**） | 借鉴实际应用 |
| WeasyPrint | 📋 开工前填 | Paged Media 支持范围、字体与 CJK 处理 | 选它做默认引擎。🔍 **开工前要核实中文字体在容器里怎么装**——这是纯 Python 方案最容易翻车的地方 | BSD-3 | 借鉴逻辑 |
| 斑马 ZPL II | — | 指令集手册 | §3.2 第二条路径。ZPL 是文本指令，**不经过任何渲染引擎** | 闭源规范 | 借鉴实际应用 |

**明确没有参考的**：JasperReports / BIRT 这类 **Java 报表引擎**。**不是没查，是语言栈不匹配**——引入它要么把
本组件改成 Java（违反 §12.4 逐格锁定的技术栈），要么起一个 Java 边车进程（合并部署时外壳五装不下）。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| ERPNext / Odoo | 默认引擎绑死 `wkhtmltopdf`，散落在调用点 | 它已停止维护、ERPNext 正在换。§3.3 把引擎藏在内部接口后 |
| 多数 ERP | 打印模块直接查业务库拿数据渲染 | §6.11 禁止。数据由调用方传入——这也是本组件能"纯函数"的前提（§1.1） |
| 常见做法 | 用 HTML→图片→标签打印机 | §3.2：条码扫不出来等于没打。ZPL 直出 |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

⭐ **有，两条，都判定为 Fork 点而不是 slot。**

| 分歧 | 现实中的分歧 | 判定 |
|---|---|---|
| **模板的形态** | **HTML**（ERPNext、Odoo）vs **ODT/LibreOffice**（Py3o、Tryton relatorio）。后者的卖点是**业务人员自己用 LibreOffice 改模板，不用开发者**——服务的是"没有 IT 团队的中小客户"这个真实画像 | ⭐ 真实分歧，**但不能做成 slot** |
| **渲染引擎** | WeasyPrint（轻）vs Chromium（版式保真但重）。ERPNext 正在从一个换到另一个 | 同上 |

**为什么不能做成 slot**（按 R-4 第 3 步）：`erp-sales` 等业务组件**对本组件建了强依赖边**（§5 的入边表）——
§5.11 硬约束明确"有我们的代码、且有组件依赖它 → 不允许做成 slot"。**落点是 `customer_fork`**，与阶段二那
9 条分歧、以及本阶段 `infra-workflow` 的审批路由完全一致（复盘 §4 第 5 条）。

**这也正面回答了"将来能不能实现 ODT 那一套"**：能，而且路径是清楚的——Fork 一份 `infra-print-odt`，
换掉 §3.3 那个内部接口的实现，**`Render` 的契约一个字不改**，调用方无感。两条 Fork 点已记进 `_可替换性地图.md`。

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | WeasyPrint 在容器里的中文字体怎么装？镜像要不要打进字体包（体积 vs 缺字变方框） | 阶段三 Task 10 实现时 | ✅ **真机实测过，比预想的更严重**：只装 `libpango`/`libcairo`/`libgdk-pixbuf` 不装字体时，中文 PDF 并不是"变方框"，而是嵌入 `DejaVu-Serif` 后 `pdftotext` 提取出来**乱码且重复**（如"测试送货单 Test测试送货单 Delivery测试送货单 Note"）。补 `fonts-noto-cjk` + `fontconfig` + `fc-cache -f` 之后完全正常（真容器 + `pdftotext` 双重验证）。残留细节：fontconfig 无 `lang` hint 时默认选 Noto CJK 的 **JP** 变体而非 **SC**，模板要显式写 `font-family: "Noto Sans CJK SC"` |
| 2 | 大批量渲染（如 200 张标签）撞 gRPC 4MB 上限怎么办 | 阶段五 `infra-storage` 建成后 | 📋 本阶段：**调用方分批**。长期：渲染结果落 `infra-storage`、只返回一个下载 URL |
| 3 | 模板里要不要支持"取数表达式"（如 `{{ order.total * 0.13 }}`）？ | 阶段三定契约时 | ⚠️ **实现时改判为完整 Jinja2，不是"纯变量替换"**——真实的送货单/发票需要 `{% for item in items %}` 循环，纯变量替换做不到这一点。"模板不许有业务逻辑"这条边界改用代码审查守，不用语法沙箱强制，同本项目"很多规则靠 review 而不是纯技术手段"的既有模式。这是实现阶段的判断，未回头找用户确认，写在 `backend/app/render/pdf.py` 的注释与 `infra-print` 的 `AGENTS.md` 里 |
| 4 | 本组件是全系统第一个 Python 组件，`be-sdk-python` 的哪些能力是它第一次真用？ | 阶段三 Task 1 与 Task 10 之间 | ✅ 真跑过：`Config`（camelCase 转换）、`with_tx`（模板版本写入、job+outbox 同事务）、`publish_outbox`/`start_outbox_pump`、`new_fastapi_app`（含中间件与 `/healthz`/`/metrics`）、`require_permission`/`scope_of`（真实 JWT + bundle 轮询）、`run_standalone`（真机跑通 gRPC+HTTP 双端口）。同时发现并修复了 `be-sdk-python` 自身四个模块（`otel.py`/`logging.py`/`metrics.py`/`outbox.py`）此前只是 `NotImplementedError` 占位——本组件是第一个真正触发这个缺口的 Python 组件，详见 `be-sdk-python@v0.3.0` 变更记录。**`besdk.consume` 本组件确实用不上**（不消费事件），它的 Python 版第一次真实调用仍要等别的组件 |
