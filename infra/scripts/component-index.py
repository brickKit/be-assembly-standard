#!/usr/bin/env python3
"""Generates docs/zh/00-overview/09-component-index.md: one row per component of the catalog with its
boundary card, its repository documents, what is implemented, the required dependencies both ways, and
the event topology declared in the built components' component.yaml.

Sources: the catalog (docs/zh/00-overview/03-catalog.md), the boundary cards (docs/zh/07-components/),
and components/<scope>/<name>/component.yaml of the components rebuilt on the new design (version 3+).

  python3 infra/scripts/component-index.py          write the page
  python3 infra/scripts/component-index.py --check  exit 1 when the page is stale
"""
import glob
import os
import re
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "docs/zh/00-overview/03-catalog.md")
CARDS = os.path.join(ROOT, "docs/zh/07-components")
OUT = os.path.join(ROOT, "docs/zh/00-overview/09-component-index.md")

ID = re.compile(r"`((?:mdm|erp|crm|hrm|prj|ana|infra|integration|frontend)/[a-z0-9\-]+)`")
FAMILY = "infra/iam-*"  # 身份 names the identity family: any infra/iam-* member
ALIASES = {"身份": FAMILY, "授权": "infra/authz"}
LAST_DOMAIN = "新增与退役的身份"


def slug(h):
    """The anchor GitHub and tools/be-acceptance/doc-checks/links.py derive from a heading."""
    h = h.strip().lower()
    h = re.sub(r"[^\w一-鿿\- ]", "", h)
    return h.replace(" ", "-")


def catalog():
    """Returns [(domain, [(id, capability, scope)])] in catalog order."""
    out, domain = [], None
    for line in open(CATALOG, encoding="utf-8"):
        if line.startswith("## "):
            title = line[3:].strip()
            if title == LAST_DOMAIN:
                break
            domain = (title, [])
            out.append(domain)
        elif domain and line.startswith("| `"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            m = ID.fullmatch(cells[0])
            if m:
                domain[1].append((m.group(1), cells[1], cells[2]))
    return [d for d in out if d[1]]


def cards():
    """Returns {id: (card file, anchor, required dependencies as written)}."""
    out = {}
    for path in sorted(glob.glob(os.path.join(CARDS, "*.md"))):
        name = os.path.basename(path)
        if name == "README.md":
            continue
        text = open(path, encoding="utf-8").read()
        for sec in re.split(r"^## ", text, flags=re.M)[1:]:
            head = sec.split("\n", 1)[0].strip()
            ids = ID.findall("`" + head + "`") or ID.findall(head)
            if not ids:
                continue
            req = []
            m = re.search(r"^\| 必需依赖 \| (.*) \|$", sec, re.M)
            if m:
                cell = m.group(1)
                req = ID.findall(cell)
                for word, dep in ALIASES.items():
                    if re.search(r"(^|[、，；（ ])" + word + r"($|[、，；（）(])", cell) and dep not in req:
                        req.append(dep)
            for cid in ids:
                out[cid] = (name, slug(head), [r for r in req if r != cid])
    return out


def built():
    """Returns {id: manifest} for components rebuilt on the new design (major version 3 or later)."""
    out = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "components/*/*/component.yaml"))):
        m = yaml.safe_load(open(path, encoding="utf-8"))
        meta = m.get("metadata", {})
        if int(str(meta.get("version", "0")).split(".")[0]) < 3:
            continue
        m["_dir"] = os.path.dirname(os.path.relpath(path, ROOT))
        out[meta["id"]] = m
    return out


def shells():
    """Returns [(id, manifest)] of the shells rebuilt on the new design (major version 3 or later)."""
    out = []
    for path in sorted(glob.glob(os.path.join(ROOT, "shell/*/*/component.yaml"))):
        m = yaml.safe_load(open(path, encoding="utf-8"))
        meta = m.get("metadata", {})
        if int(str(meta.get("version", "0")).split(".")[0]) < 3:
            continue
        m["_dir"] = os.path.dirname(os.path.relpath(path, ROOT))
        out.append((meta["id"], m))
    return out


def code(cid):
    return "身份（`infra/iam-*`）" if cid == FAMILY else f"`{cid}`"


