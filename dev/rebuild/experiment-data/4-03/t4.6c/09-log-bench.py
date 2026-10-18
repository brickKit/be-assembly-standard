"""Encode and decode of a 1 KiB request body and a 100 KiB event payload with the standard library's json,
pydantic_core (already installed with FastAPI), orjson and msgspec: microseconds per operation, best of 5 rounds."""
import json, sys, timeit
import msgspec, orjson, pydantic_core

small = {"payload": "e" * 1024}
big = {"blob": "x" * (100 * 1024), "items": [{"sku": f"SKU-{i}", "qty": i, "price": "12.50"} for i in range(200)]}
enc = {"json": lambda o: json.dumps(o, ensure_ascii=False, separators=(",", ":")).encode(),
       "pydantic_core": pydantic_core.to_json, "orjson": orjson.dumps, "msgspec": msgspec.json.encode}
dec = {"json": json.loads, "pydantic_core": pydantic_core.from_json, "orjson": orjson.loads, "msgspec": msgspec.json.decode}
print(sys.version.split()[0], "jit" if getattr(sys, "_jit", None) and sys._jit.is_enabled() else "no-jit")
for name, obj in (("1 KiB", small), ("100 KiB", big)):
    data = enc["json"](obj)
    for lib in enc:
        n = 2000 if name == "1 KiB" else 200
        e = min(timeit.repeat(lambda: enc[lib](obj), number=n, repeat=5)) / n * 1e6
        d = min(timeit.repeat(lambda: dec[lib](data), number=n, repeat=5)) / n * 1e6
        print(f"{name:8} {lib:14} encode {e:8.1f} us  decode {d:8.1f} us")
