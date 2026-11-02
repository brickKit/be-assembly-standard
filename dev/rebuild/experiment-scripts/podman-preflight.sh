#!/bin/bash
# Rootless Podman must work where a deployment runs it (the user's systemd at boot, ssh), not only in this terminal:
# a terminal inside a snap (VS Code) may allow user namespaces that the machine's AppArmor policy denies everywhere
# else. Every P and LP cell ran from such a terminal, and the gap showed only at a real reboot (step 14, 14-01-reboot).
# PODMAN_PREFLIGHT_WRAP prefixes the podman command, so a test can run it under a restricted AppArmor profile.
# Usage: podman-preflight.sh   (exit 0: podman runs under a profile that allows its user namespace)
set -u
out=$(systemd-run --user --wait --pipe --quiet ${PODMAN_PREFLIGHT_WRAP:-} podman unshare cat /proc/self/attr/current 2>&1)
rc=$?
label=$(printf '%s\n' "$out" | tail -1)
echo "podman under the user's systemd: exit=$rc, last line: $label"
if [ $rc -ne 0 ] || [ "$label" = unconfined ] || [[ "$label" == *unprivileged_userns* ]]; then
  echo "FAIL: podman cannot create its user namespace outside this terminal. Restore the profile the apparmor package"
  echo "ships: sudo apt-get install --reinstall -o Dpkg::Options::=--force-confmiss -o Dpkg::Options::=--force-confold apparmor"
  echo "       sudo apparmor_parser -r /etc/apparmor.d/podman"
  exit 1
fi
