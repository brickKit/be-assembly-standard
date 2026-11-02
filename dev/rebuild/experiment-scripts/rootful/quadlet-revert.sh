#!/bin/bash
# Undoes rootful/quadlet-up.sh, as root: `brickkit down` in the cell (it removes the units, containers, network and
# Podman secrets; nothing then comes back at boot), the cell's images from root's storage, BrickKit's
# podman-docker-forward.service and the two DOCKER-USER rules it put back.
#   sudo dev/rebuild/experiment-scripts/rootful/quadlet-revert.sh P9-S-root-q
# KEEP_FORWARD=1 leaves the forward unit and its rules in place (the reboot after `down` then checks only that no unit
# comes back).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
CELL=$1; R=/home/zhijie/Desktop/github/be-assembly-standard; D=$R/dev/rebuild/experiment-cells/$CELL
OWNER=$(stat -c %U:%G "$D/cell.yaml")
rc=0; (cd "$D" && /home/zhijie/.local/bin/brickkit down) || rc=$?
chown -R "$OWNER" "$D"
[ "$rc" = 0 ] || { echo "brickkit down failed ($rc)"; exit "$rc"; }
podman rmi -af >/dev/null 2>&1 || true
if [ "${KEEP_FORWARD:-0}" != 1 ]; then
  systemctl disable --now podman-docker-forward.service
  rm -f /etc/systemd/system/podman-docker-forward.service
  systemctl daemon-reload
  for d in -i -o; do
    while iptables -C DOCKER-USER $d podman+ -j ACCEPT 2>/dev/null; do iptables -D DOCKER-USER $d podman+ -j ACCEPT; done
  done
fi
echo "units brickkit-*: $(systemctl list-units 'brickkit-*' --all --no-legend | wc -l)"
echo "/etc/containers/systemd: $(ls /etc/containers/systemd 2>&1)"
echo "rootful containers: $(podman ps -aq | wc -l), images: $(podman images -q | wc -l), secrets: $(podman secret ls -q | wc -l)"
echo "podman-docker-forward: $(systemctl is-enabled podman-docker-forward.service 2>&1)"
echo "DOCKER-USER:"; iptables -S DOCKER-USER
