#!/usr/bin/env bash
# 一个组件的机械核对（component-loop 4.5、4.9、5.1"不写历史"、5.2）：清单里原来要人手 grep 的几项，一条命令跑完。
# 每项打印 PASS/FAIL（FAIL 下面逐处列出 文件:行: 原文），任一 FAIL 就 exit 1。只读，不改工作区。
#
# 用法：bash dev/phase-06/tools/component-check.sh <scope>/<name>; echo "exit=$?"
#   BE_SCRATCH 必填（见 env.sh）；BE_COMP_DIR 可改组件目录；BE_OVERRIDES 可换 manifest-overrides.yaml（测试用）。
# 范围：git ls-files -co --exclude-standard（已跟踪 + 未跟踪但没被忽略的文件，提交前就能查）。
#   (a) 4.5 两条 grep（驼峰键读取；DATABASE_* / MQ_* / besdk.Endpoint 等旧平台变量与旧 API）与 4.9 的 scripts/ grep；
#   (b) 历史 / 归档引用：除 gen/、*.proto、migrations/*.sql、.claude/ 以外的全部文件（含 go.mod、buf.yaml、LICENSE、
#       Makefile、注释），模式与 migrate-manifest.py 的 HIST_RE 相同；确有理由留着的命中写进 manifest-overrides.yaml
#       该组件的 history_allow（{path, text, why}），打印成 ℹ️，不算 FAIL；
#   (c) 5.2 文档：四对文件 en/zh 的 ## 小节数（维护块与代码块不计）、首行互链、没有 ../ 链接、没有越界链接、
#       BRICKKIT*.md 没有相对链接、没有 TODO / TBD / 待填。
# 退出码：0 全部 PASS；1 有 FAIL；2 用法错误或输入不对（组件目录、overrides 写错）。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
die() { echo "❌ component-check.sh: $*" >&2; exit 2; }
[ $# = 1 ] && [ "${1#-}" = "$1" ] || die "用法：bash component-check.sh <scope>/<name>"
# 只读核对不需要 brickkit / buf / .env：--no-tools 让 env.sh 跳过这些核对（task-8a 审查 Minor 3；复审 Minor 4 起是参数，不是环境变量）
envout=$(bash "$HERE/env.sh" --no-tools "$1") || exit 2
eval "$envout"

exec python3 - "$C" "$ID" "$HERE/migrate-manifest.py" <<'EOF'
import importlib.util, os, re, subprocess, sys

C, ID, MM = sys.argv[1:4]
sys.dont_write_bytecode = True             # 只读：不在工具目录里留 __pycache__
spec = importlib.util.spec_from_file_location('mm', MM)
mm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mm)
try:
    allow = mm.load_override(ID).get('history_allow') or []
except mm.Fatal as e:
    print(f'❌ component-check.sh: {e}', file=sys.stderr)
    sys.exit(2)

r = subprocess.run(['git', '-C', C, '-c', 'core.quotepath=off', 'ls-files', '-co', '--exclude-standard', '-z'],
                   capture_output=True, text=True)
if r.returncode != 0:
    print(f'❌ component-check.sh: git ls-files 失败：{r.stderr.strip()}', file=sys.stderr)
    sys.exit(2)
FILES = sorted({p for p in r.stdout.split('\0') if p and os.path.isfile(os.path.join(C, p))})
SKIP = tuple(mm.SKIP_DIRS) + ('.claude/',)


def skipped(p):
    # 只跳过顶层目录（task-8a 审查 Minor 4）：被 .gitignore 忽略的文件 git ls-files 已经去掉了，
    # 嵌套的 backend/vendor/ 之类是组件自己的源码，照查
    return p.startswith(SKIP)


_cache = {}


def lines_of(p):
    if p not in _cache:
        b = open(os.path.join(C, p), 'rb').read()
        _cache[p] = None if b'\0' in b else b.decode('utf-8', errors='replace').split('\n')
    return _cache[p]


def grep(paths, rx):
    out = []
    for p in paths:
        for n, ln in enumerate(lines_of(p) or [], 1):
            if rx.search(ln):
                out.append(f'{p}:{n}: {ln.strip()[:160]}')
    return out


NFAIL = NPASS = 0


def crit(label, probs, info=()):
    global NFAIL, NPASS
    if probs:
        NFAIL += 1
        print(f'  FAIL  {label}')
        for x in probs[:40]:
            print(f'      {x}')
        if len(probs) > 40:
            print(f'      …另有 {len(probs) - 40} 处')
    else:
        NPASS += 1
        print(f'  PASS  {label}')
    for x in info:
        print(f'      ℹ️  {x}')


print(f'🔎 component-check {ID}（{C}，{len(FILES)} 个文件）')
code = [p for p in FILES if not skipped(p) and not p.startswith('gen/')]
ext = lambda p, *e: os.path.splitext(p)[1] in e

# ── (a) component-loop 4.5 / 4.9 ──
camel = (grep([p for p in code if ext(p, '.go')], re.compile(r'(String|StringOr|MustString|Int|IntOr|Bool|BoolOr)\("[a-z]')) +
         grep([p for p in code if ext(p, '.py')], re.compile(r'\.(string|string_or|must_string|int|int_or|bool|bool_or)\(["\'][a-z]')) +
         grep([p for p in code if ext(p, '.ts', '.js')], re.compile(r'\.(string|stringOr|mustString|int|intOr|bool|boolOr)\(["\'][a-z]')))
