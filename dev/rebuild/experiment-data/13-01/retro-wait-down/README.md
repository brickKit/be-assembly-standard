# wait_down's premise (retro-step13.md J1), 2026-11-02

be-acceptance 1.0.29 makes a stop return only once fewer replicas are ready. Measured that "ready" drops on both engines:

## Docker 29.9.2 (alpine:3.22, `--health-cmd true --health-interval 1s`, two containers, `docker stop -t 1` the second)

    before: true/healthy true/healthy
    after stop: true/healthy false/unhealthy
    old check (Health only): healthy unhealthy

Format: `{{.State.Running}}/{{if .State.Health}}{{.State.Health.Status}}{{end}}`.

## minikube profile bek (Deployment of 2, readiness: a file made 3 s after start; `kubectl delete pod --wait=false` on one)

`readyReplicas` polled back to back after the delete: 1 from the first reading (0.2 s) through 3.2 s, the replacement not
yet ready (40 readings, all `ready=1`). The commands are in the session log (13ed8ff2); the Deployment:

    command: ["sh", "-c", "sleep 3; touch /tmp/ready; exec sleep 600"]
    readinessProbe: {exec: {command: ["test", "-f", "/tmp/ready"]}, periodSeconds: 1}
    terminationGracePeriodSeconds: 10

## The old error replayed

`tests/test_fault_replicas.py::test_a_stop_that_stops_no_replica_fails` against `v1.0.28:conformance/cells/faults.py`:
`1 failed` (the stop returned with both replicas ready); against 1.0.29: passes.
