[English](README.md) · [中文](README.zh.md)

# be/go-core

Runs the MDM and core ERP Go components in one process to save memory and CPU.

## Use it in a project

This shell is code of the project that contains it. With at least one member in `shell.members`:

```bash
brickkit add be/go-core --yes     # brings in the members it compiles in, nested under the shell
brickkit build be/go-core
brickkit up
```

Prepare first: see "Before you deploy" in [BRICKKIT.md](BRICKKIT.md).

## Documentation

| To find out | Read |
|---|---|
| What it hosts, what it does not do, how to configure and deploy it | [BRICKKIT.md](BRICKKIT.md) |
| Its members, configuration keys and port | [component.yaml](component.yaml) |
| How to change it | [AGENTS.md](AGENTS.md) |

## Development

Work on it from the project root, where `brickkit.yaml` is; read [AGENTS.md](AGENTS.md) first.
