#!/bin/bash
# Undoes cap/setup.sh, as root: /etc/docker/daemon.json back to the copy setup.sh kept, the slice unit and the sudoers
# file removed, Docker restarted so the base resources run under system.slice again, the empty slice stopped.
#   sudo dev/rebuild/experiment-scripts/cap/revert.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
D=/etc/docker/daemon.json
[ -f "$D.be-cap-backup" ] && mv "$D.be-cap-backup" "$D"
rm -f /etc/systemd/system/be-cap.slice /etc/sudoers.d/be-cap
systemctl daemon-reload
systemctl restart docker
# the containers have left it: stop the empty slice and its parent (a dash in a slice name is a level)
systemctl stop be-cap.slice be.slice 2>/dev/null || true
for i in $(seq 60); do docker inspect be-postgres --format '{{.State.Running}}' 2>/dev/null | grep -q true && break; sleep 2; done
echo "daemon.json:"; cat "$D"
echo "be-postgres cgroup: $(cat /proc/$(docker inspect be-postgres --format '{{.State.Pid}}')/cgroup)"
