#!/usr/bin/env python3
"""基础资源镜像检查：compose 里每个服务的镜像都写确切版本与摘要，infra/resources.tsv 与 compose 一致。

确切版本：带 @sha256 摘要（镜像因此不可变），标签写发布的版本号、不是 latest（标签只给人读，摘要才是固定）。
一致：resources.tsv 每一行的镜像与它指向的 compose 文件、服务里写的完全相同（make check-all 拿它与运行中的
容器比较）；compose 里的每个服务都在表里有一行。
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TSV = ROOT / "infra" / "resources.tsv"
SERVICE = re.compile(r"^  ([a-z0-9-]+):\s*$")
IMAGE = re.compile(r"^    image:\s*(\S+)")
# a release tag (not latest) and the digest that fixes the image
EXACT = re.compile(r"^[^@\s]+:(?!latest@)[^@\s:]+@sha256:[0-9a-f]{64}$")


def compose_images(path: pathlib.Path) -> dict[str, str]:
    images, service, in_services = {}, None, False
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            in_services = line.startswith("services:")
            service = None
            continue
        if in_services and (m := SERVICE.match(line)):
            service = m.group(1)
        elif in_services and service and (m := IMAGE.match(line)):
            images[service] = m.group(1)
    return images


def main() -> int:
    errors: list[str] = []
    rows = [line.split("\t") for line in TSV.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("#")]
    composed: dict[tuple[str, str], str] = {}
    for f in sorted({r[2] for r in rows}):
        for service, image in compose_images(ROOT / f).items():
            composed[(f, service)] = image
            if not EXACT.match(image):
                errors.append(f"{f} {service}: {image} has no digest or is tagged latest")
    listed = set()
    for r in rows:
        key = (r[2], r[3])
        listed.add(key)
        if key not in composed:
            errors.append(f"resources.tsv {r[0]}: no service {r[3]} in {r[2]}")
        elif composed[key] != r[5]:
            errors.append(f"resources.tsv {r[0]}: {r[5]} differs from {composed[key]} in {r[2]}")
    for key in sorted(set(composed) - listed):
        errors.append(f"{key[0]} {key[1]}: no row in resources.tsv")
    for e in errors:
        print(f"✗ {e}")
    print(f"{len(composed)} images, {len(rows)} rows, {len(errors)} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
