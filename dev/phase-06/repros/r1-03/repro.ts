// r1-03: @grpc/grpc-js + ts-proto. (1) a service config derived from the proto's idempotency_level
// (retryPolicy + retryThrottling, P7.8) really takes effect; (2) the server's max_connection_age
// GOAWAY is absorbed by the client (P7.5); plus what the retry budget is keyed by, and keepalive enforcement.
// Run with Node 24 directly (type stripping): node repro.ts
import * as grpc from '@grpc/grpc-js';
import { EchoClient, EchoService, protoMetadata, type GetRequest, type GetResponse } from './gen/echo.ts';

const { status } = grpc;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ---- what the SDK would generate: service config from method options (NO_SIDE_EFFECTS = 1, IDEMPOTENT = 2)
function serviceConfigFrom(meta: typeof protoMetadata) {
  const fd = meta.fileDescriptor;
  const methodConfig: object[] = [];
  for (const svc of fd.service) {
    for (const m of svc.method) {
      const lvl = m.options?.idempotencyLevel ?? 0;
      if (lvl === 1 || lvl === 2) {
        methodConfig.push({
          name: [{ service: `${fd.package}.${svc.name}`, method: m.name }],
          retryPolicy: { maxAttempts: 3, initialBackoff: '0.05s', maxBackoff: '0.5s', backoffMultiplier: 2, retryableStatusCodes: ['UNAVAILABLE'] },
        });
      }
    }
  }
  return { methodConfig, retryThrottling: { maxTokens: 10, tokenRatio: 0.1 } };
}
const SERVICE_CONFIG = serviceConfigFrom(protoMetadata);

// ---- server: behaviour per request id prefix; records every attempt
type Attempt = { t: number; peer: string };
const attempts = new Map<string, Attempt[]>();
let failFirst = new Map<string, number>(); // id -> how many attempts fail with UNAVAILABLE (Infinity = always)
const peers = new Set<string>();
function record(key: string, peer: string) {
  const a = attempts.get(key) ?? [];
  a.push({ t: performance.now(), peer });
  attempts.set(key, a);
  peers.add(peer);
  return a.length;
}
const impl = {
  get(call: grpc.ServerUnaryCall<GetRequest, GetResponse>, cb: grpc.sendUnaryData<GetResponse>) {
    const n = record(call.request.id, call.getPeer());
    if (n <= (failFirst.get(call.request.id) ?? 0)) return cb({ code: status.UNAVAILABLE, details: `injected #${n}` });
    setTimeout(() => cb(null, { id: call.request.id, peer: call.getPeer() }), call.request.sleepMs);
  },
  create(call: grpc.ServerUnaryCall<{ idempotencyKey: string }, { id: string }>, cb: grpc.sendUnaryData<{ id: string }>) {
    const n = record(call.request.idempotencyKey, call.getPeer());
    if (n <= (failFirst.get(call.request.idempotencyKey) ?? 0)) return cb({ code: status.UNAVAILABLE, details: `injected #${n}` });
    cb(null, { id: call.request.idempotencyKey });
  },
};
async function startServer(opts: grpc.ServerOptions = {}) {
  const s = new grpc.Server({ 'grpc.max_receive_message_length': 4 << 20, ...opts });
  s.addService(EchoService, impl);
  const port = await new Promise<number>((res, rej) => s.bindAsync('127.0.0.1:0', grpc.ServerCredentials.createInsecure(), (e, p) => (e ? rej(e) : res(p))));
  return { s, port };
}
const clientOpts = {
  'grpc.service_config': JSON.stringify(SERVICE_CONFIG),
  'grpc.keepalive_time_ms': 30_000, 'grpc.keepalive_timeout_ms': 10_000, 'grpc.keepalive_permit_without_calls': 0, // P7.6
};
const mk = (target: string, extra: object = {}) => new EchoClient(target, grpc.credentials.createInsecure(), { ...clientOpts, ...extra });
const get = (c: InstanceType<typeof EchoClient>, id: string, sleepMs = 0, deadlineMs = 5000) =>
  new Promise<string>((res) => c.get({ id, sleepMs }, new grpc.Metadata(), { deadline: Date.now() + deadlineMs }, (e, r) => res(e ? `ERR ${status[e.code]}` : 'OK')));
const create = (c: InstanceType<typeof EchoClient>, key: string) =>
  new Promise<string>((res) => c.create({ idempotencyKey: key }, new grpc.Metadata(), { deadline: Date.now() + 5000 }, (e) => res(e ? `ERR ${status[e.code]}` : 'OK')));
const gaps = (id: string) => {
  const a = attempts.get(id) ?? [];
  return a.slice(1).map((x, i) => Math.round(x.t - a[i].t));
};

