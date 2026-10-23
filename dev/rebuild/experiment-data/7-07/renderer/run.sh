#!/usr/bin/env bash
# Paired, alternating rounds of the two renderers in performance mode; the original power mode comes back at the end.
set -u
B=$(cd "$(dirname "$0")" && pwd)
export FONTCONFIG_FILE=$B/fonts.conf
orig=$(powerprofilesctl get)
trap 'powerprofilesctl set "$orig"; echo "power mode restored: $orig"' EXIT
powerprofilesctl set performance
echo "power mode: $(powerprofilesctl get) (was $orig)"
for round in 1 2 3; do
  for e in typst weasyprint; do
    n=200; [ "$e" = weasyprint ] && n=40
    "$B/.venv/bin/python" "$B/worker.py" "$e" "$n" "$B/out-$e-$round.pdf" | sed "s/^/round $round /"
    [ "$(powerprofilesctl get)" = performance ] || echo "PROBLEM: power mode changed to $(powerprofilesctl get)"
  done
done
for e in typst weasyprint; do
  if cmp -s "$B/out-$e-1.pdf" "$B/out-$e-2.pdf" && cmp -s "$B/out-$e-2.pdf" "$B/out-$e-3.pdf"; then
    echo "$e: identical bytes across processes"
  else
    echo "$e: DIFFERENT bytes across processes"
  fi
done
echo DONE
