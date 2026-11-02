// r1-07 (nats.js v3: @nats-io/jetstream + @nats-io/transport-node): same scenarios as ../go/main.go.
import { connect, nanos, millis } from '@nats-io/transport-node';
import { jetstream, jetstreamManager, AckPolicy, DeliverPolicy, DiscardPolicy, StorageType } from '@nats-io/jetstream';
import { readFileSync } from 'node:fs';

const SEG = 'r1js';
const STREAM = 'BE_' + SEG.toUpperCase();
const BO = [200, 500, 1000];
const DAY = 24 * 3600 * 1000;
const durableName = (component, subject) => component.replaceAll('/', '_') + '__' + subject.replaceAll('.', '_'); // P12.5
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const errOr = (p) => p.then(() => 'ok', (e) => `ERR ${e.name}: ${e.message}${e.api_error ? ` err_code=${e.api_error.err_code}` : ''}`);

const nc = await connect({ servers: process.env.NATS_URL });
const jsm = await jetstreamManager(nc);
const js = jetstream(nc);
await jsm.streams.delete(STREAM).catch(() => {});
await jsm.streams.add({ name: STREAM, subjects: [SEG + '.>'], max_age: nanos(7 * DAY), max_bytes: 2 ** 30,
  discard: DiscardPolicy.Old, duplicate_window: nanos(600_000), storage: StorageType.File, num_replicas: 1 });
const ver = (p) => JSON.parse(readFileSync(new URL(`./node_modules/${p}/package.json`, import.meta.url))).version;
console.log(`===== @nats-io/jetstream ${ver('@nats-io/jetstream')}, server ${nc.info.version}`);

const cfg = (name, subject, kw) => ({ durable_name: name, filter_subject: subject, ack_policy: AckPolicy.Explicit, ...kw });
const pub = async (subject, n) => { for (let i = 0; i < n; i++) await js.publish(subject, JSON.stringify({ n: i })); };
const D = (ms) => nanos(ms);

const subj = SEG + '.order.confirmed.v1';
await pub(subj, 3);
const name = durableName('crm/opportunity', subj);
const base = { deliver_policy: DeliverPolicy.All, ack_wait: D(30_000), max_ack_pending: 256, max_deliver: 8,
  inactive_threshold: D(30 * DAY), backoff: [1, 10, 60, 300, 900, 1800, 3600].map((s) => D(s * 1000)) };
const info = await jsm.consumers.add(STREAM, cfg(name, subj, base));
console.log(`T1 durable ${JSON.stringify(name)} created; hyphen variant -> ${await errOr(jsm.consumers.add(STREAM, cfg(durableName('infra/iam-casdoor', subj), subj, base)))}`);
const c = info.config;
console.log(`T1 config read back: AckWait=${millis(c.ack_wait)}ms MaxDeliver=${c.max_deliver} BackOff=${c.backoff.map(millis)}ms InactiveThreshold=${millis(c.inactive_threshold)}ms MaxAckPending=${c.max_ack_pending}`);
{
  const cons = await js.consumers.get(STREAM, name);
  const it = await cons.fetch({ max_messages: 10, expires: 1000 });
  let n = 0;
  for await (const m of it) { n++; m.ack(); }
  console.log(`T2 DeliverAll on first create: fetched ${n} of 3 pre-existing events`);
}
console.log('T3 consumers.add again, identical config:', await errOr(jsm.consumers.add(STREAM, cfg(name, subj, base))));
console.log('T3 consumers.add again, MaxDeliver 8->9:', await errOr(jsm.consumers.add(STREAM, cfg(name, subj, { ...base, max_deliver: 9 }))));
console.log('T3 consumers.update MaxDeliver 8->9:', await errOr(jsm.consumers.update(STREAM, name, { max_deliver: 9 })),
  '; MaxDeliver now', (await jsm.consumers.info(STREAM, name)).config.max_deliver);

