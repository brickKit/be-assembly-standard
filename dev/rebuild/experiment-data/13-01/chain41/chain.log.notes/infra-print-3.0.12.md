infra/print on be-sdk-python 3.0.0a38 (be-protocol 3.0.0-alpha.36).

## What you must do

Nothing.

## Changed

- The SDK: requests that meet an unknown kid while its key refresh runs wait for it (P8.2): the first burst after a start without the issuer keys no longer answers DEPENDENCY_UNAVAILABLE
