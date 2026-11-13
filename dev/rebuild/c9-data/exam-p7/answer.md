# C9 P7 一致性考试的答卷（摘录）

考生：一个没参与写作的子代理（2026-11-13，只读文件，约 22 万 token、45 次工具调用、6 分钟），对照线协议第 19 章、SDK 的 `storage` 与附件类别、授权组件的类别目录、附件组件的设计与代码、采购的附件、格与 L3。下面按答卷原样摘录每条的结论与依据；处理见 `result.md`。

## 必须改

- **M1** SDK 存储端口：`storage.go:285-288` 的 `copyOnce` 把 `probeCopy` 的结果永久缓存，探测时一次网络错误或 ctx 取消就让之后每次 `Copy` 失败；第一次 `copyNative` 的网络错误让 `native=false` 永久成立；`conditional()`（:261）第二次 PUT 一个 503 就永久判成“不遵守 If-None-Match”。P19.3 写不可达时下次再探测。改：只在明确答复时缓存，探测用独立带超时的 ctx，假存储单元测试先 503 后正常应恢复。
- **M2** 已确认版本的暂存对象永不删除：协议 12 第 117 行说会话到期后由清理删除；代码只删未确认到期的（`reconcile.go:104-106`）、清除的、rejected/quarantined 30 天后的；`orphans()` 把未删对象的版本当作有记录（:210-211）；`Finalize` 复制后不删暂存；桶的生命周期规则没有任何地方设置。
- **M3** 采购的替换上传绕过发票的读权限：带 `replace_attachment_id` 时 `category` 可空（`attachments.go:72`），`readable(c, o, "")` 为真（:38-40），附件组件替换路径只在类别非空时核对（`uploads.go:73`）。
- **M4** 普通类别（合同）不看字段读资格：协议 12 第 56 行、安全 09a 第 119 行要求按类别字段的读写资格；采购只对发票检查；itest 的 Erin 的 `ReadFields` 不含 `contract_file`，却断言她能列出与下载合同。建议按 `Decision.Fields` 判断。
- **M5** 替换内容后状态事件的版本号不变：`uploads.go:313-320` 切换当前版本后直接 `Publish`，没有 `revision + 1`（只有 `SetState` 加一）。
- **M6** AT09 的最长保留告警没有实现（`Retention.MaxDays` 无人读），设计却说 AT01–AT14 已实现。
- **M7** 测试索引漏报：每小时的 `lifecycle.Purge` 在 itest 里一次也没调用；AT09、FA11 的清除路径、FA31、FA35 没守住。

## 建议改

1. 测试索引对 FA21（测到的是确认之后覆盖）、FA22（结构上不可能）、FA23（没测过期）有夸大。
2. SDK 的 `TestErrorClasses` 断言日志不含 `X-Amz-Signature=0`，几乎什么也没检查；P19.9 的 `too_large`、`unavailable`，P19.3、P19.4 的退化路径都没测。
3. `Head` 把 403 归为 `ErrUnavailable`，与 P19.9 的 `denied` 不一致。
4. `copyThrough` 把整个对象读进内存（退化路径）。
5. 订单结束：完成与关闭各一个工作项，乱序时起算日期可能被改回完成日；完成后的订单仍能上传，这些附件没有起算日期。
6. 父记录级的 `Hold` 不锁附件行，可能与清除交错；单个附件的保全能插到已清除的附件上。
7. 协议 12 的状态表落后于设计（解除引用的守卫、`missing` 状态、第 247 行“尚未运行”）。
8. 设计里 Restore 写“记下的原状态”，代码把 uploading、finalizing、pending_scan 恢复成 `rejected`。
9. AT12 说 rejected 版本 30 天后删对象，新附件被拒时 `Purge` 在会话到期后就清除。
10. 设计说类别名在注册表登记、全局唯一，没有任何检查。
11. 上传凭证的签发没有审计（下载的有）。
12. `http.DetectContentType` 认不出 Office 文档。
13. 孤儿扫描 `attachment_id::text = $1` 用不上索引；`presence()` 每天每个附件一次 `Head`。
14. 格里所有组件共用一把 S3 凭据，FA01 只是形状。
15. 采购 `Ended` 的 `DEFINITION_PENDING` 分支是死代码；永久错误会无限重试。

## 可不改

`Upload` 先绑定请求体再读订单；类别为空的新附件以“超限”被拒；状态事件带文件名；`PresignGet` 不核对 inline 类型；被拒附件的清除不查保全。
