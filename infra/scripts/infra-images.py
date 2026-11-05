#!/usr/bin/env python3
"""基础资源镜像检查：compose 里每个服务的镜像都写确切版本与摘要，infra/resources.tsv 与 compose 一致。

确切版本：带 @sha256 摘要（镜像因此不可变），标签写发布的版本号、不是 latest（标签只给人读，摘要才是固定）。
在这里构建的服务（`build:`，例如带 pgBackRest 的 be-postgres）没有仓库的摘要：它的标签写版本、不是 latest，
Dockerfile 的每个 FROM 带摘要，apk 装的每个包写 `名字=版本`。
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
BUILD = re.compile(r"^    build:\s*(\S+)")
TAGGED = re.compile(r"^[^@\s]+:(?!latest$)[^@\s:]+$")
FROM = re.compile(r"^FROM\s+(\S+)", re.M)
APK = re.compile(r"apk add[^\n&]*", re.M)
# a release tag (not latest) and the digest that fixes the image
EXACT = re.compile(r"^[^@\s]+:(?!latest@)[^@\s:]+@sha256:[0-9a-f]{64}$")


def compose_images(path: pathlib.Path, builds: dict[str, str] | None = None) -> dict[str, str]:
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
        elif in_services and service and builds is not None and (m := BUILD.match(line)):
            builds[service] = m.group(1)
    return images


def built(compose: pathlib.Path, context: str, image: str) -> list[str]:
    """The rules for an image built here: a version tag, every base by its digest, every package by its version."""
    errors = []
    if not TAGGED.match(image):
        errors.append(f"{image}: a built image is tagged with its versions, not latest")
    dockerfile = compose.parent / context / "Dockerfile"
    text = dockerfile.read_text(encoding="utf-8")
    for base in FROM.findall(text):
        if not EXACT.match(base):
            errors.append(f"{dockerfile.relative_to(ROOT)}: FROM {base} has no digest")
    for cmd in APK.findall(text):
        for pkg in cmd.split()[2:]:
            if not pkg.startswith("-") and pkg != "\\" and "=" not in pkg:
                errors.append(f"{dockerfile.relative_to(ROOT)}: apk package {pkg} has no version")
    return errors


def main() -> int:
    errors: list[str] = []
    rows = [line.split("\t") for line in TSV.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("#")]
    composed: dict[tuple[str, str], str] = {}
    for f in sorted({r[2] for r in rows}):
        builds: dict[str, str] = {}
        for service, image in compose_images(ROOT / f, builds).items():
            composed[(f, service)] = image
            if service in builds:
                errors += [f"{f} {service}: {e}" for e in built(ROOT / f, builds[service], image)]
            elif not EXACT.match(image):
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