console.log('T4a BackOff len 3, MaxDeliver 2:', await errOr(jsm.consumers.add(STREAM, cfg('t4a', SEG + '.t4a', { ack_wait: D(30_000), max_deliver: 2, backoff: BO.map(D) }))));
await jsm.consumers.add(STREAM, cfg('t4a2', SEG + '.t4a', { ack_wait: D(30_000), max_deliver: 4, backoff: BO.map(D) }));
console.log('T4a stored AckWait when AckWait=30s and BackOff[0]=200ms:', millis((await jsm.consumers.info(STREAM, 't4a2')).config.ack_wait), 'ms');

const advisories = [];
const advSub = nc.subscribe(`$JS.EVENT.ADVISORY.CONSUMER.MAX_DELIVERIES.${STREAM}.>`);
(async () => { for await (const m of advSub) { const a = m.json(); advisories.push(`${m.subject}: consumer=${a.consumer} stream_seq=${a.stream_seq} deliveries=${a.deliveries}`); } })();

async function setup(n, kw) {
  await jsm.consumers.add(STREAM, cfg(n, `${SEG}.${n}`, kw));
  await pub(`${SEG}.${n}`, 1);
  return n;
}
// record (+seconds since first delivery, deliveryCount) for every delivery during `window` ms
async function consume(n, window, handler, concurrent = false) {
  const cons = await js.consumers.get(STREAM, n);
  const out = []; const tasks = []; let start = 0;
  const end = Date.now() + window;
  while (Date.now() < end) {
    const m = await cons.next({ expires: 1000 }).catch(() => null);
    if (!m) continue;
    start ||= performance.now();
    out.push(`+${((performance.now() - start) / 1000).toFixed(2)}s(n=${m.info.deliveryCount})`);
    const p = handler(m, out.length);
    if (concurrent) tasks.push(p); else await p;
  }
  await Promise.all(tasks);
  return out;
}
const slow = (every) => async (m, d) => {
  if (d > 1) { m.ack(); return; }
  const end = Date.now() + 4000;
  while (Date.now() < end) { await sleep(every || 100); if (every) m.working(); }
  m.ack();
};

console.log('T4b no ack (timeout path), BackOff 200ms,500ms,1s MaxDeliver 4:',
  await consume(await setup('t4b', { ack_wait: D(30_000), max_deliver: 4, backoff: BO.map(D) }), 4000, async () => {}));
console.log('T4c nak() each time, same BackOff:',
  await consume(await setup('t4c', { ack_wait: D(30_000), max_deliver: 4, backoff: BO.map(D) }), 3000, async (m) => m.nak()));
const t4e = await setup('t4e', { ack_wait: D(30_000), max_deliver: 4 });
console.log('T4e stored AckWait without BackOff:', millis((await jsm.consumers.info(STREAM, t4e)).config.ack_wait), 'ms');
console.log('T4e no BackOff, AckWait 30s, nak(EVENTS_BACKOFF[n-1]):',
  await consume(t4e, 4000, async (m, d) => m.nak(BO[Math.min(d - 1, BO.length - 1)])));
await sleep(500);
for (const a of advisories) console.log('T4 advisory', a);

console.log('T5a AckWait 2s, slow handler 4s with working() every 0.66s (AckWait/3):',
  await consume(await setup('t5a', { ack_wait: D(2000), max_deliver: 5 }), 8000, slow(660), true));
console.log('T5b control, slow handler 4s, no working():',
  await consume(await setup('t5b', { ack_wait: D(2000), max_deliver: 5 }), 8000, slow(0), true));
console.log('T5c AckWait 6s + BackOff [1s,2s,3s], handler 4s, working() every 2s (AckWait/3):',
  await consume(await setup('t5c', { ack_wait: D(6000), max_deliver: 5, backoff: [1000, 2000, 3000].map(D) }), 9000, slow(2000), true));
console.log('T5d same, working() every 330ms (BackOff[0]/3):',
  await consume(await setup('t5d', { ack_wait: D(6000), max_deliver: 5, backoff: [1000, 2000, 3000].map(D) }), 9000, slow(330), true));
await nc.close();
