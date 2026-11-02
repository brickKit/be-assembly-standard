// R1 #6（TS 部分）：node-pg-migrate 9 的编程接口 runner()。
// 验证：1) 默认是否忽略 migrations/lifecycle.yaml；2) 状态表能否放进组件 schema；
// 3) 同一 schema 两套状态表（组件 + SDK 平台）；4) 两个组件同时迁移（不同 schema）时的默认锁。
import { runner } from "node-pg-migrate";
import pg from "pg";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const dsn = process.env.DSN;
const schema = process.env.PG_SCHEMA;
const schema2 = process.env.PG_SCHEMA2; // 第二个组件（并发锁测试用），各自的 DSN 由 DSN2 给
const dsn2 = process.env.DSN2;
const quiet = { info() {}, warn() {}, error() {}, debug() {} };

const base = (over = {}) => ({
  databaseUrl: dsn,
  dir: join(here, "migrations"),
  direction: "up",
  schema,                                // runner 会执行会话级 SET search_path（迁移连接可以）
  migrationsSchema: schema,
  migrationsTable: `pgmigrations_${schema}`,
  checkOrder: true,
  logger: quiet,
  ...over,
});

let failed = 0;
async function step(name, fn, { expectError } = {}) {
  try {
    const r = await fn();
    if (expectError) { console.log(`FAIL ${name}: expected an error`); failed++; }
    else console.log(`PASS ${name}${r ? ": " + r : ""}`);
  } catch (e) {
    if (expectError && expectError.test(String(e.message))) console.log(`PASS ${name} (expected error): ${e.message.split("\n")[0]}`);
    else { console.log(`FAIL ${name}: ${e.message.split("\n")[0]}`); failed++; }
  }
}
const names = (ms) => ms.map((m) => m.name).join(",") || "(none)";

// N1 默认配置：目录里有 lifecycle.yaml
await step("N1 default options with lifecycle.yaml", async () => names(await runner(base())),
  { expectError: /./ });

// N2 加 ignorePattern 只认 .sql（ignorePattern 是"整名匹配"的正则：^(...)$）
const ignore = String.raw`(\..*)|(.*(?<!\.sql))`;
await step("N2 ignorePattern skips non-.sql", async () => names(await runner(base({ ignorePattern: ignore }))));

// N3 SDK 平台迁移：同一 schema，另一张状态表
await step("N3 platform migrations, second state table", async () =>
  names(await runner(base({ dir: join(here, "platform"), migrationsTable: `besdk_migrations_${schema}`, ignorePattern: ignore }))));

await step("N4 component up again (no-op)", async () => names(await runner(base({ ignorePattern: ignore }))));
await step("N5 component down 1", async () => names(await runner(base({ ignorePattern: ignore, direction: "down", count: 1 }))));
await step("N5b component up after down", async () => names(await runner(base({ ignorePattern: ignore }))));

// N6 两个组件（不同 schema、不同库用户）同时迁移：默认锁是全库常量 7241865325823964，模式 fail
const slow = (s, d, over = {}) => runner({ ...base({ ignorePattern: ignore }), databaseUrl: d, schema: s, migrationsSchema: s,
  migrationsTable: `pgmigrations_${s}`, dir: join(here, "slow"), ...over });
await step("N6 concurrent, default lock", async () => {
  const rs = await Promise.allSettled([
    slow(schema, dsn, { migrationsTable: `slowdef_${schema}` }),
    slow(schema2, dsn2, { migrationsTable: `slowdef_${schema2}` })]);
  const errs = rs.filter((r) => r.status === "rejected").map((r) => r.reason.message);
  if (errs.length) throw new Error(errs.join(" | "));
}, { expectError: /Another migration is already running/ });

// N7 同上，但锁键按 schema 派生、模式 wait
const lockFor = (s) => { let h = 0; for (const c of s) h = (h * 31 + c.charCodeAt(0)) | 0; return Math.abs(h); };
await step("N7 concurrent, per-schema lockValue", async () => {
  const rs = await Promise.allSettled([
    slow(schema, dsn, { migrationsTable: `slow_${schema}`, lockValue: lockFor(schema), advisoryLockMode: "wait" }),
    slow(schema2, dsn2, { migrationsTable: `slow_${schema2}`, lockValue: lockFor(schema2), advisoryLockMode: "wait" })]);
  const errs = rs.filter((r) => r.status === "rejected").map((r) => r.reason.message);
  if (errs.length) throw new Error(errs.join(" | "));
});

const c = new pg.Client({ connectionString: dsn });
await c.connect();
const { rows } = await c.query(`SELECT table_schema||'.'||table_name AS t FROM information_schema.tables
  WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY 1`);
for (const r of rows) console.log("TABLE", r.t);
await c.end();
process.exit(failed ? 1 : 0);
