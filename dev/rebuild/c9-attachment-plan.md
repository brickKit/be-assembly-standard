# C9：`infra/attachment` 的子计划

阶段“按依赖顺序重建其余组件”的第九个组件（[components-plan.md](components-plan.md) 的 C9）。数据与改坏检查放 `c9-data/`。维护者 2026-11-12 晚把夜里的决定都交给 AI（交接里的授权）：本计划的范围是 AI 定的，待复核。

## 依据与牵动

- 协议 12（附件与对象存储：属主与凭据、类别、记录与状态表、访问凭证、上传、扫描、下载、解除引用与保全、对账、参数、独立预期 FA01–FA35）；安全 09a 的 `AttachmentCategory`；协议 11（保留类别）、协议 01（工作项）、协议 03（审计）；决定 D53（经 SDK 的存储端口，不加转发组件）、D68（附件组件不调用业务组件）；边界卡 `infra.md#infraattachment`；指南 `guides/files-and-attachments.md`。
- 现在的状态（2026-11-13 读）：
  - 仓库 `brickKit/infra-attachment` 2026-11-12 新建（只有说明）；注册表端口 8204/9204、schema `infra_attachment`、外壳 go-infra。
  - **SDK 没有通用的存储端口**：事件的大载荷（`events/objectstore.go`）与冷热转层（`tiering/store.go`）各有一份对象存储代码，共用 `internal/s3sig`（SigV4 与预签名）；没有条件写入、服务端复制、带长度的预签名上传。
  - **资源定义里没有附件类别**：SDK 的 `authz.Resource` 没有 `AttachmentCategories`；`infra/authz` 提交时已认得 `attachment_categories`（EN22：类别的字段必须是资源的字段），但没有给附件组件读类别目录的系统方法。
  - 本机的对象存储是 RustFS（`be-rustfs`）；协议 12 的待定写着它对条件写入与服务端复制的支持要实测。

## P0 的结果：首批范围（AI 定，待复核）

| 项 | 首批 | 理由 |
| --- | --- | --- |
| 存储端口 | SDK 加 `storage` 包：属主自己的桶与前缀（`OBJECT_STORE_*`）上的放入（可带“不存在才写”）、读取（流式）、元数据、服务端复制（“不存在才写”）、预签名上传（签入确切长度与类型）、预签名下载（强制作为附件保存、文件名）、删除、列举；事件与转层的两份代码以后并过来 | D53；协议 12 的上传第 3 步要“先条件复制到最终键、再读最终对象检查” |
| RustFS 的条件写入与服务端复制 | SDK 的集成测试先实测；不支持时退回“读暂存、条件写最终键”（同样满足“检查的就是最终对象”），记下实测 | 协议 12 的待定 |
| 类别目录 | SDK 的资源定义加 `AttachmentCategories`（09a 的字段）；`infra/authz` 加系统方法“附件类别目录”（已接受的定义里每个资源类型的属主与类别，带修订），附件组件按修订缓存 | 协议 12：类别经授权组件的定义目录进入附件组件，新业务组件上线不改附件组件（FA26） |
| 附件组件 | 系统面（属主专用）：申请上传会话（新附件或替换）、申请下载（普通：预签名地址；严格：一次性凭证）、列出父记录的附件、解除引用、恢复、按擦除清除、保全与解除、保留起算；用户面：凭确认凭证确认上传、凭一次性凭证下载严格类别；状态表全实现；附件状态事件；工作项：确认超时、扫描、清理与对账 | 协议 12 的全部首批规则 |
| 扫描 | 扫描端口：首批实现“关闭”（标未扫描，开发与格）与一个测试用的假引擎（集成测试里能出干净、威胁、出错）；真实引擎（ClamAV）作为可选适配随客户要求 | 协议 12：开发环境默认关闭；引擎选择待定 |
| 第一个属主 | `erp/purchase` 的采购订单：类别 `contract_file`（合同原件，普通）与 `invoice_scan`（发票扫描件，严格）；订单的用户面加“附件”：申请上传、列表、申请下载、移除；订单作废时解除引用（工作项） | 有真实属主才验证得到凭证的协作；采购已有完整的单据与种子 |
| 属主的 SDK 帮手 | SDK 加 `attachments` 客户端（属主调附件组件系统面的薄封装、工作项里的命令） | 每个属主都要写同样的调用 |

## 任务

