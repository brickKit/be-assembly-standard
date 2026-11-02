# R1 #5：PG16 的 `GRANT m TO shell WITH INHERIT FALSE, SET TRUE`

## 假设

来自 `sdk-redesign.md` §7.9 第 5 条，支撑 P19.5（以及 P10.2、P10.7）：执行 `GRANT m TO shell WITH INHERIT FALSE, SET TRUE` 之后，外壳登录角色可以在事务里 `SET LOCAL ROLE m`，而外壳角色自己对成员的表没有任何权限。

## 环境与版本

- `postgres:16-alpine`（PostgreSQL 16.15），一次性容器 `r1-r1a-pg05-<pid>`，跑完即删（含卷）。
- 附加：`postgres:15`（15.18），一次性容器 `r1-r1a-pg15-<pid>`，用来看低版本的写法。
- 客户端是容器里的 `psql`；不涉及任何项目数据库。

## 步骤

`./run.sh`：起容器 → 以超级用户执行 `setup.sql` → 用不同的登录角色逐条检查（每条检查一个新会话，输出 PASS/FAIL）。`./pg15-fallback.sh`：在 PG15 上试同一语法和替代写法。

`setup.sql` 建的身份：

| 角色 | 角色属性 | 对 m1 的授权 | 作用 |
|---|---|---|---|
| `shell` | NOINHERIT | `INHERIT FALSE, SET TRUE`（对 m2 也一样） | P19.5 的写法 |
| `shell_inh` | INHERIT | `INHERIT FALSE, SET TRUE` | 看按授权的继承能否压过角色属性 |
| `shell_old` | INHERIT | 普通 `GRANT`（继承） | 对照组：今天的写法 |
| `shell_noset` | NOINHERIT | `INHERIT FALSE, SET FALSE` | 对照组：连 SET 都不许 |
| `m1` / `m2` | LOGIN | — | 成员，各自拥有 `s1` / `s2` 和其中的表 |

## 原始输出（关键几行）

```
 m1  | shell       | f | t
 m1  | shell_old   | t | t
PASS C1-shell-direct-read            | ERROR:  permission denied for schema s1
PASS C2-shell-privileges             | f|f|f|t|t      (schema USAGE, 表 SELECT, pg_has_role USAGE, MEMBER, SET)
PASS C3-set-local-role-rw            | 2 / t / m1|shell|s1   (行数, P10.7 探测, current_user|session_user|schema)
PASS C4-reverts-after-commit         | shell|"$user", public
PASS C5-ddl-owner                    | m1
PASS C6-grant-level-inherit-wins     | ERROR:  permission denied for schema s1
PASS C7-control-old-inherit          | 1|seed
PASS C8-control-set-false            | ERROR:  permission denied to set role "m1"
PASS C9-reset-role-escape            | ERROR:  permission denied for schema s1
PASS C10-member-cannot-read-peer     | ERROR:  permission denied for schema s2
PASS C11-member-can-switch-to-peer   | m2|m2-only
PASS C12-standalone-self-set-role    | m1
PASS C13-pg-stat-activity-usename    | shell|m1-busy
PASS C14-set-local-application-name  | shell|member:m1
PASS C14b-application-name-reverts   | psql
== result: pass=16 fail=0

[postgres] ERROR:  syntax error at or near "INHERIT"        (PG15)
[shell] ERROR:  permission denied for schema s1              (PG15，NOINHERIT 角色 + 普通 GRANT)
[shell] m1|0                                                 (PG15，SET LOCAL ROLE 可用)
```

## 结论

**成立。**

- 外壳角色直接访问成员的表被拒（C1、C2）；在事务里 `SET LOCAL ROLE m1` + `SET LOCAL search_path` 之后可以读写，P10.7 的启动探测为真（C3）；提交之后身份和 search_path 都回到外壳（C4），池里的下一个借用者不受影响。
- 在 `SET LOCAL ROLE` 下建的表属主是成员角色（C5），所以"schema 里没有属主不是 `PG_USER` 的表"在外壳里也成立。
- 起作用的是**授权上的** `INHERIT FALSE`：角色本身是 INHERIT 也一样拒绝（C6）。对照组证明这些检查能变红：普通 GRANT 时外壳能直接读（C7），`SET FALSE` 时不能切换（C8）。
- `RESET ROLE` 回到外壳之后什么都读不到（C9），所以成员代码"逃回"外壳身份也没有用处，这正是 NOINHERIT 的价值。
- 单跑时成员以自己登录，`SET LOCAL ROLE` 自己可用（C12），P10.2 不必区分单跑和外壳。

另有三点发现：

1. **外壳内成员之间的隔离不由数据库保证。** `SET ROLE` 检查的是会话用户（`shell`）的成员资格，所以 m1 的代码可以在同一事务里再 `SET LOCAL ROLE m2`，读到 m2 的数据（C11）。m1 自己的身份读不到 m2（C10），越界必须是代码主动切换角色。
2. **CP-DB-03 在外壳里按角色数不出来。** `pg_stat_activity.usename` 是登录角色，`SET LOCAL ROLE` 期间仍然是 `shell`（C13），按成员角色计数永远是 0。`SET LOCAL application_name = '<成员 ID>'` 可以实时出现在 `pg_stat_activity` 里，提交后复原（C14、C14b）。
3. **`WITH INHERIT … SET …` 是 PG16 才有的语法**，PG15 上直接语法错误。PG14/15 上"角色级 NOINHERIT + 普通 GRANT"能得到同样的效果（`pg15-fallback.sh`）。P10.7 允许 `server_version_num ≥ 140000`，两者要对齐。

## 对设计的影响

1. **P19.5 保留**，补两句：
   - "外壳内成员之间的库隔离靠 SDK，不靠数据库：外壳角色对每个成员都有 SET 权，成员代码若自己执行 `SET ROLE`，可以切到别的成员。SDK 的 `Store` 是唯一发 `SET LOCAL ROLE` 的地方，由门禁 `identity-literal-scan` 禁止组件代码里出现 `SET ROLE` / `SET LOCAL ROLE` 和角色字面量。"
   - "db-init 在 PG16 以上用 `GRANT m TO shell WITH INHERIT FALSE, SET TRUE`；在 PG14/15 上用 `CREATE ROLE shell NOINHERIT` 加普通 `GRANT`，效果相同。外壳角色在任何版本上都建成 NOINHERIT。"（或者干脆把外壳部署的最低版本定为 16，写进 P19.5。）
2. **P10.2 增加一条 `SET LOCAL application_name = '<成员 ID>'`**，和 `SET LOCAL ROLE`、`SET LOCAL search_path` 一起放在每个事务开头。单跑时也执行，代价可以忽略。
3. **CP-DB-03 的判据改为**"`pg_stat_activity` 里 `application_name = <成员 ID>` 且 `state <> 'idle'` 的连接数 ≤ `PG_POOL_MAX`"。这在单跑和外壳里都成立；原来按 `usename` 计数的写法只在单跑时有效。
