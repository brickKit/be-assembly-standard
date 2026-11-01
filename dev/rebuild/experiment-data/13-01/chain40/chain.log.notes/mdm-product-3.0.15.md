mdm/product on be-sdk-go 3.0.0-alpha.40 (be-protocol 3.0.0-alpha.35).

## What you must do

Upgrade mdm/org with it: this version names their exact versions.

## Changed

- The SDK: the system-surface server ends each connection after 30 s, so callers reach every replica of a dependency over time (P4.30); an ordered subscription has one message in flight across all its instances (P6.31).
- Depends on mdm/org 3.0.12.
