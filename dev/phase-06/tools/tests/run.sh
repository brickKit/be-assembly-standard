#!/usr/bin/env bash
# 一次性迁移工具包的测试：在 scratch 里克隆真实组件仓库（带 tag），对克隆跑四个脚本并断言。
# 绝不碰 components/ 下的子模块：所有写操作都发生在 $BE_SCRATCH/06b-tools-test/ 里的克隆上
# （工具靠 BE_COMP_DIR 指向克隆）。
#
# 用法：BE_SCRATCH=<会话 scratchpad> bash dev/phase-06/tools/tests/run.sh
#       TEST_SDK=v0.4.0 可换 SDK 版本（默认 v0.3.2）；TEST_KEEP=1 保留上一次的克隆不重建（只用于调试）
set -uo pipefail

TOOLS=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(cd "$TOOLS/../../.." && pwd)
: "${BE_SCRATCH:?请先设置 BE_SCRATCH=<会话 scratchpad 目录>}"
W=$BE_SCRATCH/06b-tools-test
SDK=${TEST_SDK:-v0.3.2}
LOG=$W/logs
export BE_SCRATCH=$W/scratch          # 工具自己的 $S 也放进测试目录

PASS=0; FAIL=0; FAILED=()
ok()  { echo "  ✅ $*"; PASS=$((PASS+1)); }
bad() { echo "  ❌ $*"; FAIL=$((FAIL+1)); FAILED+=("$*"); }
section() { echo; echo "━━━ $*"; }
# check <描述> <命令…>：命令成功即通过
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
# run_tool <日志名> <组件目录> <命令…>：把输出写进日志，返回命令的退出码；失败时把日志尾部打出来
run_tool() {
  local name=$1 dir=$2; shift 2
  BE_COMP_DIR=$dir "$@" >"$LOG/$name.log" 2>&1; local rc=$?
  echo "  · $name → exit=$rc（日志 $LOG/$name.log）"
  return $rc
}
show_log() { echo "    ┌── $1.log 末尾"; tail -n 25 "$LOG/$1.log" | sed 's/^/    │ /'; echo "    └──"; }
expect_rc() {  # expect_rc <期望码> <日志名> <组件目录> <命令…>
  local want=$1 name=$2; shift 2
  run_tool "$name" "$@"; local rc=$?
  if [ "$rc" = "$want" ]; then ok "$name 退出码 $rc"; else bad "$name 退出码 $rc（期望 $want）"; show_log "$name"; fi
}
log_has() { grep -qE -- "$2" "$LOG/$1.log"; }
clean_tree() { [ -z "$(git -C "$1" status --short)" ]; }
commit_all() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }

ALL13="crm/opportunity erp/finance erp/inventory erp/sales infra/authz infra/bff-mobile infra/iam-casdoor
infra/notification infra/print infra/workflow integration/im-dingtalk mdm/customer mdm/product"

clone() {  # clone <id> <目标目录>：本机克隆（带全部 tag），不经过网络
  local id=$1 dst=$2
  # --no-hardlinks：scratch 与仓库可能不在同一个文件系统上，--local 的硬链接会失败
  git clone -q --no-hardlinks "$ROOT/components/$id" "$dst" || { echo "克隆 $id 失败" >&2; exit 2; }
}

if [ "${TEST_KEEP:-}" != 1 ] || [ ! -d "$W" ]; then
  rm -rf "$W"; mkdir -p "$LOG" "$W/all"
  for id in $ALL13; do clone "$id" "$W/all/${id/\//-}"; done
  # 单独几份给 Go / 文档测试（与 all/ 互不影响）
  clone mdm/customer       "$W/mdm-customer"
  clone infra/notification "$W/infra-notification"
  clone infra/notification "$W/c1-notification"
  clone infra/print        "$W/infra-print"
fi
mkdir -p "$LOG"

# ───────────────────────────────────────────────────────────────────────────
section "env.sh"
( unset BE_SCRATCH; bash "$TOOLS/env.sh" mdm/customer ) >"$LOG/env-noscratch.log" 2>&1
rc=$?; if [ $rc != 0 ] && log_has env-noscratch 'BE_SCRATCH'; then ok "没设 BE_SCRATCH 时报错退出（exit=$rc）"; else bad "没设 BE_SCRATCH 应报错退出（exit=$rc）"; fi
bash "$TOOLS/env.sh" no-slash >"$LOG/env-badid.log" 2>&1; rc=$?
if [ $rc = 2 ] && log_has env-badid '<scope>/<name>'; then ok "非法 ID 报错退出（exit=2）"; else bad "非法 ID 应 exit=2 并说明格式（exit=$rc）"; fi
if out=$(bash "$TOOLS/env.sh" infra/notification 2>"$LOG/env.err"); then
  eval "$out"
  check "REPO=infra-notification"            test "$REPO" = infra-notification
  check "UREPO=INFRA_NOTIFICATION"           test "$UREPO" = INFRA_NOTIFICATION
  check "SCHEMA/ROLE 来自 registry"          test "$SCHEMA/$ROLE" = infra_notification/infra_notification_rw
  check "SVC=infra-notification-2-0-0"       test "$SVC" = infra-notification-2-0-0
  check "C 默认指向 components/<id>"          test "$C" = "$ROOT/components/infra/notification"
  check "S 在 \$BE_SCRATCH/06b/ 下且已创建"   test -d "$BE_SCRATCH/06b/infra-notification" -a "$S" = "$BE_SCRATCH/06b/infra-notification"
  check "NET 是 brickKit 的项目网络"          test "$NET" = brickkit-be-assembly-standard-net
  out2=$(BE_COMP_DIR=$W/infra-notification bash "$TOOLS/env.sh" infra/notification); eval "$out2"
  check "BE_COMP_DIR 覆盖 C"                  test "$C" = "$W/infra-notification"
  out3=$(bash "$TOOLS/env.sh" infra/bff-mobile); eval "$out3"
  check "不连库的组件 SCHEMA/ROLE 为空"       test -z "$SCHEMA$ROLE"
