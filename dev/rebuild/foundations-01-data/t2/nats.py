import json
import sys

d = json.load(sys.stdin)
test = []
for a in d.get("account_details", []):
    for s in a.get("stream_detail", []):
        if not s["name"].startswith(("BE_ERP_", "BE_MDM_")):
            test.append(f'{s["name"]}({s["state"]["messages"]} msgs, {len(s.get("consumer_detail") or [])} consumers)')
print("nats test streams:", len(test), " ".join(sorted(test)) or "none")
