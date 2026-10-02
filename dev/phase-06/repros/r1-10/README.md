# r1-10：Python 3.14（及 3.13）的二进制 wheel 是否齐全

对应 sdk-redesign §7.9 第 10 条；决定 §5.3 表里 Python 的运行时版本（今天写的是"CPython 3.13，3.14 要实测 asyncpg 和 grpcio 的 wheel 再切"）。

## 假设

1. asyncpg、grpcio、pyarrow 在 CPython 3.14 上有 Linux 二进制 wheel（glibc 和 musl、x86_64 和 arm64），不需要在镜像里装编译器。
2. be-sdk-python v0.5.0 `pyproject.toml` 现有的精确版本，以及 3.0.0 设计新增的依赖（pyarrow、yoyo-migrations、aioboto3、pypinyin、hypothesis、uuid6），再加上唯一的 Python 组件 infra/print 的依赖，在 3.14 上都能装上并且能用。

## 环境与版本

| 项 | 版本 |
|---|---|
| 解释器 | `python:3.14-slim`（CPython 3.14.8，glibc）、`python:3.14-alpine`（3.14.8，musl）、`python:3.13-slim`（3.13.16），都是一次性容器；本机 Python 没动 |
| pip | 镜像自带 |
| 冒烟用的 PG | `postgres:16-alpine` 一次性容器 `r1-r1b-pg` |
| 查询日期 | 2026-10-02（PyPI 当天的状态） |

镜像里**没有 C 编译器**，所以"装得上"就等于"有 wheel，或者是纯 Python 的 sdist"。

## 步骤

```bash
docker run -d --name r1-r1b-pg -e POSTGRES_PASSWORD=pw -p 127.0.0.1::5432 postgres:16-alpine
./run.sh > output.txt      # 3 个镜像 × {pinned, latest}，再加一张跨平台矩阵
docker rm -f r1-r1b-pg
```

`check.py native pinned|latest`：逐条解析依赖（含传递依赖），优先 wheel；带进来的 sdist 用 `pip wheel` 现场构建，能构建就说明是纯 Python。然后装上整套依赖（钉死的版本装不上时换成最新版），跑 `smoke.py`：asyncpg 真连 PG 做一次 `numeric` 运算，grpc.aio 起服务端并往返一次，pyarrow 写读一次 Parquet（含 `decimal128(19,4)`），PyJWT + cryptography 做一次 RS256 签发和校验，其余包 import。

`check.py matrix`：只看编译型的包，`pip download --only-binary=:all: --platform … --python-version …`，查 cp313 / cp314 × glibc / musl × x86_64 / arm64 有没有 wheel。

## 原始输出（关键几行）

完整输出见 `output.txt`。

