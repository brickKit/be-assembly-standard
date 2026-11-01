# An entry without `if __name__ == "__main__"`, as a launcher's `python -m <pkg>` entry often is.
import os, sys, multiprocessing
from concurrent.futures import ProcessPoolExecutor
from app.work import square
print(f"ENTRY RAN pid={os.getpid()} name={__name__}", flush=True)
if os.environ.get("CHILD_GUARD") != "1":
    os.environ["CHILD_GUARD"] = "1"  # stop a recursive run from spawning again
    ctx = multiprocessing.get_context(sys.argv[1]) if len(sys.argv) > 1 else None
    with ProcessPoolExecutor(max_workers=1, mp_context=ctx) as pool:
        print("result", pool.submit(square, 7).result(), flush=True)
