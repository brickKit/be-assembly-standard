"""r1-03b (Python): read (be.v1.max_items) from the generated descriptors at runtime (grpcio-tools output)."""
import google.protobuf
import grpc
from google.protobuf import descriptor_pool

import batch_pb2
from be.v1 import limits_pb2

print(f"===== grpcio {grpc.__version__}, protobuf {google.protobuf.__version__}")
from google.protobuf.internal import api_implementation
print("protobuf backend:", api_implementation.Type())

ext = limits_pb2.max_items
print("P1 extension:", ext.full_name, "number", ext.number)


def limits(desc, prefix=""):
    for f in desc.fields:
        rep = f.is_repeated() if callable(f.is_repeated) else f.is_repeated
        if rep:
            o = f.GetOptions()
            yield prefix + f.name, (o.Extensions[ext] if o.HasExtension(ext) else 500), o.HasExtension(ext)
        elif f.message_type is not None:
            yield from limits(f.message_type, prefix + f.name + ".")


req = batch_pb2.BatchGetWidgetsRequest.DESCRIPTOR
print("P2 limits:", list(limits(req)))
# Same lookup starting from the method path, as a server interceptor would see it
svc = batch_pb2.DESCRIPTOR.services_by_name["Widgets"]
m = svc.methods_by_name["BatchGetWidgets"]
print("P3 by method path:", f"/{svc.full_name}/{m.name}", "->", m.input_type.full_name, list(limits(m.input_type)))
print("P3 method idempotency_level:", m.GetOptions().idempotency_level)
# Through the default pool by name (no import of the generated module needed by the SDK)
d = descriptor_pool.Default().FindMessageTypeByName("r1.batch.v1.BatchGetWidgetsRequest")
print("P4 via default pool:", d.fields_by_name["ids"].GetOptions().Extensions[ext])
