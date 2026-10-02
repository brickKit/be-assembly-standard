// r1-04 (node-postgres): prepared statements x SET LOCAL ROLE / search_path on one pooled connection.
// Pool with max: 1, logged in as the NOINHERIT shell role. Mode "unnamed" = pg's default
// (no `name` => unnamed statement, parsed every time); mode "named" = { name, text } config,
// i.e. what an SDK would do to opt into server-side prepared-statement reuse.
import pg from 'pg';

const DSN = process.env.PG_DSN;
const MODE = process.argv[2] ?? 'unnamed';
const MEMBERS = { a: ['ra', 'a'], b: ['rb', 'b'] };
const pool = new pg.Pool({ connectionString: DSN, max: 1 });

// mode "named-member": statement name carries the member, so each member gets its own server-side statement
let current = '';
const q = (name, text, values) =>
  MODE === 'named' ? { name, text, values }
  : MODE === 'named-member' ? { name: `${current}:${name}`, text, values }
  : { text, values };

async function memberTx(member, fn) {
  const [role, schema] = MEMBERS[member];
  const c = await pool.connect();
  current = member;
  try {
    await c.query('BEGIN');
    await c.query(`SET LOCAL ROLE "${role}"`);
    await c.query(`SET LOCAL search_path TO "${schema}"`);
    const r = await fn(c);
    await c.query('COMMIT');
    return r;
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
}

async function runCase(name, order, fn) {
  console.log(`--- ${name}`);
  for (const m of order) {
    try {
      const r = await memberTx(m, fn);
      console.log(`  [${m}] OK   ${JSON.stringify(r)}`);
    } catch (e) {
      console.log(`  [${m}] ERR  ${e.message} (code=${e.code})`);
    }
  }
}

async function outside() {
  const r = await pool.query("SELECT pg_backend_pid() AS pid, current_user AS usr, current_setting('search_path') AS sp");
  return r.rows[0];
}

const alt = ['a', 'b', 'a', 'b'];
console.log(`===== pg ${(await import('pg/package.json', { with: { type: 'json' } })).default.version}, mode=${MODE}`);
console.log('before:', await outside());

await runCase('S1 same shape SELECT id, v FROM widget WHERE id=$1', alt,
  async (c) => (await c.query(q('s1', 'SELECT id, v, current_schema() AS s FROM widget WHERE id = $1', [1]))).rows[0]);
await runCase('S1 same shape UPDATE ... RETURNING', alt,
  async (c) => (await c.query(q('s1u', "UPDATE widget SET v = v || '+' WHERE id = $1 RETURNING v", [1]))).rows[0]);
await runCase('S2 different result type: SELECT id, payload FROM besdk_thing', alt,
  async (c) => (await c.query(q('s2', 'SELECT id, payload FROM besdk_thing WHERE id = $1', [1]))).rows[0]);
await runCase('S2 different result type: SELECT * FROM besdk_thing', alt,
  async (c) => (await c.query(q('s2s', 'SELECT * FROM besdk_thing WHERE id = $1', [1]))).rows[0]);
await runCase('S3 same listed types, b has extra col: SELECT id, payload FROM besdk_same', alt,
  async (c) => (await c.query(q('s3', 'SELECT id, payload FROM besdk_same WHERE id = $1', [1]))).rows[0]);
await runCase('S3 SELECT * FROM besdk_same (column count differs)', alt,
  async (c) => (await c.query(q('s3s', 'SELECT * FROM besdk_same WHERE id = $1', [1]))).rows[0]);
let id = 100;
await runCase('S4 INSERT INTO besdk_thing (id, payload) VALUES ($1,$2) (param text vs jsonb)', alt,
  async (c) => (await c.query(q('s4', 'INSERT INTO besdk_thing (id, payload) VALUES ($1, $2) RETURNING payload::text', [id++, '{"k":1}']))).rows[0]);

console.log('--- S5 isolation: role ra with search_path b');
{
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    await c.query('SET LOCAL ROLE "ra"');
    await c.query('SET LOCAL search_path TO "b"');
    console.log('  unexpected:', (await c.query('SELECT * FROM widget')).rows);
  } catch (e) {
    console.log(`  ERR (expected) ${e.message}`);
  } finally {
    await c.query('ROLLBACK');
    c.release();
  }
}
console.log('--- S6 NOINHERIT: shell login without SET ROLE reads a.widget');
try { console.log('  unexpected:', (await pool.query('SELECT * FROM a.widget')).rows); } catch (e) { console.log(`  ERR (expected) ${e.message}`); }

console.log('--- S7 leak check after commit:', await outside());
try { await memberTx('a', (c) => c.query('SELECT 1/0')); } catch (e) { console.log(`  (forced error: ${e.message})`); }
console.log('--- S7 leak check after rollback:', await outside());

const n = 2000;
const t0 = performance.now();
for (let i = 0; i < n; i++) {
  await memberTx('ab'[i % 2], (c) => c.query(q('bench', 'SELECT id, v FROM widget WHERE id = $1', [1])));
}
const dt = (performance.now() - t0) / 1000;
console.log(`--- bench: ${n} alternating member tx in ${dt.toFixed(2)}s = ${(dt / n * 1e3).toFixed(3)} ms/tx`);
await pool.end();
