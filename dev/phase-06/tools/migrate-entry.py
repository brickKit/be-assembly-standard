#!/usr/bin/env python3
"""component-loop §4.6 的机械部分（be-sdk-go v0.4.0 起）：迁移入口改成 SDK 的一行，模块里删掉 Migrations 字段。

用法：python3 migrate-entry.py <组件目录> --apply | --check
  --apply  1. 找本组件的迁移嵌入包（含 `//go:embed *.sql` 的那个包）；没有就建 migrations/embed.go
           2. backend/cmd/migrate/main.go 整份写成：package main + import (嵌入包; be-sdk-go/migrate)
              + func main() { migrate.Main(migrations.FS) }
           3. backend/module/module.go 删掉 besdk.Module{…} 里的 `Migrations:` 一行（连同紧挨在它上面、
              只说它的注释行），以及因此不再用到的 import / 变量；然后 gofmt
  --check  只核对：main.go 恰好是那一行入口、嵌入包存在、非 gen 代码里没有 `Migrations:` 字段；
           有问题逐条打印、exit 1
由 go-v2.sh 在 --sdk ≥ v0.4.0 时调用（v0.4.0 删了 Module.Migrations，不做这一步 go build 必然失败）。
退出码：0 成功 / 通过；1 --check 有问题；2 输入不符合预期（大声失败，不猜）。
"""
import os
import re
import shutil
import subprocess
import sys

SKIP = ('gen/', 'vendor/', 'node_modules/', '.git/')
EMBED_GO = '''package migrations

import "embed"

// FS 是本组件的全部迁移文件，迁移入口 backend/cmd/migrate 用 be-sdk-go 的 migrate.Main 跑它。
//
//go:embed *.sql
var FS embed.FS
'''


class Fatal(Exception):
    pass


def go_files(c):
    for root, dirs, files in os.walk(c):
        rel = os.path.relpath(root, c)
        rel = '' if rel == '.' else rel + '/'
        dirs[:] = [d for d in dirs if not (rel + d + '/').startswith(SKIP) and d not in ('.git', 'node_modules', 'vendor')]
        for f in files:
            if f.endswith('.go'):
                yield rel + f


def module_path(c):
    for ln in open(os.path.join(c, 'go.mod'), encoding='utf-8'):
        m = re.match(r'^module\s+(\S+)', ln)
        if m:
            return m.group(1)
    raise Fatal('go.mod 里没有 module 行')


def gofmt():
    g = shutil.which('gofmt')
    if not g:
        r = subprocess.run(['go', 'env', 'GOROOT'], capture_output=True, text=True)
        g = os.path.join(r.stdout.strip(), 'bin', 'gofmt')
    if not os.path.exists(g):
        raise Fatal('找不到 gofmt')
    return g


def fmt_source(src):
    r = subprocess.run([gofmt()], input=src, capture_output=True, text=True)
    if r.returncode != 0:
        raise Fatal(f'gofmt 失败：{r.stderr.strip()}')
    return r.stdout


def find_embed(c):
    """返回 (相对目录, 包名, 变量名) 或 None。"""
    hits = []
    for p in go_files(c):
        if p.endswith('_test.go'):
            continue
        text = open(os.path.join(c, p), encoding='utf-8').read()
        if not re.search(r'^//go:embed\s+\*\.sql\s*$', text, re.M):
            continue
        pkg = re.search(r'^package\s+(\w+)', text, re.M)
        var = re.search(r'^//go:embed\s+\*\.sql\s*\n\s*var\s+(\w+)\s+embed\.FS', text, re.M)
        if not pkg or not var:
            raise Fatal(f'{p} 有 //go:embed *.sql，但认不出包名或 `var X embed.FS`')
        hits.append((os.path.dirname(p), pkg.group(1), var.group(1)))
    if len(hits) > 1:
        raise Fatal(f'找到不止一个迁移嵌入包：{hits}')
    return hits[0] if hits else None


def expected_main(c, emb):
    d, pkg, var = emb
    imp = module_path(c) + ('/' + d if d else '')
    sdk = 'github.com/brickKit/be-sdk-go/migrate'
    lines = sorted([f'\t"{sdk}"', f'\t{"" if pkg == "migrations" else "migrations "}"{imp}"'],
                   key=lambda s: s.split('"')[1])
    src = 'package main\n\nimport (\n' + '\n'.join(lines) + '\n)\n\nfunc main() { migrate.Main(migrations.%s) }\n' % var
    return fmt_source(src)


MIG_LINE = re.compile(r'^\s*Migrations\s*:\s*(?P<val>[^,/]+?)\s*,\s*(//.*)?$')


