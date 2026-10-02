"""verify-component.sh 的测试：--deploy-only（只算闭包、生成 deploy.verify.yaml），以及用 PATH 上的假
brickkit / docker / curl 跑完整流程（鉴权判据、迁移判据、KEEP/FOCUS 取值、中断时的收尾）——不碰真实 Docker。
直接 `python3 infra/scripts/tests/test_verify_deploy.py` 运行（不依赖 pytest）。
"""
import os
import pathlib
import shlex
import signal
import subprocess
import time
import sys
import tempfile
import traceback

import yaml

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "verify-component.sh"

# 依赖：sales → customer、product（必需）、notification（可选，未加入项目）；opportunity → customer；
#       iam-casdoor → authz；外壳 be/go-core 托管 customer、sales；print 无关
MANIFESTS = {
    "mdm/customer": {"port": 8080, "migration": True},
    "mdm/product": {"port": 8081},
    "erp/sales": {"port": 8100, "deps": ["mdm/customer@2.0.0", "mdm/product@2.0.0",
                                         {"id": "infra/notification@2.0.0", "optional": True}]},
    "crm/opportunity": {"port": 8110, "deps": ["mdm/customer@2.0.0", {"id": "erp/sales@2.0.0", "optional": True}]},
    "infra/authz": {"port": 8223},
    "infra/iam-casdoor": {"port": 8200, "deps": ["infra/authz@2.0.0"]},
    "infra/print": {"port": 8400},
}


def make(tmp: pathlib.Path, ids, deploy_components, shells=None) -> pathlib.Path:
    shells = shells or {}
    comps = [{"id": i, "version": "2.0.0"} for i in ids] + \
            [{"id": s, "version": "1.0.0", "kind": "shell"} for s in shells]
    (tmp / "brickkit.yaml").write_text(yaml.safe_dump({"project": "t", "components": comps}), encoding="utf-8")
    for cid, spec in MANIFESTS.items():
        m = {"apiVersion": "brickkit/v1", "kind": "Component",
             "metadata": {"id": cid, "version": "2.0.0"},
             "deployment": {"type": "container", "port": spec["port"]}}
        if spec.get("deps"):
            m["dependencies"] = {"components": spec["deps"]}
        if spec.get("migration"):
            m["migration"] = {"command": ["./migrate", "up"]}
        p = tmp / "components" / cid / "component.yaml"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(yaml.safe_dump(m), encoding="utf-8")
    for sid, members in shells.items():
        m = {"apiVersion": "brickkit/v1", "kind": "Component", "metadata": {"id": sid, "version": "1.0.0"},
             "shell": {"members": [f"{x}@2.0.0" for x in members]},
             "deployment": {"type": "container", "port": 8090}}
        p = tmp / "shell" / sid / "component.yaml"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(yaml.safe_dump(m), encoding="utf-8")
    (tmp / "deploy.yaml").write_text(yaml.safe_dump({"target": "docker", "vars": {"PG_HOST": "h"},
                                                     "components": deploy_components}), encoding="utf-8")
    return tmp


def run(root: pathlib.Path, cid: str):
    out = root / "deploy.verify.yaml"
    r = subprocess.run(["bash", str(SCRIPT), cid, "--deploy-only", str(out)], capture_output=True, text=True,
                       env={**os.environ, "BE_ROOT": str(root)})
    vars_ = {}
    for line in r.stdout.splitlines():
        k, _, v = line.partition("=")
        vars_[k] = (shlex.split(v) or [""])[0]
    d = yaml.safe_load(out.read_text(encoding="utf-8")) if out.exists() else None
    return r, vars_, d


def modes(d) -> dict:
    out = {}
    for e in d["components"]:
        out[e["id"]] = e.get("mode")
        for m in e.get("members") or []:
            out[f"{e['id']}>{m['id']}"] = m.get("mode")
    return out


ALL = ["mdm/customer", "mdm/product", "erp/sales", "crm/opportunity", "infra/print"]


