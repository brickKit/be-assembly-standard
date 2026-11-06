# T2a：冷层用哪个 Go 的 Parquet 库（2026-11-06）

**问题**：转层的冷路线（对象存储上的 Parquet 加清单，协议 11）要在 Go SDK 里写与读 Parquet。组件的列在编译时不知道（SDK 按组件声明的数据类别处理），所以要能在运行时建表结构；不用 cgo（本项目不在 Go 组件里嵌 DuckDB）；第三方读取器要能从文件读出同样的值（门槛 G3）。

**服务的需求**：每个组件的转层工作项把一个归档单元（常见几千到几十万行）写成一个 Parquet 对象并完整读回校验；冷读按单元读回。组件进程里运行，外壳里多个成员共用一个进程，所以内存峰值与二进制大小都算。

## 候选与版本

| 候选 | 版本（发布日期） | 说明 |
| --- | --- | --- |
| `github.com/parquet-go/parquet-go` | v0.32.0（2026-08-10） | 纯 Go，`parquet.Group` 在运行时建表结构，`parquet.Row` 带重复与定义级别写入 |
| `github.com/apache/arrow-go/v18` 的 `parquet/pqarrow` | v18.8.0（2026-09-04） | 纯 Go，Apache 官方；经 Arrow 的记录批写与读 |

没有测的：DuckDB（要 cgo，本项目已定不嵌入 Go 组件）；`xitongsys/parquet-go`（多年不活跃，靠反射与结构体标签）。

## 方法

- 程序 [`bench/main.go`](bench/main.go)：两个库写同样的行（十列：布尔、decimal(19,4)、可空 JSON 文本、UTC 微秒时刻、文本、日期、两列 UUID、可空文本、int64），zstd，每 10 万行一个行组；读时每个值都过一遍并折成校验值。一个库一种操作一个进程，峰值内存取 `/proc/self/status` 的 VmHWM。
- 运行 [`run.sh`](run.sh)：100 万行，两个库交替，5 轮，每轮先写后读；电源模式切到 performance、结束时恢复（原来是 balanced）。
- 机器：12th Gen Intel Core i5-12450H，12 个逻辑 CPU；Go 1.27.2；Linux 7.0。
- 原始输出：[`results.jsonl`](results.jsonl)（第一行记了时间、电源模式、Go 版本与 CPU）。

## 结果

100 万行，5 轮的中位数（括号里是最小到最大）：

| | 写：耗时 | 写：CPU | 写：峰值内存 | 文件 | 读：耗时 | 读：CPU | 读：峰值内存 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| parquet-go v0.32.0 | 1282 ms（1272–1324） | 1430 ms | 109 MiB（94–114） | 34.0 MB | 322 ms（318–350） | 362 ms | 37 MiB |
| arrow-go v18.8.0 | 1502 ms（1481–1544） | 1641 ms | 160 MiB（149–170） | 38.2 MB | 470 ms（457–477） | 665 ms | 127 MiB |

写的耗时里含两边相同的造数据（同一个生成函数），库本身的差别比表里大。两组的范围都不重叠，差别超出波动。

依赖（只引入这个包的最小程序，`go mod tidy` 之后；[`footprint.sh`](footprint.sh) → [`footprint.txt`](footprint.txt)）：parquet-go 20 个模块、105 个包、二进制 10,620 KiB；`pqarrow` 104 个模块、211 个包、40,640 KiB。

正确性：1 万行的冒烟里，两个库各自读两边写的文件，得到的校验值相同（[`cross-read.txt`](cross-read.txt)）；pyarrow 26.0.1 与 DuckDB 2.0.0 读两边的文件（[`third.py`](third.py) → [`third-party.txt`](third-party.txt)），行数、金额合计、最早时刻与非空计数相同。parquet-go 写的 UUID 与 JSON 带着逻辑类型（pyarrow 读出 `extension<arrow.uuid>`、`extension<arrow.json>`）；arrow-go 写 `FixedSizeBinary(16)` 时只是字节，要另用它的 UUID 扩展类型才带。

## 结论

选 parquet-go v0.32.0（A149）：适配上纯 Go、依赖小、运行时建表结构直接、逻辑类型齐；实测写与读都更快，读的峰值内存约为三分之一。代价：版本还在 0.x，接口可能变，钉确切版本、升级时重跑这个基准与第三方读取的核对；`parquet.Group` 的列按名字排序，清单里记下列的顺序，摘要按规范行算、不依赖文件里的列序。decimal 的精度大于 18 位要用定长字节数组（按 Parquet 规范 int64 只到 18 位）。

**什么时候复测**：parquet-go 出 1.0 或换主要版本、arrow-go 大改 Parquet 写入路径、单元的典型行数或列型变了（例如大量长文本或嵌套结构）。
