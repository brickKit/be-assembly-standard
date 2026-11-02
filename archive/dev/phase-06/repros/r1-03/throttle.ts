// r1-03 follow-up (asked after R1a's grpc-go findings): in grpc-js,
//  M1 maxAttempts semantics (total incl. the first attempt?) and its cap;
//  M2 how many successes re-enable retries after the budget is exhausted;
//  M3 does a resolver update (re-resolution after GOAWAY) refill the budget, as grpc-go does?
// Run: GRPC_TRACE=resolving_load_balancer,ip_resolver GRPC_VERBOSITY=DEBUG node throttle.ts 2> trace.log
import * as grpc from '@grpc/grpc-js';
import { EchoClient, EchoService, type GetRequest, type GetResponse } from './gen/echo.ts';

const { status } = grpc;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const mark = (s: string) => { console.log(s); console.error(`#### ${new Date().toISOString()} ${s}`); };
const sc = (maxAttempts: number) => JSON.stringify({
  methodConfig: [{ name: [{ service: 'r1.echo.v1.Echo', method: 'Get' }],
    retryPolicy: { maxAttempts, initialBackoff: '0.05s', maxBackoff: '0.5s', backoffMultiplier: 2, retryableStatusCodes: ['UNAVAILABLE'] } }],
  retryThrottling: { maxTokens: 10, tokenRatio: 0.1 },
});

const attempts = new Map<string, number>();
const failFirst = new Map<string, number>();
const impl = {
  get(call: grpc.ServerUnaryCall<GetRequest, GetResponse>, cb: grpc.sendUnaryData<GetResponse>) {
    const n = (attempts.get(call.request.id) ?? 0) + 1;
    attempts.set(call.request.id, n);
    const ff = failFirst.get(call.request.id) ?? (call.request.id.startsWith('fail') ? Infinity : 0);
    if (n <= ff) return cb({ code: status.UNAVAILABLE, details: 'injected' });
    cb(null, { id: call.request.id, peer: call.getPeer() });
  },
  create(_c: unknown, cb: grpc.sendUnaryData<{ id: string }>) { cb(null, { id: '' }); },
};
async function server(opts: grpc.ServerOptions = {}) {
  const s = new grpc.Server(opts);
  s.addService(EchoService, impl);
  const port = await new Promise<number>((res, rej) => s.bindAsync('127.0.0.1:0', grpc.ServerCredentials.createInsecure(), (e, p) => (e ? rej(e) : res(p))));
  return { s, port };
}
let seq = 0;
const call = (c: InstanceType<typeof EchoClient>, id: string) =>
  new Promise<number>((res) => c.get({ id, sleepMs: 0 }, new grpc.Metadata(), { deadline: Date.now() + 5000 }, () => res(attempts.get(id) ?? 0)));
const fails = async (c: InstanceType<typeof EchoClient>, n: number) => { const a = []; for (let i = 0; i < n; i++) a.push(await call(c, `fail${seq++}`)); return a; };
const oks = async (c: InstanceType<typeof EchoClient>, n: number) => { for (let i = 0; i < n; i++) await call(c, `ok${seq++}`); };
// probe: first attempt fails, a retry would succeed -> attempts 2 iff a retry was allowed
const probe = async (c: InstanceType<typeof EchoClient>) => { const id = `probe${seq++}`; failFirst.set(id, 1); return call(c, id); };

// grpc-js keys the budget by the canonical target string ("127.0.0.1:P" == "dns:127.0.0.1:P"), so every
// measurement below gets its own server port = its own fresh bucket.
const fresh = async (maxAttempts: number, opts: grpc.ServerOptions = {}, host = '127.0.0.1', copts: object = {}) => {
  const srv = await server(opts);
  const c = new EchoClient(`${host}:${srv.port}`, grpc.credentials.createInsecure(), { 'grpc.service_config': sc(maxAttempts), ...copts });
  return { c, close: () => { c.close(); srv.s.forceShutdown(); } };
};
// M1
for (const m of [2, 3, 4, 5, 6, 10]) {
  const { c, close } = await fresh(m);
  mark(`M1 maxAttempts=${m}: attempts on an always-UNAVAILABLE Get = ${(await fails(c, 1))[0]}`);
  close();
}
// M2: exhaust to 0 tokens, then n successes, then probe
for (const n of [60, 61]) {
  const { c, close } = await fresh(3);
  const f = await fails(c, 12);
  await oks(c, n);
  mark(`M2 12 failing calls -> attempts ${f.join(',')}; then ${n} successes; probe attempts=${await probe(c)} (2 = retries back on)`);
  close();
}
// M3 re-resolution: server rotates connections every 1 s (GOAWAY) -> client goes IDLE, reconnects, re-resolves "localhost"
{
  const { c, close } = await fresh(3, { 'grpc.max_connection_age_ms': 1000, 'grpc.max_connection_age_grace_ms': 500 }, 'localhost',
    { 'grpc.dns_min_time_between_resolutions_ms': 100 }); // default 30 s would suppress the re-resolution
  const f = await fails(c, 12);
  mark(`M3 target localhost: exhausted, attempts ${f.join(',')}; probe right away attempts=${await probe(c)}`);
  for (let i = 0; i < 6; i++) { await oks(c, 1); await sleep(500); } // ~3 s: 2-3 GOAWAY/reconnect cycles, only +0.6 tokens earned
  mark(`M3 after 3 s of connection rotation (+6 successes = +0.6 tokens): probe attempts=${await probe(c)} (2 = budget was refilled)`);
  close();
}
