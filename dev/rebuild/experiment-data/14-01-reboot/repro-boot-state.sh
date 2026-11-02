#!/bin/bash
# The state at boot: no container running, no pause process; podman started by the user's systemd (unconfined).
O=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-data/14-01-reboot/${OUT:-repro-boot-state.txt}
podman stop -a -t 5 >/dev/null 2>&1
for p in $(pgrep -u zhijie -x catatonit); do kill "$p"; done; sleep 1
echo "running containers: $(podman ps -q 2>/dev/null | wc -l) (this podman call is from the snap-confined shell)" > $O
for p in $(pgrep -u zhijie -x catatonit); do kill "$p"; done; sleep 1
echo "pause processes: $(pgrep -u zhijie -x catatonit | wc -l); conmon: $(pgrep -u zhijie -x conmon | wc -l)" >> $O
K0=$(journalctl -k --no-pager -o cat | wc -l)
out=$(systemd-run --user --wait --pipe --quiet podman info --format '{{.Host.Security.Rootless}}' 2>&1); rc=$?
{ echo "systemd-run --user podman info: exit=$rc"; echo "$out" | tail -2; echo "kernel lines since:"; journalctl -k --no-pager -o short-precise | tail -n +$((K0+1)) | grep -iE "userns|apparmor" | cut -c1-250; } >> $O
cat $O
