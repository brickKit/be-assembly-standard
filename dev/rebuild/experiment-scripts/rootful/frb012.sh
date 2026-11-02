#!/bin/bash
# FRB-012 retest (BrickKit v1.12.1): `up` refuses a second copy of a Quadlet project deployed from the other systemd
# (DEPLOYED_ELSEWHERE). Run once, as root, by the maintainer:
#   sudo dev/rebuild/experiment-scripts/rootful/frb012.sh P9-S-root-q
# The deploying user's steps run as that user (runuser, with the user's systemd bus), so one sudo covers both sides:
# root up -> the user's up is refused, nothing installed on the user's side, the user's status and down warn and
# root's copy keeps running -> root down -> the user's up -> root's up is refused, with SUDO_USER and without it
# (as `sudo -i` would be; the project directory's owner names the user) -> the user's down. Then BrickKit's
# podman-docker-forward.service, root's images and the DOCKER-USER rules go again (as rootful/quadlet-revert.sh).
# Each step's output and exit code go to experiment-data/14-04-frb012/<step>.txt.
set -u
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
CELL=$1; R=/home/zhijie/Desktop/github/be-assembly-standard; D=$R/dev/rebuild/experiment-cells/$CELL
OUT=$R/dev/rebuild/experiment-data/14-04-frb012; BK=/home/zhijie/.local/bin/brickkit
U=$(stat -c %U "$D/cell.yaml"); UI=$(id -u "$U"); OWNER=$(stat -c %U:%G "$D/cell.yaml"); P=brickkit-$(echo "$CELL" | tr 'A-Z' 'a-z')
mkdir -p "$OUT"
asuser() {  # as the deploying user, reaching the user's systemd and Podman as a login would
  runuser -u "$U" -- env -i HOME="/home/$U" USER="$U" LOGNAME="$U" PATH="/home/$U/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="/run/user/$UI" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UI/bus" "$@"
}
step() {  # step <name> <command...>: output and exit code into <name>.txt; the cell back to its owner
  local name=$1; shift
  { echo "\$ $*"; "$@"; echo "exit=$?"; } > "$OUT/$name.txt" 2>&1
  chown -R "$OWNER" "$D" "$OUT"; echo "$name: $(tail -1 "$OUT/$name.txt")"
}
side() {  # what each side has installed
  echo "root units: $(systemctl list-units --all --no-legend "${P}_*" | wc -l), running: $(systemctl list-units --no-legend --state=running "${P}_*" | wc -l)"
  echo "root unit dir: $(ls /etc/containers/systemd/$P 2>/dev/null | wc -l) files; root secrets: $(podman secret ls --format '{{.Name}}' | grep -c "^${P}_")"
  asuser systemctl --user list-units --all --no-legend "${P}_*" | sed 's/^/user unit: /'
  echo "user units: $(asuser systemctl --user list-units --all --no-legend "${P}_*" | wc -l)"
  echo "user unit dir: $(ls /home/$U/.config/containers/systemd/$P 2>/dev/null | wc -l) files; user secrets: $(asuser podman secret ls --format '{{.Name}}' | grep -c "^${P}_")"
}

# root's side: BrickKit's forward unit and the images, as rootful/quadlet-up.sh does
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
systemctl daemon-reload; systemctl enable --now podman-docker-forward.service
for img in $(python3 -c 'import sys,yaml
[print(c["id"].replace("/","-")+":"+c["version"]) for c in yaml.safe_load(open(sys.argv[1]))["components"]]' "$D/brickkit.yaml"); do
  docker save "$img" | podman load -q >/dev/null && podman tag "docker.io/library/$img" "localhost/$img"
done
step 0-version "$BK" --version

# direction 1: root deployed, the user tries
step 1-root-up bash -c "cd '$D' && '$BK' up"
step 2-user-up asuser bash -c "cd '$D' && brickkit up"
step 2b-sides side
step 3-user-status asuser bash -c "cd '$D' && brickkit status"
step 3b-user-down asuser bash -c "cd '$D' && brickkit down"
step 3c-sides side
step 4-root-down bash -c "cd '$D' && '$BK' down"

# direction 2: the user deployed, root tries, with SUDO_USER and without it
step 5-user-up asuser bash -c "cd '$D' && brickkit up"
step 6-root-up-sudo-user bash -c "cd '$D' && '$BK' up"
step 6b-root-up-no-sudo-user env -u SUDO_USER bash -c "cd '$D' && '$BK' up"
step 6c-sides side
step 7-user-down asuser bash -c "cd '$D' && brickkit down"
step 7b-sides side

# root's side back as before (rootful/quadlet-revert.sh)
podman rmi -af >/dev/null 2>&1 || true
systemctl disable --now podman-docker-forward.service; rm -f /etc/systemd/system/podman-docker-forward.service; systemctl daemon-reload
for d in -i -o; do while iptables -C DOCKER-USER $d podman+ -j ACCEPT 2>/dev/null; do iptables -D DOCKER-USER $d podman+ -j ACCEPT; done; done
step 8-after side
chown -R "$OWNER" "$D" "$OUT"
echo "done: outputs in $OUT"
