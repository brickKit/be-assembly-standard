#!/usr/bin/env python3
"""从 .env 里只取 POSTGRES_PASSWORD 这一行，URL 编码后打印（不换行），给 env.sh 拼 TEST_PG_DSN 用。

用法：python3 dotenv-pgpass.py <.env 路径>            打印编码后的口令
      python3 dotenv-pgpass.py <.env 路径> --check    只核对（键在、值非空、引号成对），什么都不打印
不把 .env 当 shell 执行（Compose 的 .env 语法不是 shell 语法；里面的 $(…) 不会跑），读到第一行
POSTGRES_PASSWORD= 就停：别的键（含多行 PEM）只被逐行跳过，不解析、不保存。
值的写法按 Compose：成对的单 / 双引号去掉；不带引号时 ` #` 起是行内注释、首尾空白去掉。
编码用 urllib.parse.quote(safe="")：除字母数字与 -._~ 外全部百分号编码，解码结果与 be-sdk-go 的 PGDSN
（url.UserPassword）相同，所以 @ : / % 空格都能用。
退出码：0 成功；3 没有这个键 / 值为空 / 引号不成对（多行值不支持）；2 用法错误。
"""
import re
import sys
import urllib.parse


def main():
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != '--check'):
        print('用法：dotenv-pgpass.py <.env> [--check]', file=sys.stderr)
        return 2
    rx = re.compile(r'(?:export\s+)?POSTGRES_PASSWORD=(.*)$')
    with open(sys.argv[1], encoding='utf-8', errors='replace') as f:
        m = next((x for x in (rx.match(ln.rstrip('\r\n')) for ln in f) if x), None)
    if m is None:
        return 3
    v = m.group(1).strip()
    if v[:1] in ('"', "'"):
        if len(v) < 2 or not v.endswith(v[0]):
            return 3
        v = v[1:-1]
    else:
        v = re.split(r'\s+#', v, maxsplit=1)[0].strip()
    if not v:
        return 3
    if len(sys.argv) == 2:
        sys.stdout.write(urllib.parse.quote(v, safe=''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
