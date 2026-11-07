TITLE = "be-sdk-python work (T4a of foundations item 6): one rule of chapter 07 broken per mutant"
BUILD = ["uv", "run", "python", "-c", "import besdk.work"]
TEST = ["uv", "run", "pytest", "-q", "-p", "no:cacheprovider", "-m", "integration", "-x", "tests/test_work_integration.py"]
ENV = {"PYTHONDONTWRITEBYTECODE": "1"}
R = "besdk/work/runner.py"
U = "besdk/work/run.py"
MUTANTS = [
    (U, "AND (claim_db_generation, claim_db_timeline) = (SELECT generation, timeline FROM be_current_db_epoch())",
     "AND true", "P7.6: the claim epoch must still be current"),
    (U, "id = $1 AND state = 'running' AND epoch = $2", "id = $1 AND state = 'running' AND $2::bigint IS NOT NULL",
     "P7.6: a commit checks the holder's own epoch"),
    (R, "state = 'running' AND lease_until <= now()", "state = 'running' AND lease_until <= now() + interval '1 hour'",
     "P7.5: a live lease is never taken over"),
    (R, "AND run_at <= now()\n", "\n", "P7.24: an item is not claimed before its run_at"),
    (R, "attempts = w.attempts + 1, holder", "attempts = w.attempts, holder", "P7.5: a claim counts an attempt"),
    (R, "await asyncio.shield(r.exec(\"lease_until = now(), attempts = attempts - 1\"))", "pass",
     "P7.8: a stop gives the lease and the attempt back"),
    (R, "if row[\"effect_class\"] == NON_IDEMPOTENT_EXTERNAL and row[\"outcome_unknown\"]:", "if False:",
     "P7.12: a non-idempotent item whose call may have been sent is paused at its next claim"),
    (R, "elif j.effect == NON_IDEMPOTENT_EXTERNAL and kind != \"not_effective\" and await self._unknown(r):",
     "elif False:", "P7.12: a failure after a possible send pauses the item"),
    (R, "elif r.attempts >= r.max_attempts:", "elif r.attempts > r.max_attempts + 5:", "P7.13: the attempts run out into dead"),
    (R, "            if j.dead_letter is not None:\n                await j.dead_letter(tx, r, cause)",
     "            pass", "P7.13: the dead letter in the transaction that marks the item dead"),
    (R, "        elif kind == \"permanent\":\n            await self._dead(r, cause)", "        elif False:\n            pass",
     "P7.13: a permanent failure is dead at once"),
    (R, "state = 'retry_wait', attempts = attempts - 1, holder", "state = 'retry_wait', attempts = attempts, holder",
     "P7.13: a business wait spends no attempt"),
    (R, "                if waited:", "                if False:", "P7.13: a wait past max_wait is permanent"),
    (R, "last_error = $5, run_at = now() + make_interval(secs => $6)\"\"\", (msg, backoff(r.attempts)))",
     "last_error = $5, run_at = now() + make_interval(secs => $6)\"\"\", (msg, 0.0))", "P7.13: the retry waits its backoff"),
    (U, "attempts = 0, progress = NULL, operation_id = $5,", "attempts = 0, operation_id = $5,",
     "P7.17: a completed singleton starts its next run without the old progress"),
    (U, "await self.exec(\"progress = $5::jsonb, operation_id = $6, call_results = '{}'\", (json.dumps(progress), nxt), fn)",
     "pass", "P7.17: a checkpoint commits the progress"),
    (R, "            tx.after_commit(lambda: self._wake(False))", "            pass", "P7.21: a commit wakes a worker"),
    (R, "        self._wake(True)\n        return False", "        for _ in range(self.concurrency):\n            self._wake(True)\n        return False",
     "P7.23: a poll wakes one worker"),
    (R, "                async with asyncio.timeout(float(j.timeout)):\n                    await j.handle(r)",
     "                await j.handle(r)", "a run past its deadline fails as retryable"),
]
