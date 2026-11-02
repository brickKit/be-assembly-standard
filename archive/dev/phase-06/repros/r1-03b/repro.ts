// r1-03b: can the TS SDK read (be.v1.max_items) from ts-proto output at runtime and enforce P7.10?
// Generated with outputServices=grpc-js,outputSchema=true (the r1-03 options). Run: node repro.ts
import * as grpc from "@grpc/grpc-js";
import { protoMetadata, WidgetsService, WidgetsClient } from "./gen/batch.ts";

const DEFAULT_MAX = 500; // P7.10: no option -> 500
type Limit = { field: string; prop: string; max: number; explicit: boolean; nested?: Limits };
type Limits = Limit[];

console.log("R1 protoMetadata.options =", JSON.stringify(protoMetadata.options));
const reqDesc = protoMetadata.fileDescriptor.messageType.find((m) => m.name === "BatchGetWidgetsRequest")!;
console.log("R2 fileDescriptor field 'ids' options keys =", Object.keys(reqDesc.field[0].options ?? {}).join(","));

// Build limits for one message type from the descriptor (field names, labels, json names) plus the
// ts-proto custom-option table (keyed by proto field name, nested messages under `nested`).
function limitsFor(msg: any, opts: any, pkgPath: string): Limits {
  const out: Limits = [];
  for (const f of msg.field) {
    const fo = opts?.fields?.[f.name];
    if (f.label === 3) {
      const v = fo?.["max_items"];
      out.push({ field: f.name, prop: f.jsonName, max: v ?? DEFAULT_MAX, explicit: v !== undefined });
    } else if (f.type === 11) { // message-typed singular field: descend into nested types of this file
      const short = f.typeName.split(".").pop();
      const nmsg = msg.nestedType.find((n: any) => n.name === short);
      if (nmsg) out.push({ field: f.name, prop: f.jsonName, max: 0, explicit: false, nested: limitsFor(nmsg, opts?.nested?.[short], pkgPath) });
    }
  }
  return out;
}
const byMethod = new Map<string, Limits>();
for (const svc of protoMetadata.fileDescriptor.service) {
  for (const m of svc.method) {
    const name = m.inputType.split(".").pop()!;
    const msg = protoMetadata.fileDescriptor.messageType.find((x) => x.name === name)!;
    byMethod.set(`/${protoMetadata.fileDescriptor.package}.${svc.name}/${m.name}`, limitsFor(msg, protoMetadata.options?.messages?.[name], ""));
  }
}
console.log("R3 limits by method =", JSON.stringify([...byMethod]));

function check(limits: Limits, req: any, prefix = ""): { field: string; max: number; got: number } | undefined {
  for (const l of limits) {
    const v = req?.[l.prop];
    if (l.nested) { const r = check(l.nested, v, prefix + l.field + "."); if (r) return r; continue; }
    if (Array.isArray(v) && v.length > l.max) return { field: prefix + l.field, max: l.max, got: v.length };
  }
}

// SDK-style wrapper: every unary handler checks its request against the limits of its method path.
function enforce(def: typeof WidgetsService, impl: any): any {
  const out: any = {};
  for (const [k, d] of Object.entries(def)) {
    const limits = byMethod.get(d.path) ?? [];
    out[k] = (call: any, cb: any) => {
      const bad = check(limits, call.request);
      if (bad) return cb({ code: grpc.status.INVALID_ARGUMENT, details: `BATCH_TOO_LARGE ${JSON.stringify(bad)}` });
      return impl[k](call, cb);
    };
  }
  return out;
}

const server = new grpc.Server();
server.addService(WidgetsService, enforce(WidgetsService, {
  batchGetWidgets: (call: any, cb: any) => cb(null, { ids: call.request.ids }),
}));
const port = await new Promise<number>((res, rej) =>
  server.bindAsync("127.0.0.1:0", grpc.ServerCredentials.createInsecure(), (e, p) => (e ? rej(e) : res(p))));
const client = new WidgetsClient(`127.0.0.1:${port}`, grpc.credentials.createInsecure());
const n = (k: number) => Array.from({ length: k }, (_, i) => `w${i}`);
const cases: [string, any][] = [
  ["ids=100 (limit 100)", { ids: n(100), tags: [], widgetIds: [] }],
  ["ids=101", { ids: n(101), tags: [], widgetIds: [] }],
  ["tags=500 (no option)", { ids: [], tags: n(500), widgetIds: [] }],
  ["tags=501", { ids: [], tags: n(501), widgetIds: [] }],
  ["widget_ids=3 (limit 2)", { ids: [], tags: [], widgetIds: n(3) }],
  ["filter.sku_ids=8 (limit 7)", { ids: [], tags: [], widgetIds: [], filter: { skuIds: n(8) } }],
];
for (const [name, req] of cases) {
  await new Promise<void>((res) => client.batchGetWidgets(req, (err, r) => {
    console.log(`R4 ${name}: ${err ? `ERR ${grpc.status[err.code]} ${err.details}` : `OK ${r!.ids.length} ids`}`);
    res();
  }));
}
client.close();
server.forceShutdown();
