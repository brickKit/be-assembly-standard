#!/usr/bin/env python3
"""按本项目的"配置值"规则填写 config/<repo>.yaml（brickkit add 写出的骨架）。

用法：python3 infra/scripts/config-fill.py <id> [--set KEY=VALUE …] [--root <项目根>]

逐个 configSchema 键决定值（文本级编辑：注释行、行尾注释原样保留）：
  --set KEY=VALUE        原样写（覆盖已有值；值需要时自动加引号）
  已有非空值             不动
  外壳（有 shell 段）    PG_USER → shell_<name>；PG_PASSWORD → ${SHELL_<NAME>_PASSWORD}；不写 PG_SCHEMA
  组件                   PG_USER / PG_SCHEMA → registry/schemas.tsv 的字面量；PG_PASSWORD → ${<UREPO>_DB_PASSWORD}
  config/vars.yaml 有的键 → $var:KEY（组件有默认值也显式写，换环境时部署文件的 vars: 能覆盖到）
其余键不动：组件自有可选键保持注释（跟随组件默认），其它密钥由人给值（会给出 ${<UREPO>_<KEY>} 的建议写法）。
required 键最后仍没有值 → 列出键名，退出码 3（已能填的照样写盘）。参数或文件错误 → 退出码 2。
"""
import argparse
import json
import pathlib
import re
import sys

import yaml

KEY_RE = re.compile(r"^(?P<key>[A-Z][A-Z0-9_]*):(?P<rest>.*)$")
COMMENTED_RE = re.compile(r"^#\s?(?P<key>[A-Z][A-Z0-9_]*):(?P<rest>.*)$")
PG_SPECIAL = {"PG_USER", "PG_PASSWORD", "PG_SCHEMA"}
# secret: true 的键只允许引用：${VAR}（只允许空默认值 :-，非空默认值等于明文）、file://…、$var:NAME——明文会被提交进 config/
SECRET_REF = re.compile(r"^(\$\{[A-Za-z_][A-Za-z0-9_]*(:-)?\}|file://\S+|\$var:[A-Za-z_][A-Za-z0-9_]*)$")


def die(msg: str, code: int = 2) -> None:
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(code)


def load_yaml(p: pathlib.Path):
    return yaml.safe_load(p.read_text(encoding="utf-8")) or {}


def pinned_version(root: pathlib.Path, cid: str):
    """brickkit.yaml 里该组件的默认版本（没有 requiredBy 的那一行）；不在项目里返回 None。"""
    p = root / "brickkit.yaml"
    if not p.exists():
        return None
    for c in load_yaml(p).get("components") or []:
        if c.get("id") == cid and not c.get("requiredBy"):
            return str(c.get("version"))
    return None


def find_manifest(root: pathlib.Path, cid: str, ver):
    """本地源（components/、shell/）的版本与钉的版本一致时用它，否则用 .brickkit/manifests 缓存。"""
    for base in ("components", "shell"):
        p = root / base / cid / "component.yaml"
        if p.exists():
            m = load_yaml(p)
            if ver is None or str((m.get("metadata") or {}).get("version")) == ver:
                return p, m
    if ver is not None:
        p = root / ".brickkit" / "manifests" / cid / ver / "component.yaml"
        if p.exists():
            return p, load_yaml(p)
    die(f"找不到 {cid}{'@' + ver if ver else ''} 的 component.yaml（本地源 components/、shell/ 或 .brickkit/manifests/ 缓存）")


def schema_row(root: pathlib.Path, repo: str):
    p = root / "registry" / "schemas.tsv"
    if not p.exists():
        return None
    for line in p.read_text(encoding="utf-8").splitlines():
        cols = line.split("\t")
        if line.startswith("#") or len(cols) < 3:
            continue
        if cols[0] == repo:
            return {"schema": cols[1], "role": cols[2]}
    return None


def yaml_scalar(value: str) -> str:
    """原样写；只有原文作为 YAML 读回来不等于它本身（或读成 null）时才加双引号。"""
    if value == "":
        return '""'
    try:
        back = yaml.safe_load(f"k: {value}")
        if isinstance(back, dict) and set(back) == {"k"} and back["k"] is not None \
                and not isinstance(back["k"], (dict, list)) and str(back["k"]) == value:
            return value
    except yaml.YAMLError:
        pass
    return json.dumps(value, ensure_ascii=False)


def split_value_comment(rest: str):
    """'  $var:X  # string' → ('$var:X', '  # string')；值本身里的 # 不算注释。"""
    try:
        whole = yaml.safe_load(f"k:{rest}")
    except yaml.YAMLError:
        whole = None
    for m in re.finditer(r"\s+#", rest):
        head = rest[:m.start()]
        try:
            if yaml.safe_load(f"k:{head}") == whole:
                return head.strip(), rest[m.start():]
        except yaml.YAMLError:
            continue
    return rest.strip(), ""


def is_empty(raw: str) -> bool:
    try:
        v = yaml.safe_load(f"k: {raw}")["k"] if raw else None
    except yaml.YAMLError:
        return False
    return v is None or v == ""