def test_dependency_target_enabled_rest_disabled(tmp):
    root = make(tmp, ALL, [{"id": i} for i in ALL])
    r, v, d = run(root, "mdm/customer")
    assert r.returncode == 0, r.stdout + r.stderr
    m = modes(d)
    assert m["mdm/customer"] == "enabled", m          # 被依赖的组件不会自己启动：显式 enabled
    for other in ("mdm/product", "erp/sales", "crm/opportunity", "infra/print"):
        assert m[other] == "disable", m
    assert d["vars"] == {"PG_HOST": "h"} and d["target"] == "docker"   # 其余内容原样
    assert v["KEEP_IDS"] == "mdm/customer@2.0.0", v
    assert v["SVC"] == "mdm-customer-2-0-0" and v["PORT"] == "8080" and v["IS_SHELL"] == "0", v


def test_closure_follows_required_and_present_optional(tmp):
    root = make(tmp, ALL, [{"id": i} for i in ALL])
    r, v, d = run(root, "crm/opportunity")
    assert r.returncode == 0, r.stdout + r.stderr
    keep = set(v["KEEP_IDS"].split())
    # opportunity → customer（必需）、sales（可选且在项目里）→ product；notification 不在项目里，不进闭包
    assert keep == {"crm/opportunity@2.0.0", "mdm/customer@2.0.0", "erp/sales@2.0.0", "mdm/product@2.0.0"}, keep
    assert modes(d)["infra/print"] == "disable"


def test_authz_and_iam_always_kept_when_in_project(tmp):
    ids = ALL + ["infra/authz", "infra/iam-casdoor"]
    root = make(tmp, ids, [{"id": i} for i in ids])
    r, v, d = run(root, "mdm/product")
    assert r.returncode == 0, r.stdout + r.stderr
    m = modes(d)
    assert m["infra/authz"] == "enabled" and m["infra/iam-casdoor"] == "enabled", m
    assert m["mdm/customer"] == "disable", m


def test_shell_with_closure_member_kept_whole(tmp):
    deploy = [{"id": "mdm/product"}, {"id": "crm/opportunity"}, {"id": "infra/print"},
              {"id": "be/go-core", "members": [{"id": "mdm/customer"}, {"id": "erp/sales"}]}]
    root = make(tmp, ALL, deploy, shells={"be/go-core": ["mdm/customer", "erp/sales"]})
    r, v, d = run(root, "mdm/customer")
    assert r.returncode == 0, r.stdout + r.stderr
    m = modes(d)
    assert m["be/go-core"] == "enabled", m
    assert m["be/go-core>mdm/customer"] is None and m["be/go-core>erp/sales"] is None, m
    # 外壳里的 sales 必需 product：外壳整个保留，product 也得跑
    assert m["mdm/product"] == "enabled", m
    assert m["crm/opportunity"] == "disable" and m["infra/print"] == "disable", m


def test_disabled_shell_members_disabled_too(tmp):
    deploy = [{"id": "mdm/product"}, {"id": "infra/print"},
              {"id": "be/go-core", "members": [{"id": "mdm/customer"}, {"id": "erp/sales"}]}]
    ids = ["mdm/customer", "mdm/product", "erp/sales", "infra/print"]
    root = make(tmp, ids, deploy, shells={"be/go-core": ["mdm/customer", "erp/sales"]})
    r, v, d = run(root, "infra/print")
    assert r.returncode == 0, r.stdout + r.stderr
    m = modes(d)
    assert m["be/go-core"] == "disable", m
    assert m["be/go-core>mdm/customer"] == "disable" and m["be/go-core>erp/sales"] == "disable", m


def test_shell_target_lists_members(tmp):
    deploy = [{"id": "mdm/product"}, {"id": "infra/print"},
              {"id": "be/go-core", "members": [{"id": "mdm/customer"}, {"id": "erp/sales"}]}]
    ids = ["mdm/customer", "mdm/product", "erp/sales", "infra/print"]
    root = make(tmp, ids, deploy, shells={"be/go-core": ["mdm/customer", "erp/sales"]})
    r, v, d = run(root, "be/go-core")
    assert r.returncode == 0, r.stdout + r.stderr
    assert v["IS_SHELL"] == "1", v
    assert v["MEMBERS"].split() == ["mdm/customer@2.0.0|mdm-customer-2-0-0|8080", "erp/sales@2.0.0|erp-sales-2-0-0|8100"], v
    assert modes(d)["infra/print"] == "disable"


def test_target_not_in_project_fails(tmp):
    root = make(tmp, ["mdm/customer"], [{"id": "mdm/customer"}])
    r, _, _ = run(root, "erp/sales")
    assert r.returncode != 0
    assert "make integrate" in r.stdout + r.stderr


