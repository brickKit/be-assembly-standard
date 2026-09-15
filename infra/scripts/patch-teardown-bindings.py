#!/usr/bin/env python3
"""临时给 brickkit.yaml 打上"全拆态"专用的资源绑定，配合
`brickkit up --ignore-served-by` 一起用（不 commit，teardown-down 时
`git checkout` 整份恢复）。

`strip-shell-servedby.py` 的继任者——brickKit v0.4.2 新增
`brickkit up --ignore-served-by`（内存里清空全部 servedBy 声明再跑一次，
不写回文件）之后，"删掉每个成员的 `servedBy: <外壳 id>@<版本>` 那一行"
这一半工作已经不需要脚本自己动手了，见根 AGENTS.md 与 `docs/plans/
04b-验证记录.md` Task 0.6。但下面两件事 `--ignore-served-by` 管不到，
仍然需要这条脚本临时改 `brickkit.yaml`：

1. **资源绑定**：阶段四附加 Task 0.4 起，`resources:` 段的 `bindings`
   只绑外壳自己的 componentId（brickKit v0.4.1 的 `servingShellID`：
   外壳绑了资源，等价于它收编的每个成员也绑了）。这条等价关系的前提是
   "成员的 `servedBy` 指向这个外壳"——`--ignore-served-by` 在内存里把
   这个字段清空之后，等价关系跟着失效，12 个成员必须每个都有一条指向
   自己 componentId 的直接绑定，否则 `brickkit up`（非 `--dry-run`）
   直接报 `RESOURCE_UNBOUND` 阻断（已用 `--dry-run` 真机验证过这个
   结论：只加 `--ignore-served-by`、不打这个补丁，12 个成员全部因为
   缺资源绑定被警告，生成的 compose 里一个 `DATABASE_*`/`MQ_*` 环境
   变量都没有）。
2. **`expose: true`**：12 个成员从 servedBy 落地起就不再生成自己的
   容器，`expose`/`exposePort` 这两个字段对它没有意义，Task 0.4 时统一
   删掉了；全拆态下它们重新变回独立容器，`make tier0`/`make tier1`
   里靠 curl 直接打宿主机端口的用例需要这个字段映射端口。

`enabled: false` 那 4 行则是为了不让 4 个外壳组件条目本身也陪跑成
4 个空转容器（`BRICKKIT_SERVED_MEMBERS_CONFIG` 会是 `[]`，起了也没用，
只会把"全拆态 14 个组装态容器"这个数字变成 18，容易让人误读）。

只做"打补丁"这一半，不做"恢复"——恢复用 `git checkout -- brickkit.yaml`
就够了，不需要专门的脚本。
"""
import re
import sys

# 找"这个成员被哪个外壳收编"不再需要匹配那段随时可能改措辞的固定注释，
# 只认 `servedBy: shell/<name>@<version>` 这一行本身——这行的格式是
# brickKit 自己的 manifest 语法，不是本仓库注释风格，改动概率低得多。
SERVED_BY_REF = re.compile(r"^    servedBy: shell/([a-z-]+)@\d+\.\d+\.\d+\n", re.MULTILINE)
COMPONENT_ID_PATTERN = re.compile(r"^  - id: ([a-z0-9/-]+)\n", re.MULTILINE)
SHELL_ENTRY_PATTERN = re.compile(r"( {2}- id: shell/[a-z-]+\n)")

# 外壳 componentId → 它对应的 postgres 资源 id（4 个外壳各自独占一个
# database 资源，见 resources 段的既有注释）。
SHELL_TO_DB_RESOURCE = {
    "go-core": "postgres-go-core",
    "go-backoffice": "postgres-go-backoffice",
    "go-infra": "postgres-go-infra",
    "py-render": "postgres-py-render",
}

# nats-shared 里已经各自留着一条独立绑定、不需要脚本再补的成员
# （历史遗留，见 resources 段——不是这次要修的问题，跳过即可）。
ALREADY_BOUND_TO_NATS = {"infra/print", "crm/opportunity"}


