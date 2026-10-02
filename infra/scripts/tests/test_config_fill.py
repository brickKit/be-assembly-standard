"""config-fill.py 的测试：直接 `python3 infra/scripts/tests/test_config_fill.py` 运行（不依赖 pytest）。

夹具是一个最小项目：brickkit.yaml、组件与外壳的 component.yaml、`brickkit add` 风格的
config 骨架、迷你 registry/schemas.tsv 与 config/vars.yaml。
"""
import pathlib
import subprocess
import sys
import tempfile
import textwrap
import traceback

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "config-fill.py"

BRICKKIT_YAML = """\
project: t
components:
  - id: demo/app
    version: 2.0.0
  - id: be/x-y
    version: 1.0.0
    kind: shell
"""

APP_MANIFEST = """\
apiVersion: brickkit/v1
kind: Component
metadata: {id: demo/app, name: App, version: 2.0.0, description: d}
configSchema:
  type: object
  properties:
    PG_HOST: {type: string}
    PG_PORT: {type: string, default: "5432"}
    PG_DATABASE: {type: string}
    PG_USER: {type: string}
    PG_PASSWORD: {type: string, secret: true}
    PG_SCHEMA: {type: string, default: demo_app}
    NATS_URL: {type: string}
    S3_URL: {type: string, default: ""}
    OTEL_BASE_URL: {type: string, default: ""}
    AUTHZ_BUNDLE_URL: {type: string}
    IAM_JWKS_URL: {type: string}
    APP_TOKEN: {type: string, secret: true}
    LOW_STOCK_THRESHOLD: {type: integer, default: 10}
    DEFAULT_WAREHOUSE_ID: {type: string}
  required: [PG_HOST, PG_DATABASE, PG_USER, PG_PASSWORD, NATS_URL, AUTHZ_BUNDLE_URL, IAM_JWKS_URL, APP_TOKEN, DEFAULT_WAREHOUSE_ID]
deployment: {type: container, build: {context: .}, port: 8302}
"""

# brickkit add --yes 写出的骨架形态（v1.1.0 实测）；这里故意让几个共享键保持空/注释，验证脚本自己会推导
APP_SKELETON = """\
# Component: demo/app@2.0.0
# Environment variables for this component; every key is injected as-is.
# Shared variable: $var:NAME (config/vars.yaml) · environment variable: ${NAME} · local file: file://path

# === Required: startup is blocked until these have a value ===
APP_TOKEN: ""  # string | secret
AUTHZ_BUNDLE_URL: $var:AUTHZ_BUNDLE_URL  # string
DEFAULT_WAREHOUSE_ID: ""  # string
IAM_JWKS_URL: ""  # string
NATS_URL: $var:NATS_URL  # string
PG_DATABASE: $var:PG_DATABASE  # string
PG_HOST: $var:PG_HOST  # string
PG_PASSWORD: ""  # string | secret
PG_USER: ""  # string

# === Optional: commented keys use the component's default; uncomment to override ===
# LOW_STOCK_THRESHOLD: 10  # integer (default)
# OTEL_BASE_URL:  # string (default)
# PG_PORT: 5432  # string (default)
# PG_SCHEMA: demo_app  # string (default)
# S3_URL:  # string (default)
"""

SHELL_MANIFEST = """\
apiVersion: brickkit/v1
kind: Component
metadata: {id: be/x-y, name: X, version: 1.0.0, description: d}
shell:
  members: [demo/app@2.0.0]
configSchema:
  type: object
  properties:
    PG_HOST: {type: string}
    PG_PORT: {type: string, default: "5432"}
    PG_DATABASE: {type: string}
    PG_USER: {type: string}
    PG_PASSWORD: {type: string, secret: true}
    NATS_URL: {type: string}
  required: [PG_HOST, PG_DATABASE, PG_USER, PG_PASSWORD, NATS_URL]
deployment: {type: container, build: {context: .}, port: 8399}
"""

SHELL_SKELETON = """\
# Component: be/x-y@1.0.0
# === Required: startup is blocked until these have a value ===
NATS_URL: $var:NATS_URL  # string
PG_DATABASE: $var:PG_DATABASE  # string
PG_HOST: $var:PG_HOST  # string
PG_PASSWORD: ""  # string | secret
PG_USER: ""  # string

# === Optional: commented keys use the component's default; uncomment to override ===
PG_PORT: $var:PG_PORT  # string
"""

VARS = """\
# 共享值
PG_HOST: host.docker.internal
PG_PORT: "5432"
PG_DATABASE: brickkit_db
NATS_URL: nats://host.docker.internal:4222
OTEL_BASE_URL: ""
AUTHZ_BUNDLE_URL: http://infra-authz-2-0-0:8223/authz/bundle
IAM_JWKS_URL: http://infra-iam-casdoor-2-0-0:8200/.well-known/jwks.json
"""

