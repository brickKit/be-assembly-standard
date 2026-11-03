# The browser path end to end (2026-11-03)

Foundations item 2, T6 step 4: `experiment-scripts/t6loginflow.py`, every part real: Casdoor 4.1.0 (`be-casdoor`),
infra/iam-casdoor 3.0.16 run as a process the way a deployment runs it (migrate, then serve; be-sdk-go alpha.56),
Traefik v3.0.4 with the be-edge plugin (v3.0.0-alpha.1 source), test/probe-go 3.2.33 with its guard on and trusting
iam-casdoor's keys, the features document from `be-ops features`. The suite's test deployment (be-sdk-python a45's
`besdk.testing`) issues the service certificates (iam-casdoor's system surface, the edge's `infra/edge`, the probe)
and the authorization views. One stand-in: after the password change the test deployment raises the account's
security version in the view (`security_change`); the authorization member consuming iam-casdoor's account status
is foundations item 3. A throwaway Casdoor user is made and deleted. The login's callback goes to iam-casdoor
directly (the redirect URI registered in Casdoor is its port 8200); everything after it goes through the edge.

`steps.jsonl`: each step, what was expected and what came back; all 20 held (the run of 2026-11-03, after the
precondition step was added; the run before it, with the same 19 other steps, also held). `iam.log`: iam-casdoor's
log, `traefik.log`: Traefik's (checked: no client secret, password, signing key, cookie or session digest in either;
a 3-character development password matched inside a random trace ID once, a coincidence).

| step | expected | covers |
| --- | --- | --- |
| the session's token on the user surface | 501 (no such route) | UI04 |
| a request with the session; without | 200; 401 TOKEN_INVALID | CK-EDGE-01 |
| POST without BE-Request; a top-level GET without it | 403 CSRF_HEADER_REQUIRED; 200 | UI06, UI21, CK-EDGE-02 |
| features with a session; without | 200; 401 SESSION_ENDED | UI25, CK-EDGE-06 |
| six tabs at once on a fresh session | all 200, one Exchange in iam-casdoor's access log | UI05, CK-EDGE-01 |
| the password changed through the edge | 204 | UI22 |
| the session that changed it, next request | 200, after exactly one 401 at the probe and one Exchange (the precondition: the stale token was refused and replayed) | UI22, CK-EDGE-03 |
| the account's two other sessions | 401 SESSION_ENDED | UI23, CK-EDGE-05 |
| iam-casdoor stopped: a cached session; a session with no token yet | 200; 503 DEPENDENCY_UNAVAILABLE, then 200 once it is back | UI19, UI29, CK-EDGE-04 |
| logout through the edge, then the old cookie | 204; 401 SESSION_ENDED | UI07, CK-EDGE-05 |
| the logs | no cookie, digest or password | CK-EDGE-07, CK-ID-02 |

Not covered here: UI20 (an ended session the edge never learns of ends at the token's expiry: by construction, the
cache entry ends 30 s before it); UI28 and UI31 (a downstream 401 is CK-ID-06 of the identity profile; the front
end's retry with an idempotency key has no front end yet); CK-ID-07's caller check (iam-casdoor's end-to-end test).
