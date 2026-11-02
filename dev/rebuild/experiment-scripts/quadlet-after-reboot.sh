#!/bin/bash
# FRR-025 retest: what came back after a real reboot with a cell as Podman Quadlet units, into <output directory>.
# Rootless (default) reads the user's systemd; ROOTFUL=1 reads the system's (journal readable through group adm or
# systemd-journal; the container list needs root and is left out). Then the cell's L3 scenarios (KEEP: no seed data
# written, so the cell stays as it was). Expected after `down`: no unit, nothing answering.
# Usage: quadlet-after-reboot.sh <cell> <output directory>
set -u
CELL=$1; OUT=$(realpath -m "$2"); R=/home/zhijie/Desktop/github/be-assembly-standard
D=$R/dev/rebuild/experiment-cells/$CELL; CONF=$R/tools/be-acceptance/conformance; mkdir -p "$OUT"
P=brickkit-$(echo "$CELL" | tr 'A-Z' 'a-z')
if [ "${ROOTFUL:-0}" = 1 ]; then SC=(systemctl); JC=(journalctl); else SC=(systemctl --user); JC=(journalctl --user); fi
{ echo "# $(date -Is) boot $(cat /proc/sys/kernel/random/boot_id), up $(cut -d' ' -f1 /proc/uptime) s, $CELL ($P)"
  echo "## units"; "${SC[@]}" list-units --all --no-legend "${P}_*"
  echo "## failed"; "${SC[@]}" list-units --failed --no-legend
  echo "## compose-path boot units (should not matter)"
  echo "podman-restart: $("${SC[@]}" is-enabled podman-restart.service 2>&1) / $("${SC[@]}" is-active podman-restart.service 2>&1)"
  [ "${ROOTFUL:-0}" = 1 ] || ls ~/.config/systemd/user/podman-restart.service.d 2>&1
} > "$OUT/1-units.txt" 2>&1
# the order this boot: network online, each migration and component started and done
{ journalctl -b -o short-precise -u NetworkManager-wait-online.service -u systemd-networkd-wait-online.service --no-pager | tail -3
  [ "${ROOTFUL:-0}" = 1 ] || "${JC[@]}" -b -o short-precise -u podman-user-wait-network-online.service --no-pager | tail -3
  [ "${ROOTFUL:-0}" = 1 ] && journalctl -b -o short-precise -u podman-docker-forward.service -u docker.service --no-pager | grep -E 'Started|Finished' | tail -4
  "${JC[@]}" -b -o short-precise --no-pager -u "${P}_*" | grep -E 'Starting|Started|Finished|Failed|Deactivated'
} > "$OUT/2-order.txt" 2>&1
"${JC[@]}" -b -o short-precise --no-pager -u "${P}_*" -p warning > "$OUT/3-warnings.txt" 2>&1
[ "${ROOTFUL:-0}" = 1 ] || podman ps -a --format '{{.Names}} {{.Status}} restarts={{.Restarts}}' > "$OUT/4-containers.txt" 2>&1
n=$("${SC[@]}" list-units --no-legend "${P}_*" | grep -vc migration)
if [ "$n" -gt 0 ]; then
  (cd "$CONF" && BE_ACC_CELL="$D" IAM_TEST_PASSWORD="$(grep '^IAM_TEST_PASSWORD=' "$R/.env" | cut -d= -f2- | tr -d "\"'")" \
     BE_ACC_IAM_TEST_PASSWORD="$(grep '^IAM_TEST_PASSWORD=' "$R/.env" | cut -d= -f2- | tr -d "\"'")" uv run pytest -q scenarios) \
    > "$OUT/5-scenarios.txt" 2>&1
  echo "scenarios exit=$?" >> "$OUT/5-scenarios.txt"
fi
echo "units running (not migrations): $n"; cat "$OUT/1-units.txt" | head -40; tail -2 "$OUT/5-scenarios.txt" 2>/dev/null
