#!/usr/bin/env bash
# 删掉 up.sh 起的全部容器（-v 连匿名卷一起删）和网络。
docker rm -f -v r1-k2-casdoor r1-k2-pg r1-k2-spa >/dev/null 2>&1 || true
docker network rm r1-k2-net >/dev/null 2>&1 || true
echo down
