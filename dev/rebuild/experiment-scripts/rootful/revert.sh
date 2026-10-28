#!/bin/bash
# Undoes rootful/setup.sh, as root: removes what the experiment left in rootful Podman (containers, images, networks),
# stops and disables root's podman.socket and drops its override, deletes the two DOCKER-USER rules.
#   sudo dev/rebuild/experiment-scripts/rootful/revert.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
podman rm -af >/dev/null 2>&1 || true
podman network prune -f >/dev/null 2>&1 || true
podman rmi -af >/dev/null 2>&1 || true
systemctl disable --now podman.socket
chmod 0700 /run/podman 2>/dev/null || true
rm -f /etc/systemd/system/podman.socket.d/be-rootful.conf
rmdir /etc/systemd/system/podman.socket.d 2>/dev/null || true
systemctl daemon-reload
for d in -i -o; do
  while iptables -C DOCKER-USER $d podman+ -j ACCEPT 2>/dev/null; do iptables -D DOCKER-USER $d podman+ -j ACCEPT; done
done
echo "podman.socket: $(systemctl is-active podman.socket) / $(systemctl is-enabled podman.socket 2>&1)"
echo "rootful containers: $(podman ps -aq | wc -l), images: $(podman images -q | wc -l)"
echo "DOCKER-USER:"; iptables -S DOCKER-USER