def test_disabled_target_fails_early(tmp):  # 修复轮 M-8
    deploy = [{"id": i} for i in ALL]
    deploy[0]["mode"] = "disable"                       # mdm/customer
    root = make(tmp, ALL, deploy)
    r, _, _ = run(root, "mdm/customer")
    assert r.returncode != 0, r.stdout + r.stderr
    assert "mode: disable" in r.stdout + r.stderr, r.stdout + r.stderr


# ---------- 用假 brickkit / docker / curl 跑完整流程 ----------
FAKE_BRICKKIT = """#!/bin/sh
[ "$1" = version ] && { echo "BrickKit CLI ${FAKE_BK_VERSION:-v1.1.0}"; exit 0; }
echo "brickkit $*" >> "$FAKE_CALLS"
case "$1 $2" in
  "local status") echo "Local mode: ${FAKE_LOCAL_MODE:-off}" ;;
  "local off") [ -n "$FAKE_LOCAL_OFF_FAIL" ] && exit 1 ;;
  "local on") [ -f "$BE_ROOT/deploy.local.yaml" ] || cp "$BE_ROOT/deploy.yaml" "$BE_ROOT/deploy.local.yaml" ;;
  "up --focus")
    [ -n "$FAKE_FOCUS_SNAPSHOT" ] && { cp "$BE_ROOT/deploy.local.yaml" "$FAKE_FOCUS_SNAPSHOT"; exit 1; }
    echo $$ > "$FAKE_FOCUS_PID"; exec sleep 300 ;;
esac
exit 0
"""
FAKE_DOCKER = r"""#!/bin/sh
echo "docker $*" >> "$FAKE_CALLS"
case "$1" in
  ps) case "$*" in *com.docker.compose.service=*) echo fakectr ;; esac ;;
  inspect) case "$*" in *RestartCount*) echo "0 running" ;; *) echo "running healthy" ;; esac ;;
  run)
    case "$*" in
      *"getent hosts hgw"*) [ -n "$FAKE_GW_EMPTY" ] || echo "172.17.0.1      hgw  hgw" ;;
      *" -d "*) echo toolbox ;;
      *Authorization*) printf 200 ;;
      *"/healthz") printf 200 ;;
      *) printf 401 ;;
    esac ;;
  exec)
    case "$*" in
      *access_token*) echo '{"id_token":"idt"}' ;;
      *get-application*) echo '{"data":{"clientId":"c","clientSecret":"s"}}' ;;
      *get-user*)
        case "$FAKE_SUB" in
          null) echo '{"status":"ok","data":null}' ;;
          ok) echo '{"data":{"id":"u1"}}' ;;
          *) echo '<html>502 Bad Gateway</html>' ;;
        esac ;;
      *api/iam/token*) echo '{"access_token":"tok"}' ;;
    esac ;;
esac
exit 0
"""
FAKE_CURL = "#!/bin/sh\nprintf 000\nexit 7\n"


def fake_env(tmp: pathlib.Path, **extra) -> dict:
    b = tmp / "fakebin"
    b.mkdir(exist_ok=True)
    for name, body in (("brickkit", FAKE_BRICKKIT), ("docker", FAKE_DOCKER), ("curl", FAKE_CURL)):
        (b / name).write_text(body, encoding="utf-8")
        (b / name).chmod(0o755)
    env = {**os.environ, "PATH": f"{b}:{os.environ['PATH']}", "BE_ROOT": str(tmp), "OUT": str(tmp / "out"),
           "FAKE_CALLS": str(tmp / "calls"), "FAKE_FOCUS_PID": str(tmp / "focus.pid"),
           "BE_PROJECT_LOCK": str(tmp / "lock"), "ROUTE": "", "FOCUS": "", "KEEP": "", "FAKE_FOCUS_SNAPSHOT": "",
           "FAKE_LOCAL_MODE": "", "FAKE_LOCAL_OFF_FAIL": "", "SEED": "", "FAKE_GW_EMPTY": ""}
    env.pop("BE_PROJECT_LOCK_HELD", None)
    env.update(extra)
    return env


def verify(tmp, cid, **extra):
    return subprocess.run(["bash", str(SCRIPT), cid], capture_output=True, text=True, env=fake_env(tmp, **extra),
                          timeout=120)