SCHEMAS = "# repo\tschema\trole\tshell_login_role\ndemo-app\tdemo_app\tdemo_app_rw\tshell_x_y\n"


def make_root(tmp: pathlib.Path, app_skeleton: str = APP_SKELETON, cache: bool = False) -> pathlib.Path:
    files = {
        "brickkit.yaml": BRICKKIT_YAML,
        "config/vars.yaml": VARS,
        "registry/schemas.tsv": SCHEMAS,
        "config/demo-app.yaml": app_skeleton,
        "shell/be/x-y/component.yaml": SHELL_MANIFEST,
        "config/be-x-y.yaml": SHELL_SKELETON,
    }
    if cache:  # 没有本地源，只有 .brickkit/manifests 缓存
        files[".brickkit/manifests/demo/app/2.0.0/component.yaml"] = APP_MANIFEST
    else:
        files["components/demo/app/component.yaml"] = APP_MANIFEST
    for rel, body in files.items():
        p = tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")
    return tmp


def run(root: pathlib.Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), *args],
                          capture_output=True, text=True)


def values(path: pathlib.Path) -> dict:
    """只取未注释的 KEY: value 行（原文，不解析 YAML）。"""
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#") and ":" in line:
            k, _, rest = line.partition(":")
            v = rest.split("  #", 1)[0].strip()
            out[k.strip()] = v
    return out


def test_derives_shared_pg_and_password(tmp):
    root = make_root(tmp)
    r = run(root, "demo/app")
    assert r.returncode == 3, r.stdout + r.stderr          # APP_TOKEN / DEFAULT_WAREHOUSE_ID 仍缺
    v = values(root / "config/demo-app.yaml")
    assert v["PG_USER"] == "demo_app_rw", v
    assert v["PG_SCHEMA"] == "demo_app", v                  # 注释行被取消注释并写字面量
    assert v["PG_PASSWORD"] == "${DEMO_APP_DB_PASSWORD}", v
    assert v["IAM_JWKS_URL"] == "$var:IAM_JWKS_URL", v      # 空的 required 共享键
    assert v["PG_PORT"] == "$var:PG_PORT", v                # 有默认值的共享键也显式写 $var:
    assert v["OTEL_BASE_URL"] == "$var:OTEL_BASE_URL", v
    assert "S3_URL" not in v, v                             # vars.yaml 没有这个键：保持注释
    assert "LOW_STOCK_THRESHOLD" not in v, v                # 组件自有可选键：保持注释，跟随组件默认


def test_missing_required_exit3_lists_keys_and_keeps_partial_fill(tmp):
    root = make_root(tmp)
    r = run(root, "demo/app")
    assert r.returncode == 3, r.stdout + r.stderr
    out = r.stdout + r.stderr
    assert "APP_TOKEN" in out and "DEFAULT_WAREHOUSE_ID" in out, out
    assert "${DEMO_APP_APP_TOKEN}" in out, out              # 给出密钥变量名的建议写法
    missing = [l.split()[1] for l in out.splitlines() if l.startswith("   - ")]
    assert missing == ["APP_TOKEN", "DEFAULT_WAREHOUSE_ID"], out   # 只列真正缺的，每行 "   - KEY …"
    assert values(root / "config/demo-app.yaml")["PG_USER"] == "demo_app_rw"


def test_comments_preserved(tmp):
    root = make_root(tmp)
    run(root, "demo/app")
    text = (root / "config/demo-app.yaml").read_text(encoding="utf-8")
    for line in APP_SKELETON.splitlines()[:5]:
        assert line in text, line                           # 文件头与分节注释原样保留
    assert "# LOW_STOCK_THRESHOLD: 10  # integer (default)" in text
    assert "PG_USER: demo_app_rw  # string" in text          # 行尾注释保留
    assert "PG_SCHEMA: demo_app  # string\n" in text         # 取消注释后去掉 "(default)"


def test_set_values_written_verbatim(tmp):
    root = make_root(tmp)
    r = run(root, "demo/app", "--set", "APP_TOKEN=${DEMO_APP_APP_TOKEN}",
            "--set", "DEFAULT_WAREHOUSE_ID=wh-001", "--set", "LOW_STOCK_THRESHOLD=20")
    assert r.returncode == 0, r.stdout + r.stderr
    v = values(root / "config/demo-app.yaml")
    assert v["APP_TOKEN"] == "${DEMO_APP_APP_TOKEN}", v
    assert v["DEFAULT_WAREHOUSE_ID"] == "wh-001", v
    assert v["LOW_STOCK_THRESHOLD"] == "20", v              # 注释的可选键被 --set 取消注释
    assert "${" not in r.stdout.replace("${DEMO_APP_APP_TOKEN}", ""), r.stdout


