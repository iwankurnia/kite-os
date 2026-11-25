#!/usr/bin/python3
"""Measure RAM (PSS) and CPU of the processes running inside one root
directory (a chroot of the KiteOS image), grouped like kite-resource-report.

  measure-procs.py ROOT SECONDS LABEL
"""
import os
import sys
import time

ROOT, SECS, LABEL = sys.argv[1], float(sys.argv[2]), sys.argv[3]
HZ = os.sysconf("SC_CLK_TCK")


def group(comm):
    c = comm
    if c.startswith(("brave", "chrome_crashpad")):
        return "Brave"
    if c in ("DesktopEditors", "editors", "editors_helper", "x2t") or c.startswith("onlyoffice"):
        return "ONLYOFFICE"
    if c.startswith(("xfwm4", "picom", "xfce4-", "xfdesktop", "xfsettingsd", "xfconfd", "Thunar", "panel-", "wrapper-2.0", "rofi")):
        return "Desktop (XFCE)"
    if c.startswith(("pipewire", "wireplumber")):
        return "Audio"
    return "Other session processes"


def procs():
    out = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            if os.readlink(f"/proc/{pid}/root") != ROOT:
                continue
            comm = open(f"/proc/{pid}/comm").read().strip()
            st = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
            cpu = int(st[11]) + int(st[12])
            pss = 0
            for line in open(f"/proc/{pid}/smaps_rollup"):
                if line.startswith("Pss:"):
                    pss = int(line.split()[1])
            out[int(pid)] = (comm, cpu, pss)
        except (OSError, IndexError, ValueError):
            pass
    return out


a = procs()
t0 = time.time()
time.sleep(SECS)
b = procs()
dt = time.time() - t0
mem, cpu = {}, {}
for pid, (comm, c, pss) in b.items():
    g = group(comm)
    mem[g] = mem.get(g, 0) + pss
    # processes started during the window count with all their CPU time
    cpu[g] = cpu.get(g, 0) + (c - a[pid][1] if pid in a else c)
print(f"== {LABEL}  ({len(b)} processes, {dt:.0f}s sample)")
print(f"   {'group':26} {'RAM PSS MiB':>12} {'CPU % of 1 core':>16}")
for g in sorted(mem, key=lambda g: -mem[g]):
    print(f"   {g:26} {mem[g] / 1024:12.0f} {100 * cpu.get(g, 0) / HZ / dt:16.1f}")
print(f"   {'TOTAL':26} {sum(mem.values()) / 1024:12.0f} {100 * sum(cpu.values()) / HZ / dt:16.1f}")