def rows(tmp) -> dict:
    out = {}
    for line in (tmp / "out" / "summary.md").read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 4 and cells[1] in ("PASS", "FAIL", "SKIP"):
            out[cells[0]] = (cells[1], cells[2], cells[3])
    return out


def calls(tmp) -> str:
    p = tmp / "calls"
    return p.read_text(encoding="utf-8") if p.exists() else ""


IDS_AUTH = ALL + ["infra/authz", "infra/iam-casdoor"]


def row_like(rs: dict, needle: str):
    hits = [v for k, v in rs.items() if needle in k]
    assert hits, (needle, rs)
    return hits[0]


def test_token_skip_only_when_casdoor_says_no_user(tmp):  # 修复轮 I-3
    make(tmp, IDS_AUTH, [{"id": i} for i in IDS_AUTH])
    verify(tmp, "mdm/product", ROUTE="GET /api/x", FAKE_SUB="null")
    st, why, _ = row_like(rows(tmp), "带 token → 200")
    assert st == "SKIP" and "种子" in why, (st, why)


def test_token_casdoor_broken_is_fail_with_log(tmp):  # 修复轮 I-3 + M-7
    make(tmp, IDS_AUTH, [{"id": i} for i in IDS_AUTH])
    verify(tmp, "mdm/product", ROUTE="GET /api/x", FAKE_SUB="broken")
    st, why, logf = row_like(rows(tmp), "带 token → 200")
    assert st == "FAIL", (st, why)
    assert logf and (tmp / "out" / logf).stat().st_size > 0, logf   # token.log 里有原因


def test_token_ok_is_pass(tmp):
    make(tmp, IDS_AUTH, [{"id": i} for i in IDS_AUTH])
    verify(tmp, "mdm/product", ROUTE="GET /api/x", FAKE_SUB="ok")
    assert row_like(rows(tmp), "带 token → 200")[0] == "PASS"
    assert row_like(rows(tmp), "不带 token →")[0] == "PASS"


def test_declared_migration_without_container_fails(tmp):  # 修复轮 M-6
    make(tmp, ALL, [{"id": i} for i in ALL])
    verify(tmp, "mdm/customer")
    assert row_like(rows(tmp), "迁移")[0] == "FAIL"
    verify(tmp, "mdm/product")                               # 没声明迁移：SKIP
    assert row_like(rows(tmp), "迁移")[0] == "SKIP"


def test_keep_and_focus_only_on_with_1(tmp):  # 修复轮 M-5
    make(tmp, ALL, [{"id": i} for i in ALL])
    verify(tmp, "mdm/product", KEEP="0", FOCUS="0", FORCE_BUILD="0")
    c = calls(tmp)
    assert "brickkit down -f" in c, c
    assert "up --focus" not in c, c
    assert "--force" not in c, c


def test_normal_teardown_runs_once(tmp):  # 修复轮 I-2：trap 与正常收尾不重复
    make(tmp, ALL, [{"id": i} for i in ALL])
    verify(tmp, "mdm/product")
    assert calls(tmp).count("brickkit down -f") == 1, calls(tmp)
    assert not (tmp / "deploy.verify.yaml").exists()


