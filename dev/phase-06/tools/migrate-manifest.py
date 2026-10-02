#!/usr/bin/env python3
"""1.x → 2.0.0 一次性迁移：重写 component.yaml / assembly.yaml，并把代码里的旧配置键读法改成新键。

用法：python3 migrate-manifest.py <scope>/<name> [--write] [--check]
  不带参数   打印将写出的 component.yaml、assembly.yaml、代码改动与 diff，不写盘；生成结果先过一遍自检
  --write    写盘：component.yaml 整份重写，assembly.yaml 文本级删改，代码里旧键的读取改成新键
  --check    对当前工作区跑 component-loop 3.2 的全部检查 + 代码里的驼峰键读取；任一项不是"无"就 exit 1
  --force    与 --write 一起：覆盖手改过的文件（默认拒绝，见下）
  两个一起给：先写，再查。

手改保护：--write 写盘前逐个核对 component.yaml / assembly.yaml——工作区文件既不是 tag 原文、也不是本次会
生成的内容、也不是本脚本上次在这个检出里写出的内容（sha1 记在组件仓库的 git 目录 be-migrate-manifest/ 下，
不进提交），就说明 C3 之后有人手改过；这时一个文件都不写、打印会丢掉的 diff、exit 3。要长期保留的增量写进
manifest-overrides.yaml（add_properties、deps_add、permissions_add、menus_add、edge_routes_add 等）再重跑。

输入是组件**最后一个 1.x tag** 上的 component.yaml / assembly.yaml（不是工作区），加上同目录
manifest-overrides.yaml 里该组件的条目，所以重复运行结果相同。组件目录默认 <仓库>/components/<id>，
环境变量 BE_COMP_DIR 可以改（测试指向 scratch 里的克隆）。
退出码：0 成功；1 --check 有问题或生成结果自检不过；2 用法错误 / 输入不符合预期（大声失败，不猜）；
        3 --write 拒绝覆盖手改过的文件。
"""
import argparse
import difflib
import json
import os
import re
import subprocess
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
# 测试可以用 BE_OVERRIDES 指向另一份 overrides（不改真文件）
OVERRIDES = os.environ.get('BE_OVERRIDES') or os.path.join(HERE, 'manifest-overrides.yaml')

# 共享键按 04-configuration.md 的固定名；其余驼峰键机械转大写下划线（component-loop §2.1）
SHARED = {'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL',
          'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL'}
SHARED_ORDER = ['OTEL_BASE_URL', 'AUTHZ_BUNDLE_URL', 'IAM_JWKS_URL']
NO_DEFAULT = {'AUTHZ_BUNDLE_URL', 'IAM_JWKS_URL'}          # P1：一律 required、不给默认值
SECRET_RE = re.compile(r'PASSWORD|SECRET|SIGNING_KEY')
RESERVED = {'COMPONENT_ID', 'COMPONENT_VERSION', 'PORT', 'BRICKKIT_SERVED_MEMBERS', 'BRICKKIT_SERVED_MEMBERS_CONFIG'}
KEY_RE = re.compile(r'[A-Z][A-Z0-9_]*')
OVERRIDE_FIELDS = {'name', 'description', 'tags', 'add_properties', 'required_add', 'drop_default', 'deps_add',
                   'start_period_seconds', 'migration_command', 'local'} | {f'{k}_add' for k in ('permissions', 'menus', 'edge_routes')}
# assembly.yaml 里允许由 overrides 追加条目的列表（每个任务新增的权限键、菜单、网关路由），以及条目的身份键
ASSEMBLY_LISTS = {'permissions': 'key', 'menus': 'key', 'edge_routes': 'path'}
KNOWN_TOP = ['apiVersion', 'kind', 'metadata', 'tags', 'artifacts', 'dependencies', 'configSchema',
             'deployment', 'migration', 'healthCheck', 'local']
ROLE_COMMENT = '# 登录角色，`PG_USER` 的值'

# 代码里读配置的方法（SDK 的 Config API）。Go：rt.Config.X("k"；Python：rt.config.x("k"；TS：config.x("k"
CODE_LANGS = {
    '.go': ('String|StringOr|MustString|Int|IntOr|Bool|BoolOr', '"'),
    '.py': ('string|string_or|must_string|int|int_or|bool|bool_or', '"\''),
    '.ts': ('string|stringOr|mustString|int|intOr|bool|boolOr', '"\''),
    '.js': ('string|stringOr|mustString|int|intOr|bool|boolOr', '"\''),
}
SKIP_DIRS = ('gen/', 'node_modules/', 'dist/', '.venv/', 'build/', 'vendor/')


class Fatal(Exception):
    pass


def snake(k):
    s = re.sub(r'(?<=[a-z0-9])([A-Z])', r'_\1', k)
    s = re.sub(r'(?<=[A-Z])([A-Z][a-z])', r'_\1', s)
    return s.upper()


