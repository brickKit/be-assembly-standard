import sys, re, pathlib, yaml
for cell in sys.argv[1:]:
    g = pathlib.Path(cell) / ".brickkit/generated"
    print("==", pathlib.Path(cell).name)
    if (g / "compose.yaml").exists():
        d = yaml.safe_load((g / "compose.yaml").read_text())
        for name, s in d["services"].items():
            env = s.get("environment") or {}
            if isinstance(env, list):
                env = dict(e.split("=", 1) for e in env)
            hc = " ".join(map(str, (s.get("healthcheck") or {}).get("test", [])))
            hp = re.search(r"localhost:(\d+)", hc)
            print(f"  {name:45} PORT={env.get('PORT','-'):6} health={hp.group(1) if hp else '-'}")
    else:
        for f in sorted((g / "k8s").rglob("*.yaml")):
            for doc in yaml.safe_load_all(f.read_text()):
                if not doc or doc.get("kind") != "Deployment": continue
                for c in doc["spec"]["template"]["spec"]["containers"]:
                    env = {e["name"]: e.get("value") for e in c.get("env", [])}
                    cp = [p["containerPort"] for p in c.get("ports", [])]
                    print(f"  {doc['metadata']['name']:45} PORT={env.get('PORT','-'):6} containerPort={cp}")