```
===== native CPython 3.14.8 (x86_64, glibc), mode=pinned
  [FAIL] asyncpg==0.30.0                                sdist asyncpg-0.30.0.tar.gz NEEDS A COMPILER
  [OK] nats-py==2.11.0                                  sdist nats_py-2.11.0.tar.gz builds without a compiler (pure Python)
  [OK] grpcio==1.76.0                                   grpcio-1.76.0[cp314]
  [OK] pyarrow                                          pyarrow-25.0.1[cp314]
  [FAIL] psycopg2-binary==2.9.10                        Failed to build 'psycopg2-binary' when getting requirements to build wheel
  smoke: asyncpg 0.31.0: 2.2345
         grpcio 1.76.0: aio round trip b'ping'
         pyarrow 25.0.1: parquet 743 bytes, rows=2
         PyJWT+cryptography: RS256 ok=True; uvloop 0.23.0; pydantic-core 2.46.5
         import weasyprint: OSError: cannot load library 'libgobject-2.0-0' ...
         stdlib uuid.uuid7: True
===== native CPython 3.13.16 (x86_64, glibc), mode=pinned     -> 全部 OK（asyncpg 0.30.0、psycopg2-binary 2.9.10 都有 cp313 wheel）
===== native CPython 3.14.8 (x86_64, musl), mode=pinned      -> 与 3.14 glibc 相同：只有 asyncpg 0.30.0、psycopg2-binary 2.9.10 失败
===== native … mode=latest（三个镜像）                       -> 全部 OK

===== wheel matrix
  distribution             3.13/glibc-x86_64 3.13/glibc-arm64 3.13/musl-x86_64 3.13/musl-arm64 3.14/glibc-x86_64 3.14/glibc-arm64 3.14/musl-x86_64 3.14/musl-arm64
  asyncpg==0.30.0          0.30.0            0.30.0           0.30.0           0.30.0          -                 -                -                -
  asyncpg (latest)         0.31.0            0.31.0           0.31.0           0.31.0          0.31.0            0.31.0           0.31.0           0.31.0
  grpcio==1.76.0           1.76.0            1.76.0           1.76.0           1.76.0          1.76.0            1.76.0           1.76.0           1.76.0
  pyarrow (latest)         25.0.1            …（8 列都有）
  psycopg2-binary==2.9.10  2.9.10            2.9.10           2.9.10           2.9.10          -                 -                -                -
  psycopg2-binary (latest) 2.9.13            …（8 列都有）
  其余编译型依赖（uvloop、httptools、watchfiles、websockets、pydantic-core、cryptography、cffi、PyYAML、
  psycopg-binary、aiohttp 一族、protobuf、pillow、brotli、markupsafe）：8 列都有 wheel
```

## 结论

**假设 1 成立；假设 2 部分成立。**

- asyncpg、grpcio、pyarrow 在 3.14 上 8 个平台组合都有 wheel，冒烟全过（含 musl）。但 asyncpg 要 **0.31.0**：今天钉的 0.30.0 没有 cp314 wheel，在不带编译器的镜像里装不上。
- 今天钉的其余版本在 3.14 上都能用，包括 grpcio 1.76.0、uvicorn[standard] 0.38.0（uvloop 0.23、httptools 0.8）、fastapi 0.118.0（pydantic-core 2.46.5）。
- infra/print 的 `psycopg2-binary==2.9.10` 同样没有 cp314 wheel，要 2.9.13。
- nats-py 2.11.0 在 PyPI 上只有 sdist，但它是纯 Python，没有编译器也能装（最新版有 `none-any` wheel）。
- 3.14 的标准库有 `uuid.uuid7`（3.13 没有），apis §3 的 "uuid6（3.14 起用标准库）" 可以直接落地，少一个依赖。
- weasyprint 的 import 失败与 Python 版本无关：缺 pango/gobject 系统库，infra/print 的 Dockerfile 本来就要装（3.13 上同样失败）。

## 对设计的影响

1. **§5.3 的 Python 运行时改为 CPython 3.14**（基础镜像 `python:3.14-slim`），3.13 不再作为目标：wheel 齐全的前提已经满足，还能省掉 uuid6。
2. **be-sdk-python v0.6.0 的精确版本至少要改两处**：`asyncpg==0.31.0`（否则 3.14 上装不上）；infra/print 3.0.0 的 `psycopg2-binary==2.9.13`（如果它的迁移仍由 yoyo 驱动；按 apis §3 迁移入口收进 SDK，SDK 也要选一个 yoyo 的同步驱动，建议 `psycopg[binary]==3.3.6`，8 列都有 wheel，是 psycopg2 的后继，yoyo 9.0.0 用 `postgresql+psycopg://` 后端接它，已核对该后端存在）。其余现有钉的版本可以不动，但发 v0.6.0 时顺手升到当天最新（grpcio 1.84.0 等）也全部可用。
3. **pyarrow 只放在 `besdk[cold]` 里**（apis §3 已经这样写）。25.0.1 的 wheel 单个就几十 MB，不该进每个 Python 镜像。
4. 镜像不需要编译器。门禁可以加一条：Python 组件的 Dockerfile 里出现 `gcc` / `build-essential` 就提醒，说明有依赖退回了 sdist。