def git(c, *args):
    r = subprocess.run(['git', '-C', c, *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise Fatal(f'git {" ".join(args)} 失败：{r.stderr.strip()}')
    return r.stdout


# ───────────────────────────── 上下文（与 env.sh 同一套取值） ─────────────────────────────

def context(cid):
    if not re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*/[a-z0-9]+(-[a-z0-9]+)*', cid):
        raise Fatal(f'组件 ID 必须是 <scope>/<name>，收到 {cid}')
    repo = cid.replace('/', '-')
    c = os.environ.get('BE_COMP_DIR') or os.path.join(ROOT, 'components', cid)
    if not os.path.isfile(os.path.join(c, 'component.yaml')):
        raise Fatal(f'{c} 里没有 component.yaml')
    schema = role = None
    for line in open(os.path.join(ROOT, 'registry', 'schemas.tsv'), encoding='utf-8'):
        f = line.rstrip('\n').split('\t')
        if f and f[0] == repo and not line.startswith('#'):
            schema, role = f[1], f[2]
    http = grpc = None
    for line in open(os.path.join(ROOT, 'registry', 'ports.tsv'), encoding='utf-8'):
        f = line.rstrip('\n').split('\t')
        if len(f) >= 4 and f[1] == cid and not line.startswith('#'):
            http, grpc = f[2], f[3]
    if http is None:
        raise Fatal(f'registry/ports.tsv 里没有 {cid}')
    return dict(id=cid, repo=repo, dir=os.path.abspath(c), schema=schema, role=role,
                http=int(http), grpc=None if grpc in ('-', '') else int(grpc))


def last_v1_tag(c):
    # 06a 之前的组件 tag 都带 v（v1.0.10），brickKit 的裸 tag（1.0.10）两种都认
    tags = [t for t in git(c, 'tag', '-l', '1.*', 'v1.*').split() if re.fullmatch(r'v?1\.\d+\.\d+', t)]
    if not tags:
        raise Fatal(f'{c} 没有任何 1.x tag（git tag -l "1.*" "v1.*" 为空），无法确定迁移输入')
    return max(tags, key=lambda t: tuple(int(x) for x in t.lstrip('v').split('.')))


def load_override(cid):
    data = yaml.safe_load(open(OVERRIDES, encoding='utf-8')) or {}
    if cid not in data:
        raise Fatal(f'manifest-overrides.yaml 里没有 {cid} 的条目')
    ov = data[cid] or {}
    unknown = set(ov) - OVERRIDE_FIELDS
    if unknown:
        raise Fatal(f'manifest-overrides.yaml 的 {cid} 有不认识的字段：{sorted(unknown)}')
    for f in ('name', 'description', 'local'):
        if f not in ov:
            raise Fatal(f'manifest-overrides.yaml 的 {cid} 缺必填字段 {f}')
    for f in ('name', 'description'):
        if re.search(r'[　-鿿＀-￯]', str(ov[f])):
            raise Fatal(f'manifest-overrides.yaml 的 {cid}.{f} 必须是英文：{ov[f]}')
    for lst, ident in ASSEMBLY_LISTS.items():
        items = ov.get(f'{lst}_add')
        if items is None:
            continue
        if not isinstance(items, list) or not all(isinstance(x, dict) and x.get(ident) for x in items):
            raise Fatal(f'manifest-overrides.yaml 的 {cid}.{lst}_add 必须是映射列表，每项带 {ident}')
    loc = ov['local']
    if not isinstance(loc, dict) or not isinstance(loc.get('runCommand'), list) or not loc.get('language'):
        raise Fatal(f'manifest-overrides.yaml 的 {cid}.local 必须有 language 和数组形式的 runCommand')
    return ov


# ───────────────────────────── component.yaml 推导（§2.2 / §2.3 / §3.1） ─────────────────────────────

def dep_to_v2(d, where):
    if isinstance(d, str):
        return d.split('@')[0] + '@2.0.0'
    if isinstance(d, dict) and 'id' in d:
        out = {'id': d['id'].split('@')[0] + '@2.0.0'}
        for k, v in d.items():
            if k != 'id':
                out[k] = v
        return out
    raise Fatal(f'{where} 里有看不懂的依赖写法：{d!r}')


def dep_id(d):
    return (d if isinstance(d, str) else d['id']).split('@')[0]


def build_component(old, ov, cx):
    unknown = set(old) - set(KNOWN_TOP)
    if unknown:
        raise Fatal(f'旧 component.yaml 有脚本不认识的顶层字段 {sorted(unknown)}，先人工判断再改脚本')
    md = old['metadata']
    if md.get('id') != cx['id']:
        raise Fatal(f'旧 component.yaml 的 metadata.id 是 {md.get("id")}，不是 {cx["id"]}')
    new = {'apiVersion': old.get('apiVersion', 'brickkit/v1'), 'kind': old.get('kind', 'Component')}
    meta = {'id': md['id'], 'name': ov['name'], 'version': '2.0.0', 'description': ov['description'],
            'repository': f'https://github.com/brickKit/{cx["repo"]}'}
    for k in ('license', 'vendor'):
        if k in md:
            meta[k] = md[k]
    new['metadata'] = meta
    tags = ov.get('tags', old.get('tags'))
    if tags:
        new['tags'] = tags
    if old.get('artifacts'):
        new['artifacts'] = old['artifacts']

    # 依赖：全部 @2.0.0；resources 删除（改为声明 PG_* / NATS_URL）
    olddeps = old.get('dependencies') or {}
    deps = [dep_to_v2(d, 'dependencies.components') for d in (olddeps.get('components') or [])]
    for d in ov.get('deps_add') or []:
        nd = dep_to_v2(d, 'deps_add')
        if (d if isinstance(d, str) else d['id']) != (nd if isinstance(nd, str) else nd['id']):
            raise Fatal(f'deps_add 的版本必须写 2.0.0：{d!r}')
        deps.append(nd)
    ids = [dep_id(d) for d in deps]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        raise Fatal(f'依赖重复：{dup}')
    new['dependencies'] = {'components': deps}
    resources = {r.get('kind') for r in (olddeps.get('resources') or [])}

    # configSchema
    ocs = old.get('configSchema') or {}
    oprops = ocs.get('properties') or {}
    oreq = set(ocs.get('required') or [])
    drop_default = set(ov.get('drop_default') or [])
    props = {}

    def put(key, spec):
        if key in props:
            raise Fatal(f'新键 {key} 重复（两个旧键映射到了同一个新键？）')
        props[key] = spec

    if 'database' in resources:
        schema_default = (oprops.get('pgSchema') or {}).get('default', cx['schema'])
        if schema_default != cx['schema']:
            raise Fatal(f'旧 pgSchema 默认值 {schema_default} 与 registry/schemas.tsv 的 {cx["schema"]} 不一致')
        for k, spec in (('PG_HOST', {'type': 'string'}), ('PG_PORT', {'type': 'string', 'default': '5432'}),
                        ('PG_DATABASE', {'type': 'string'}), ('PG_USER', {'type': 'string'}),
                        ('PG_PASSWORD', {'type': 'string', 'secret': True}),
                        ('PG_SCHEMA', {'type': 'string', 'default': schema_default})):
            put(k, spec)
    if 'mq' in resources:
        put('NATS_URL', {'type': 'string'})
    unknown_res = resources - {'database', 'mq'}
    if unknown_res:
        raise Fatal(f'旧 dependencies.resources 有脚本不处理的种类 {sorted(unknown_res)}（S3_URL 之类要人工声明）')

    rest = []
    for k, v in oprops.items():
        nk = SHARED.get(k, snake(k))
        if nk == 'PG_SCHEMA' and 'PG_SCHEMA' in props:
            continue
        spec = {kk: vv for kk, vv in (v or {}).items() if kk != 'description'}   # §2.3.4：说明写在 BRICKKIT.md
        if nk in NO_DEFAULT or nk in drop_default or k in oreq:
            spec.pop('default', None)
        if SECRET_RE.search(nk):
            spec['secret'] = True
        rest.append((nk, spec))
    for nk in SHARED_ORDER:
        for k2, spec in rest:
            if k2 == nk:
                put(k2, spec)
    for k2, spec in rest:
        if k2 not in SHARED_ORDER:
            put(k2, spec)
    for k, spec in (ov.get('add_properties') or {}).items():
        put(k, dict(spec))
    for k in drop_default:
        if k not in props:
            raise Fatal(f'drop_default 里的 {k} 没有在 configSchema 里声明')
    required = [k for k, v in props.items() if 'default' not in v]
    for k in ov.get('required_add') or []:
        if k not in props:
            raise Fatal(f'required_add 里的 {k} 没有声明')
        if 'default' in props[k]:
            raise Fatal(f'required_add 里的 {k} 有默认值；要改成 required 用 drop_default')
        if k not in required:
            required.append(k)
    cs = {'type': 'object', 'properties': props}
    if required:
        cs['required'] = required
    new['configSchema'] = cs

    od = old.get('deployment') or {}
    dep = {'type': od.get('type', 'container'), 'build': {'context': '.', 'dockerfile': 'Dockerfile'}}
    for k, v in od.items():
        if k not in ('type', 'image', 'build'):
            dep[k] = v
    new['deployment'] = dep

    if 'migration_command' in ov:
        new['migration'] = {'command': list(ov['migration_command'])}
    elif old.get('migration'):
        new['migration'] = old['migration']
    hc = dict(old.get('healthCheck') or {'type': 'http', 'path': '/healthz'})
    if 'start_period_seconds' in ov:
        hc['startPeriodSeconds'] = ov['start_period_seconds']
    new['healthCheck'] = hc
    new['local'] = {'language': ov['local']['language'], 'runCommand': list(ov['local']['runCommand'])}
    return new


# ───────────────────────────── YAML 输出（§3.1 的版式，无注释） ─────────────────────────────

FLOW_DICT_KEYS = {'build', 'requests', 'limits'}
FLOW_ITEM_LISTS = {'extraPorts'}


def scalar(v, flow=False):
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if v is None:
        return 'null'
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v)
    if s == '':
        return '""'
    plain = re.fullmatch(r'[A-Za-z0-9_./@~(\u00a0-\uffff][A-Za-z0-9_./@~+()\-:\u00a0-\uffff]*(?: [A-Za-z0-9_./@~+()\-,;:\u00a0-\uffff]+)*', s)
    if plain and flow and re.search(r'[,\[\]{}:]', s):     # 流式里冒号、逗号一律加引号
        plain = None
    if plain and ': ' not in s and ' #' not in s:
        try:
            if yaml.safe_load(s) == s:
                return s
        except yaml.YAMLError:
            pass
    return json.dumps(s, ensure_ascii=False)


def is_scalar(v):
    return not isinstance(v, (dict, list))


def flow(v):
    if isinstance(v, dict):
        return '{' + ', '.join(f'{scalar(k, True)}: {flow(x)}' for k, x in v.items()) + '}'
    if isinstance(v, list):
        return '[' + ', '.join(flow(x) for x in v) + ']'
    return scalar(v, True)


def emit(v, indent, key=None):
    """返回 v 作为 `key:` 的值时应写成的行（第一行跟在冒号后面）。"""
    pad = '  ' * indent
    if is_scalar(v):
        return [' ' + scalar(v)]
    if not v:
        return [' []' if isinstance(v, list) else ' {}']
    if isinstance(v, list):
        if all(is_scalar(x) for x in v):
            return [' ' + flow(v)]
        lines = ['']
        for item in v:
            if isinstance(item, dict) and (key in FLOW_ITEM_LISTS or (all(is_scalar(x) for x in item.values()) and len(item) == 1)):
                lines.append(f'{pad}- {flow(item)}')
            elif isinstance(item, dict):
                first = True
                for k, x in item.items():
                    sub = emit(x, indent + 2, k)
                    lead = f'{pad}- ' if first else f'{pad}  '
                    lines.append(f'{lead}{scalar(k)}:{sub[0]}')
                    lines.extend(sub[1:])
                    first = False
            else:
                lines.append(f'{pad}- {flow(item)}')
        return lines
    # dict
    if all(is_scalar(x) for x in v.values()) and (key in FLOW_DICT_KEYS or key == '__prop__'):
        return [' ' + flow(v)]
    lines = ['']
    for k, x in v.items():
        sub = emit(x, indent + 1, '__prop__' if key == 'properties' else k)
        lines.append(f'{pad}{scalar(k)}:{sub[0]}')
        lines.extend(sub[1:])
    return lines


def render(doc):
    out = []
    for i, (k, v) in enumerate(doc.items()):
        if i > 0 and k != 'kind':
            out.append('')
        sub = emit(v, 1, k)
        out.append(f'{k}:{sub[0]}')
        out.extend(sub[1:])
    return '\n'.join(out) + '\n'


# ───────────────────────────── assembly.yaml（文本级编辑） ─────────────────────────────

def edit_assembly(text, cx, adds=None):
    """删 version/shell/asset，改 data.role 的注释，按 overrides 的 *_add 往列表末尾追加条目；其余逐字保留。"""
    lines = text.splitlines(keepends=True)
    out, removed, i = [], [], 0
    in_data, data_indent = False, None
    while i < len(lines):
        ln = lines[i]
        m = re.match(r'^(version|shell|asset)\s*:', ln)
        if m:
            removed.append(m.group(1))
            i += 1
            # 吞掉这个键的块：缩进行，以及块内部（后面还有缩进行）的空行
            while i < len(lines):
                if lines[i].startswith((' ', '\t')):
                    i += 1
                    continue
                if lines[i].strip() == '':
                    j = i
                    while j < len(lines) and lines[j].strip() == '':
                        j += 1
                    if j < len(lines) and lines[j].startswith((' ', '\t')):
                        i = j
                        continue
                break
            continue
        if re.match(r'^\S', ln):
            in_data, data_indent = ln.startswith('data:'), None
        elif in_data and ln.strip() and not ln.lstrip().startswith('#') and data_indent is None:
            data_indent = re.match(r'^\s*', ln).group(0)      # data 的直接子键的缩进
        rm = re.match(r'^(\s+)(role:\s*)(\S+)(\s*)(#.*)?$', ln.rstrip('\n')) if in_data else None
        if rm and rm.group(1) == data_indent:                   # 只改 data.role，不碰更深层的 role
            gap = rm.group(4) if rm.group(5) else '  '
            ln = f'{rm.group(1)}{rm.group(2)}{rm.group(3)}{gap or "  "}{ROLE_COMMENT}\n'
        out.append(ln)
        i += 1
    new = re.sub(r'\n{3,}', '\n\n', ''.join(out)).strip('\n') + '\n'
    old_doc = yaml.safe_load(text) or {}
    want = {k: v for k, v in old_doc.items() if k not in ('version', 'shell', 'asset')}
    for lst, items in (adds or {}).items():
        if not items:
            continue
        ident = ASSEMBLY_LISTS[lst]
        have = [x.get(ident) for x in (want.get(lst) or []) if isinstance(x, dict)]
        newids = [x[ident] for x in items]
        dup = sorted({x for x in newids if x in have or newids.count(x) > 1})
        if dup:
            raise Fatal(f'{lst}_add 里的 {dup} 在 tag 版 assembly.yaml 里已经有了（或重复写了两次）')
        if want.get(lst) not in (None, []) and not isinstance(want.get(lst), list):
            raise Fatal(f'assembly.yaml 的 {lst} 不是列表（{want.get(lst)!r}），没法追加')
        new = append_items(new, lst, items)
        want[lst] = list(want.get(lst) or []) + [dict(x) for x in items]
    # 语义自检：除删掉的键与追加的条目外，内容与旧文件完全一样
    if (yaml.safe_load(new) or {}) != want:
        raise Fatal('assembly.yaml 文本编辑后语义不对（脚本 bug），不写盘')
    return new, removed


def append_items(text, key, items):
    """把 items 以 `  - { k: v, … }` 的写法追加到顶层列表 key 的最后一个条目后面（没有这个键就加在文件末尾）。"""
    lines = text.rstrip('\n').split('\n')
    idx = next((i for i, l in enumerate(lines) if re.match(rf'^{re.escape(key)}\s*:', l)), None)
    prefix = '  '
    if idx is None:
        lines += ['', f'{key}:']
        at = len(lines)
    else:
        mi = re.match(rf'^({re.escape(key)}\s*:)\s*\[\s*\]\s*(#.*)?$', lines[idx])
        if mi:                                                   # `key: []` → 块写法
            lines[idx] = mi.group(1) + (f'  {mi.group(2)}' if mi.group(2) else '')
            at = idx + 1
        elif re.match(rf'^{re.escape(key)}\s*:\s*(#.*)?$', lines[idx]):
            at = idx + 1
            for j in range(idx + 1, len(lines)):
                if lines[j].strip() == '' or lines[j].startswith((' ', '\t')):
                    if lines[j].strip() and not lines[j].lstrip().startswith('#'):
                        at = j + 1
                        if lines[j].lstrip().startswith('- ') and prefix == '  ':
                            prefix = re.match(r'^\s*', lines[j]).group(0)
                    continue
                break
        else:
            raise Fatal(f'assembly.yaml 的 {key}: 写法看不懂（行内列表？），没法追加：{lines[idx]}')
    body = [f'{prefix}- {{ ' + ', '.join(f'{k}: {scalar(v, True)}' for k, v in x.items()) + ' }' for x in items]
    lines[at:at] = body
    return '\n'.join(lines) + '\n'


# ───────────────────────────── 代码里的配置键读取 ─────────────────────────────

def code_files(c):
    r = subprocess.run(['git', '-C', c, 'ls-files', '-co', '--exclude-standard'], capture_output=True, text=True)
    if r.returncode != 0:
        raise Fatal(f'git ls-files 失败：{r.stderr.strip()}')
    for p in r.stdout.split('\n'):
        if p and os.path.splitext(p)[1] in CODE_LANGS and not p.startswith(SKIP_DIRS) and \
                not any(f'/{d}' in p for d in SKIP_DIRS) and os.path.isfile(os.path.join(c, p)):
            yield p


def call_re(ext, key_pat):
    meths, quotes = CODE_LANGS[ext]
    q = '["\']' if len(quotes) > 1 else '"'
    return re.compile(r'(\.(?:%s)\(\s*)(%s)(%s)(\2)' % (meths, q, key_pat))


def rewrite_code(c, mapping, write):
    """把 SDK Config 读法里的旧键换成新键；返回 [(文件, 行号, 旧, 新, 新行)]。"""
    if not mapping:
        return []
    key_pat = '|'.join(re.escape(k) for k in sorted(mapping, key=len, reverse=True))
    changes = []
    for p in code_files(c):
        rx = call_re(os.path.splitext(p)[1], key_pat)
        path = os.path.join(c, p)
        text = open(path, encoding='utf-8').read()
        lines = text.split('\n')
        hit = False
        for n, ln in enumerate(lines):
            new = rx.sub(lambda m: m.group(1) + m.group(2) + mapping[m.group(3)] + m.group(4), ln)
            if new != ln:
                for m in rx.finditer(ln):
                    changes.append((p, n + 1, m.group(3), mapping[m.group(3)], new.strip()))
                lines[n] = new
                hit = True
        if hit and write:
            open(path, 'w', encoding='utf-8').write('\n'.join(lines))
    return changes


def is_test_file(p):
    return bool(p.endswith('_test.go') or re.search(r'\.test\.[tj]s$', p) or
                re.search(r'(^|/)tests?/', p) or re.search(r'(^|/)test_[^/]*\.py$', p))


def old_key_mentions(c, mapping):
    """代码的**字符串字面量与注释**里还提到旧键名的地方（报错文案、日志、注释）：[(文件, 行号, 旧键, 行)]。
    只提示，不改；同名的变量名（如 Go 的 casdoorOrgName）不算。"""
    if not mapping:
        return []
    key_pat = '|'.join(re.escape(k) for k in sorted(mapping, key=len, reverse=True))
    word = re.compile(r'(?<![A-Za-z0-9_])(%s)(?![A-Za-z0-9_])' % key_pat)
    strs = re.compile(r'"(?:[^"\\]|\\.)*"|`[^`]*`|\'(?:[^\'\\]|\\.)*\'')
    out = []
    for p in code_files(c):
        ext = os.path.splitext(p)[1]
        rx = call_re(ext, key_pat)
        cmt = '#' if ext == '.py' else '//'
        for n, ln in enumerate(open(os.path.join(c, p), encoding='utf-8').read().split('\n')):
            code = rx.sub('', ln)
            segs = [m.group(0) for m in strs.finditer(code)]
            bare = strs.sub('""', code)
            if cmt in bare:
                segs.append(bare[bare.index(cmt):])
            elif bare.lstrip().startswith(('*', '/*')):
                segs.append(bare)                                  # 块注释的中间行
            for seg in segs:
                for m in word.finditer(seg):
                    out.append((p, n + 1, m.group(1), ln.strip()))
    return out


def print_mentions(c, mapping):
    ms = old_key_mentions(c, mapping)
    if ms:
        print('  ℹ️  代码里还提到旧键名（不是 SDK 读取，脚本不改；多半是报错文案或注释，人工看要不要改成新键名）：')
        for p, n, k, ln in ms:
            print(f'      {p}:{n}: {k}    {ln[:140]}')


def code_reads(c, test_files=True):
    """当前工作区代码里所有经 SDK Config 读取的键：[(文件, 行号, 键)]。"""
    out = []
    for p in code_files(c):
        if not test_files and is_test_file(p):
            continue
        rx = call_re(os.path.splitext(p)[1], r'[A-Za-z_][A-Za-z0-9_]*')
        for n, ln in enumerate(open(os.path.join(c, p), encoding='utf-8').read().split('\n')):
            for m in rx.finditer(ln):
                out.append((p, n + 1, m.group(3)))
    return out


# ───────────────────────────── 检查（component-loop 3.2 + 代码） ─────────────────────────────

def manifest_checks(m, text, cx):
    """返回 [(检查项, 问题列表)]；问题列表为空即"无"。"""
    cs = m.get('configSchema') or {}
    props = cs.get('properties') or {}
    req = list(cs.get('required') or [])
    dep = m.get('deployment') or {}
    deps = (m.get('dependencies') or {}).get('components') or []
    md = m.get('metadata') or {}
    res = []
    res.append(('驼峰/非法键', [k for k in props if not KEY_RE.fullmatch(k)]))
    res.append(('保留名', [k for k in props if k.endswith('_ENDPOINT') or k in RESERVED]))
    res.append(('无默认值却不在 required', [k for k, v in props.items() if 'default' not in (v or {}) and k not in req]))
    res.append(('required 却有默认值', [k for k in req if 'default' in (props.get(k) or {})]))
    res.append(('required 里有未声明的键', [k for k in req if k not in props]))
    res.append(('密码/密钥未标 secret', [k for k in props if SECRET_RE.search(k) and not (props[k] or {}).get('secret')]))
    res.append(('残留字段', (['dependencies.resources'] if 'resources' in (m.get('dependencies') or {}) else []) +
                (['deployment.image'] if 'image' in dep else [])))
    res.append(('依赖不是 @2.0.0', [d for d in deps if not (d if isinstance(d, str) else str(d.get('id'))).endswith('@2.0.0')]))
    res.append(('版本注释', [f'第 {n} 行：{ln.strip()}' for n, ln in enumerate(text.split('\n'), 1)
                          if re.search(r'#.*[0-9]+\.[0-9]+\.[0-9]+', ln)]))
    ports = []
    if dep.get('port') != cx['http']:
        ports.append(f'deployment.port={dep.get("port")}，registry={cx["http"]}')
    grpc = [p.get('port') for p in dep.get('extraPorts') or [] if p.get('name') == 'grpc']
    if (grpc[0] if grpc else None) != cx['grpc']:
        ports.append(f'extraPorts.grpc={grpc[0] if grpc else "无"}，registry={cx["grpc"] or "无"}')
    res.append(('端口与 registry 不一致', ports))
    sch = []
    if cx['schema'] and 'PG_SCHEMA' in props and (props['PG_SCHEMA'] or {}).get('default') != cx['schema']:
        sch.append(f'PG_SCHEMA 默认值 {(props["PG_SCHEMA"] or {}).get("default")!r}，registry={cx["schema"]}')
    if cx['schema'] and 'PG_SCHEMA' not in props:
        sch.append('连库组件没有声明 PG_SCHEMA')
    res.append(('PG_SCHEMA 与 registry 不一致', sch))
    mt = []
    if not str(md.get('version', '')).startswith('2.'):
        mt.append(f'metadata.version={md.get("version")}')
    if md.get('repository') != f'https://github.com/brickKit/{cx["repo"]}':
        mt.append(f'metadata.repository={md.get("repository")}')
    for f in ('name', 'description'):
        if re.search(r'[　-鿿＀-￯]', str(md.get(f, ''))) or not md.get(f):
            mt.append(f'metadata.{f} 不是英文：{md.get(f)}')
    res.append(('metadata 不合要求', mt))
    st = []
    if not isinstance(dep.get('build'), dict):
        st.append('没有 deployment.build')
    loc = m.get('local') or {}
    if not isinstance(loc.get('runCommand'), list):
        st.append(f'local.runCommand 不是数组：{loc.get("runCommand")!r}')
    res.append(('deployment.build / local 不合要求', st))
    return res


def assembly_checks(a, cx, ov=None):
    p = []
    for lst, ident in ASSEMBLY_LISTS.items():
        have = {x.get(ident) for x in (a.get(lst) or []) if isinstance(x, dict)}
        for x in (ov or {}).get(f'{lst}_add') or []:
            if x.get(ident) not in have:
                p.append(f'overrides 的 {lst}_add 里的 {x.get(ident)} 不在 assembly.yaml 里')
    for k in ('version', 'shell', 'asset'):
        if k in a:
            p.append(f'残留 {k}')
    if a.get('id') != cx['id']:
        p.append(f'id={a.get("id")}')
    if 'data_scopes' not in a:
        p.append('缺 data_scopes（无行级范围写 data_scopes: none）')
    if cx['role']:
        role = (a.get('data') or {}).get('role')
        if role != cx['role']:
            p.append(f'data.role={role}，registry={cx["role"]}')
    return [('assembly.yaml 不合要求', p)]


def code_checks(c, props):
    reads = code_reads(c)
    camel = [f'{p}:{n}: "{k}"' for p, n, k in reads if not KEY_RE.fullmatch(k)]
    undeclared = sorted({f'{p}:{n}: "{k}"' for p, n, k in code_reads(c, test_files=False)
                         if KEY_RE.fullmatch(k) and k not in props})
    return [('代码里还有驼峰键读取', camel), ('代码读取了 configSchema 没声明的键', undeclared)]


def print_checks(results, title):
    print(f'\n🔎 {title}')
    bad = 0
    for name, probs in results:
        if probs:
            bad += 1
            print(f'  {name}: {probs}')
        else:
            print(f'  {name}: 无')
    return bad


# ───────────────────────────── 主流程 ─────────────────────────────

def written_record(c, name):
    """本脚本上次在这个检出里写出的文件内容的 sha1 存在哪（放在组件仓库的 git 目录里：不进提交、与会话无关）。"""
    r = subprocess.run(['git', '-C', c, 'rev-parse', '--absolute-git-dir'], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return os.path.join(r.stdout.strip(), 'be-migrate-manifest', name + '.sha1')


def sha1(s):
    import hashlib
    return hashlib.sha1(s.encode('utf-8')).hexdigest()


def last_written(c, name):
    p = written_record(c, name)
    try:
        return open(p).read().strip() if p else None
    except OSError:
        return None


def remember_written(c, name, text):
    p = written_record(c, name)
    if p:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'w').write(sha1(text) + '\n')


def show_diff(path_label, old, new):
    d = list(difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True),
                                  f'a/{path_label}', f'b/{path_label}'))
    sys.stdout.write(''.join(d) if d else f'（{path_label} 与工作区一致）\n')