def derive(key: str, *, shell: bool, name: str, repo: str, row, var_keys: set):
    """按项目规则推导一个键的值；推不出返回 None。"""
    urepo = repo.upper().replace("-", "_")
    if key in PG_SPECIAL:
        if shell:
            uname = name.upper().replace("-", "_")
            return {"PG_USER": f"shell_{name.replace('-', '_')}",
                    "PG_PASSWORD": f"${{SHELL_{uname}_PASSWORD}}"}.get(key)
        if row is None:
            return None
        return {"PG_USER": row["role"], "PG_SCHEMA": row["schema"],
                "PG_PASSWORD": f"${{{urepo}_DB_PASSWORD}}"}[key]
    if key in var_keys:
        return f"$var:{key}"
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("id")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE")
    ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parents[2]))
    a = ap.parse_args()
    root = pathlib.Path(a.root)
    cid = a.id
    if not re.fullmatch(r"[a-z0-9-]+/[a-z0-9-]+", cid):
        die(f"组件 ID 应为 <scope>/<name>：{cid}")
    scope, name = cid.split("/")
    repo = f"{scope}-{name}"
    urepo = repo.upper().replace("-", "_")

    ver = pinned_version(root, cid)
    mpath, manifest = find_manifest(root, cid, ver)
    schema = manifest.get("configSchema") or {}
    props = schema.get("properties") or {}
    required = list(schema.get("required") or [])
    shell = "shell" in manifest

    sets = {}
    for s in a.set:
        k, eq, v = s.partition("=")
        if not eq:
            die(f"--set 要写成 KEY=VALUE：{s}")
        if k not in props:
            die(f"--set {k}：{cid} 的 configSchema 没有这个键（有：{', '.join(sorted(props))}）")
        sets[k] = v
    bad = [k for k, v in sets.items() if props[k].get("secret") and not SECRET_REF.match(v)]
    if bad:
        die(f"--set {', '.join(bad)}：secret 键的值只能是引用 ${{VAR}}（值放 .env）、file://<路径> 或 $var:<名>，"
            f"不能写明文（config/ 会被提交）。例：--set '{bad[0]}=${{{urepo}_{bad[0]}}}'")

    cfg = root / "config" / f"{repo}.yaml"
    if not cfg.exists():
        die(f"没有 {cfg.relative_to(root)}——先 brickkit add {cid}@<版本> 生成骨架")
    vars_path = root / "config" / "vars.yaml"
    var_keys = set(load_yaml(vars_path)) if vars_path.exists() else set()
    row = schema_row(root, repo)
    ctx = dict(shell=shell, name=name, repo=repo, row=row, var_keys=var_keys)

    lines = cfg.read_text(encoding="utf-8").splitlines()
    seen, final, changed, plain = set(), {}, [], []
    for i, line in enumerate(lines):
        m = KEY_RE.match(line)
        if m and m["key"] in props:
            key = m["key"]
            seen.add(key)
            raw, comment = split_value_comment(m["rest"])
            if key in sets:
                new = yaml_scalar(sets[key])
            elif not is_empty(raw):
                final[key] = raw
                if props[key].get("secret") and not SECRET_REF.match(str(yaml.safe_load(f"k: {raw}")["k"])):
                    plain.append(key)
                continue
            else:
                d = derive(key, **ctx)
                if d is None:
                    final[key] = ""
                    continue
                new = yaml_scalar(d)
            if new != raw:
                lines[i] = f"{key}: {new}{comment}"
                changed.append(key)
            final[key] = new
            continue
        m = COMMENTED_RE.match(line)
        if m and m["key"] in props and m["key"] not in seen:
            key = m["key"]
            new = yaml_scalar(sets[key]) if key in sets else (
                yaml_scalar(d) if (d := derive(key, **ctx)) is not None else None)
            if new is None:
                continue
            seen.add(key)
            _, comment = split_value_comment(m["rest"])
            comment = re.sub(r"\s*\(default\)\s*$", "", comment)
            lines[i] = f"{key}: {new}{comment}"
            changed.append(key)
            final[key] = new

    appended = []
    for key in props:
        if key in seen:
            continue
        new = yaml_scalar(sets[key]) if key in sets else (
            yaml_scalar(d) if (d := derive(key, **ctx)) is not None else None)
        if new is None:
            continue
        if not appended:
            lines.append("")
            lines.append("# === config-fill.py 补写（骨架里没有这些键） ===")
        lines.append(f"{key}: {new}")
        appended.append(key)
        changed.append(key)
        final[key] = new

    if plain:
        die(f"{cfg.relative_to(root)} 里 secret 键 {', '.join(plain)} 写的是明文：改成 ${{VAR}}（值放 .env）、file://<路径> 或 $var:<名>"
            f"（可用 --set 覆盖），本次没有写盘")
    text = "\n".join(lines) + "\n"
    rel = cfg.relative_to(root)
    if text != cfg.read_text(encoding="utf-8"):
        cfg.write_text(text, encoding="utf-8")
        print(f"✓ {rel}（{mpath.relative_to(root)}）：写了 {len(changed)} 个键：{', '.join(changed)}")
    else:
        print(f"✓ {rel}：无需改动")

    missing = [k for k in required if is_empty(final.get(k, "")) and "default" not in props[k]]
    if missing:
        print(f"✗ {rel} 还有 {len(missing)} 个 required 键没有值，需要人给（再跑一次带 --set KEY=VALUE）：")
        for k in missing:
            hint = f"密钥，建议 ${{{urepo}_{k}}}（值进 .env）；基础资源的密钥沿用它原有的变量名；多行密钥用 file://.secrets/{repo}/<文件>" \
                if props[k].get("secret") else "组件自有键，按组件 BRICKKIT.md 的 Configuration 一节给值"
            print(f"   - {k}  （{hint}）")
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
