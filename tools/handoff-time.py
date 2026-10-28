#!/usr/bin/env python3
"""Reads `adb logcat -d -v time` on stdin: seconds from Amazon's Home start to a given package's window being displayed,
plus how many 'Activity start request ... stopped' lines (Android's 5 s app-switch hold) appeared. Usage: handoff-time.py PACKAGE"""
import re, sys

def sec(s):
    h, m, r = s.split(":")
    return int(h) * 3600 + int(m) * 60 + float(r)

pkg = sys.argv[1]
home = disp = None
held = 0
for line in sys.stdin:
    m = re.search(r"(\d\d:\d\d:\d\d\.\d+)", line)
    if not m:
        continue
    if "Activity start request" in line and "stopped" in line:
        held += 1
    if home is None and "START u0" in line and "category.HOME" in line and "amazon.tv.launcher" in line:
        home = sec(m.group(1))
    if disp is None and ("Displayed " + pkg) in line:
        disp = sec(m.group(1))
print(f"{round(disp - home, 2)}s" if home is not None and disp is not None else "n/a", f"(held-start lines: {held})")
