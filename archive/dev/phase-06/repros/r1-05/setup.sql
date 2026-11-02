-- 以超级用户执行：模拟 db-init 给一个外壳和两个成员建身份。
-- shell        外壳登录角色：NOINHERIT，对成员的授权写 INHERIT FALSE, SET TRUE（P19.5 的写法）
-- shell_inh    角色本身是 INHERIT，但授权写 INHERIT FALSE —— 看 PG16 的"按授权继承"是否压过角色属性
-- shell_old    对照组：今天的写法，GRANT m1 TO shell_old（默认继承）
-- shell_noset  对照组：INHERIT FALSE, SET FALSE，连 SET ROLE 都不许
-- m1 / m2      两个成员角色，各自拥有自己的 schema 和表

CREATE ROLE m1 LOGIN PASSWORD 'm1';
CREATE ROLE m2 LOGIN PASSWORD 'm2';
CREATE ROLE shell LOGIN NOINHERIT PASSWORD 'shell';
CREATE ROLE shell_inh LOGIN INHERIT PASSWORD 'shell_inh';
CREATE ROLE shell_old LOGIN INHERIT PASSWORD 'shell_old';
CREATE ROLE shell_noset LOGIN NOINHERIT PASSWORD 'shell_noset';

CREATE SCHEMA s1 AUTHORIZATION m1;
CREATE SCHEMA s2 AUTHORIZATION m2;

SET ROLE m1;
CREATE TABLE s1.orders (id int PRIMARY KEY, note text);
INSERT INTO s1.orders VALUES (1, 'seed');
RESET ROLE;

SET ROLE m2;
CREATE TABLE s2.secrets (id int PRIMARY KEY, note text);
INSERT INTO s2.secrets VALUES (1, 'm2-only');
RESET ROLE;

GRANT m1 TO shell WITH INHERIT FALSE, SET TRUE;
GRANT m2 TO shell WITH INHERIT FALSE, SET TRUE;
GRANT m1 TO shell_inh WITH INHERIT FALSE, SET TRUE;
GRANT m1 TO shell_old;
GRANT m1 TO shell_noset WITH INHERIT FALSE, SET FALSE;

SELECT r.rolname AS member_of, m.rolname AS grantee, am.inherit_option, am.set_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
ORDER BY 2, 1;