const pkg = (p: string) => (process as any).getBuiltinModule('module').createRequire(import.meta.url)(`${p}/package.json`).version;
console.log(`===== node ${process.version}, @grpc/grpc-js ${pkg('@grpc/grpc-js')}, ts-proto ${pkg('ts-proto')}`);
console.log('service config derived from protoMetadata:', JSON.stringify(SERVICE_CONFIG));

// ---------------- R1-R3 retry policy
{
  const { s, port } = await startServer();
  const c = mk(`127.0.0.1:${port}`);
  failFirst = new Map([['r1', 2], ['r2', Infinity], ['r3', Infinity]]);
  console.log('R1 Get (NO_SIDE_EFFECTS), first 2 attempts UNAVAILABLE:', await get(c, 'r1'), `attempts=${attempts.get('r1')?.length} gaps(ms)=${gaps('r1')}`);
  console.log('R2 Get, always UNAVAILABLE (maxAttempts 3):', await get(c, 'r2'), `attempts=${attempts.get('r2')?.length} gaps(ms)=${gaps('r2')}`);
  console.log('R3 Create (no idempotency level), always UNAVAILABLE:', await create(c, 'r3'), `attempts=${attempts.get('r3')?.length}`);
  c.close(); s.forceShutdown();
}

// ---------------- R4 retry throttling (maxTokens 10, tokenRatio 0.1) and what the budget is keyed by
{
  const { s, port } = await startServer();
  const ids = Array.from({ length: 6 }, (_, i) => `t${i}`);
  failFirst = new Map([...ids, 'other-ch', 'other-ch-local', 'other-target'].map((id) => [id, Infinity]));
  const a = mk(`127.0.0.1:${port}`);
  const per: number[] = [];
  for (const id of ids) { await get(a, id); per.push(attempts.get(id)!.length); }
  console.log('R4 channel A, 6 failing Get calls, attempts per call:', per.join(','));
  const b = mk(`127.0.0.1:${port}`, { 'grpc.use_local_subchannel_pool': 1, 'grpc.primary_user_agent': 'member-b' });
  await get(b, 'other-ch-local');
  console.log('R4 channel B (new channel, same target string, local subchannel pool), first failing call attempts:', attempts.get('other-ch-local')!.length);
  const d = mk(`dns:///127.0.0.1:${port}`);
  await get(d, 'other-target');
  console.log(`R4 channel D (same server, target spelled "dns:///127.0.0.1:${port}"), first failing call attempts:`, attempts.get('other-target')!.length);
  a.close(); b.close(); d.close(); s.forceShutdown();
}

// ---------------- R5 max_connection_age -> GOAWAY under steady load, no client-visible errors?
async function ageRun(label: string, ageMs: number, graceMs: number, slowMs: number) {
  failFirst = new Map();
  peers.clear();
  const { s, port } = await startServer({ 'grpc.max_connection_age_ms': ageMs, 'grpc.max_connection_age_grace_ms': graceMs });
  const c = mk(`127.0.0.1:${port}`);
  const results = new Map<string, number>();
  const bump = (k: string) => results.set(k, (results.get(k) ?? 0) + 1);
  const end = Date.now() + 7000;
  let i = 0;
  const loops = Array.from({ length: 8 }, (_, w) => (async () => {
    while (Date.now() < end) {
      const n = i++;
      bump(`${w % 2 ? 'Create' : 'Get'} ${w % 2 ? await create(c, `k${n}`) : await get(c, `g${n}`)}`);
    }
  })());
  // one long call straddling the first GOAWAY
  await sleep(ageMs - 300);
  const slow = await get(c, 'slow', slowMs, 10_000);
  await Promise.all(loops);
  console.log(`${label} age=${ageMs}ms grace=${graceMs}ms: ${JSON.stringify(Object.fromEntries(results))}; distinct client connections seen by server=${peers.size}; slow ${slowMs}ms call started ~300ms before GOAWAY: ${slow}`);
  c.close(); s.forceShutdown();
}
await ageRun('R5a', 2000, 3000, 2500);
await ageRun('R5b', 2000, 500, 2500);

// ---------------- R6 keepalive enforcement: does a grpc-js server police client ping rate (grpc-go EnforcementPolicy.MinTime)?
{
  peers.clear();
  const { s, port } = await startServer({ 'grpc.http2.min_ping_interval_without_data_ms': 20_000 } as grpc.ServerOptions);
  const c = mk(`127.0.0.1:${port}`, { 'grpc.keepalive_time_ms': 100, 'grpc.keepalive_permit_without_calls': 1 });
  await get(c, 'ka1');
  await sleep(3000); // ~30 pings while idle
  console.log('R6 client pings every 100ms for 3s while idle, then calls again:', await get(c, 'ka2'),
    `same connection=${attempts.get('ka1')![0].peer === attempts.get('ka2')![0].peer}`);
  c.close(); s.forceShutdown();
}
