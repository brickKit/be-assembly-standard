<!-- brickkit:components lang=en -->
<!-- maintained by brickkit (init, add, remove, upgrade, skills update) from brickkit.yaml and each component's component.yaml: the whole file is rewritten -->
# Components

Every component this project uses, at the version `brickkit.yaml` pins. Where each one's documentation and contracts are: the end of `AGENTS.md`.

| Component | Version | What it does | Docs | Home |
|---|---|---|---|---|
| test/probe-go | 3.2.21 | The acceptance suite's Go probe: communication only (echo, CPU work, a write with its event, relay), for measuring paths | BRICKKIT.md | https://github.com/brickKit/be-acceptance |
| test/probe-go2 | 3.2.21 | A variant of test/probe-go: the same code under its own component ID, ports and event stream | BRICKKIT.md | https://github.com/brickKit/be-acceptance |
| test/probe-py | 3.2.19 | The acceptance suite's Python probe: the same contract as the Go probe, for measuring paths | BRICKKIT.md | https://github.com/brickKit/be-acceptance |
| test/probe-py2 | 3.2.19 | A variant of test/probe-py: the same code under its own component ID, ports and event stream | BRICKKIT.md | https://github.com/brickKit/be-acceptance |
