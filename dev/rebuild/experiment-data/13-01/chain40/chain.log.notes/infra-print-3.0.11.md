infra/print on be-sdk-python 3.0.0a37 (be-protocol 3.0.0-alpha.35).

## What you must do

Nothing.

## Changed

- The SDK: the system-surface server ends each connection after 30 s, so callers reach every replica of a dependency over time (P4.30); an ordered subscription has one message in flight across all its instances (P6.31).
