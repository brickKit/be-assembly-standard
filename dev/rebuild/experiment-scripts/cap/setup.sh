#!/bin/bash
# Step 10, B3 and B4 (step10-plan.md 4.1): puts every Docker container (the cells and the base resources) under one
# systemd slice, be-cap.slice, whose memory limit the runner sets per cell. Run once, as root, by the maintainer:
#   sudo dev/rebuild/experiment-scripts/cap/setup.sh <user>
# It (1) adds "cgroup-parent": "be-cap.slice" to /etc/docker/daemon.json (a copy of the old file is kept beside it),
# (2) installs the slice unit with memory accounting and no limit, (3) lets <user> run exactly the three commands of
# cap/limit.sh without a password (/etc/sudoers.d/be-cap, checked with visudo), (4) restarts Docker, so the base
# resources restart under the slice (restart policy unless-stopped). cap/revert.sh undoes all four.
set -eu
U=${1:?usage: setup.sh <user>}
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
D=/etc/docker/daemon.json
[ -f "$D.be-cap-backup" ] || cp "$D" "$D.be-cap-backup"
python3 - "$D" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["cgroup-parent"] = "be-cap.slice"
open(p, "w").write(json.dumps(d, indent=2) + "\n")
EOF
cat > /etc/systemd/system/be-cap.slice <<'EOF'
[Unit]
Description=be-assembly-standard experiment: every Docker container, under one memory limit (step 10, B3 and B4)

[Slice]
MemoryAccounting=yes
EOF
S=/usr/bin/systemctl
cat > /tmp/be-cap.sudoers <<EOF
# be-assembly-standard experiment, step 10 B3 and B4: the runner sets the containers' common memory limit
$U ALL=(root) NOPASSWD: $S set-property --runtime be-cap.slice MemoryMax=3300M MemorySwapMax=1G
$U ALL=(root) NOPASSWD: $S set-property --runtime be-cap.slice MemoryMax=5300M MemorySwapMax=1G
$U ALL=(root) NOPASSWD: $S set-property --runtime be-cap.slice MemoryMax=infinity MemorySwapMax=infinity
EOF
visudo -cf /tmp/be-cap.sudoers
install -m 0440 /tmp/be-cap.sudoers /etc/sudoers.d/be-cap
rm /tmp/be-cap.sudoers
systemctl daemon-reload
systemctl restart docker
for i in $(seq 60); do docker inspect be-postgres --format '{{.State.Running}}' 2>/dev/null | grep -q true && break; sleep 2; done
echo "daemon.json:"; cat "$D"
echo "be-postgres cgroup: $(cat /proc/$(docker inspect be-postgres --format '{{.State.Pid}}')/cgroup)"
echo "slice: $(systemctl show be-cap.slice -p MemoryMax -p MemorySwapMax | tr '\n' ' ')"