def find_members_by_shell(content: str) -> dict[str, list[str]]:
    """按 servedBy 出现的顺序，把"外壳短名 → 它收编的成员 componentId
    列表"找出来——只读不删，`servedBy:` 那一行本身留给
    `--ignore-served-by` 在内存里处理，这条脚本不碰它。
    """
    by_shell: dict[str, list[str]] = {}
    pos = 0
    while True:
        m = SERVED_BY_REF.search(content, pos)
        if not m:
            break
        block_start = content.rfind("\n  - id: ", 0, m.start())
        comp_m = COMPONENT_ID_PATTERN.match(content, block_start + 1)
        if comp_m:
            by_shell.setdefault(m.group(1), []).append(comp_m.group(1))
        pos = m.end()
    return by_shell


def add_expose(content: str, members: list[str]) -> str:
    for member in members:
        anchor = re.compile(rf"(  - id: {re.escape(member)}\n)")
        content, n = anchor.subn(lambda mo: mo.group(1) + "    expose: true  # teardown-up 临时加回：curl 打 HTTP 需要\n", content, count=1)
        if n == 0:
            print(f"  ⚠️ 没找到 {member} 的条目锚点，expose 没能加上——"
                  "正则要跟着 brickkit.yaml 的实际结构同步改", file=sys.stderr)
    return content


def add_db_bindings(content: str, shell: str, members: list[str]) -> str:
    resource_id = SHELL_TO_DB_RESOURCE[shell]
    anchor = re.compile(
        rf"(- id: {re.escape(resource_id)}\n"
        rf"(?:.*\n)*?"
        rf"      - componentId: shell/{re.escape(shell)}\n"
        rf"        database: brickkit_db\n)"
    )
    extra = "".join(
        f"      - componentId: {member}\n        database: brickkit_db\n"
        for member in members
    )
    new_content, n = anchor.subn(lambda mo: mo.group(1) + extra, content, count=1)
    if n == 0:
        print(f"  ⚠️ 没找到 {resource_id} 里 shell/{shell} 的绑定锚点，"
              "数据库绑定没能补上——正则要跟着 brickkit.yaml 的实际结构同步改",
              file=sys.stderr)
        return content
    return new_content


def add_nats_bindings(content: str, members: list[str]) -> str:
    to_add = [m for m in members if m not in ALREADY_BOUND_TO_NATS]
    if not to_add:
        return content
    anchor = re.compile(r"(- id: nats-shared\n(?:.*\n)*?      - componentId: crm/opportunity\n)")
    extra = "".join(f"      - componentId: {m}\n" for m in to_add)
    new_content, n = anchor.subn(lambda mo: mo.group(1) + extra, content, count=1)
    if n == 0:
        print("  ⚠️ 没找到 nats-shared 的绑定锚点，MQ 绑定没能补上——"
              "正则要跟着 brickkit.yaml 的实际结构同步改", file=sys.stderr)
        return content
    return new_content


def main() -> int:
    with open("brickkit.yaml", encoding="utf-8") as f:
        content = f.read()

    members_by_shell = find_members_by_shell(content)

    all_members: list[str] = []
    for shell, members in members_by_shell.items():
        content = add_db_bindings(content, shell, members)
        all_members.extend(members)
    content = add_nats_bindings(content, all_members)
    content = add_expose(content, all_members)
    content, n_shells = SHELL_ENTRY_PATTERN.subn(r"\1    enabled: false\n", content)

    with open("brickkit.yaml", "w", encoding="utf-8") as f:
        f.write(content)

    print(f"  禁用了 {n_shells} 个外壳组件条目，给 {len(all_members)} 个成员"
          f"补上了各自的资源绑定 + expose:true")
    if n_shells == 0 or not all_members:
        print("  ⚠️ 至少一类一处都没匹配到——brickkit.yaml 的结构是不是变了？"
              " 正则要跟着同步改，见本脚本顶部的说明", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
