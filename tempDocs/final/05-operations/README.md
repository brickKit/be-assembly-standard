# 运维手册

本目录给部署与运维的人用：遇到一件具体的运维事务，按哪几步做、每一步看什么、出了问题怎么办。规则本身（为什么这样做、保证什么）在协议中，本目录只写操作，并指向规则所在。

| 手册 | 什么时候读 | 规则所在 |
| --- | --- | --- |
| [备份与恢复](01-backup-and-recovery.md) | 日常备份核对；数据损坏后整套恢复到较早的时刻；恢复演练 | [协议 15](../06-protocols/15-backup-and-recovery.md) |
| [升级与维护窗口](02-upgrade-and-maintenance.md) | 发布新版本、迁移结构、换密钥、换成员或存储路线 | [协议 17](../06-protocols/17-runtime-and-resources.md)、[19](../06-protocols/19-config-secrets-registries-release.md)，安全 [10](../06-protocols/security/10-providers-and-member-switching.md)、[11](../06-protocols/security/11-identity-member-switching.md) |
| [告警与处置](03-alerts.md) | 收到一条告警，它是什么意思、先做什么 | [协议 17 的观测](../06-protocols/17-runtime-and-resources.md#观测) |
| [客户上线](04-go-live.md) | 新客户从旧系统迁入：试迁移、对账、签字、正式切换 | [协议 16](../06-protocols/16-go-live-and-import.md) |

## 共同约定

- **先看后动**：每个手册的第一步都是确认现状（版本、状态、告警、在途的工作），记入运行档案，再动手。
- **一切操作留记录**：时间、操作人、原因、结果写入客户的运行档案；需要批准的操作先有批准记录。
- **不绕过协议**：手册里找不到的情形，不临时发明做法；按协议的规则判断，拿不准时暂停受影响的业务并上报。
- **单节点是起点**：标准起步是单实例、单数据库；高可用的操作（同步复制、切换、降级）是底层预留，客户真正启用高可用时才适用（D66），手册中单列。
