#!/bin/bash
# Step 10, B6 (step10-plan.md 4.2): rootful Podman beside the rootless one, without stopping Docker. Run once, as
# root, by the maintainer:   sudo dev/rebuild/experiment-scripts/rootful/setup.sh
# (1) root's podman.socket, group docker (whose members are root-equivalent already, through Docker's own socket), so
# the runner reaches rootful Podman as the user with CONTAINER_HOST=unix:///run/podman/podman.sock; (2) two rules in
# Docker's DOCKER-USER chain that let Podman's bridges (podman+) through FORWARD: Docker sets FORWARD's policy to DROP,
# which silently cut rootful Podman's container-to-container and published-port traffic (step 0, record 0-11).
# The base resources stay in Docker, as for every other row. rootful/revert.sh undoes both.
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
mkdir -p /etc/systemd/system/podman.socket.d
cat > /etc/systemd/system/podman.socket.d/be-rootful.conf <<'EOF'
# be-assembly-standard experiment, step 10 B6: the user reaches rootful Podman (group docker)
[Socket]
SocketGroup=docker
SocketMode=0660
DirectoryMode=0755
EOF
systemctl daemon-reload
systemctl enable --now podman.socket
for d in -i -o; do
  iptables -C DOCKER-USER $d podman+ -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER $d podman+ -j ACCEPT
done
echo "socket: $(ls -l /run/podman/podman.sock)"
echo "DOCKER-USER:"; iptables -S DOCKER-USER