crit('4.5 无驼峰键读取（Go / Python / TS 的 SDK Config 读法）', camel)
oldp = re.compile(r'besdk\.(Endpoint|MustEndpoint)\(|StorageEndpoint|STORAGE_ENDPOINT|DATABASE_|MQ_(HOST|PORT|USER|PASSWORD)')
crit('4.5 无旧平台变量 / 旧 API（DATABASE_*、MQ_*、besdk.Endpoint、STORAGE_ENDPOINT；*.go *.py *.ts *.sh Makefile）',
     grep([p for p in code if ext(p, '.go', '.py', '.ts', '.js', '.sh', '.mk') or os.path.basename(p) == 'Makefile'], oldp))
crit('4.9 scripts/ 里没有旧版本服务名（1-0-N）与 DATABASE_*',
     grep([p for p in code if p.startswith('scripts/')], re.compile(r'1-0-[0-9]+|DATABASE_')))

# ── (b) 历史 / 归档引用 ──
scope = [p for p in FILES if not (p.startswith(('gen/', '.claude/')) or p.endswith('.proto') or
                                  (p.startswith('migrations/') and p.endswith('.sql')))]
hits, info, used = [], [], set()
for p in scope:
    cand = [(0, f'（文件名）{p}')] if mm.HIST_RE.search(p) else []
    cand += [(n, ln) for n, ln in enumerate(lines_of(p) or [], 1) if mm.HIST_RE.search(ln)]
    for n, ln in cand:
        # 放行（task-8a 审查 Important 1）：path 必须恰好是这个文件；这一行的**每一处**命中都要落在某个
        # 放行 text 在这一行里的出现范围内——一条放行盖不住同一行的第二处引用
        mine = [(i, x) for i, x in enumerate(allow) if x['path'] == p]
        spans = [(m.start(), m.end(), i) for i, x in mine for m in re.finditer(re.escape(x['text']), ln)]
        covered = []
        for h in mm.HIST_RE.finditer(ln):
            c = next((i for s, e, i in spans if s <= h.start() and h.end() <= e), None)
            covered.append(c)
        if not covered or None in covered:
            hits.append(f'{p}:{n}: {ln.strip()[:160]}')
        else:
            used.update(covered)
            info.append(f'{p}:{n}: history_allow 放行（{"；".join(sorted({allow[i]["why"] for i in covered}))}）')
info += [f'history_allow 没用上（可以删掉）：{x}' for i, x in enumerate(allow) if i not in used]
crit('历史 / 归档引用（§、决策 N、设计计划、阶段…、Task N、docs/plans/、archive/；除 gen/ *.proto migrations/*.sql .claude/）',
     hits, info)

# ── (c) component-loop 5.2 文档 ──
docs = [p for p in FILES if p.endswith('.md') and not skipped(p)]


def h2_count(p):
    n, fence, managed = 0, False, False
    for ln in lines_of(p) or []:
        s = ln.strip()
        if 'brickkit:managed:begin' in s:
            managed = True
        elif 'brickkit:managed:end' in s:
            managed = False
        elif s.startswith(('```', '~~~')):
            fence = not fence
        elif not fence and not managed and ln.startswith('## '):
            n += 1
    return n


pairs, firsts = [], []
for base in ('BRICKKIT', 'AGENTS', 'README', 'docs/design'):
    en, zh = base + '.md', base + '.zh.md'
    missing = [f for f in (en, zh) if f not in FILES]
    if missing:
        pairs.append(f'缺 {"、".join(missing)}')
        continue
    a, b = h2_count(en), h2_count(zh)
    if a != b:
        pairs.append(f'{base}：en={a} zh={b}')
    if base != 'BRICKKIT':                  # BRICKKIT*.md 不许有相对链接，所以不写互链行
        b0 = os.path.basename(base)
        for f in (en, zh):
            first = (lines_of(f) or [''])[0]
            if f'[English]({b0}.md)' not in first or f'[中文]({b0}.zh.md)' not in first:
                firsts.append(f'{f}:1: {first.strip()[:120]}')
crit('文档 en/zh ## 小节数相等（BRICKKIT / AGENTS / README / docs/design；维护块与代码块不计）'
     + (f'：{"；".join(pairs)}' if pairs else ''), pairs)
crit('文档首行互链（AGENTS / README / docs/design：[English](X.md) · [中文](X.zh.md)）'
     + (f'：{"、".join(x.split(":")[0] for x in firsts)}' if firsts else ''), firsts)
crit('文档没有 ../ 链接（DOC_LINK_NOT_PORTABLE）', grep(docs, re.compile(r'\]\(\s*<?\.\./|^\s*\[[^\]]+\]:\s*<?\.\./')))
crit('文档没有越界链接（dev/、archive/）', grep(docs, re.compile(r'\]\((\.\./)+(dev|archive)/|archive/pre-v1|dev/phase-06')))
crit('BRICKKIT*.md 没有相对链接', grep([p for p in docs if re.fullmatch(r'BRICKKIT(\.[a-z-]+)?\.md', p)],
                                         re.compile(r'\]\((?!https?://)|^\s*\[[^\]]+\]:\s*(?!https?://)')))
crit('文档没有 TODO / TBD / 待填 占位（DOC_PLACEHOLDER）', grep(docs, re.compile(r'\bTODO\b|\bTBD\b|待填')))

print()
if NFAIL:
    print(f'❌ component-check {ID}：{NFAIL} 项 FAIL，{NPASS} 项 PASS', file=sys.stderr)
    sys.exit(1)
print(f'✅ component-check {ID}：{NPASS} 项全部 PASS')
EOF
