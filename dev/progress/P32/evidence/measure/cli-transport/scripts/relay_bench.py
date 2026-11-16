"""The real gptr stdio relay (inst/gptr/mcp_relay.R) with an instant responder in place of the
R session: what the relay hop alone costs (Rscript startup, its 10 ms response poll, the file
mailbox). The responder polls the mailbox every `poll_ms` (0.5 ms here; gptr's session task polls
every 20 ms). No gptr, no network. Prints JSON lines."""
import json
import os
import statistics
import subprocess
import sys
import tempfile
import threading
import time

relay = "/Users/wgu/Desktop/gptr/inst/gptr/mcp_relay.R"
work = sys.argv[1]
n_msgs = int(sys.argv[2]) if len(sys.argv) > 2 else 60
reps = int(sys.argv[3]) if len(sys.argv) > 3 else 5
poll_ms = float(sys.argv[4]) if len(sys.argv) > 4 else 0.5
big = "x" * 100_000


def responder(box, stop, poll):
    req = os.path.join(box, "req")
    while not stop.is_set():
        if os.path.exists(req):
            try:
                with open(req) as f:
                    line = f.read()
            except OSError:
                time.sleep(poll)
                continue
            os.unlink(req)
            msg = json.loads(line)
            if "id" in msg:
                text = big if msg.get("params", {}).get("big") else "[1] 2"
                out = json.dumps(dict(jsonrpc="2.0", id=msg["id"],
                                      result=dict(content=[dict(type="text", text=text)])))
            else:
                out = ""
            tmp = os.path.join(box, "resp.tmp")
            with open(tmp, "w") as f:
                f.write(out + "\n")
            os.rename(tmp, os.path.join(box, "resp"))
        else:
            time.sleep(poll)


rows = []
for rep in range(reps):
    box = tempfile.mkdtemp(prefix="relay-", dir=work)
    stop = threading.Event()
    th = threading.Thread(target=responder, args=(box, stop, poll_ms / 1000), daemon=True)
    th.start()
    t0 = time.perf_counter()
    p = subprocess.Popen(["Rscript", "--vanilla", relay, box, "60"], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)

    def ask(msg, notify=False):
        t1 = time.perf_counter()
        p.stdin.write(json.dumps(msg) + "\n")
        p.stdin.flush()
        if notify:
            # the relay waits for the session's empty answer and prints nothing; no line to read
            return t1, None
        line = p.stdout.readline()
        return t1, time.perf_counter()

    t1, t2 = ask(dict(jsonrpc="2.0", id=1, method="initialize"))
    first = t2 - t0
    init_rtt = t2 - t1
    ask(dict(jsonrpc="2.0", method="notifications/initialized"), notify=True)
    small, large = [], []
    for i in range(n_msgs):
        t1, t2 = ask(dict(jsonrpc="2.0", id=10 + i, method="tools/call", params=dict(big=False)))
        small.append(t2 - t1)
    for i in range(10):
        t1, t2 = ask(dict(jsonrpc="2.0", id=1000 + i, method="tools/call", params=dict(big=True)))
        large.append(t2 - t1)
    p.stdin.close()
    p.wait(timeout=10)
    stop.set()
    th.join()
    rows.append(dict(rep=rep, spawn_to_first_response_s=first, initialize_rtt_s=init_rtt,
                     small_rtt_median_s=statistics.median(small), small_rtt_p90_s=sorted(small)[int(0.9 * len(small))],
                     small_rtt_max_s=max(small), large_100kB_rtt_median_s=statistics.median(large),
                     exit=p.returncode))
    print(json.dumps(rows[-1]), flush=True)

print(json.dumps(dict(summary=True, poll_ms=poll_ms, reps=reps, n_msgs=n_msgs,
                      spawn_to_first_response_median_s=statistics.median(r["spawn_to_first_response_s"] for r in rows),
                      small_rtt_median_of_medians_s=statistics.median(r["small_rtt_median_s"] for r in rows),
                      large_rtt_median_of_medians_s=statistics.median(r["large_100kB_rtt_median_s"] for r in rows))),
      flush=True)