def generate(cx):
    tag = last_v1_tag(cx['dir'])
    old_c_text = git(cx['dir'], 'show', f'{tag}:component.yaml')
    old_a_text = git(cx['dir'], 'show', f'{tag}:assembly.yaml')
    old_c = yaml.safe_load(old_c_text)
    ov = load_override(cx['id'])
    new_c = build_component(old_c, ov, cx)
    text_c = render(new_c)
    if yaml.safe_load(text_c) != new_c:
        raise Fatal('生成的 component.yaml 解析回来与推导结果不一致（脚本的 YAML 输出有 bug），不写盘')
    adds = {lst: ov.get(f'{lst}_add') or [] for lst in ASSEMBLY_LISTS}
    text_a, removed = edit_assembly(old_a_text, cx, adds)
    mapping = {k: SHARED.get(k, snake(k)) for k in ((old_c.get('configSchema') or {}).get('properties') or {})}
    mapping = {k: v for k, v in mapping.items() if k != v}
    return tag, new_c, text_c, text_a, removed, mapping, old_c_text, old_a_text, adds


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('id')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--force', action='store_true', help='--write 时覆盖手改过的文件（会丢掉手改）')
    a = ap.parse_args()
    if a.force and not a.write:
        raise Fatal('--force 只和 --write 一起用')
    cx = context(a.id)
    c = cx['dir']
    rc = 0
    if a.write or not a.check:
        tag, new_c, text_c, text_a, removed, mapping, tag_c, tag_a, adds = generate(cx)
        cur_c = open(os.path.join(c, 'component.yaml'), encoding='utf-8').read()
        cur_a = open(os.path.join(c, 'assembly.yaml'), encoding='utf-8').read()
        print(f'📦 {cx["id"]}：输入 = tag {tag} 的 component.yaml / assembly.yaml + manifest-overrides.yaml')
        print(f'   assembly.yaml 删除的键：{removed or "无"}；data.role 注释 → {ROLE_COMMENT}')
        print(f'   旧键 → 新键：{mapping or "无"}')
        print(f'   assembly.yaml 追加：{ {k: [x[ASSEMBLY_LISTS[k]] for x in v] for k, v in adds.items() if v} or "无"}')
        bad = print_checks(manifest_checks(new_c, text_c, cx) + assembly_checks(yaml.safe_load(text_a), cx),
                           '生成结果自检（component-loop 3.2）')
        if bad:
            print('❌ 生成结果自检不过：改 manifest-overrides.yaml 或脚本，不写盘', file=sys.stderr)
            return 1
        if not a.write:
            print('\n──── component.yaml（将写出）────')
            sys.stdout.write(text_c)
            print('──── assembly.yaml（将写出）────')
            sys.stdout.write(text_a)
            print('──── diff ────')
            show_diff('component.yaml', cur_c, text_c)
            show_diff('assembly.yaml', cur_a, text_a)
            changes = rewrite_code(c, mapping, write=False)
            print('──── 代码里将改的配置键读取 ────')
            for p, n, o, nw, line in changes:
                print(f'  {p}:{n}: "{o}" → "{nw}"    {line}')
            if not changes:
                print('  无')
            print_mentions(c, mapping)
            print('\n（预览，未写盘；加 --write 写入）')
        else:
            # 手改保护：工作区文件既不是 tag 原文、也不是本次生成结果、也不是本脚本上次在这里写出的内容
            # → 有人在 C3 之后手改过，拒绝覆盖（--force 例外）。"上次写出的"让"改 overrides → 重跑"可以照常进行
            files = (('component.yaml', cur_c, text_c, tag_c), ('assembly.yaml', cur_a, text_a, tag_a))
            touched = [(n, cur, new) for n, cur, new, tg in files
                       if cur not in (new, tg) and sha1(cur) != last_written(c, n)]
            if touched and not a.force:
                for n, cur, new in touched:
                    print(f'\n❌ {n} 被手改过：它既不是 tag {tag} 的原文，也不是本次会生成的内容。'
                          f'--write 会丢掉下面 diff 里以 "-" 开头的改动：', file=sys.stderr)
                    sys.stderr.write(''.join(difflib.unified_diff(cur.splitlines(keepends=True), new.splitlines(keepends=True),
                                                                  f'工作区/{n}', f'将写出/{n}')))
                print('\n❌ 没有写任何文件。要保留的改动请写进 manifest-overrides.yaml（add_properties / required_add / '
                      'deps_add / permissions_add / menus_add / edge_routes_add …）再重跑；确认要丢掉，加 --force。', file=sys.stderr)
                return 3
            for n, cur, new in touched:
                print(f'  ⚠️  {n} 被手改过，--force：覆盖')
            for name, cur, new, _ in files:
                remember_written(c, name, new)
                if cur == new:
                    print(f'  {name}：未改动（已是目标内容）')
                else:
                    open(os.path.join(c, name), 'w', encoding='utf-8').write(new)
                    print(f'  ✏️  {name}：已重写')
                    show_diff(name, cur, new)
            changes = rewrite_code(c, mapping, write=True)
            for p, n, o, nw, line in changes:
                print(f'  ✏️  {p}:{n}: "{o}" → "{nw}"    {line}')
            if not changes:
                print('  代码里的配置键读取：未改动（没有旧键读法）')
            print_mentions(c, mapping)
    if a.check:
        text = open(os.path.join(c, 'component.yaml'), encoding='utf-8').read()
        try:
            m = yaml.safe_load(text) or {}
            asm = yaml.safe_load(open(os.path.join(c, 'assembly.yaml'), encoding='utf-8')) or {}
        except yaml.YAMLError as e:
            raise Fatal(f'工作区的 component.yaml / assembly.yaml 不是合法 YAML：{e}')
        props = (m.get('configSchema') or {}).get('properties') or {}
        results = manifest_checks(m, text, cx) + assembly_checks(asm, cx, load_override(cx["id"])) + code_checks(c, props)
        bad = print_checks(results, f'--check（工作区 {c}）')
        print('  依赖:', (m.get('dependencies') or {}).get('components'))
        old_props = (yaml.safe_load(git(c, 'show', f'{last_v1_tag(c)}:component.yaml')).get('configSchema') or {}).get('properties') or {}
        print_mentions(c, {k: SHARED.get(k, snake(k)) for k in old_props if SHARED.get(k, snake(k)) != k})
        if bad:
            print(f'❌ --check：{bad} 项不是"无"', file=sys.stderr)
            rc = 1
        else:
            print('✅ --check 全部为"无"')
    return rc


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Fatal as e:
        print(f'❌ migrate-manifest.py: {e}', file=sys.stderr)
        sys.exit(2)
