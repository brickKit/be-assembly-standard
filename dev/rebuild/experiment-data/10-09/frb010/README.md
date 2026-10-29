# FRB-010: a local component's shell-member dependencies are published twice (CLI v1.10.1)

Smoke of the new LD and LP cells (night10g.sh), 2026-10-29 19:21-19:33, short parameters: every cell failed at the
first seed. `smoke-status.log` (the runner), per cell `bring-up-status.log` and `forward-error.txt` (the measurement
forwarder could not bind 127.0.0.1:18086), `LD9-H/seed-error.txt` (inventory's seed answered 404 by another service),
`LD9-H/go-infra-ports.txt` (be/go-infra publishes each member twice: its exposePort and a port scanned from 18080),
`LD9-H/local-shell-endpoints.txt` (the local shell is given the scanned ports, e.g. currency on 18086, not 18226).

Retest on CLI v1.10.2 (2026-10-29 19:46-20:38, same short parameters): `retest-status.log`, every cell through bring-up,
seeds, baseline, scenarios and the mix, digests equal; `LD9-H/*-v1.10.2.txt`: each member published once, the local shell
given the members' own exposePorts.
