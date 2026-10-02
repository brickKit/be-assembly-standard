#!/usr/bin/env python3
"""让 deploy.teardown.yaml 与 deploy.yaml 保持一致（拆回验证用的部署文件）。

用法：python3 infra/scripts/teardown-sync.py [--check] [--root <项目根>]

brickkit add / remove / upgrade 只维护 deploy.yaml（和存在时的 deploy.local.yaml），拆回验证的
deploy.teardown.yaml 由本脚本同步：target 相同、components 一字不差（含外壳的 members 嵌套）、
没有 vars:（authz / iam 地址本来就是成员自己的服务名，不需要覆盖）。文件头的注释保留。
  --check  只核对：不一致时打印差异并退出 1，不写文件。
"""
import argparse
import difflib
import pathlib
import re
import sys

import yaml

DEFAULT_HEADER = (
    "# 拆回验证专用部署文件：配合 --ignore-shells 使用，所有成员都按独立组件部署。\n"
    "# 由 infra/scripts/teardown-sync.py（make teardown-sync）从 deploy.yaml 同步，不要手改。\n"
)
TOP_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*:")


def header_of(text: str) -> str:
    """文件开头连续的注释行与空行。"""
    out = []
    for line in text.splitlines(keepends=True):
        if line.startswith("#") or not line.strip():
            out.append(line)
        else:
            break
    while out and not out[-1].strip():
        out.pop()
    return "".join(out)


def section(text: str, key: str) -> str:
    """deploy.yaml 里某个顶层键的原文（到下一个顶层键为止，去掉末尾空行与注释）。"""
    lines = text.splitlines(keepends=True)
    start = next((i for i, l in enumerate(lines) if l.startswith(f"{key}:")), None)
    if start is None:
        return ""
    end = next((i for i in range(start + 1, len(lines)) if TOP_KEY.match(lines[i])), len(lines))
    body = lines[start:end]
    while body and (not body[-1].strip() or body[-1].startswith("#")):
        body.pop()
    text = "".join(body)
    return text if text.endswith("\n") else text + "\n"


def render(deploy_text: str, teardown_text: str | None) -> str:
    d = yaml.safe_load(deploy_text) or {}
    header = header_of(teardown_text) if teardown_text else DEFAULT_HEADER
    parts = [header.rstrip("\n") + "\n", f"target: {d.get('target', 'docker')}\n"]
    if "k8s" in d:
        parts.append(section(deploy_text, "k8s"))
    parts.append(section(deploy_text, "components") or "components: []\n")
    return "".join(parts)


def consistent(deploy_text: str, teardown_text: str) -> bool:
    d = yaml.safe_load(deploy_text) or {}
    t = yaml.safe_load(teardown_text) or {}
    return (t.get("target") == d.get("target") and (t.get("components") or []) == (d.get("components") or [])
            and "vars" not in t and t.get("k8s") == d.get("k8s"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parents[2]))
    a = ap.parse_args()
    root = pathlib.Path(a.root)
    dp, tp = root / "deploy.yaml", root / "deploy.teardown.yaml"
    if not dp.exists():
        print(f"✗ 找不到 {dp}", file=sys.stderr)
        return 2
    deploy_text = dp.read_text(encoding="utf-8")
    teardown_text = tp.read_text(encoding="utf-8") if tp.exists() else None
    want = render(deploy_text, teardown_text)

    if a.check:
        if teardown_text is not None and consistent(deploy_text, teardown_text):
            print("✓ deploy.teardown.yaml 与 deploy.yaml 一致")
            return 0
        print("✗ deploy.teardown.yaml 与 deploy.yaml 不一致（make teardown-sync 同步）；应有的改动：")
        sys.stdout.writelines(difflib.unified_diff(
            (teardown_text or "").splitlines(keepends=True), want.splitlines(keepends=True),
            "deploy.teardown.yaml（现在）", "deploy.teardown.yaml（同步后）"))
        return 1

    if teardown_text == want:
        print("✓ deploy.teardown.yaml 已与 deploy.yaml 一致，无需改动")
        return 0
    tp.write_text(want, encoding="utf-8")
    assert consistent(deploy_text, want), "内部错误：同步结果与 deploy.yaml 不一致"
    print("✓ deploy.teardown.yaml 已从 deploy.yaml 同步（target、components；不带 vars:）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
