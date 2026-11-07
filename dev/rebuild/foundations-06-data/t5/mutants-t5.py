TITLE = "be-sdk-python redelivery (T5 of foundations item 6): one rule of P6.12, P6.36-P6.40 broken per mutant"
BUILD = ["uv", "run", "python", "-c", "import besdk.host"]
TEST = ["uv", "run", "pytest", "-q", "-p", "no:cacheprovider", "-m", "integration or not integration", "-x",
        "tests/test_progress.py", "tests/test_resend_integration.py", "tests/test_redelivery_integration.py"]
ENV = {"PYTHONDONTWRITEBYTECODE": "1"}
P = "besdk/events/progress.py"
R = "besdk/events/resend.py"
D = "besdk/events/redelivery.py"
O = "besdk/events/outbox.py"
MUTANTS = [
    (P, "        if last is not None and starts[k] <= _minus(last, lifetime):", "        if last is not None:",
     "P6.37: a run that did not last L gives no cut"),
    (P, "        if r.pos is None or r.at > cut:", "        if r.pos is None:", "P6.37: only rows handled by the cut count"),
    (P, "processed_at <= $2\n", "processed_at <= $2 + interval '1 day'\n", "P6.37: the database reading respects the cut"),
    (R, "                beyond = after is None or after < purged", "                beyond = after is not None and after < purged",
     "P6.38: no start and a purged partition is beyond the retention"),
    (R, "                return beyond, after.seq > r[\"last_seq\"]", "                return beyond, False",
     "P6.38: a start past the counter is ahead"),
    (R, "                return beyond, True  # an epoch this partition never had", "                return beyond, False",
     "P6.38: an epoch the partition never had is ahead"),
    (R, "                m.msg_id = f\"{row.event_id}/resend/{rid}\"", "                pass",
     "P6.38: a redelivered message has its own message ID"),
    (R, "            if not f.HasField(\"after\") or f.after.impl != self.impl:", "            if not f.HasField(\"after\"):",
     "P6.38: another implementation instance's position starts at the first row kept"),
    (O, "                if key not in top or top[key] < pos:", "                if key not in top or top[key] > pos:",
     "P6.12: the purge notes the largest position"),
    (D, "            elif p < cur[1]:", "            elif p > cur[1]:", "P6.39: the smallest progress of the subscriptions"),
    (D, "        open_.update(n for n in starts if n not in mine)", "        pass",
     "P6.39: a partition one subscription has no progress on starts at the first row kept"),
    (D, "            return (last[\"epoch_generation\"], last[\"epoch_timeline\"]) != now, now", "            return False, now",
     "P6.39: a different epoch means the database went back"),
    (D, "        if failures:\n            raise RuntimeError(\"; \".join(failures))", "        pass",
     "P6.39: settle only once every producer answered"),
    (D, "            for n in parts:\n                await self._gap(kind, component, stream, n, subs, by_sub)", "            pass",
     "P6.40: the partitions a redelivery cannot cover are recorded"),
]
