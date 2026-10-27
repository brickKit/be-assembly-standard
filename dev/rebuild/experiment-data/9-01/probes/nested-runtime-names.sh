#!/bin/bash
# Container runtime processes on this host by name, split by where their cgroup is: the host's own, or inside a
# container (a minikube node, kind, Docker-in-Docker run the same names). A sampler that matches names counts the
# inner ones twice when it also reads the container. Usage: nested-runtime-names.sh
for n in dockerd containerd containerd-shim-runc-v2 docker-proxy cri-dockerd kubelet; do
  for p in $(pgrep -x "${n:0:15}"); do
    cg=$(cut -d: -f3 /proc/$p/cgroup 2>/dev/null)
    if echo "$cg" | grep -qE '/(docker|libpod)-[0-9a-f]{64}\.scope(/|$)|/kubepods'; then w=container; else w=host; fi
    awk -v n=$n -v w=$w '/^VmRSS:/{r=$2} /^RssAnon:/{a=$2} END{print w, n, r, a}' /proc/$p/status
  done
done | awk '{k=$1" "$2; c[k]++; r[k]+=$3; a[k]+=$4} END{for(k in c) printf "%-10s %-24s n=%-3d rss=%5d MiB anon=%5d MiB\n", substr(k,1,index(k," ")-1), substr(k,index(k," ")+1), c[k], r[k]/1024, a[k]/1024}' | sort
