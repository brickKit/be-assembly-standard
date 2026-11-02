# r1-03b：运行时读取自定义字段选项 `(be.v1.max_items)`（ts-proto、Python protobuf）

r1-03 第 6 条留下的问题：P7.10 规定批量上限写在 proto 字段选项 `[(be.v1.max_items) = N]` 里（`tools/be-protocol/proto/be/v1/limits.proto`，扩展号 51001），没写就是 500。SDK 要在服务端按它拒绝超限请求，前提是运行时读得到这个值。

## 假设

1. ts-proto（`outputSchema=true`）生成的 `protoMetadata` 里有自定义字段选项的值，TS SDK 不需要另跑生成器或自己解析描述符字节。
2. 从方法路径（grpc-js 服务定义的 `path`）能找到请求消息及其每个 repeated 字段的上限，包括 snake_case 字段和嵌套消息里的字段，从而做成一个通用的服务端检查。
3. Python 的 grpcio-tools 生成代码 + protobuf 运行时，用 `FieldOptions.Extensions[limits_pb2.max_items]` 能读到同一个值。

## 环境与版本

| 项 | 版本 |
|---|---|
| Node | v24.21.0（本机 fnm），直接跑 `.ts`（类型擦除） |
| ts-proto | 2.12.4（与 r1-03 相同），protoc 3.19.1 来自 `grpc-tools` 1.13.1；`@grpc/grpc-js` 1.14.5，`@bufbuild/protobuf` 2.16.0 |
| Python | CPython 3.13（`python:3.13-slim` 一次性容器），grpcio / grpcio-tools 1.76.0（与 `tools/be-sdk-python/pyproject.toml` 一致），protobuf 6.33.6（upb 后端） |

`proto/batch.proto` 直接 `import "be/v1/limits.proto"`（`-I` 指向 be-protocol 子模块里的真文件）：

| 字段 | 选项 | 测什么 |
|---|---|---|
| `ids` | `max_items = 100` | 显式上限 |
| `tags` | 无 | 默认 500 |
| `widget_ids` | `max_items = 2` | snake_case 字段名与 TS 属性名（`widgetIds`）的对应 |
| `filter.sku_ids` | `max_items = 7` | 嵌套消息 `Filter` 里的字段 |

## 步骤

```bash
./run.sh > output.txt   # npm ci → 生成 gen/ → node repro.ts → Python 容器里 grpc_tools.protoc + py/check.py
```

`repro.ts` 从 `protoMetadata` 为每个方法路径建上限表，包一层 grpc-js handler：请求超限答 `INVALID_ARGUMENT`（`details` 里放 `{field, max, got}`），否则交给真实 handler。`gen/` 由 `run.sh` 重新生成，不入库。

第一次生成用的是 r1-03 的选项（`outputServices=grpc-js,esModuleInterop=true,outputSchema=true,importSuffix=.ts`），`node repro.ts` 直接失败；加 `enumsAsLiterals=true` 后通过（见下）。

## 原始输出（关键几行）

完整输出见 `output.txt`。

```
# 第一次（没有 enumsAsLiterals）：
file:///…/r1-03b/gen/google/protobuf/descriptor.ts:195
  > export enum FieldDescriptorProto_Type {
SyntaxError [ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX]: TypeScript enum is not supported in strip-only mode

# 加 enumsAsLiterals=true 之后：
R1 protoMetadata.options = {"messages":{"BatchGetWidgetsRequest":{"fields":{"ids":{"max_items":100},"widget_ids":{"max_items":2}},"nested":{"Filter":{"fields":{"sku_ids":{"max_items":7}}}}}}}
R2 fileDescriptor field 'ids' options keys = ctype,packed,jstype,lazy,…,uninterpretedOption      （描述符里的 options 没有 max_items）
R3 limits by method = [["/r1.batch.v1.Widgets/BatchGetWidgets",[{"field":"ids","prop":"ids","max":100,…},{"field":"tags","max":500,"explicit":false},{"field":"widget_ids","prop":"widgetIds","max":2,…},{"field":"filter",…,"nested":[{"field":"sku_ids","prop":"skuIds","max":7,…}]}]]]
R4 ids=100 (limit 100): OK 100 ids
R4 ids=101: ERR INVALID_ARGUMENT BATCH_TOO_LARGE {"field":"ids","max":100,"got":101}
R4 tags=500 (no option): OK 0 ids
R4 tags=501: ERR INVALID_ARGUMENT BATCH_TOO_LARGE {"field":"tags","max":500,"got":501}
R4 widget_ids=3 (limit 2): ERR INVALID_ARGUMENT BATCH_TOO_LARGE {"field":"widget_ids","max":2,"got":3}
R4 filter.sku_ids=8 (limit 7): ERR INVALID_ARGUMENT BATCH_TOO_LARGE {"field":"filter.sku_ids","max":7,"got":8}
===== grpcio 1.76.0, protobuf 6.33.6
protobuf backend: upb
P1 extension: be.v1.max_items number 51001
P2 limits: [('ids', 100, True), ('tags', 500, False), ('widget_ids', 2, True), ('filter.sku_ids', 7, True)]
P3 by method path: /r1.batch.v1.Widgets/BatchGetWidgets -> r1.batch.v1.BatchGetWidgetsRequest [同 P2]
P3 method idempotency_level: 1
P4 via default pool: 100
```