def render():
    cats, crd, blt = catalog(), cards(), built()
    users = {}
    for cid, (_, _, req) in crd.items():
        for r in req:
            users.setdefault(r, []).append(cid)
    lines = [
        "# 组件索引",
        "",
        "> 由 `make docs-index`（`infra/scripts/component-index.py`）从[组件货架](03-catalog.md)、[边界卡](../07-components/README.md)与各组件的 `component.yaml` 生成，不要手改。",
        "",
        "按组件 ID 找到它的边界卡、仓库里的文档与实现状态；“被谁必需依赖”是改它会影响到的组件（只算必需依赖，可选依赖与缺件行为见边界卡）。",
        "业务词先查[术语表](07-glossary.md)，它给出所属组件；跨组件的业务过程见[业务流程](../08-flows/README.md)。",
        "",
        "**实现**一列：已按新设计重建的组件写版本，打开“组件文档”里的 `AGENTS.md` 从代码地图开始；没有版本的只有设计（边界卡与协议）。",
    ]
    for title, rows in cats:
        lines += ["", f"## {title}", "", "| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |", "| --- | --- | --- | --- | --- | --- | --- | --- |"]
        for cid, cap, scope in rows:
            card = crd.get(cid)
            card_link = f"[{card[0]}](../07-components/{card[0]}#{card[1]})" if card else "—"
            req = "、".join(code(r) for r in card[2]) if card and card[2] else "—"
            us = sorted(set(users.get(cid, [])))
            by = f"{len(us)} 个组件（几乎全部业务组件，见各边界卡）" if len(us) > 30 else "、".join(code(u) for u in us) or "—"
            if cid.startswith("infra/iam-"):
                fam = sorted(set(users.get(FAMILY, [])))
                by = f"身份族的全部 {len(fam)} 个使用者（见边界卡）" if fam else by
            m = blt.get(cid)
            if m:
                d = "../../../" + m["_dir"]
                docs = [f"[BRICKKIT]({d}/BRICKKIT.md)", f"[AGENTS]({d}/AGENTS.md)"]
                if os.path.exists(os.path.join(ROOT, m["_dir"], "docs/design.md")):
                    docs.append(f"[design]({d}/docs/design.md)")
                impl, docs = m["metadata"]["version"], " · ".join(docs)
            else:
                impl, docs = "—", "—"
            lines.append(f"| {code(cid)} | {cap} | {scope} | {impl} | {card_link} | {docs} | {req} | {by} |")
    lines += ["", "## 外壳", "", "已按新设计重建的外壳与它们编进的成员（外壳只把几个成员合进一个进程，见[部署与运行](../04-foundations/01-deployment-and-runtime.md)）。成员的版本是外壳编进的版本，可能落后于组件自己的最新版本。", "",
              "| 外壳 | 版本 | 编进的成员 | 文档 |", "| --- | --- | --- | --- |"]
    for sid, m in shells():
        d = "../../../" + m["_dir"]
        members = "、".join(f"`{x}`" for x in (m.get("shell") or {}).get("members") or []) or "—"
        lines.append(f"| `{sid}` | {m['metadata']['version']} | {members} | [BRICKKIT]({d}/BRICKKIT.md) · [AGENTS]({d}/AGENTS.md) |")
    pub, sub = {}, {}
    for cid, m in blt.items():
        ev = m.get("events") or {}
        for e in ev.get("publishes") or []:
            pub.setdefault(e, []).append(cid)
        for e in ev.get("subscribes") or []:
            sub.setdefault(e, []).append(cid)
    lines += ["", "## 事件", "", "已重建组件在 `component.yaml` 的 `events` 里声明的发布与订阅（`brickkit deps` 给出同一张表）。订阅项以 `*` 结尾时匹配以它前面那一段开头的全部事件。", "",
              "- 订阅者一栏的“—”是“已重建的组件都没有声明订阅它”；还没重建的组件将来是否订阅，看它们的边界卡与协议。",
              "- 订阅者不是全部受影响的组件：完整状态事件的载荷通常也是发布方来源方法（`SourceService`）返回的数据，经来源方法读它的依赖方同样受影响，看上面各表的“被谁必需依赖”。", ""]
    if pub or sub:
        lines += ["| 事件 | 发布者 | 订阅者 |", "| --- | --- | --- |"]
        for e in sorted(pub):
            subs = sorted({c for s, cs in sub.items() for c in cs if s == e or (s.endswith("*") and e.startswith(s[:-1]))})
            lines.append(f"| `{e}` | {'、'.join(code(c) for c in sorted(pub[e]))} | {'、'.join(code(c) for c in subs) or '—'} |")
        for s in sorted(sub):
            if not any(s == e or (s.endswith("*") and e.startswith(s[:-1])) for e in pub):
                lines.append(f"| `{s}` | —（没有已重建的组件发布） | {'、'.join(code(c) for c in sorted(sub[s]))} |")
    else:
        lines.append("已重建的组件还没有声明事件。")
    return "\n".join(lines) + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        cur = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if cur != text:
            print("docs/zh/00-overview/09-component-index.md is stale: run make docs-index", file=sys.stderr)
            return 1
        print("component index: up to date")
        return 0
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote docs/zh/00-overview/09-component-index.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
