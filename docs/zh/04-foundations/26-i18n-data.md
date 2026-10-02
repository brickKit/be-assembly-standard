[English](../../en/04-foundations/26-i18n-data.md) · [中文](26-i18n-data.md)

# 数据里的多语言

哪些存下来的数据有多种语言、怎么存；哪些标准码取代了存名称；服务端怎么知道它该用哪种语言写；以及服务端到底在哪些输出里要按语言出文字。读者是要给主数据加名称字段、要打印单据、要发通知，或者被要求"出口订单上要有英文品名"的人。

## 范围

- **覆盖：** 主数据和参考数据上的可翻译列及其契约字段；按语言取值；单据语言和名称快照；语言、国家、币种、时区、单位的标准码；服务端语言从哪来；部署的默认语言；错误体的语言（引用）。
- **不覆盖：** 前端的界面文案和格式化（[03-frontend.md](../01-conventions/03-frontend.md#国际化)）；错误模型和它的目录（[15-user-api-and-errors.md](15-user-api-and-errors.md)）；时区和业务日期（[05-time-and-calendars.md](05-time-and-calendars.md)）；币种、金额和单位（[06-money-quantity-units.md](06-money-quantity-units.md)）；对翻译后名称的搜索（[25-search.md](25-search.md)）。

## 选择

- **可翻译的短文本加一列同名的 JSONB 兄弟列**：`name` 保存部署默认语言的值，`name_i18n` 放其他语言。只做加法：现有读 `name` 的地方全部照常工作。
- **契约在字段旁边加一个 map**（`map<string, string> name_i18n`）；调用方按自己的语言、沿一条固定的回退链取值。
- **存码，绝不存码的名称**：BCP 47 语言、ISO 3166 国家、ISO 4217 币种、IANA 时区、UN/ECE 第 20 号建议书的单位。码的名称由前端渲染。
- **服务端只在没有前端参与的地方写文字**：通知和打印出来的单据，用收件方的语言。用户在应用里看到的一切都由前端翻译。
- **服务端从数据里得知语言，从不看 `Accept-Language`**：用户的 `locale` 来自身份提供方，客户或供应商的 `preferred_language` 来自主数据，单据的 `language` 来自单据本身。
- **错误带机器可读的 reason**；前端按目录翻译（[15](15-user-api-and-errors.md#reason-目录)）。
- **一个部署默认语言**，共享键 `DEFAULT_LOCALE`，默认 `zh-CN`（协议键，见 `be-protocol` 的 `schemas/config-keys.yaml`；[24](24-config-and-secrets.md)）。

**状态**：已就位：主数据只有一个 `name TEXT`（客户、产品、单位、分类、科目、商机阶段）；前端中英文齐全，语言是存在浏览器里的前端偏好；没有任何服务端知道用户的语言。已定（随 3.0.0 统一升级）：错误模型和目录（[15](15-user-api-and-errors.md)）、`locale` claim 及其在目录事件里的位置（[21-identity-provider.md](21-identity-provider.md)）、标准码、`DEFAULT_LOCALE`（错误体里默认语言的 `title` 和 `detail` 要用它）。以后（要，但不急）：`_i18n` 列和契约字段、`preferred_language`、单据 `language`、前端把用户语言写回身份提供方。

## 端口契约

### 语言标签

- BCP 47 标签，规范大小写（`zh-CN`、`en`、`zh-Hant-TW`），存成 `TEXT`。
- **匹配**用 RFC 4647 的 lookup：先找请求的标签，再逐个去掉最后一个子标签直到只剩语言（`zh-Hant-TW` → `zh-Hant` → `zh`），最后是默认语言。[15](15-user-api-and-errors.md#reason-目录) 的目录键（`zh`、`en`）按同一规则匹配。
- `DEFAULT_LOCALE` 整个部署只有一个值，在 `config/vars.yaml` 里写一次；已有数据之后再改它是一次数据迁移，不是一个设置。

### 可翻译列

| 列 | 类型 | 规则 |
|---|---|---|
| `name` | `TEXT NOT NULL` | `DEFAULT_LOCALE` 下的值；必填；现有每个消费者读的都是它 |
| `name_i18n` | `JSONB NOT NULL DEFAULT '{}'` | `{"<标签>": "<文本>"}`，放其他语言；默认标签的条目读时忽略、写时丢弃，因为默认语言以 `name` 为准 |

- **哪些字段**：主数据和参考数据上用于展示的短文本：名称、简短描述、单位名和分类名、科目名、阶段名。不包括：单据上的自由文本（备注、地址）、人名、任何用户用一种语言填一次的东西。
- **JSONB 只作不透明存储**（[03-database.md](03-database.md#能力清单)）：SQL 里绝不按键过滤、排序或建索引。搜索经 `search_text` 覆盖每种语言（[25](25-search.md#搜索列)）；排序按 `name`。
- 同一对列适用于任何字段：`description` / `description_i18n`。

### 线上形态

- **gRPC**：在实体消息里加 `string name = N; map<string, string> name_i18n = M;`；`BatchGet` 两者都返回，由每个调用方自己取。
- **REST**：JSON 里同样的两个成员。写请求带了 `name_i18n` 就整体替换这个 map。
- **事件**：主数据事件随 `name` 一起带 `name_i18n`，所以快照两者都复制（[11-consistency-across-components.md](11-consistency-across-components.md)）。
- **取值**：沿上面的匹配链在 `name_i18n` 里找，找不到就回退到 `name`。每个官方 SDK 实现同一条链；提议在 be-protocol 里为它加一组共享向量。

### 单据与快照

- 会被打印或发给合作方的交易单据带 `language TEXT NOT NULL`（BCP 47），默认取合作方的 `preferred_language`，否则取 `DEFAULT_LOCALE`。
- 名称的行快照（订单行上的品名）在建行时按单据语言取值，之后永不改变：一张出口订单打印的就是它创建时的英文品名。
- 合作方主数据加 `preferred_language`（mdm/customer、mdm/supplier），只做加法。

### 服务端语言从哪来

| 输出 | 语言 | 来源 |
|---|---|---|
| 发给用户的通知 | 用户的语言 | 身份提供方目录事件里的 `locale`，复制进通知组件的快照；没有就用 `DEFAULT_LOCALE` |
| 打印的单据 | 单据的语言 | 单据的 `language` |
| 发给客户或供应商联系人的消息 | 合作方的语言 | 主数据里的 `preferred_language` |
| 用户申请的导出文件（列标题） | 申请人的语言 | 请求所带 token 的 `locale` claim |
| 错误体的 `title` 和 `detail` | 默认语言 | `DEFAULT_LOCALE`；只供日志和兜底（[15](15-user-api-and-errors.md#错误体)） |
| 每个页面 | 用户的选择 | 前端（[0404](../02-decisions/04-frontend/0404-four-user-preferences.md)）；写回身份提供方（计划中的 `PUT /api/me/locale`），服务端才看得到 |

任何地方都不用 `Accept-Language`。token 里的 `locale` 可能比用户的修改晚最多一个 access token 的有效期（600 s）。

### 标准码

| 东西 | 标准 | 列 | 例子 | 名称由谁渲染 |
|---|---|---|---|---|
| 语言 | BCP 47 | `TEXT` | `zh-CN` | 前端（CLDR，`Intl.DisplayNames`） |
| 国家或地区 | ISO 3166-1 alpha-2 | `CHAR(2)` | `CN` | 前端（CLDR） |
| 下级行政区 | ISO 3166-2；中国行政区划用 GB/T 2260 | `TEXT` | `CN-SH` | 前端，或者一张本身可翻译的参考表 |
| 币种 | ISO 4217 字母码 | `CHAR(3)` | `CNY` | 前端；小数位来自 mdm/currency（[06](06-money-quantity-units.md)） |
| 时区 | IANA | `TEXT` | `Asia/Shanghai` | 前端（[05](05-time-and-calendars.md)） |
| 计量单位 | UN/ECE 第 20 号建议书 | `TEXT` | `KGM` | mdm/product 里单位自己的可翻译名称 |

码列是"按标准码引用"（[04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)）；它从不存"China"或"中国"。

## 备选方案

| 做法 | 谁在用 | 好处 | 代价 |
|---|---|---|---|
| **基础列旁边加一列 JSONB 翻译列**（选用） | Odoo 16 及以后（从翻译表迁到了 JSONB 列） | 不用 JOIN；读一行就拿到全部语言；只做加法 | SQL 里不能按语言建索引或排序 |
| 每个实体一张文本表 `<entity>_texts(id, lang, name)` | SAP（MAKT 等）、Dynamics 365 | 可以按语言建索引、排序 | 每次读都要 JOIN；开发者或 AI 很容易漏掉 |
| 每种语言一列（`name_en`、`name_zh`） | 小系统 | 最简单 | 每加一种语言就一次迁移 |
| 中央翻译服务 | 一些套件 | 一处 | 每个组件都依赖它，违反组件边界 |
| 服务端按 `Accept-Language` 翻译 | 传统 Web 应用 | 客户端拿到什么就显示什么 | 每个组件都维护每种语言的文案；语言是前端偏好 |
| 数据里存消息键，前端翻译 | 一些 SaaS 产品 | 库里没有翻译 | 主数据是客户录入的，不是开发者写的 |

## 为什么选它

- **只做加法、只在本地**：属主的表里多一列，契约里多一个 map；不新增组件，不用 JOIN，没有消费者会坏（[0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)）。
- **契约是那个 map，不是存储**：以后某张表改成文本表，任何调用方都察觉不到。
- **码让数据与语言无关**：国家和币种在库里永远不需要翻译。
- **文字在知道语言的地方产生**：屏幕上的给前端，服务端只管不经前端就发出去的输出。

## 为什么不选其他

- **文本表**：每个列表、每次 `BatchGet` 都多一个 JOIN，换来的功能（SQL 里按非默认语言排序）没人要。
- **每种语言一列**：客户每加一种语言就改一次表结构。
- **翻译服务**：每个组件都会依赖它，组件就再也不能单独运行。
- **服务端翻译**：把每种语言塞进每个组件，而且和"语言是用户在前端的选择"相矛盾。
- **数据里存消息键**：客户自己输入品名，没有可以翻译的键。

## 什么时候换

- **某个实体需要超过大约十种语言**，或者 **SQL 里要按语言排序或建索引**：把那张表改成文本表。
- **单据上的自由文本要翻译**：那是一项业务功能（翻译流程），不是存储上的改动。
- **服务端渲染的文字要超出通知、打印和导出**：给错误加一个本地化消息成员，作为加法（[15](15-user-api-and-errors.md#什么时候换)）。

## 怎么换

1. 在属主的 schema 里建文本表，从 `name_i18n` 回填（可续跑的任务，[19-background-jobs.md](19-background-jobs.md)）。
2. 读写改走文本表；契约里保留 `name_i18n`，改为由这张表拼出来。
3. 在后面的某个版本删掉 JSONB 列（先扩后缩）。调用方、事件和前端都不变。

## 一致性测试

先写成红的测试：

- 每个官方 SDK：回退链（`zh-Hant-TW` → `zh-Hant` → `zh` → `name`）；默认标签的条目被忽略；不认识的标签回退到 `name`；
- mdm/product，等这些列加上之后：`BatchGet` 返回 `name_i18n`；更新整体替换这个 map；更新事件带上它；
- erp/sales：用 `en` 创建的订单快照的是英文品名；之后改产品的英文名，订单行不变；
- infra/print：单据按它的 `language` 渲染；infra/notification：通知用收件人的 `locale`，没有就回退到 `DEFAULT_LOCALE`；
- 错误语言由 [15](15-user-api-and-errors.md#一致性测试) 里错误模型的测试覆盖。

没有端口套件：这里没有可替换的基础设施。

## 相关决策

- [0404 用户偏好只有四项](../02-decisions/04-frontend/0404-four-user-preferences.md)：语言是用户在前端的选择；计划修订，让这个选择也写进身份提供方，供服务端出文字。
- [0302 契约只做加法](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)：`name_i18n` 和 `preferred_language` 都是加法。
- [0203 token 只承载身份](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md)：它计划中的修订会加上 `locale`（[21](21-identity-provider.md)）。
- [0504 一种错误对象，由目录里的 reason 标识](../02-decisions/05-runtime/0504-error-model-and-reason-catalogue.md)：错误带机器可读的 reason；前端翻译。

## 已知限制

- **按名称排序跟随默认语言**；另一种语言的列表也按 `name` 排，而不是按翻译后的值。
- **自由文本只有一种语言**：备注、地址、人名按录入时的样子保存。
- **没有机器翻译**；缺翻译时显示默认语言的值。
- **快照保留取快照时的翻译**；改正产品的英文名不会改变已经建好的订单。
- **用户改了语言，要等 token 刷新**（最多 600 s）、而且要等前端把它写回之后，服务端的文字才跟着变。
- **从右到左的语言**，今天的前端没有考虑。