def strip_module(text):
    """删 Migrations 字段及其专属注释，再删因此不再用到的 import / 变量。返回 (新文本, [说明])。"""
    lines = text.split('\n')
    notes, vals = [], []
    i = 0
    out = []
    while i < len(lines):
        ln = lines[i]
        m = MIG_LINE.match(ln)
        if m:
            # 紧挨在上面、中间没有空行的注释行只说这个字段，一起删
            while out and out[-1].strip().startswith('//'):
                notes.append(f'删注释：{out.pop().strip()}')
            notes.append(f'删字段：{ln.strip()}')
            vals.append(m.group('val').strip())
            i += 1
            continue
        if re.search(r'\bMigrations\s*:', ln) and not ln.strip().startswith('//'):
            raise Fatal(f'module.go 的 Migrations 字段不是单行 `Migrations: x,` 写法，脚本不改：{ln.strip()}')
        out.append(ln)
        i += 1
    new = '\n'.join(out)
    code = lambda s: re.sub(r'//.*', '', s)              # 判断"还用不用"时不看注释
    for v in vals:
        mq = re.fullmatch(r'(\w+)\.(\w+)', v)
        if mq:                                            # pkg.FS → 包名不再用到就删 import
            name = mq.group(1)
            body = '\n'.join(l for l in new.split('\n') if not re.match(r'^\s*(\w+\s+)?"[^"]+"\s*$', l))
            if not re.search(rf'\b{name}\.', code(body)):
                imp = re.compile(rf'^\s*(?:{name}\s+)?"[^"]*/{name}"\s*(//.*)?$|^\s*{name}\s+"[^"]+"\s*(//.*)?$')
                kept = []
                for l in new.split('\n'):
                    if imp.match(l):
                        notes.append(f'删 import：{l.strip()}')
                    else:
                        kept.append(l)
                new = '\n'.join(kept)
        elif re.fullmatch(r'\w+', v):                     # 变量 → 只剩声明这一处就删声明
            uses = re.findall(rf'\b{v}\b', code(new))
            decl = re.compile(rf'^\s*{v}\s*:?=.*$')
            decls = [l for l in new.split('\n') if decl.match(l)]
            if len(decls) == 1 and len(uses) == 1:
                new = '\n'.join(l for l in new.split('\n') if not decl.match(l))
                notes.append(f'删变量：{decls[0].strip()}')
    return new, notes


def apply(c):
    changed = []
    emb = find_embed(c)
    if emb is None:
        mig = os.path.join(c, 'migrations')
        if not os.path.isdir(mig) or not any(f.endswith('.sql') for f in os.listdir(mig)):
            raise Fatal('没有迁移嵌入包，migrations/ 下也没有 .sql 文件，不知道该嵌什么')
        open(os.path.join(mig, 'embed.go'), 'w', encoding='utf-8').write(EMBED_GO)
        changed.append('新建 migrations/embed.go（//go:embed *.sql → var FS embed.FS）')
        emb = ('migrations', 'migrations', 'FS')
    else:
        print(f'  ⏭  迁移嵌入包已存在：{emb[0] or "."}（package {emb[1]}，var {emb[2]}）')
        print(f'  ℹ️  {emb[0]}/ 里嵌入文件的注释若还在说"给 Module.Migrations 用 / 迁移容器读磁盘"，C4 审查时改掉')
    main = os.path.join(c, 'backend', 'cmd', 'migrate', 'main.go')
    want = expected_main(c, emb)
    cur = open(main, encoding='utf-8').read() if os.path.exists(main) else None
    if cur != want:
        os.makedirs(os.path.dirname(main), exist_ok=True)
        # 迁移入口目录里只留 main.go：旧入口的辅助文件（若有）会和新 main 冲突
        others = [f for f in os.listdir(os.path.dirname(main)) if f.endswith('.go') and f != 'main.go' and not f.endswith('_test.go')]
        if others:
            raise Fatal(f'backend/cmd/migrate/ 里除 main.go 还有 {others}，脚本不知道怎么处理')
        open(main, 'w', encoding='utf-8').write(want)
        changed.append('backend/cmd/migrate/main.go 改成一行：migrate.Main(migrations.FS)')
    mod = os.path.join(c, 'backend', 'module', 'module.go')
    if not os.path.exists(mod):
        raise Fatal('没有 backend/module/module.go')
    text = open(mod, encoding='utf-8').read()
    new, notes = strip_module(text)
    if new != text:
        new = fmt_source(new)
        open(mod, 'w', encoding='utf-8').write(new)
        changed += [f'backend/module/module.go：{n}' for n in notes] + ['backend/module/module.go：gofmt']
    for ch in changed:
        print(f'  ✏️  {ch}')
    if not changed:
        print('  ⏭  迁移入口已是一行、模块里没有 Migrations 字段')


def check(c):
    probs = []
    emb = find_embed(c)
    if emb is None:
        probs.append('没有迁移嵌入包（//go:embed *.sql）')
    main = os.path.join(c, 'backend', 'cmd', 'migrate', 'main.go')
    if emb and (not os.path.exists(main) or open(main, encoding='utf-8').read() != expected_main(c, emb)):
        probs.append('backend/cmd/migrate/main.go 不是 `func main() { migrate.Main(migrations.FS) }` 那一行入口')
    for p in go_files(c):
        for n, ln in enumerate(open(os.path.join(c, p), encoding='utf-8').read().split('\n'), 1):
            if re.search(r'\bMigrations\s*:', re.sub(r'//.*', '', ln)):
                probs.append(f'{p}:{n} 还有 Migrations 字段：{ln.strip()}')
    for x in probs:
        print(f'  · {x}')
    return 1 if probs else 0


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ('--apply', '--check'):
        raise Fatal('用法：migrate-entry.py <组件目录> --apply|--check')
    c = os.path.abspath(sys.argv[1])
    if sys.argv[2] == '--apply':
        apply(c)
        return 0
    return check(c)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Fatal as e:
        print(f'❌ migrate-entry.py: {e}', file=sys.stderr)
        sys.exit(2)