else
  bad "env.sh infra/notification 失败"; cat "$LOG/env.err"
fi

# ───────────────────────────────────────────────────────────────────────────
section "migrate-manifest.py：全部 13 个组件（克隆）"
for id in $ALL13; do
  d=$W/all/${id/\//-}; n=${id/\//-}
  run_tool "mm-dry-$n" "$d" python3 "$TOOLS/migrate-manifest.py" "$id"; rc=$?
  if [ $rc = 0 ] && clean_tree "$d"; then ok "$id 预览 exit=0 且没有写盘"; else bad "$id 预览 exit=$rc / 工作区有改动"; show_log "mm-dry-$n"; fi
  run_tool "mm-check-old-$n" "$d" python3 "$TOOLS/migrate-manifest.py" "$id" --check; rc=$?
  if [ $rc = 1 ]; then ok "$id 旧清单 --check 失败（exit=1）"; else bad "$id 旧清单 --check 应为 exit=1，实际 $rc"; show_log "mm-check-old-$n"; fi
  expect_rc 0 "mm-write-$n" "$d" python3 "$TOOLS/migrate-manifest.py" "$id" --write
  expect_rc 0 "mm-check-$n" "$d" python3 "$TOOLS/migrate-manifest.py" "$id" --check
  before=$(git -C "$d" diff | sha1sum)
  run_tool "mm-write2-$n" "$d" python3 "$TOOLS/migrate-manifest.py" "$id" --write >/dev/null
  after=$(git -C "$d" diff | sha1sum)
  if [ "$before" = "$after" ] && log_has "mm-write2-$n" '未改动'; then ok "$id 重复 --write 无改动"; else bad "$id 重复 --write 有改动"; show_log "mm-write2-$n"; fi
done

section "migrate-manifest.py：生成结果与 component-loop §2.2 表逐项比对"
python3 - "$W/all" >"$LOG/mm-table.log" 2>&1 <<'EOF'
import sys, yaml, os
base = sys.argv[1]
PG = ['PG_HOST', 'PG_DATABASE', 'PG_USER', 'PG_PASSWORD', 'NATS_URL']
STD = PG + ['IAM_JWKS_URL', 'AUTHZ_BUNDLE_URL']
def d(schema, **extra):
    r = {'PG_PORT': '5432', 'PG_SCHEMA': schema, 'OTEL_BASE_URL': ''}; r.update(extra); return r
# §2.2：依赖 / 新 required / 带默认值的键 / secret（P11：bff 另加 notification、opportunity 两个 optional）
EXP = {
 'crm/opportunity': (['mdm/customer@2.0.0', 'mdm/product@2.0.0'], STD, d('crm_opportunity'), ['PG_PASSWORD']),
 'erp/finance': ([], STD, d('erp_finance'), ['PG_PASSWORD']),
 'erp/inventory': ([], STD, d('erp_inventory', LOW_STOCK_THRESHOLD='10'), ['PG_PASSWORD']),
 'erp/sales': (['mdm/customer@2.0.0', 'mdm/product@2.0.0', 'erp/inventory@2.0.0', 'erp/finance@2.0.0', ('infra/workflow@2.0.0', True)],
               STD + ['DEFAULT_WAREHOUSE_ID'], d('erp_sales', EXCEPTION_ASSIGNEE_SUB=''), ['PG_PASSWORD']),
 'infra/authz': ([], STD + ['PERMISSION_CATALOG'],
                 d('infra_authz', ACCESS_TOKEN_TTL_SECONDS='600', DEFAULT_ORG_ID='1', BOOTSTRAP_ADMIN_SUB=''), ['PG_PASSWORD']),
 'infra/bff-mobile': ([(x + '@2.0.0', True) for x in ['mdm/customer', 'mdm/product', 'erp/sales', 'erp/inventory', 'infra/workflow',
                                                      'infra/notification', 'crm/opportunity']],
                      ['IAM_JWKS_URL', 'AUTHZ_BUNDLE_URL'], {'OTEL_BASE_URL': ''}, []),
 'infra/iam-casdoor': (['infra/authz@2.0.0'],
                       PG + ['IAM_JWKS_URL', 'CASDOOR_BASE_URL', 'CASDOOR_ADMIN_PASSWORD', 'WEBHOOK_SHARED_SECRET', 'APP_TOKEN_SIGNING_KEY_PEM', 'ENABLED_COMPONENTS'],
                       d('infra_iam_casdoor', CASDOOR_ADMIN_USERNAME='admin', CASDOOR_ORG_NAME='brickkit', CASDOOR_APP_NAME='brickkit-app',
                         WEBHOOK_CALLBACK_URL='', APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM='', APP_TOKEN_TTL_SECONDS='600', REFRESH_TOKEN_TTL_SECONDS='604800'),
                       ['PG_PASSWORD', 'CASDOOR_ADMIN_PASSWORD', 'WEBHOOK_SHARED_SECRET', 'APP_TOKEN_SIGNING_KEY_PEM']),
 'infra/notification': ([], STD, d('infra_notification', IM_TARGET_ADAPTERS='dingtalk'), ['PG_PASSWORD']),
 'infra/print': ([], STD, d('infra_print'), ['PG_PASSWORD']),
 'infra/workflow': ([], STD, d('infra_workflow'), ['PG_PASSWORD']),
 'integration/im-dingtalk': ([], STD + ['DINGTALK_APP_KEY', 'DINGTALK_APP_SECRET', 'DINGTALK_AGENT_ID'],
                             d('integration_im_dingtalk', DINGTALK_BASE_URL='https://oapi.dingtalk.com'), ['PG_PASSWORD', 'DINGTALK_APP_SECRET']),
 'mdm/customer': ([], STD, d('mdm_customer'), ['PG_PASSWORD']),
 'mdm/product': ([], STD, d('mdm_product'), ['PG_PASSWORD']),
}
bad = 0
for cid, (deps, req, dflt, sec) in EXP.items():
    m = yaml.safe_load(open(os.path.join(base, cid.replace('/', '-'), 'component.yaml')))
    props = m['configSchema']['properties']
    got_deps = [(x['id'], bool(x.get('optional'))) if isinstance(x, dict) else x for x in m['dependencies']['components']]
    want_deps = [x if isinstance(x, tuple) else x for x in deps]
    got = (got_deps, sorted(m['configSchema'].get('required', [])),
           {k: str(v['default']) for k, v in props.items() if 'default' in v},
           sorted(k for k, v in props.items() if v.get('secret')))
    want = (want_deps, sorted(req), dflt, sorted(sec))
    for name, g, w in zip(('依赖', 'required', '默认值', 'secret'), got, want):
        if g != w:
            bad += 1; print(f'❌ {cid} {name}：\n   生成 {g}\n   期望 {w}')
    extra = [k for k in ('image',) if k in m['deployment']] + [k for k in ('resources',) if k in m['dependencies']]
    if extra or m['metadata']['version'] != '2.0.0' or 'build' not in m['deployment'] or not isinstance(m['local']['runCommand'], list):
        bad += 1; print(f'❌ {cid} 结构：{extra} version={m["metadata"]["version"]}')
    if m['metadata']['repository'] != 'https://github.com/brickKit/' + cid.replace('/', '-'):
        bad += 1; print(f'❌ {cid} repository={m["metadata"]["repository"]}')
print('table-ok' if bad == 0 else f'{bad} 处不符')
sys.exit(1 if bad else 0)
EOF
if [ $? = 0 ]; then ok "13 个组件的依赖 / required / 默认值 / secret 与 §2.2 一致"; else bad "与 §2.2 表不一致"; cat "$LOG/mm-table.log"; fi

section "migrate-manifest.py：细节断言"
d=$W/all/mdm-customer
check "customer：module.go 改读 PG_SCHEMA"                grep -q 'StringOr("PG_SCHEMA", "mdm_customer")' "$d/backend/module/module.go"
check "customer：日志逐处列出改动的文件与行"               log_has mm-write-mdm-customer 'backend/module/module.go:[0-9]+.*pgSchema.*PG_SCHEMA'
check "customer：component.yaml 无任何注释"               bash -c "! grep -q '#' '$d/component.yaml'"
check "customer：assembly.yaml 删了 version/shell/asset" bash -c "! grep -qE '^(version|shell|asset):' '$d/assembly.yaml'"
check "customer：assembly.yaml 保留 edge_routes/menus 与注释" bash -c "grep -q '^edge_routes:' '$d/assembly.yaml' && grep -q '# 必须与 component.yaml 一致' '$d/assembly.yaml'"
check "customer：data.role 注释改成登录角色"               grep -qE '^  role: +mdm_customer_rw +# 登录角色，`PG_USER` 的值$' "$d/assembly.yaml"
# assembly.yaml 的 diff 只有删除行与 role 那一行的改动
check "customer：assembly.yaml 只删不加（role 行除外）"    bash -c "[ \"\$(git -C '$d' diff -U0 assembly.yaml | grep '^+[^+]' | grep -vc 'role:')\" = 0 ]"
d=$W/all/infra-notification
check "notification：IM_TARGET_ADAPTERS 读取已改"         grep -q 'StringOr("IM_TARGET_ADAPTERS", "dingtalk")' "$d/backend/module/module.go"
d=$W/all/infra-print
check "print（Python）：string_or 改读 PG_SCHEMA"          grep -q 'string_or("PG_SCHEMA", "infra_print")' "$d/backend/app/module.py"
check "print：startPeriodSeconds=120、local 来自 overrides" python3 -c "
import yaml; m=yaml.safe_load(open('$d/component.yaml'))
assert m['healthCheck']['startPeriodSeconds']==120 and m['local']['language']=='python', m"
d=$W/all/integration-im-dingtalk
check "im-dingtalk：Int/MustString 读法全部改成新键"        bash -c "grep -q 'Int(\"DINGTALK_AGENT_ID\")' '$d/backend/module/module.go' && ! grep -qE 'Config\.[A-Za-z]+\(\"dingtalk' '$d/backend/module/module.go'"
check "im-dingtalk：提示代码里还提到旧键名（报错文案，不改）"  log_has mm-write-integration-im-dingtalk 'dingtalkAgentId'

section "migrate-manifest.py --check 能抓住回退"
d=$W/all/mdm-customer
cp "$d/backend/module/module.go" "$W/module.go.bak"
printf '\nfunc probeOldKey(rt interface{ StringOr(string, string) string }) string { return rt.StringOr("fooBar", "x") }\n' >>"$d/backend/module/module.go"
expect_rc 1 mm-neg-code "$d" python3 "$TOOLS/migrate-manifest.py" mdm/customer --check
check "--check 报出代码里的驼峰键读取"                       log_has mm-neg-code 'fooBar'
cp "$W/module.go.bak" "$d/backend/module/module.go"
printf '\nfunc probeUndeclared(rt interface{ StringOr(string, string) string }) string { return rt.StringOr("NOT_DECLARED_KEY", "x") }\n' >>"$d/backend/module/module.go"
expect_rc 1 mm-neg-undeclared "$d" python3 "$TOOLS/migrate-manifest.py" mdm/customer --check
check "--check 报出代码读了 configSchema 没声明的键"         log_has mm-neg-undeclared 'NOT_DECLARED_KEY'
cp "$W/module.go.bak" "$d/backend/module/module.go"
cp "$d/component.yaml" "$W/cy.bak"
python3 - "$d/component.yaml" <<'EOF'
import sys, re
p = sys.argv[1]; t = open(p).read()
t = t.replace('    IAM_JWKS_URL: {type: string}\n', '    IAM_JWKS_URL: {type: string}\n    fooBar: {type: string, default: x}\n    MY_SECRET: {type: string}\n')
t = t.replace('2.0.0\n', '2.0.0 # 1.0.10 的历史\n', 1)
open(p, 'w').write(t)
EOF
expect_rc 1 mm-neg-yaml "$d" python3 "$TOOLS/migrate-manifest.py" mdm/customer --check
check "--check 报出驼峰键 / 未标 secret / 未进 required / 版本注释" bash -c "grep -q 'fooBar' '$LOG/mm-neg-yaml.log' && grep -qE '未标 secret.*MY_SECRET' '$LOG/mm-neg-yaml.log' && grep -qE '不在 required.*MY_SECRET' '$LOG/mm-neg-yaml.log' && grep -q '版本注释' '$LOG/mm-neg-yaml.log'"
cp "$W/cy.bak" "$d/component.yaml"
expect_rc 0 mm-check-restored "$d" python3 "$TOOLS/migrate-manifest.py" mdm/customer --check

section "修复轮 C-1：--write 不覆盖手改（既不等于 tag 版也不等于本次生成结果）"
d=$W/all/mdm-product
printf '  - { key: mdm.product.hand_edit, title: 手改的键, type: action }\n' >>"$d/assembly.yaml"
sum_a=$(sha1sum <"$d/assembly.yaml"); sum_c=$(sha1sum <"$d/component.yaml")
expect_rc 3 mm-refuse-asm "$d" python3 "$TOOLS/migrate-manifest.py" mdm/product --write
check "拒绝时 assembly.yaml 原样不动"            test "$(sha1sum <"$d/assembly.yaml")" = "$sum_a"
check "拒绝时 component.yaml 也不写（全有或全无）" test "$(sha1sum <"$d/component.yaml")" = "$sum_c"
check "拒绝时点名文件并提示 --force"             bash -c "grep -q 'assembly.yaml' '$LOG/mm-refuse-asm.log' && grep -q -- '--force' '$LOG/mm-refuse-asm.log'"
check "拒绝时列出会丢掉的手改内容"               log_has mm-refuse-asm 'hand_edit'
sed -i 's/^  version: 2\.0\.0$/  version: 2.0.1/' "$d/component.yaml"
expect_rc 3 mm-refuse-cy "$d" python3 "$TOOLS/migrate-manifest.py" mdm/product --write
check "component.yaml 手改也被拒绝且原样不动"   grep -q '^  version: 2.0.1$' "$d/component.yaml"
expect_rc 0 mm-force "$d" python3 "$TOOLS/migrate-manifest.py" mdm/product --write --force
check "--force 覆盖：手改消失"                  bash -c "! grep -q hand_edit '$d/assembly.yaml' && grep -q '^  version: 2.0.0$' '$d/component.yaml'"
expect_rc 0 mm-after-force "$d" python3 "$TOOLS/migrate-manifest.py" mdm/product --write
check "--force 之后再 --write 是未改动"          log_has mm-after-force 'assembly.yaml：未改动'

section "修复轮 C-1：overrides 的 permissions_add / menus_add / edge_routes_add"
check "mdm/product 的 set_status 由 overrides 写进 assembly.yaml" grep -qE 'key: mdm\.product\.set_status' "$W/all/mdm-product/assembly.yaml"
check "bff-mobile 的三个新键由 overrides 写进 assembly.yaml" bash -c "for k in task.act notification.view opportunity.view; do grep -q \"key: infra.bff-mobile.\$k\" '$W/all/infra-bff-mobile/assembly.yaml' || exit 1; done"
OV=$W/overrides-test.yaml
python3 - "$TOOLS/manifest-overrides.yaml" "$OV" <<'EOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d['mdm/customer']['permissions_add'] = [{'key': 'mdm.customer.probe_add', 'title': '探针权限', 'type': 'action'}]
d['mdm/customer']['menus_add'] = [{'key': 'mdm.customer.probe', 'title': '探针菜单', 'permission': 'mdm.customer.probe_add'}]
d['mdm/customer']['edge_routes_add'] = [{'path': '/mdm/customer/probe/**', 'auth': 'required'}]
yaml.safe_dump(d, open(sys.argv[2], 'w'), allow_unicode=True, sort_keys=False)
EOF
d=$W/all/mdm-customer; cp "$d/assembly.yaml" "$W/asm-before-add.yaml"
expect_rc 0 mm-add "$d" env BE_OVERRIDES="$OV" python3 "$TOOLS/migrate-manifest.py" mdm/customer --write
check "*_add 追加进对应列表的末尾" python3 -c "
import yaml; a=yaml.safe_load(open('$d/assembly.yaml'))
assert a['permissions'][-1]['key']=='mdm.customer.probe_add' and a['permissions'][-1]['title']=='探针权限', a['permissions']
assert a['menus'][-1]['key']=='mdm.customer.probe' and a['edge_routes'][-1]['path']=='/mdm/customer/probe/**'"
check "*_add 只加不删（原有行与注释逐字保留）" bash -c "[ \"\$(diff '$W/asm-before-add.yaml' '$d/assembly.yaml' | grep -c '^<')\" = 0 ]"
expect_rc 0 mm-add-2 "$d" env BE_OVERRIDES="$OV" python3 "$TOOLS/migrate-manifest.py" mdm/customer --write
check "带 *_add 重复 --write 未改动" log_has mm-add-2 'assembly.yaml：未改动'
expect_rc 0 mm-add-check "$d" env BE_OVERRIDES="$OV" python3 "$TOOLS/migrate-manifest.py" mdm/customer --check
printf '  - { key: mdm.customer.hand_edit, title: 手改, type: action }\n' >>"$d/assembly.yaml"
expect_rc 3 mm-add-hand "$d" env BE_OVERRIDES="$OV" python3 "$TOOLS/migrate-manifest.py" mdm/customer --write
check "在 *_add 生成的文件上再手改 → 拒绝" log_has mm-add-hand 'hand_edit'
sed -i '/mdm.customer.hand_edit/d' "$d/assembly.yaml"
expect_rc 0 mm-add-dropped "$d" python3 "$TOOLS/migrate-manifest.py" mdm/customer --write
check "改 overrides（去掉 *_add）后重跑：照 overrides 重写，diff 里列出去掉的行" bash -c "grep -q -- '^-.*probe_add' '$LOG/mm-add-dropped.log' && ! grep -q probe_add '$d/assembly.yaml'"
python3 - "$OV" <<'EOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])); d['mdm/customer']['permissions_add'] = [{'key': 'mdm.customer.view', 'title': '重复', 'type': 'page'}]
yaml.safe_dump(d, open(sys.argv[1], 'w'), allow_unicode=True, sort_keys=False)
EOF
expect_rc 2 mm-add-dup "$d" env BE_OVERRIDES="$OV" python3 "$TOOLS/migrate-manifest.py" mdm/customer --write
check "permissions_add 与已有键重复时大声失败" log_has mm-add-dup 'mdm.customer.view'
cp "$W/asm-before-add.yaml" "$d/assembly.yaml"

section "修复轮：assembly.yaml 的 --check 反向路径、data.role 只改 data 的直接子键"
cp "$d/assembly.yaml" "$W/asm.bak"
sed -i '/^data_scopes:/d' "$d/assembly.yaml"; echo 'shell: go-core' >>"$d/assembly.yaml"
expect_rc 1 mm-neg-asm "$d" python3 "$TOOLS/migrate-manifest.py" mdm/customer --check
check "--check 报出残留 shell 与缺 data_scopes" bash -c "grep -q '残留 shell' '$LOG/mm-neg-asm.log' && grep -q '缺 data_scopes' '$LOG/mm-neg-asm.log'"
cp "$W/asm.bak" "$d/assembly.yaml"
python3 - "$TOOLS/migrate-manifest.py" >"$LOG/mm-role-unit.log" 2>&1 <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('mm', sys.argv[1]); mm = importlib.util.module_from_spec(spec); spec.loader.exec_module(mm)
src = 'id: x/y\ndata:\n  schema: x_y\n  role:   x_y_rw     # 旧注释\n  extra:\n    role: other     # 保留\ndata_scopes: none\n'
out, _ = mm.edit_assembly(src, {'id': 'x/y'})
assert '  role:   x_y_rw     ' + mm.ROLE_COMMENT in out, out
assert '    role: other     # 保留' in out, out
print('role-unit-ok')
EOF
check "data.role 注释只改 data 的直接子键（嵌套的 role 不动）" log_has mm-role-unit 'role-unit-ok'

section "修复轮 M-4：旧键名提示只看字符串与注释"
check "iam-casdoor：报错文案里的旧键名被列出" log_has mm-write-infra-iam-casdoor 'appTokenPreviousPublicKeyPem'
check "iam-casdoor：纯 Go 变量名不再刷屏" bash -c "! sed -n '/ℹ️/,\$p' '$LOG/mm-write-infra-iam-casdoor.log' | grep -qE ':= rt\.Config\.'"

# ───────────────────────────────────────────────────────────────────────────
section "docs-skel.sh（mdm/customer）"
d=$W/mdm-customer; S=$BE_SCRATCH/06b/mdm-customer
orig_agents=$(sha1sum <"$d/AGENTS.md")
expect_rc 0 skel-1 "$d" bash "$TOOLS/docs-skel.sh" mdm/customer
for f in BRICKKIT.md BRICKKIT.zh.md AGENTS.md AGENTS.zh.md README.md README.zh.md docs/design.md docs/design.zh.md CLAUDE.md; do
  check "写出 $f" test -s "$d/$f"
done
check "CLAUDE.md 恰好是 @AGENTS.md"                       test "$(cat "$d/CLAUDE.md")" = "@AGENTS.md"
check "旧 AGENTS.md 留底且与原文一致"                       test "$(sha1sum <"$S/old/AGENTS.md")" = "$orig_agents"
for f in README.md component.yaml assembly.yaml Makefile Dockerfile 手册.md; do check "留底 $f" test -s "$S/old/$f"; done
for f in BRICKKIT README AGENTS docs/design; do
  en=$(grep -c '^## ' "$d/$f.md"); zh=$(grep -c '^## ' "$d/$f.zh.md")
  [ "$f" = AGENTS ] && en=$((en - $(sed -n '/brickkit:managed:begin/,$p' "$d/$f.md" | grep -c '^## ')))
  check "$f 中英 ## 小节数一致（en=$en zh=$zh）" test "$en" = "$zh"
done
check "BRICKKIT.zh.md 用固定中文标题" bash -c "for h in 组件定位 部署前准备 依赖说明 配置指南 契约索引 外壳声明; do grep -qx \"## \$h\" '$d/BRICKKIT.zh.md' || exit 1; done"
check "AGENTS.zh.md 用固定中文标题"   bash -c "for h in 代码地图 构建与测试 设计取舍 易错点 改代码前自查; do grep -qx \"## \$h\" '$d/AGENTS.zh.md' || exit 1; done"
check "README.zh.md 用固定中文标题"   bash -c "for h in 在项目里使用 文档 开发; do grep -qx \"## \$h\" '$d/README.zh.md' || exit 1; done"
for f in AGENTS README docs/design; do
  b=$(basename $f)
  check "$f.md / .zh.md 首行互链" bash -c "head -1 '$d/$f.md' | grep -qF '[English]($b.md) · [中文]($b.zh.md)' && head -1 '$d/$f.zh.md' | grep -qF '[English]($b.md) · [中文]($b.zh.md)'"
done
check "BRICKKIT*.md 没有相对链接" bash -c "! grep -qP '\]\((?!https?://)' '$d/BRICKKIT.md' '$d/BRICKKIT.zh.md'"
check "README 的 add 命令写 @2.0.0" grep -q 'brickkit add mdm/customer@2.0.0' "$d/README.md"
check "中文正文是待填（lint 可识别的 TODO）" grep -q '待填' "$d/BRICKKIT.zh.md"
sum1=$(cd "$d" && sha1sum BRICKKIT*.md AGENTS*.md README*.md docs/design*.md CLAUDE.md)
expect_rc 0 skel-2 "$d" bash "$TOOLS/docs-skel.sh" mdm/customer
check "重复运行无改动"            test "$(cd "$d" && sha1sum BRICKKIT*.md AGENTS*.md README*.md docs/design*.md CLAUDE.md)" = "$sum1"
check "重复运行没有覆盖第一次的留底" test "$(sha1sum <"$S/old/AGENTS.md")" = "$orig_agents"
echo "已填写的内容" >>"$d/BRICKKIT.md"; filled=$(sha1sum <"$d/BRICKKIT.md")
expect_rc 0 skel-3 "$d" bash "$TOOLS/docs-skel.sh" mdm/customer
check "已填写的文件不被覆盖（并提示 --force）" bash -c "[ \"\$(sha1sum <'$d/BRICKKIT.md')\" = '$filled' ] && grep -q -- '--force' '$LOG/skel-3.log'"
expect_rc 0 skel-force "$d" bash "$TOOLS/docs-skel.sh" mdm/customer --force
check "--force 覆盖回骨架" bash -c "! grep -q '已填写的内容' '$d/BRICKKIT.md'"

section "修复轮 I-1：换会话 / 清空 \$S 后 docs-skel 不覆盖已填写的文档"
d=$W/mdm-customer; TAG=$(git -C "$d" tag -l 'v1.*' | sort -V | tail -1)
echo "FILLED BY C5 - real content" >>"$d/AGENTS.md"; echo "FILLED BY C5 - real content" >>"$d/README.md"
fa=$(sha1sum <"$d/AGENTS.md"); fr=$(sha1sum <"$d/README.md")
expect_rc 0 skel-session2 "$d" env BE_SCRATCH="$W/scratch2" bash "$TOOLS/docs-skel.sh" mdm/customer
check "新会话：已填写的 AGENTS.md / README.md 不被覆盖" bash -c "[ \"\$(sha1sum <'$d/AGENTS.md')\" = '$fa' ] && [ \"\$(sha1sum <'$d/README.md')\" = '$fr' ]"
check "新会话：留底取自 $TAG（不是已填写的文件）" bash -c "git -C '$d' show '$TAG:AGENTS.md' | cmp -s - '$W/scratch2/06b/mdm-customer/old/AGENTS.md'"
rm -rf "$BE_SCRATCH/06b/mdm-customer"
expect_rc 0 skel-cleaned "$d" bash "$TOOLS/docs-skel.sh" mdm/customer
check "清空 \$S 后：已填写的文档不被覆盖" bash -c "[ \"\$(sha1sum <'$d/AGENTS.md')\" = '$fa' ] && [ \"\$(sha1sum <'$d/README.md')\" = '$fr' ]"
check "清空 \$S 后：留底重新取自 tag" bash -c "git -C '$d' show '$TAG:README.md' | cmp -s - '$BE_SCRATCH/06b/mdm-customer/old/README.md'"
expect_rc 0 skel-restore "$d" bash "$TOOLS/docs-skel.sh" mdm/customer --force
# 组件仓库里的 brickkit lint：结构类问题必须为零，只剩占位符（C5 去填）
( cd "$d" && BE_COMP_DIR=$d python3 "$TOOLS/migrate-manifest.py" mdm/customer --write >/dev/null 2>&1 && brickkit lint ) >"$LOG/skel-lint.log" 2>&1
# lint 不打印错误码，只打印文字：允许的只有占位符（DOC_PLACEHOLDER）与"文档还没提到某个键 / 契约"（DOC_OUT_OF_STEP），
# 这两类正是 C5 要填的；出现任何别的警告（缺文件、缺小节、翻译漂移、不可移植链接……）或错误都算失败
check "brickkit lint：component.yaml 通过、0 个错误" bash -c "grep -q '✅ component.yaml' '$LOG/skel-lint.log' && grep -q '0 with errors' '$LOG/skel-lint.log' && ! grep -q '❌' '$LOG/skel-lint.log'"
check "brickkit lint：只剩占位符与'文档没提到'两类警告" bash -c "! grep '⚠️' '$LOG/skel-lint.log' | grep -vE 'a placeholder \\(TODO\\) is still in the text|is listed under artifacts, but|is a required config key, but|is a dependency, but'"
check "brickkit lint：占位符被报出（中英两边都有）" bash -c "grep -A1 'a placeholder' '$LOG/skel-lint.log' | grep -q 'BRICKKIT.zh.md' && grep -A1 'a placeholder' '$LOG/skel-lint.log' | grep -q 'File: BRICKKIT.md'"

# ───────────────────────────────────────────────────────────────────────────
section "go-v2.sh：形态 A（mdm/customer）"
d=$W/mdm-customer
expect_rc 0 go-a-1 "$d" bash "$TOOLS/go-v2.sh" mdm/customer --sdk "$SDK"
check "判出形态 A"                         log_has go-a-1 '形态 A'
check "go.mod 是 /v2"                      test "$(head -1 "$d/go.mod")" = "module github.com/brickKit/mdm-customer/v2"
check "require 契约包真实 tag v1.0.6"      grep -qE 'github.com/brickKit/mdm-customer/gen/mdm/customer v1\.0\.6$' "$d/go.mod"
check "go list -m all 只有两行本仓库模块" bash -c "[ \"\$(cd '$d' && go list -m all | grep -c 'brickKit/mdm-customer')\" = 2 ]"
check "全部判据 PASS 无 FAIL"              bash -c "grep -q 'PASS' '$LOG/go-a-1.log' && ! grep -q 'FAIL' '$LOG/go-a-1.log'"
check "报告第 8.3 步不需要打契约包 tag"    log_has go-a-1 '第 8.3 步.*不需要'
commit_all "$d" "go-v2 第一次"
expect_rc 0 go-a-2 "$d" bash "$TOOLS/go-v2.sh" mdm/customer --sdk "$SDK"
check "重复运行无改动（git status --short 为空）" clean_tree "$d"
# 模拟契约有新增：改一处生成物后 --recheck → 下一个 minor
echo "// probe: 契约新增" >>"$(ls "$d"/gen/mdm/customer/v1/*.pb.go | head -1)"
expect_rc 0 go-a-recheck "$d" bash "$TOOLS/go-v2.sh" mdm/customer --recheck
check "--recheck：gen 有变化 → require v1.1.0" grep -qE 'github.com/brickKit/mdm-customer/gen/mdm/customer v1\.1\.0$' "$d/go.mod"
check "--recheck：报出第 8.3 步要打 gen/mdm/customer/v1.1.0" log_has go-a-recheck 'gen/mdm/customer/v1\.1\.0'

section "修复轮 M-2 / M-3：多余的 replace、裸导入旧根包"
d=$W/mdm-customer
SDKSRC=$(go env GOMODCACHE)/github.com/brick\!kit/be-sdk-go@$SDK
rm -rf "$W/sdk-local"; cp -r "$SDKSRC" "$W/sdk-local"; chmod -R u+w "$W/sdk-local"
( cd "$d" && go mod edit -replace=github.com/brickKit/be-sdk-go="$W/sdk-local" )
expect_rc 1 go-stray-replace "$d" bash "$TOOLS/go-v2.sh" mdm/customer --recheck
check "根 go.mod 里契约包之外的 replace → FAIL" log_has go-stray-replace 'FAIL.*replace'
( cd "$d" && go mod edit -dropreplace=github.com/brickKit/be-sdk-go && go mod tidy >/dev/null 2>&1 )
printf '//go:build ignore\n\npackage probe\n\nimport _ "github.com/brickKit/mdm-customer"\n' >"$d/backend/probe_ignore.go"
expect_rc 1 go-bare-import "$d" bash "$TOOLS/go-v2.sh" mdm/customer --recheck
check "裸导入旧根包（不带子路径）→ FAIL" log_has go-bare-import 'FAIL.*import'
rm -f "$d/backend/probe_ignore.go"
expect_rc 0 go-a-recheck-clean "$d" bash "$TOOLS/go-v2.sh" mdm/customer --recheck

section "go-v2.sh：形态 B（infra/notification）"
d=$W/infra-notification
expect_rc 0 go-b-1 "$d" bash "$TOOLS/go-v2.sh" infra/notification --sdk "$SDK"
check "判出形态 B"                                  log_has go-b-1 '形态 B'
check "拆出 gen/infra/notification/go.mod"          test -f "$d/gen/infra/notification/go.mod"
check "契约包模块路径不带 /v2"                       test "$(head -1 "$d/gen/infra/notification/go.mod")" = "module github.com/brickKit/infra-notification/gen/infra/notification"
check "go.mod 是 /v2"                               test "$(head -1 "$d/go.mod")" = "module github.com/brickKit/infra-notification/v2"
check "require 契约包 v1.0.0 + 本地 replace"        bash -c "grep -qE 'infra-notification/gen/infra/notification v1\.0\.0$' '$d/go.mod' && grep -qE '^replace github.com/brickKit/infra-notification/gen/infra/notification => \./gen/infra/notification' '$d/go.mod'"
check "go list -m all 只有两行本仓库模块"          bash -c "[ \"\$(cd '$d' && go list -m all | grep -c 'brickKit/infra-notification')\" = 2 ]"
check "Dockerfile 改成先 COPY . . 再 go mod download" bash -c "awk '/^COPY \. \./{c=NR} /go mod download/{g=NR} END{exit !(c && g && c<g)}' '$d/Dockerfile' && ! grep -q '^COPY go.mod' '$d/Dockerfile'"
check "报告第 8.3 步要打 gen/infra/notification/v1.0.0" log_has go-b-1 '第 8.3 步.*gen/infra/notification/v1\.0\.0'
check "全部判据 PASS 无 FAIL"                       bash -c "grep -q 'PASS' '$LOG/go-b-1.log' && ! grep -q 'FAIL' '$LOG/go-b-1.log'"
commit_all "$d" "go-v2 第一次"
expect_rc 0 go-b-2 "$d" bash "$TOOLS/go-v2.sh" infra/notification --sdk "$SDK"
check "重复运行无改动（git status --short 为空）"   clean_tree "$d"
expect_rc 0 go-b-recheck "$d" bash "$TOOLS/go-v2.sh" infra/notification --recheck
check "--recheck 后仍无改动"                        clean_tree "$d"

section "go-v2.sh：C-1（形态 B 被当成形态 A 改，v2 静默对着自己的 v1 生成代码编译）"
d=$W/c1-notification; M=github.com/brickKit/infra-notification
( cd "$d" && go mod edit -module $M/v2 \
  && git ls-files '*.go' | grep -v '^gen/' | xargs perl -pi -e 's#"github.com/brickKit/infra-notification/(?!v2/|gen/)#"github.com/brickKit/infra-notification/v2/#g' \
  && go mod tidy && go build ./... ) >"$LOG/c1-break.log" 2>&1
check "复现：错误做法下 go build 照样是绿的"                      bash -c "tail -1 '$LOG/c1-break.log' >/dev/null; cd '$d' && go build ./..."
check "复现：go mod tidy 自己加回了 require $M v1.x.y"             grep -qE "^\s+$M v1\.[0-9]+\.[0-9]+" "$d/go.mod"
expect_rc 1 go-c1-recheck "$d" bash "$TOOLS/go-v2.sh" infra/notification --recheck
check "判据抓住：go.mod require 自己的旧路径 → FAIL"            log_has go-c1-recheck 'FAIL.*旧路径'
check "判据抓住：go list -m all 多出 v1 模块 → FAIL"            log_has go-c1-recheck 'FAIL.*go list -m all'
check "判据抓住：go list -deps 多出 v1 模块 → FAIL"             log_has go-c1-recheck 'FAIL.*go list -deps'
check "判据抓住：契约包不是嵌套模块 → FAIL"                     log_has go-c1-recheck 'FAIL.*嵌套模块'
expect_rc 0 go-c1-fix "$d" bash "$TOOLS/go-v2.sh" infra/notification --sdk "$SDK"
check "完整运行：明确报出 C-1 残留并删掉"                       log_has go-c1-fix 'C-1'
check "完整运行后不再 require 旧路径"                           bash -c "! grep -qE '^\s+$M v1\.' '$d/go.mod'"
check "完整运行后 go list -m all 只有两行本仓库模块"           bash -c "[ \"\$(cd '$d' && go list -m all | grep -c 'brickKit/infra-notification')\" = 2 ]"

section "go-v2.sh：非 Go 组件"
expect_rc 2 go-python "$W/infra-print" bash "$TOOLS/go-v2.sh" infra/print --sdk "$SDK"
check "go-v2.sh 对 Python 组件拒绝执行" log_has go-python '不是 Go 组件'
expect_rc 2 go-noargs "$W/mdm-customer" bash "$TOOLS/go-v2.sh" mdm/customer
check "go-v2.sh 没有 --sdk 也没有 --recheck 时说明用法" log_has go-noargs '--recheck'
expect_rc 2 mm-unknown "$W/mdm-customer" python3 "$TOOLS/migrate-manifest.py" frontend/standard
check "migrate-manifest.py 对没有 overrides 条目的组件大声失败" log_has mm-unknown 'manifest-overrides.yaml 里没有'
expect_rc 2 skel-noscratch "$W/mdm-customer" env -u BE_SCRATCH bash "$TOOLS/docs-skel.sh" mdm/customer
check "docs-skel.sh 没设 BE_SCRATCH 时大声失败" log_has skel-noscratch 'BE_SCRATCH'

# ───────────────────────────────────────────────────────────────────────────
echo
echo "━━━ 结果：$PASS 通过，$FAIL 失败（日志 $LOG）"
if [ $FAIL -gt 0 ]; then printf '  ❌ %s\n' "${FAILED[@]}"; exit 1; fi
echo "全部通过"