## 结论

| 假设 | 结论 |
|---|---|
| 1 TS 运行时拿得到 | **成立，但位置和 r1-03 的 `idempotencyLevel` 不同**。自定义选项**不在** `protoMetadata.fileDescriptor…field[].options` 里（那里只有标准字段，R2），而在单独的 `protoMetadata.options.messages.<Msg>.fields.<proto 字段名>.max_items`，嵌套消息在 `.nested.<Inner>` 下（R1）。值是生成时就解好的字面量 `100`，运行时不用解码。键是扩展的**短名** `max_items`，不带包名（ts-proto `schema.js` 用 `extension.name`） |
| 2 按方法路径做通用检查 | **成立**。方法 → `inputType` → 描述符里的 repeated 字段（`label === 3`）→ 上限（选项表里有就用，没有就 500）；TS 属性名用描述符的 `jsonName`（`widget_ids` → `widgetIds`）。6 个用例全部按预期放行或拒绝（R4） |
| 3 Python 拿得到 | **成立**。`field.GetOptions().Extensions[limits_pb2.max_items]`，`HasExtension` 区分"没写"（用 500）；从 `DESCRIPTOR.services_by_name[…].methods_by_name[…].input_type` 出发也一样，`descriptor_pool.Default()` 按全名查也能读到（P2–P4）。前提是 `be.v1.limits_pb2` 可导入：生成的 `batch_pb2` 里有 `from be.v1 import limits_pb2` |

新发现：**只要某个 proto 引入了 `be/v1/limits.proto`，ts-proto 就会连带生成 `gen/google/protobuf/descriptor.ts`（约 300 KB，含 TS `enum`），Node 24 的类型擦除不支持 `enum`，生成代码无法直接运行**。r1-03 的 `echo.proto` 没有枚举也没引入 descriptor，所以没碰到。`enumsAsLiterals=true` 把枚举生成成 `const … as const` 对象，问题消失；组件自己 proto 里的枚举同样受益。

## 对设计的影响

1. **TS SDK 的生成选项定为 `outputServices=grpc-js,esModuleInterop=true,outputSchema=true,importSuffix=.ts,enumsAsLiterals=true`**（在 r1-03 第 6 条基础上加 `enumsAsLiterals=true`），写进 be-protocol 的 TS 生成说明和 TS 一致性 widget。不加的话，任何用了 `max_items` 或带枚举的组件 proto 在 Node 24 下直接起不来。另一条路是保留构建步骤（`tsc` 或 `--experimental-transform-types`），与 §5.3"不经构建直接跑"的取向相反，不建议。
2. **P7.10 的 TS 实现读 `protoMetadata.options`，不读 `fileDescriptor` 的 field options**；上限表在服务注册时按方法路径建一次，请求时只做数组长度比较。默认 500 来自"描述符里所有 repeated 字段"，不是选项表（选项表只列写了选项的字段）。嵌套消息要递归 `nested`；引用别的文件里的消息类型时要沿 `protoMetadata.dependencies` 查，本次只测了同文件嵌套。
3. 由于 TS 选项表的键是短名 `max_items`，be-protocol 以后新增的选项**不要和其他常见扩展重名**（例如别取 `max_items`/`max_len` 这种 protoc-gen-validate、buf validate 也可能用的短名，或者在 be-protocol 说明里约定"be 的选项短名以 be 语义命名且全局唯一"）。今天只有一个选项，暂无冲突。
4. **Python SDK 需要一个可导入的 `be.v1.limits_pb2`**：be-protocol 不发布生成代码（limits.proto 头注释），所以要么 besdk 随包附带生成好的 `be/v1/limits_pb2.py`（顶层包名 `be`），要么组件生成时连同 limits.proto 一起生成。建议前者，由 SDK 固定 protobuf 版本生成，组件只生成自己的 proto；这一点写进 Python 的 M1 迁移说明。
5. Go 未在本次测试（`proto.GetExtension(fd.Options(), bev1.E_MaxItems)` 是 protobuf-go 的标准用法，R1a/Go SDK 实现时顺手验证）；Go 同样需要一个生成好的 `be/v1` 包，对应 limits.proto 注释里的 `M be/v1/limits.proto=<their package>`。
