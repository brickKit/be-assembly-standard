chore: be-sdk-go 3.0.0-alpha.40; depends on mdm/org 3.0.12, mdm/currency 3.0.13, mdm/partner 3.0.15, mdm/product 3.0.15, erp/inventory 3.0.12, erp/credit 3.0.11; 3.0.18

the system-surface server ends each connection after 30 s, so callers reach every replica of a dependency over time (P4.30); an ordered subscription has one message in flight across all its instances (P6.31).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
