#!/bin/bash
# Undoes rootful/setup-boot.sh (run rootful/revert.sh too to undo setup.sh). As root.
set -u
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
systemctl disable podman-restart.service
systemctl disable --now be-podman-docker-forward.service
rm -f /etc/systemd/system/be-podman-docker-forward.service
systemctl daemon-reload
echo "podman-restart (system): $(systemctl is-enabled podman-restart.service 2>&1)"
