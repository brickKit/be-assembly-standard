#!/usr/bin/env python3
"""临时去掉 brickkit.yaml 里全部 local:true/localPort（不 commit）。

从 infra/scripts/weekly-teardown-gate.sh 抽出来的独立脚本——阶段四 Task 12
出档检查时发现 `make teardown-up` 从来没有真的达到过"全拆态"：Task 6/7
把 `local: true` 原子式切换进了 brickkit.yaml 并提交之后，`teardown-up`
自己从来没有跟着补上"临时去掉它"这一步，`brickkit up` 因此只会起 2 个
从没被合并过的独立组件（frontend-standard/infra-bff-mobile），不是文档
写的 14 个。抽成独立脚本是为了不在 weekly-teardown-gate.sh 和 Makefile 的
teardown-up 目标里各写一份同样脆弱的正则（同一个匹配模式改一处、忘记改
另一处，就是这条 bug 本身的同类复发）。

只做"去掉"这一半，不做"恢复"——恢复用 `git checkout -- brickkit.yaml`
就够了，不需要专门的脚本。
"""
import re
import sys

pattern = re.compile(
    r"[ \t]*# ⚠️ local: true 不是有人在调试，是合并部署（阶段四 Task [67] 原子式切换，设计书 §13\.1）\n"
    r"[ \t]*local: true\n"
    r"[ \t]*localPort: \d+\n"
)


def main() -> int:
    with open("brickkit.yaml", encoding="utf-8") as f:
        content = f.read()
    new_content, n = pattern.subn("", content)
    with open("brickkit.yaml", "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"  去掉了 {n} 处 local: true")
    if n == 0:
        print("  ⚠️ 一处都没匹配到——brickkit.yaml 里的注释措辞是不是变了？"
              " 正则要跟着同步改，见本脚本顶部的说明", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