def _interrupt_during_focus(tmp, keep: str, wrapper_only: bool = False, setup=None):
    make(tmp, ALL, [{"id": i} for i in ALL])
    if setup:
        setup(tmp)
    extra = {} if wrapper_only else {"BE_PROJECT_LOCK_HELD": "1"}
    p = subprocess.Popen(["bash", str(SCRIPT), "mdm/product"], env=fake_env(tmp, FOCUS="1", KEEP=keep, **extra),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    pidf = tmp / "focus.pid"
    for _ in range(100):
        if pidf.exists() and pidf.read_text().strip():
            break
        time.sleep(0.2)
    assert pidf.exists(), calls(tmp)
    focus_pid = int(pidf.read_text())
    time.sleep(1)
    if wrapper_only:
        p.send_signal(signal.SIGTERM)   # 只发给 project-lock 包装进程（timeout / kill <pid> 的情形）
    else:
        os.killpg(p.pid, signal.SIGTERM)   # 像 Ctrl+C / 超时那样发给整个前台进程组（p 就是 verify 本身，便于等它收尾完）
    p.wait(timeout=60)
    time.sleep(0.5)
    alive = True
    try:
        os.kill(focus_pid, 0)
    except ProcessLookupError:
        alive = False
    return alive, calls(tmp)


def test_focus_rewrites_host_docker_internal_and_removes_its_local_copy(tmp):
    """focus 是宿主机进程：config/vars.yaml 里的 host.docker.internal 在宿主机解析不了，verify 在 deploy.local.yaml
    的 vars: 里换成 host-gateway IP（容器与宿主机都能到）；deploy.local.yaml 是 verify 建的就在收尾时删掉。"""
    make(tmp, ALL, [{"id": i} for i in ALL])
    (tmp / "config").mkdir(exist_ok=True)
    (tmp / "config" / "vars.yaml").write_text(
        "PG_HOST: host.docker.internal\nNATS_URL: nats://host.docker.internal:4222\nOTEL_BASE_URL: ''\n", encoding="utf-8")
    snap = tmp / "focus-local.yaml"
    verify(tmp, "mdm/product", FOCUS="1", FAKE_FOCUS_SNAPSHOT=str(snap))
    assert snap.exists(), calls(tmp)
    v = (yaml.safe_load(snap.read_text(encoding="utf-8")) or {}).get("vars") or {}
    assert v.get("NATS_URL") == "nats://172.17.0.1:4222", v
    assert v.get("PG_HOST") == "h", v                    # deploy 文件里已有的 vars 不覆盖
    assert "OTEL_BASE_URL" not in v, v
    assert not (tmp / "deploy.local.yaml").exists(), "verify 建的 deploy.local.yaml 应在收尾时删掉"


def test_focus_restores_existing_local_copy(tmp):
    make(tmp, ALL, [{"id": i} for i in ALL])
    (tmp / "config").mkdir(exist_ok=True)
    (tmp / "config" / "vars.yaml").write_text("NATS_URL: nats://host.docker.internal:4222\n", encoding="utf-8")
    before = "# 我的个人副本\ntarget: docker\ncomponents: []\n"
    (tmp / "deploy.local.yaml").write_text(before, encoding="utf-8")
    verify(tmp, "mdm/product", FOCUS="1", FAKE_FOCUS_SNAPSHOT=str(tmp / "snap.yaml"))
    assert (tmp / "deploy.local.yaml").read_text(encoding="utf-8") == before


VARS_HDI = "PG_HOST: host.docker.internal\nNATS_URL: nats://host.docker.internal:4222\n"
USER_LOCAL = "# 我的个人副本\ntarget: docker\ncomponents: []\n"


def _vars(tmp):
    (tmp / "config").mkdir(exist_ok=True)
    (tmp / "config" / "vars.yaml").write_text(VARS_HDI, encoding="utf-8")


def _user_local(tmp):
    _vars(tmp)
    (tmp / "deploy.local.yaml").write_text(USER_LOCAL, encoding="utf-8")


def test_focus_stale_local_copy_set_aside(tmp):
    """本地模式关着却留有 deploy.local.yaml：focus 不沿用它，用从 deploy.yaml 新复制的一份；收尾放回原文。"""
    make(tmp, ALL, [{"id": i} for i in ALL])
    _user_local(tmp)
    snap = tmp / "snap.yaml"
    r = verify(tmp, "mdm/product", FOCUS="1", FAKE_FOCUS_SNAPSHOT=str(snap))
    d = yaml.safe_load(snap.read_text(encoding="utf-8"))
    assert [c["id"] for c in d["components"]] == ALL, d          # 来自 deploy.yaml，不是过期副本的 components: []
    assert d["vars"]["NATS_URL"] == "nats://172.17.0.1:4222", d
    assert "我的个人副本" not in snap.read_text(encoding="utf-8")
    assert (tmp / "deploy.local.yaml").read_text(encoding="utf-8") == USER_LOCAL
    assert "移到" in r.stdout, r.stdout


def test_focus_local_mode_on_uses_and_restores_personal_copy(tmp):
    make(tmp, ALL, [{"id": i} for i in ALL])
    _user_local(tmp)
    snap = tmp / "snap.yaml"
    verify(tmp, "mdm/product", FOCUS="1", FAKE_FOCUS_SNAPSHOT=str(snap), FAKE_LOCAL_MODE="on")
    d = yaml.safe_load(snap.read_text(encoding="utf-8"))
    assert d["components"] == [] and d["vars"]["PG_HOST"] == "172.17.0.1", d   # 用的是正在用的个人副本
    assert (tmp / "deploy.local.yaml").read_text(encoding="utf-8") == USER_LOCAL


def test_local_off_failure_still_restores(tmp):
    make(tmp, ALL, [{"id": i} for i in ALL])
    _vars(tmp)
    verify(tmp, "mdm/product", FOCUS="1", FAKE_FOCUS_SNAPSHOT=str(tmp / "s1.yaml"), FAKE_LOCAL_OFF_FAIL="1")
    assert rows(tmp)["brickkit local off"][0] == "FAIL", rows(tmp)
    assert not (tmp / "deploy.local.yaml").exists(), "local off 失败时也要删掉 verify 自己建的副本"
    (tmp / "deploy.local.yaml").write_text(USER_LOCAL, encoding="utf-8")
    verify(tmp, "mdm/product", FOCUS="1", FAKE_FOCUS_SNAPSHOT=str(tmp / "s2.yaml"), FAKE_LOCAL_OFF_FAIL="1",
           FAKE_LOCAL_MODE="on")
    assert (tmp / "deploy.local.yaml").read_text(encoding="utf-8") == USER_LOCAL


def test_interrupt_removes_created_local_copy(tmp):
    alive, c = _interrupt_during_focus(tmp, keep="", setup=_vars)
    assert not alive, "focus 进程还活着"
    assert not (tmp / "deploy.local.yaml").exists(), c


def test_interrupt_with_keep_restores_local_copy(tmp):
    alive, c = _interrupt_during_focus(tmp, keep="1", setup=_user_local)
    assert not alive, "focus 进程还活着"
    assert "brickkit down" not in c, c                       # KEEP 照样保留容器
    assert "brickkit local off" in c, c
    assert (tmp / "deploy.local.yaml").read_text(encoding="utf-8") == USER_LOCAL


def test_focus_no_host_gateway_ip_degrades_without_rewrite(tmp):  # T7 审查 (e)：getent 查不到时降级
    make(tmp, ALL, [{"id": i} for i in ALL])
    _vars(tmp)
    snap = tmp / "snap.yaml"
    r = verify(tmp, "mdm/product", FOCUS="1", FAKE_FOCUS_SNAPSHOT=str(snap), FAKE_GW_EMPTY="1")
    assert "查不到 host-gateway 的 IP，focus 不改写 host.docker.internal" in r.stdout, r.stdout
    assert snap.read_text(encoding="utf-8") == (tmp / "deploy.yaml").read_text(encoding="utf-8")   # local on 的原样副本
    assert not (tmp / "deploy.local.yaml").exists()


def test_interrupt_restores_set_aside_local_copy(tmp):  # T7 审查 (e)：中断后 deploy.local.yaml 与原文逐字节相同
    alive, c = _interrupt_during_focus(tmp, keep="", setup=_user_local)
    assert not alive, "focus 进程还活着"
    assert "brickkit down -f" in c, c
    assert (tmp / "deploy.local.yaml").read_bytes() == USER_LOCAL.encode("utf-8")


def test_interrupt_cleans_up(tmp):  # 修复轮 I-2
    alive, c = _interrupt_during_focus(tmp, keep="")
    assert not alive, "focus 进程还活着"
    assert "brickkit local off" in c and "brickkit down -f" in c, c
    assert not (tmp / "deploy.verify.yaml").exists()


def test_interrupt_wrapper_only_still_cleans_up(tmp):  # 修复轮 2：project-lock 转发 TERM 并等子进程收尾
    alive, c = _interrupt_during_focus(tmp, keep="", wrapper_only=True)
    assert not alive, "focus 进程还活着"
    assert "brickkit local off" in c and "brickkit down -f" in c, c


def test_interrupt_with_keep_leaves_containers(tmp):
    alive, c = _interrupt_during_focus(tmp, keep="1")
    assert not alive, "focus 进程还活着（KEEP 只保留容器，不留宿主机进程）"
    assert "brickkit down" not in c, c


def test_wrong_brickkit_version_refused(tmp):  # T7 审查 Important 2：~/go/bin 的旧 CLI 遮住 v1.1.0
    make(tmp, ALL, [{"id": i} for i in ALL])
    r = verify(tmp, "mdm/product", FAKE_BK_VERSION="v0.4.6")
    assert r.returncode == 2, r.stdout + r.stderr
    assert f"❌ PATH 上的 brickkit 是 {tmp / 'fakebin' / 'brickkit'}：BrickKit CLI v0.4.6" in r.stderr, r.stderr
    assert calls(tmp) == "", calls(tmp)                     # 一条 brickkit / docker 命令都没跑
    assert not (tmp / "deploy.verify.yaml").exists()


def test_deploy_only_needs_no_brickkit(tmp):  # --deploy-only 不调 brickkit，不做版本核对
    root = make(tmp, ALL, [{"id": i} for i in ALL])
    r = subprocess.run(["bash", str(SCRIPT), "mdm/customer", "--deploy-only", str(tmp / "v.yaml")],
                       capture_output=True, text=True, env=fake_env(tmp, FAKE_BK_VERSION="v0.4.6"))
    assert r.returncode == 0 and (tmp / "v.yaml").exists(), r.stdout + r.stderr


SEED_MK = "seed:\n\t@echo \"make seed $$SEED\" >> \"$$FAKE_CALLS\"\n"


def _makefile(tmp, cid, body):
    (tmp / "components" / cid / "Makefile").write_text(body, encoding="utf-8")


def test_seed_runs_after_health_before_teardown(tmp):  # T7 审查 (c)-2：SEED=1 替代"拷回 deploy.verify.yaml 再起"
    make(tmp, ALL, [{"id": i} for i in ALL])
    _makefile(tmp, "mdm/product", "all:\n\t@true\n" + SEED_MK)
    verify(tmp, "mdm/product", SEED="1")   # 假 docker 没有镜像，镜像检查总是 FAIL：这里只看 seed 那一行
    st, why, logf = row_like(rows(tmp), "seed")
    assert st == "PASS" and logf.endswith("seed.log"), (st, why, logf)
    c = calls(tmp)
    assert "make seed 1" in c, c
    assert c.index("brickkit up -f") < c.index("make seed") < c.index("brickkit down -f"), c   # 起来之后、收尾之前


def test_seed_failure_is_fail(tmp):
    make(tmp, ALL, [{"id": i} for i in ALL])
    _makefile(tmp, "mdm/product", "seed:\n\t@echo 种子炸了; exit 1\n")
    verify(tmp, "mdm/product", SEED="1")
    st, _, logf = row_like(rows(tmp), "seed")
    assert st == "FAIL", st
    assert "种子炸了" in (tmp / "out" / logf).read_text(encoding="utf-8")
    assert "brickkit down -f" in calls(tmp)                  # 种子失败照样收尾


def test_seed_without_target_skips_with_reason(tmp):
    make(tmp, ALL, [{"id": i} for i in ALL])
    _makefile(tmp, "mdm/product", "test:\n\t@echo \"make test\" >> \"$$FAKE_CALLS\"\n")
    verify(tmp, "mdm/product", SEED="1")   # 假 docker 没有镜像，镜像检查总是 FAIL：这里只看 seed 那一行
    st, why, _ = row_like(rows(tmp), "seed")
    assert st == "SKIP" and "没有 seed 目标" in why, (st, why)
    assert "make test" not in calls(tmp)                     # 只探测目标，不跑别的
    (tmp / "components" / "mdm/product" / "Makefile").unlink()
    verify(tmp, "mdm/product", SEED="1")
    st, why, _ = row_like(rows(tmp), "seed")
    assert st == "SKIP" and "Makefile" in why, (st, why)


def test_seed_only_with_1(tmp):
    make(tmp, ALL, [{"id": i} for i in ALL])
    _makefile(tmp, "mdm/product", SEED_MK)
    verify(tmp, "mdm/product", SEED="0")
    st, why, _ = row_like(rows(tmp), "seed")
    assert st == "SKIP" and "SEED=1" in why, (st, why)
    assert "make seed" not in calls(tmp), calls(tmp)


def main() -> int:
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        with tempfile.TemporaryDirectory() as d:
            try:
                fn(pathlib.Path(d))
                print(f"  ok   {name}")
            except Exception:  # noqa: BLE001
                failed += 1
                print(f"  FAIL {name}")
                traceback.print_exc()
    print(f"{len(tests) - failed}/{len(tests)} 通过")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