| # | 要做到什么 | 依赖 | 验收 | 状态 |
| --- | --- | --- | --- | --- |
| P0 | 读全依据，定首批范围 | — | 上面一节 | ✅ 2026-11-13（AI 定，待复核） |
| P1 | 设计：线协议的条款（存储端口的行为、附件类别在定义里、属主与附件组件的系统面）、附件组件的设计（规则编号）、授权组件的类别目录方法、采购的附件；考设计 | P0 | 文档与考试记录（`c9-data/exam-p1/`） | ✅ 2026-11-13：第 19 章草稿、AT01–AT14、授权组件与采购的设计；考设计一份 25 条全部处理（`c9-data/exam-p1/result.md`），附件的设计整份重写 |
| P2 | 契约：线协议（条款、向量、能力）；附件组件的 proto 与 OpenAPI、事件；授权组件契约加方法；采购的 OpenAPI | P1 | 校验；`make authz-keys-check` | ✅ 2026-11-13：线协议 alpha.127（第 19 章、`UPLOAD_INCOMPLETE`、`OBJECT_STORE_PUBLIC_URL`）；授权契约 alpha.7；附件契约 `contract/v3.0.0-alpha.1`（proto、OpenAPI、事件）；采购契约 alpha.8（四个附件路由） |
| P3 | SDK：`storage`（对 RustFS 的集成测试，实测条件写入与服务端复制）、资源定义的附件类别；先接真实组件再发（复盘 C7 的 R1）；全系统换 SDK | P2 | SDK 测试、改坏检查、发布 | ✅ 2026-11-13：be-sdk-go alpha.130 已发（`storage`、`s3sig.Presign`、`AttachmentCategories`、`httpx.Context.Download`、`UPLOAD_INCOMPLETE`）；改坏检查 9/9 红（`c9-data/mut-p3-sdk/`）；全系统换 SDK 在后台跑（`sdk-unify.py`，17 个组件） |
| P4 | `infra/authz`：附件类别目录的系统方法 | P3 | 集成测试、发布 | ✅ 2026-11-13：`infra/authz` 3.0.55 已发（集成测试 185 s 全过） |
| P5 | `infra/attachment`：状态表、凭证、上传确认（条件复制到最终键后检查）、扫描端口、下载、解除引用与保全、清理与对账、事件；先写红的测试 | P3、P4 | 集成测试（对 RustFS）、改坏检查、`make layout-check` | ✅ 2026-11-13：`infra/attachment` 3.0.0 发布，3.0.1 补了布局检查要的每层文件表（3.0.0 发布前没跑 `make layout-check`，复盘记一条）；改坏检查 13/16 红，2 处两道守卫、1 处要故障注入（`c9-data/mut-p5-attachment/`） |
| P6 | `erp/purchase`：订单的附件（类别、用户面、作废时解除引用）；种子：几张订单带合同附件 | P5 | 集成测试、发布 | ✅ 2026-11-13：`erp/purchase` 3.0.15（类别、操作 `read_invoice`、四个路由、订单结束的工作项；集成测试新步 `attachments` 用附件组件的替身，改坏检查 5/5 红）；3.0.16 补种子（`read_invoice` 授给维护与主管；CN01 六张订单各一份合同）——3.0.15 发布时漏了种子，复盘记一条 |
| P7 | 发布与连锁：外壳 `be/go-infra` 加成员；格的对象存储配置（浏览器可达的主机名）；L3（经预签名地址上传、确认、下载；凭证用错附件或别人用被拒；严格类别转发字节；作废后解除引用）；一致性考试 | P5、P6 | 格从空库到 L3；`make version-check`、`make gates` | 进行中：全系统 be-sdk-go alpha.130（17 个组件；采购因为标了“已单独发布”没跟依赖，3.0.17 补上，财务 3.0.17、付款 3.0.21 连锁）；探针 3.2.59、套件 v1.0.94；外壳 go-infra 3.0.92（加附件成员）、go-core 3.0.111；be-ops alpha.26、be-edge alpha.12；`make version-check` 通过；格 C9-A 待跑 |

## P1 的设计（草稿，AI 定）

- **线协议**：第 19 章“存储端口”（`tools/be-protocol/spec/19-storage-port.md`，P19.1–P19.10：键、元数据、条件放入、条件复制（不支持时退回读后条件放入）、读取与 `not_found`、带长度与类型的预签名上传、强制作为附件保存的预签名下载、删除与列举、错误分类、日志脱敏）；资源定义的 `attachment_categories` 已在安全记录的 schema 里，SDK 补上。
- **附件组件**：`components/infra/attachment/docs/design.md`（AT01–AT14）。
- **授权组件**：系统方法 `AttachmentCategories`（只给 `infra/attachment` 调）：答已接受的定义里每个带类别的资源类型（资源类型、属主组件、类别的全部属性）与目录修订；请求带上次的修订，没变答“未变”。
- **采购**（第一个属主，考设计后改）：采购订单的资源加字段 `contract_file`（普通）、`invoice_scan`（受限：读要 `erp.purchase.order.read_invoice`）与两个类别 `erp.purchase.order_contract`（字段 `contract_file`，普通，PDF、PNG、JPEG，16 MiB，保留类别 `purchase_contract`）、`erp.purchase.order_invoice`（字段 `invoice_scan`，严格，同样的类型，10 MiB，保留类别 `purchase_invoice`）；不收 SVG 与 HTML。用户面 `POST /api/purchase/orders/{id}/attachments`（申请上传：要订单的修改操作，订单已取消或关闭不许）、`GET …/attachments`（列表：要读取，按字段资格过滤类别）、`POST …/attachments/{aid}/download`（要读取与类别字段的读取资格）、`DELETE …/attachments/{aid}`（解除引用：要修改）；订单取消时经工作项解除全部附件并给出保留起算日期（取消的日期），订单完成时给出起算日期（完成的日期）（D68：属主命令）。
