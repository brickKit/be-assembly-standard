"""Keeps every CPU out of its deep sleep states without root: one lowest-priority process per CPU wakes every 50 us,
so the idle governor picks a shallow state. Runs until killed."""
import os, sys, time

def spin(cpu):
    os.sched_setaffinity(0, {cpu})
    os.nice(19)
    while True:
        time.sleep(50e-6)

pids = []
for cpu in sorted(os.sched_getaffinity(0)):
    pid = os.fork()
    if pid == 0:
        spin(cpu)
    pids.append(pid)
print(" ".join(map(str, pids)), flush=True)
os.waitpid(-1, 0)
