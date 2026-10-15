# 实验档案

> 代表部署实验（[计划](../experiment-plan.md)）每一项测试的完整记录，给以后查细节用。每项测完立刻写，结构见计划的“记录与报告”。原始输出在 [`../experiment-data/`](../experiment-data/)。给人看的结论在报告（`../experiment-report.md`，测到可以汇总时建立）。

## 索引

| 编号 | 测什么 | 在哪一格 | 日期 | 结果 | 记录 |
| --- | --- | --- | --- | --- | --- |
| 0-01 | `GOPRIVATE` 让 Go 绕过公共代理与校验和库 | 第 0 步 | 2026-10-16 | 部分通过（重新使用版本号的一半在第 1 步补验） | [0-01-goprivate.md](0-01-goprivate.md) |
| 0-02 | 同一版本号删掉重发：BrickKit 的发布与两层缓存 | 第 0 步 | 2026-10-16 | 通过；发现缓存静默给出旧内容，第 1 步须清缓存 | [0-02-reused-version-brickkit.md](0-02-reused-version-brickkit.md) |
