#!/bin/bash
# FRR-024/025 retest (BrickKit v1.12.0): a rootful cell as Podman Quadlet units. Run as root by the maintainer while
# cell-chain.sh waits at its up-by-root stage:
#   sudo dev/rebuild/experiment-scripts/rootful/quadlet-up.sh P9-S-root-q
# (1) BrickKit's podman-docker-forward.service, as its troubleshooting page writes it (v1.11.4): Docker's DOCKER-USER
# chain lets Podman's bridges through, at every boot; (2) the cell's Docker-built images into root's Podman storage
# (the same images in every row); (3) `brickkit up` as root (it installs into /etc/containers/systemd), the cell's
# .env holding the ${VAR}s; then the cell's files go back to their owner; (4) BrickKit's environment check, as root:
# with the forward unit enabled, briefly with it disabled (FRR-024 expects a warning), and with --units quadlet.
# The install claim needs no second `up` since infra/authz 3.0.20 (a one-time code the secure stage presents, A130).
# Outputs go to experiment-data/14-03-quadlet/rootful-setup/. rootful/quadlet-revert.sh undoes all of it.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
CELL=$1; R=/home/zhijie/Desktop/github/be-assembly-standard; D=$R/dev/rebuild/experiment-cells/$CELL
OUT=$R/dev/rebuild/experiment-data/14-03-quadlet/rootful-setup; CHECK=/home/zhijie/Desktop/github/brickKit/scripts/podman/check-environment.sh
OWNER=$(stat -c %U:%G "$D/cell.yaml"); mkdir -p "$OUT"
grep -q '^units: *quadlet' "$D/cell.yaml" && grep -q '^podman: *rootful' "$D/cell.yaml" || { echo "$CELL is not a rootful Quadlet cell"; exit 1; }
up() {  # up <output file>: `brickkit up` as root, then the cell's files back to their owner
  local rc=0; (cd "$D" && /home/zhijie/.local/bin/brickkit up) 2>&1 | tee "$1" || rc=$?
  chown -R "$OWNER" "$D"
  [ "$rc" = 0 ] || { echo "brickkit up failed ($rc)"; exit "$rc"; }
}

cat > /etc/systemd/system/podman-docker-forward.service <<'UNIT'
[Unit]
Description=Let rootful Podman's bridges through Docker's DOCKER-USER chain
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
systemctl enable --now podman-docker-forward.service
{ echo "podman-docker-forward: $(systemctl is-enabled podman-docker-forward.service) $(systemctl is-active podman-docker-forward.service)"
  echo "podman-restart (system): $(systemctl is-enabled podman-restart.service 2>&1)"
  echo "podman.socket (system): $(systemctl is-enabled podman.socket 2>&1)"
  iptables -S DOCKER-USER; } | tee "$OUT/1-forward-unit.txt"

for img in $(python3 -c 'import sys,yaml
[print(c["id"].replace("/","-")+":"+c["version"]) for c in yaml.safe_load(open(sys.argv[1]))["components"]]' "$D/brickkit.yaml"); do
  # Podman resolves the short name to localhost/ first: the Docker-built image takes that name too
  docker save "$img" | podman load -q && podman tag "docker.io/library/$img" "localhost/$img"
done
podman images --format '{{.Repository}}:{{.Tag}}' | sort | tee "$OUT/2-images.txt"

up "$OUT/3-up.txt"
{ systemctl list-units 'brickkit-*' --all --no-legend; podman ps --format '{{.Names}} {{.Status}}'; } | tee "$OUT/4-units.txt"

bash "$CHECK" > "$OUT/5-check-env.txt" 2>&1 || true
systemctl disable podman-docker-forward.service
bash "$CHECK" > "$OUT/6-check-env-forward-disabled.txt" 2>&1 || true
systemctl enable podman-docker-forward.service
bash "$CHECK" --units quadlet > "$OUT/7-check-env-quadlet.txt" 2>&1 || true
chown -R "$OWNER" "$OUT"
echo "done: outputs in $OUT"
