TITLE = "be-sdk-python cron (T4b of foundations item 6): one rule of P7.15, P7.16, P7.23 broken per mutant"
BUILD = ["uv", "run", "python", "-c", "import besdk.work.cron"]
TEST = ["uv", "run", "pytest", "-q", "-p", "no:cacheprovider", "-m", "integration or not integration", "-x",
        "tests/test_work_cron.py", "tests/test_work_cron_integration.py"]
ENV = {"PYTHONDONTWRITEBYTECODE": "1"}
C = "besdk/work/cron.py"
R = "besdk/work/runner.py"
MUTANTS = [
    (C, "            return dom or dow", "            return dom and dow", "P7.15: day of month or day of week when both are restricted"),
    (C, "        first = local.replace(tzinfo=self.tz, fold=0)", "        first = local.replace(tzinfo=self.tz, fold=1)",
     "P7.15: a repeated local time runs the first time"),
    (C, "        if u.astimezone(self.tz).replace(tzinfo=None) == local:\n            return u\n        t = local",
     "        return u\n        t = local", "P7.15: a skipped local time runs after the jump"),
    (C, "        dows = {d % 7 for d in _field(f[4], 0, 7)}", "        dows = _field(f[4], 0, 6)", "P7.15: 7 is Sunday"),
    (C, "out += [s for s in self._day(d) if after < s.at <= until]", "out += [s for s in self._day(d) if after <= s.at < until]",
     "P7.16: the interval is (after, until]"),
    (C, "        return due[:max_backlog], due[max_backlog:], due[-1].at", "        return due, [], due[-1].at",
     "P7.16: all: beyond max_backlog paused"),
    (C, "    if backfill == LATEST or (backfill == NONE and last.at > now - NONE_WINDOW):",
     "    if backfill == LATEST or backfill == NONE:", "P7.16: none runs only a slot due within the minute"),
    (C, "        return [last], [], last.at", "        return [last], [], watermark", "P7.16: the watermark moves to the last due slot"),
    (R, "            if at is not None and dt.datetime.now(dt.UTC) + dt.timedelta(seconds=self._skew) < at:\n                continue",
     "            pass", "P7.23: no transaction before the next slot"),
    (R, """            await tx.execute("INSERT INTO be_cron_watermark (job, watermark_at) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                             j.name, at)""",
     """            await tx.execute("INSERT INTO be_cron_watermark (job, watermark_at) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                             j.name, at - dt.timedelta(days=1))""", "P7.16: a job seen first starts at now, no history"),
]
