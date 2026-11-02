#!/bin/bash
# Step 14 follow-up (FRR-023, D80 rootful or rootless): rootful Podman coming back at boot, beside Docker. Run once, as
# root, by the maintainer, after rootful/setup.sh:   sudo dev/rebuild/experiment-scripts/rootful/setup-boot.sh
# (1) a oneshot unit that puts setup.sh's two DOCKER-USER rules back after Docker starts: Docker builds its chains
# afresh at boot and sets FORWARD's policy to DROP, so without them rootful Podman's containers can't reach each other
# (record 0-11); (2) the system unit podman-restart.service enabled: at boot it starts the containers whose restart
# policy is `always`. rootful/revert-boot.sh undoes both.
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
cat > /etc/systemd/system/be-podman-docker-forward.service <<'UNIT'
# be-assembly-standard experiment: let rootful Podman's bridges (podman+) through Docker's FORWARD policy
[Unit]
Description=Let rootful Podman bridges through DOCKER-USER
After=docker.service
Before=podman-restart.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for d in -i -o; do iptables -C DOCKER-USER $d podman+ -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER $d podman+ -j ACCEPT; done'

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now be-podman-docker-forward.service
systemctl enable podman-restart.service
echo "be-podman-docker-forward: $(systemctl is-enabled be-podman-docker-forward.service) $(systemctl is-active be-podman-docker-forward.service)"
echo "podman-restart (system): $(systemctl is-enabled podman-restart.service)"
iptables -S DOCKER-USER
