#!/usr/bin/env python3
"""临时去掉 brickkit.yaml 里全部 servedBy（不 commit）。

`strip-shell-local.py` 的 servedBy 版——阶段四附加 Task 0.4 把 12 个组件
从 `local: true` 全量切到真实 `servedBy` 之后，`strip-shell-local.py`
自己的正则找不到任何 `local: true`/`localPort` 行可删了（brickkit.yaml
里已经一行都没有），`teardown-up` 名义上"拆回全部独立容器"，实际上什么
也没发生——这条脚本接过同一份职责，改删每个成员的 `servedBy: <外壳
id>@<版本>` 那一行（连同它固定措辞的四行注释）。删掉这个字段后
brickKit 直接回落到默认行为（普通独立容器），不需要像 local:true 那样
额外恢复 `localPort`。

12 个成员的 `servedBy` 全部去掉之后，4 个外壳组件条目本身（`shell/
go-core`/`go-backoffice`/`go-infra`/`py-render`，阶段四附加 Task 0.4
新增，本身也是普通 brickkit.yaml 组件条目）没有任何成员再指向它们，
但条目本身还在——不额外处理的话它们会作为 4 个空转容器（`SHELL_CONFIG_
JSON` 列的模块全部因为找不到 `BRICKKIT_SERVED_MEMBERS` 匹配项而空转）
陪跑，把"全拆态 14 个组装态容器"这个 AGENTS.md 记录在案的既有数字变成
18，一个真但容易让人误读的数字。所以这条脚本额外给这 4 个条目每个都插
一行 `enabled: false`——它们互相之间、以及跟其它 12 个真实组件之间都没
有 `dependencies.components` 依赖边（没人对外壳声明依赖，只有成员反过来
用 `servedBy` 指向外壳），`enabled: false` 在这里不会级联关掉任何东西
（AGENTS.md 第 10 条的顾虑不适用），单纯是"这次不生成这个容器"。

⚠️ **真机踩到的坑（第一处）**：光删 `servedBy` 不够——`resources:` 段的
`bindings` 从阶段四附加 Task 0.4 起就只绑外壳自己的 componentId（見
brickKit v0.4.1 的 `servingShellID`：外壳绑了资源，等价于它收编的每个
成员也绑了）。一旦某个成员不再被任何外壳 servedBy，它就不再享有这条
"等价于绑了"的判定，`brickkit up` 会报 `RESOURCE_UNBOUND`（12 个成员
的数据库、其中 10 个的 NATS——`infra/print`/`crm/opportunity` 本来就在
`nats-shared` 里各自留着一条独立绑定，不需要再补）。所以这条脚本额外
给每个成员在它原来所属外壳对应的资源上补一条它自己的 `bindings` 条目
（同 `local: true` 时代、以及 v0.4.1 修复前"临时绕过"时期的写法一样），
`teardown-down` 用 `git checkout` 整份恢复时这些临时绑定自然一起消失，
不需要专门再删一遍。

⚠️ **真机踩到的坑（第二处）**：`resources` 补齐之后 `brickkit up` 能
起来了，但 `make tier0`/`make tier1` 里靠 curl/docker exec 从宿主机
直接访问某个成员主端口的用例（`closedloop/tier0_test.go` 的
`httpBase = "http://localhost:8080"`）连不上——12 个成员从 Phase 1
起就一直带着 `expose: true`（阶段一 commit `3ad3f2e`，"档 0 验收要用
curl 从宿主机直接打 HTTP"），阶段四附加 Task 0.4 切到 servedBy 时因为
"servedBy 成员不生成容器，这两个字段对它不生效"被统一删掉——这个理由
在 servedBy 常态下成立，但在这条脚本临时把它们变回独立容器的场景下
不成立了。所以这条脚本也把 `expose: true` 加回来（只映射主端口，额外
端口/gRPC 依旧只能走容器网络 IP，见 3ad3f2e 的原始说明）。

只做"去掉/补上"这一半，不做"恢复"——恢复用 `git checkout --
brickkit.yaml` 就够了，不需要专门的脚本。
"""
import re
import sys

served_by_pattern = re.compile(
    r"[ \t]*# ⚠️ 阶段四附加 Task 0\.4：local:true 退休，改用 brickKit 原生的\n"
    r"[ \t]*# servedBy——工作负载被 shell/([a-z-]+) 收编，不再自己起容器（合并\n"
    r"[ \t]*# 部署现在走平台原生机制而不是本仓库外壳的手写 shell-compose\.yml，\n"
    r"[ \t]*# 设计书 §13\.1，见 docs/plans/04b-验证记录\.md Task 0\.4）\n"
    r"[ \t]*servedBy: shell/[a-z-]+@\d+\.\d+\.\d+\n"
)

component_id_pattern = re.compile(r"^  - id: ([a-z0-9/-]+)\n", re.MULTILINE)

shell_entry_pattern = re.compile(r"( {2}- id: shell/[a-z-]+\n)")

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
    """按 servedBy 出现的顺序，把"外壳短名 → 它收编的成员 componentId 列表"
    找出来——必须在删 servedBy 之前跑，删完就没有这份信息了。
    """
    by_shell: dict[str, list[str]] = {}
    pos = 0
    while True:
        m = served_by_pattern.search(content, pos)
        if not m:
            break
        block_start = content.rfind("\n  - id: ", 0, m.start())
        comp_m = component_id_pattern.match(content, block_start + 1)
        if comp_m:
            by_shell.setdefault(m.group(1), []).append(comp_m.group(1))
        pos = m.end()
    return by_shell


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
    extra = "".join(f"      - componentId: {member}\n" for member in to_add)
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

    content, n_served_by = served_by_pattern.subn(
        "    expose: true  # teardown-up 临时加回：curl 打 HTTP 需要，见本脚本顶部说明\n",
        content,
    )
    content, n_shells = shell_entry_pattern.subn(r"\1    enabled: false\n", content)

    all_members: list[str] = []
    for shell, members in members_by_shell.items():
        content = add_db_bindings(content, shell, members)
        all_members.extend(members)
    content = add_nats_bindings(content, all_members)

    with open("brickkit.yaml", "w", encoding="utf-8") as f:
        f.write(content)

    print(f"  去掉了 {n_served_by} 处 servedBy，禁用了 {n_shells} 个外壳组件条目，"
          f"给 {len(all_members)} 个成员补上了各自的资源绑定")
    if n_served_by == 0 or n_shells == 0:
        print("  ⚠️ 至少一类一处都没匹配到——brickkit.yaml 里的注释/结构是不是变了？"
              " 正则要跟着同步改，见本脚本顶部的说明", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