def test_set_value_needing_quotes(tmp):
    root = make_root(tmp)
    r = run(root, "demo/app", "--set", "APP_TOKEN=${A}", "--set", "DEFAULT_WAREHOUSE_ID=a: b #c")
    assert r.returncode == 0, r.stdout + r.stderr
    import yaml
    d = yaml.safe_load((root / "config/demo-app.yaml").read_text(encoding="utf-8"))
    assert d["DEFAULT_WAREHOUSE_ID"] == "a: b #c", d


def test_existing_values_untouched_and_idempotent(tmp):
    skel = APP_SKELETON.replace('PG_USER: ""', "PG_USER: custom_rw").replace(
        'APP_TOKEN: ""', "APP_TOKEN: ${X}").replace('DEFAULT_WAREHOUSE_ID: ""', "DEFAULT_WAREHOUSE_ID: w1")
    root = make_root(tmp, skel)
    r = run(root, "demo/app")
    assert r.returncode == 0, r.stdout + r.stderr
    v = values(root / "config/demo-app.yaml")
    assert v["PG_USER"] == "custom_rw", v
    assert v["AUTHZ_BUNDLE_URL"] == "$var:AUTHZ_BUNDLE_URL", v
    before = (root / "config/demo-app.yaml").read_text(encoding="utf-8")
    r2 = run(root, "demo/app")
    assert r2.returncode == 0, r2.stdout + r2.stderr
    assert (root / "config/demo-app.yaml").read_text(encoding="utf-8") == before


def test_set_overrides_existing_value(tmp):
    skel = APP_SKELETON.replace('DEFAULT_WAREHOUSE_ID: ""', "DEFAULT_WAREHOUSE_ID: old")
    root = make_root(tmp, skel)
    r = run(root, "demo/app", "--set", "DEFAULT_WAREHOUSE_ID=new", "--set", "APP_TOKEN=${T}")
    assert r.returncode == 0, r.stdout + r.stderr
    assert values(root / "config/demo-app.yaml")["DEFAULT_WAREHOUSE_ID"] == "new"


def test_shell_rules(tmp):
    root = make_root(tmp)
    r = run(root, "be/x-y")
    assert r.returncode == 0, r.stdout + r.stderr
    v = values(root / "config/be-x-y.yaml")
    assert v["PG_USER"] == "shell_x_y", v
    assert v["PG_PASSWORD"] == "${SHELL_X_Y_PASSWORD}", v
    assert "PG_SCHEMA" not in v, v
    assert v["NATS_URL"] == "$var:NATS_URL", v


def test_manifest_from_cache(tmp):
    root = make_root(tmp, cache=True)
    r = run(root, "demo/app", "--set", "APP_TOKEN=${T}", "--set", "DEFAULT_WAREHOUSE_ID=w")
    assert r.returncode == 0, r.stdout + r.stderr
    assert values(root / "config/demo-app.yaml")["PG_USER"] == "demo_app_rw"


def test_unknown_set_key_rejected(tmp):
    root = make_root(tmp)
    before = (root / "config/demo-app.yaml").read_text(encoding="utf-8")
    r = run(root, "demo/app", "--set", "PG_USR=x")
    assert r.returncode == 2, r.stdout + r.stderr
    assert "PG_USR" in r.stdout + r.stderr
    assert (root / "config/demo-app.yaml").read_text(encoding="utf-8") == before


def test_missing_config_file_errors(tmp):
    root = make_root(tmp)
    (root / "config/demo-app.yaml").unlink()
    r = run(root, "demo/app")
    assert r.returncode == 2, r.stdout + r.stderr
    assert "brickkit add" in r.stdout + r.stderr


def test_key_absent_from_file_is_appended(tmp):
    skel = "\n".join(l for l in APP_SKELETON.splitlines() if not l.startswith("# PG_SCHEMA")) + "\n"
    root = make_root(tmp, skel)
    run(root, "demo/app", "--set", "APP_TOKEN=${T}", "--set", "DEFAULT_WAREHOUSE_ID=w")
    assert values(root / "config/demo-app.yaml")["PG_SCHEMA"] == "demo_app"


def main() -> int:
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        with tempfile.TemporaryDirectory() as d:
            try:
                fn(pathlib.Path(d))
                print(f"  ok   {name}")
            except Exception:  # noqa: BLE001 —— 测试运行器要接住一切失败
                failed += 1
                print(f"  FAIL {name}")
                traceback.print_exc()
    print(f"{len(tests) - failed}/{len(tests)} 通过")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
