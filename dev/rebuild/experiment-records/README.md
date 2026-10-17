# 实验档案

> 代表部署实验（[计划](../experiment-plan.md)）每一项测试的完整记录，给以后查细节用。每项测完立刻写，结构见计划的“记录与报告”。原始输出在 [`../experiment-data/`](../experiment-data/)。给人看的结论在报告（`../experiment-report.md`，测到可以汇总时建立）。

## 索引

| 编号 | 测什么 | 在哪一格 | 日期 | 结果 | 记录 |
| --- | --- | --- | --- | --- | --- |
| 0-01 | `GOPRIVATE` 让 Go 绕过公共代理与校验和库 | 第 0 步 | 2026-10-16 | 部分通过；决定改为不重用版本号（A110），后一半不再补验 | [0-01-goprivate.md](0-01-goprivate.md) |
| 0-02 | 同一版本号删掉重发：BrickKit 的发布与两层缓存 | 第 0 步 | 2026-10-16 | 通过；发现缓存静默给出旧内容，成为改用新号（A110）的理由；v1.5.0 复测改为报 `VERSION_CHANGED`（FRR-002） | [0-02-reused-version-brickkit.md](0-02-reused-version-brickkit.md) |
| 0-03 | 一个仓库放多个组件（探针） | 第 0 步 | 2026-10-16 | 通过；v1.4.1 时 `add` 加不进子目录组件；v1.5.0 复测：写 `repo` 的安装源后 `add` 一条命令写好三层（FRR-003） | [0-03-monorepo-components.md](0-03-monorepo-components.md) |
| 0-04 | Go 外壳承载成员；成员版本不一致时被拒 | 第 0 步 | 2026-10-17 | 通过；BrickKit 拦下三种不一致，“编进的代码与声明不符”只有外壳启动器能拦（协议 17 已要求）；C3b 报错不够直接（FRR-004）；v1.6.0 复测：报错写出本地仓库的版本与两条出路；v1.6.1 复测：`up` 对只写 `image`、旁边有 `Dockerfile` 的组件给出警告（FRB-001） | [0-04-go-shell-members.md](0-04-go-shell-members.md) |
