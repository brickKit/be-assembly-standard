// r1-08: Fastify 5 — several instances in one process (the TS shell launcher), each on its own port,
// each with its own hooks, error handler, logger, request context, server timeouts and body limit.
import Fastify from 'fastify';
import { AsyncLocalStorage } from 'node:async_hooks';
import net from 'node:net';
import { Writable } from 'node:stream';
import { createRequire } from 'node:module';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const als = new AsyncLocalStorage(); // ONE process-wide ALS, as the SDK would have
const logLines = [];
const sink = new Writable({ write(chunk, _e, cb) { logLines.push(JSON.parse(chunk)); cb(); } });

function member(id, { headersMs, bodyLimit, handlerTimeout }) {
  const hits = { onRequest: 0, preHandler: 0, onSend: 0, onError: 0, onResponse: 0 };
  const app = Fastify({
    logger: { level: 'info', base: { component: id }, stream: sink },
    bodyLimit, // P3.6
    handlerTimeout, // route deadline (P3.4); Fastify answers 503 by itself, remapped to 504 below
    keepAliveTimeout: 120_000, // P3.5 idle connection
    requestTimeout: 30_000, // P3.5 whole request
    http: { headersTimeout: headersMs, connectionsCheckingInterval: 200 }, // P3.5 headers; see R5 for the default interval
  });
  for (const h of Object.keys(hits)) {
    app.addHook(h, h === 'onSend' ? async (_req, _rep, payload) => { hits[h]++; return payload; } : async () => { hits[h]++; });
  }
  // request context: run() wrapping the rest of the lifecycle (callback-style hook)
  app.addHook('onRequest', (req, _rep, done) => als.run({ member: id, reqId: req.id }, done));
  app.setErrorHandler((err, req, reply) => {
    const map = { FST_ERR_CTP_BODY_TOO_LARGE: [413, 'BODY_TOO_LARGE'], FST_ERR_HANDLER_TIMEOUT: [504, 'DEADLINE_EXCEEDED'] };
    const [code, reason] = map[err.code] ?? [500, 'INTERNAL'];
    reply.code(code).type('application/problem+json').send({ status: code, reason, member: id, ctx: als.getStore()?.member ?? null });
  });
  app.get('/whoami', async (req) => {
    await sleep(20); // cross an await: does the context survive?
    req.log.info({ ctxMember: als.getStore()?.member }, 'handled');
    return { member: id, ctx: als.getStore() ?? null };
  });
  app.post('/upload', async (req) => ({ bytes: JSON.stringify(req.body).length }));
  app.post('/upload-big', { bodyLimit: 4 << 20 }, async (req) => ({ bytes: JSON.stringify(req.body).length }));
  app.get('/slow', async (req) => {
    await sleep(1500);
    return { aborted: req.signal?.aborted ?? 'n/a' };
  });
  app.addHook('onClose', async () => { hits.onClose = (hits.onClose ?? 0) + 1; });
  return { id, app, hits };
}

// slowloris: open a TCP connection, send a partial request line + one header, then nothing; time until server closes
function slowloris(port) {
  return new Promise((res) => {
    const t0 = performance.now();
    const s = net.connect(port, '127.0.0.1', () => s.write('GET /whoami HTTP/1.1\r\nHost: x\r\n'));
    let data = '';
    s.on('data', (d) => { data += d; });
    s.on('close', () => res(`${Math.round(performance.now() - t0)}ms ${data.split('\r\n')[0] || '(no response)'}`));
  });
}

const fver = createRequire(import.meta.url)('fastify/package.json').version;
console.log(`===== node ${process.version}, fastify ${fver}`);
const A = member('erp/sales', { headersMs: 1000, bodyLimit: 1 << 20, handlerTimeout: 1000 });
const B = member('erp/finance', { headersMs: 3000, bodyLimit: 1 << 20, handlerTimeout: 0 });
await A.app.listen({ port: 0, host: '127.0.0.1' });
await B.app.listen({ port: 0, host: '127.0.0.1' });
const pa = A.app.server.address().port;
const pb = B.app.server.address().port;
console.log(`F1 two instances listening: A=${pa} B=${pb}`);

const j = async (port, path, init) => { const r = await fetch(`http://127.0.0.1:${port}${path}`, init); return `${r.status} ${await r.text()}`; };
// concurrent requests to both, so contexts interleave
const rs = await Promise.all([j(pa, '/whoami'), j(pb, '/whoami'), j(pa, '/whoami'), j(pb, '/whoami')]);
console.log('F2 /whoami x4 interleaved:', rs.map((r) => r.replace(/"reqId":"[^"]+"/, '"reqId":…')).join(' | '));
console.log('F3 hook counts after 2 requests each: A', JSON.stringify(A.hits), 'B', JSON.stringify(B.hits));
await j(pa, '/nope');
console.log('F3 after one 404 on A only: A.onRequest', A.hits.onRequest, 'B.onRequest', B.hits.onRequest);
console.log('F4 log lines carry their own component:', logLines.filter((l) => l.msg === 'handled').map((l) => `${l.component}/ctx=${l.ctxMember}`).join(', '));

const big = JSON.stringify({ x: 'a'.repeat(2 << 20) });
console.log('F5 A POST 2 MiB to /upload (limit 1 MiB):', await j(pa, '/upload', { method: 'POST', body: big, headers: { 'content-type': 'application/json' } }));
console.log('F5 A POST 2 MiB to /upload-big (route limit 4 MiB):', await j(pa, '/upload-big', { method: 'POST', body: big, headers: { 'content-type': 'application/json' } }));
console.log('F6 A /slow (handlerTimeout 1000ms, handler 1500ms):', await j(pa, '/slow'));
console.log('F6 B /slow (no handlerTimeout):', await j(pb, '/slow'));
console.log('F7 slowloris (partial headers): A (headersTimeout 1000)', await slowloris(pa), '| B (headersTimeout 3000)', await slowloris(pb));

await A.app.close();
console.log('F8 after A.close(): B still serves ->', await j(pb, '/whoami').then((r) => r.slice(0, 3)), '; A ->', await j(pa, '/whoami').catch((e) => `ERR ${e.cause?.code}`),
  '; onClose A', A.hits.onClose, 'B', B.hits.onClose ?? 0);
await B.app.close();

// R5: the same headersTimeout without connectionsCheckingInterval (Node default 30 s)
const C = Fastify({ http: { headersTimeout: 1000 } });
C.get('/', async () => 'ok');
await C.listen({ port: 0, host: '127.0.0.1' });
console.log('F9 headersTimeout 1000 with default connectionsCheckingInterval:', await slowloris(C.server.address().port),
  `(server.connectionsCheckingInterval default ${C.server.connectionsCheckingInterval ?? 'n/a'})`);
await C.close();
