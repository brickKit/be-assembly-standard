#!/bin/bash
# Sets the memory limit of be-cap.slice (cap/setup.sh), where every Docker container runs. The budget is the whole
# stack's; Docker's own processes (dockerd, containerd, the shims and docker-proxy, about 0.7 GiB in step 10's cells)
# run outside the slice, so the slice gets the budget less 0.7 GiB; swap up to 1 GiB, as a small server would have.
# Only these three commands may run without a password (/etc/sudoers.d/be-cap).
# Usage: limit.sh <4G|6G|none>
set -eu
S=/usr/bin/systemctl
case ${1:?usage: limit.sh <4G|6G|none>} in
  4G) sudo -n $S set-property --runtime be-cap.slice MemoryMax=3300M MemorySwapMax=1G ;;
  6G) sudo -n $S set-property --runtime be-cap.slice MemoryMax=5300M MemorySwapMax=1G ;;
  none) sudo -n $S set-property --runtime be-cap.slice MemoryMax=infinity MemorySwapMax=infinity ;;
  *) echo "unknown cap $1"; exit 1 ;;
esac
echo "be-cap.slice memory.max=$(cat /sys/fs/cgroup/be-cap.slice/memory.max) swap.max=$(cat /sys/fs/cgroup/be-cap.slice/memory.swap.max)"
