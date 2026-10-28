#!/usr/bin/env python3
"""Leak/load test for the launcher. Needs ADB_SERIAL. Only sends DPAD keys (no OK), never writes settings.
usage: ADB_SERIAL=<ip:5555> python3 tools/load-test.py [cycles] [sample_every]
Each cycle: carousel RIGHT, LEFT, DOWN (dock), UP (featured). Prints one CSV row per sample."""
import os, re, subprocess, sys, time
S = os.environ["ADB_SERIAL"]
def sh(*a):
    return subprocess.run(["adb", "-s", S, "shell", *a], capture_output=True, text=True, timeout=60).stdout
def key(k, wait=0.9):
    sh("input", "keyevent", k); time.sleep(wait)
def sample():
    pid = sh("pidof", "com.gathin.tvhome").strip()
    m = sh("dumpsys", "meminfo", "com.gathin.tvhome")
    g = lambda pat: int((re.search(pat, m) or [0, 0])[1] or 0) if re.search(pat, m) else -1
    row = {"pid": pid,
           "pss": g(r"TOTAL\s+(\d+)"), "swap": g(r"TOTAL SWAP PSS:\s+(\d+)"),
           "java": g(r"Java Heap:\s+(\d+)"), "native": g(r"Native Heap:\s+(\d+)"),
           "gfx": g(r"Graphics:\s+(\d+)"), "views": g(r"Views:\s+(\d+)"), "acts": g(r"Activities:\s+(\d+)")}
    free = re.search(r"Free RAM:\s+([\d,]+)K", sh("dumpsys", "meminfo"))
    row["free_ram"] = int(free[1].replace(",", "")) if free else -1
    return row
cycles = int(sys.argv[1]) if len(sys.argv) > 1 else 40
every = int(sys.argv[2]) if len(sys.argv) > 2 else 5
sh("input", "keyevent", "KEYCODE_HOME"); time.sleep(4)
sh("dumpsys", "gfxinfo", "com.gathin.tvhome", "reset")
cols = None
for i in range(cycles + 1):
    if i % every == 0:
        r = sample()
        if cols is None:
            cols = list(r); print("cycle," + ",".join(cols))
        print(f"{i}," + ",".join(str(r[c]) for c in cols), flush=True)
    if i == cycles: break
    key("KEYCODE_DPAD_RIGHT", 1.4); key("KEYCODE_DPAD_LEFT", 1.4)
    key("KEYCODE_DPAD_DOWN", 1.6); key("KEYCODE_DPAD_UP", 1.6)
g = sh("dumpsys", "gfxinfo", "com.gathin.tvhome")
for pat in (r"Total frames rendered: \d+", r"Janky frames: .*", r"50th percentile: \w+", r"90th percentile: \w+", r"99th percentile: \w+"):
    m = re.search(pat, g); print("#", m[0] if m else pat + " ?")
