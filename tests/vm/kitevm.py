#!/usr/bin/python3
"""kitevm — drive a KiteOS test VM (QEMU + OVMF) from the command line.

  kitevm.py start NAME --iso X.iso [--disk D.qcow2] [--usb U.img] [--mem 4096] [--smp 2]
                      [--kernel K --initrd I --append "..."] [--boot-disk]
  kitevm.py shot NAME out.png          screenshot of the VM display
  kitevm.py keys NAME ctrl-alt-t ret   press key combos (QEMU qcodes joined by '-')
  kitevm.py type NAME "text"           type text
  kitevm.py click NAME X Y [left|right|middle] [--double]
  kitevm.py move NAME X Y
  kitevm.py ocr NAME                   screenshot + print recognised text
  kitevm.py wait NAME "text" [TIMEOUT] wait until text is on screen (OCR)
  kitevm.py find NAME "regex"          print X Y of the text on screen (OCR), or exit 1
  kitevm.py clicktext NAME "regex" [TIMEOUT] [--last] [--dx N] [--dy N]
                                       wait for the text, then click its middle
                                       (--last: the lowest match; --dx/--dy: offset)
  kitevm.py sh NAME "command" [TIMEOUT] run a command on the serial console (logged in)
  kitevm.py login NAME USER PASSWORD   log in on the serial console
  kitevm.py usb NAME add|del [IMG]     plug / unplug the virtual USB disk
  kitevm.py stop NAME                  power off (hard)
  kitevm.py qmp NAME '{"execute": ...}'

Display: 1366x768 (the HP Chromebook 11 G8 EE panel). Keyboard: PS/2 (like
the Chromebook's internal keyboard). Mouse: USB tablet (absolute).
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time

RUN = os.environ.get("KITEVM_DIR", "/tmp/kitevm")
OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS = "/usr/share/OVMF/OVMF_VARS_4M.fd"
W, H = (int(v) for v in os.environ.get("KITEVM_RES", "1366x768").split("x"))


def p(name, ext):
    return os.path.join(RUN, f"{name}.{ext}")


# ------------------------------------------------------------------ QMP --
def qmp(name, cmd, args=None):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(p(name, "qmp"))
    f = s.makefile("rw")
    json.loads(f.readline())
    f.write(json.dumps({"execute": "qmp_capabilities"}) + "\n"); f.flush()
    json.loads(f.readline())
    msg = {"execute": cmd}
    if args:
        msg["arguments"] = args
    f.write(json.dumps(msg) + "\n"); f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r:
            s.close()
            if "error" in r:
                raise RuntimeError(r["error"])
            return r["return"]


def start(name, argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--iso"); ap.add_argument("--disk"); ap.add_argument("--usb")
    ap.add_argument("--mem", default="4096"); ap.add_argument("--smp", default="2")
    ap.add_argument("--kernel"); ap.add_argument("--initrd"); ap.add_argument("--append")
    ap.add_argument("--boot-disk", action="store_true")
    a = ap.parse_args(argv)
    os.makedirs(RUN, exist_ok=True)
    vars_file = p(name, "vars")
    if not os.path.exists(vars_file):
        shutil.copy(OVMF_VARS, vars_file)
    cmd = [
        "qemu-system-x86_64", "-name", name,
        "-machine", "q35",
        *(["-accel", "kvm"] if os.access("/dev/kvm", os.W_OK) else []),
        "-accel", "tcg,thread=multi,tb-size=1024",   # fallback when there is no KVM
        # Denverton = Goldmont, the closest QEMU model to the N4020 (Goldmont Plus)
        "-cpu", os.environ.get("KITEVM_CPU", "Denverton"),
        "-smp", a.smp, "-m", a.mem,
        "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
        "-drive", f"if=pflash,format=raw,file={vars_file}",
        "-device", f"VGA,xres={W},yres={H},edid=on",
        "-device", "qemu-xhci,id=xhci", "-device", "usb-tablet,bus=xhci.0",
        "-device", "ahci,id=ahci",
        "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
        "-device", "intel-hda", "-device", "hda-duplex,audiodev=a0", "-audiodev", "none,id=a0",
        "-qmp", f"unix:{p(name, 'qmp')},server=on,wait=off",
        "-chardev", f"socket,id=ser0,path={p(name, 'ser')},server=on,wait=off,logfile={p(name, 'serial.log')}",
        "-serial", "chardev:ser0",
        "-display", "none", "-daemonize", "-pidfile", p(name, "pid"),
    ]
    if a.iso:
        cmd += ["-drive", f"id=cd0,if=none,media=cdrom,readonly=on,file={a.iso}",
                "-device", f"ide-cd,drive=cd0,bus=ahci.0{',bootindex=2' if a.boot_disk else ',bootindex=0'}"]
    if a.disk:
        # The Chromebook's eMMC shows up as mmcblk0; emulate it with an SD/MMC host.
        cmd += ["-drive", f"id=d0,if=none,format=qcow2,file={a.disk},cache=unsafe,discard=unmap"]
        if os.environ.get("KITEVM_DISK", "nvme") == "sd":
            # eMMC-like naming (mmcblk0), but QEMU's SD host writes out discards: very slow
            cmd += ["-device", "sdhci-pci,id=sdhci", "-device", "sd-card,drive=d0"]
        else:
            cmd += ["-device", "nvme,serial=kite-emmc,drive=d0,bootindex=1"]
    if a.usb:
        cmd += ["-drive", f"id=usb0,if=none,format=raw,file={a.usb},cache=unsafe",
                "-device", "usb-storage,id=usbdisk,drive=usb0,bus=xhci.0"]
    if a.kernel:
        cmd += ["-kernel", a.kernel, "-initrd", a.initrd, "-append", a.append or ""]
    subprocess.run(cmd, check=True)
    print("started", name)


# ------------------------------------------------------------- display --
def shot(name, out):
    tmp = p(name, "ppm")
    qmp(name, "screendump", {"filename": tmp})
    subprocess.run(["convert", tmp, out], check=True)
    return out


def ocr(name):
    out = p(name, "ocr.png")
    shot(name, out)
    big = p(name, "ocr-big.png")
    subprocess.run(["convert", out, "-resize", "200%", "-colorspace", "Gray", big], check=True)
    r = subprocess.run(["tesseract", big, "-", "--psm", "11"], capture_output=True, text=True)
    return r.stdout


def find_text(name, text, last=False):
    """Screen position (x, y) of the middle of the first (or lowest) OCR line
    part matching the regex TEXT, or None. tesseract reads a 2x grey copy."""
    out = p(name, "find.png")
    shot(name, out)
    big = p(name, "find-big.png")
    subprocess.run(["convert", out, "-resize", "200%", "-colorspace", "Gray", big], check=True)
    r = subprocess.run(["tesseract", big, "-", "--psm", "11", "tsv"], capture_output=True, text=True)
    lines = {}
    for row in r.stdout.splitlines()[1:]:
        f = row.split("\t")
        if len(f) < 12 or f[0] != "5" or not f[11].strip():
            continue
        key = (f[1], f[2], f[3], f[4])            # page, block, paragraph, line
        lines.setdefault(key, []).append((int(f[6]), int(f[7]), int(f[8]), int(f[9]), f[11]))
    rx = re.compile(text, re.I)
    hits = []
    for words in lines.values():
        words.sort()
        joined, spans = "", []
        for w in words:
            if joined:
                joined += " "
            spans.append((len(joined), len(joined) + len(w[4]), w))
            joined += w[4]
        m = rx.search(joined)
        if not m:
            continue
        sel = [w for a, b, w in spans if a < m.end() and b > m.start()]
        x0 = min(w[0] for w in sel); y0 = min(w[1] for w in sel)
        x1 = max(w[0] + w[2] for w in sel); y1 = max(w[1] + w[3] for w in sel)
        hits.append(((x0 + x1) // 4, (y0 + y1) // 4))
    if not hits:
        return None
    hits.sort(key=lambda h: (h[1], h[0]))
    return hits[-1] if last else hits[0]


def click_text(name, text, timeout=60, last=False, dx=0, dy=0):
    end = time.time() + float(timeout)
    while True:
        pos = find_text(name, text, last)
        if pos:
            click(name, pos[0] + dx, pos[1] + dy)
            return pos
        if time.time() > end:
            return None
        time.sleep(3)


def wait(name, text, timeout=600):
    end = time.time() + float(timeout)
    rx = re.compile(text, re.I)
    while time.time() < end:
        t = ocr(name)
        if rx.search(t):
            return True
        time.sleep(5)
    return False


# --------------------------------------------------------------- input --
SHIFTED = {'!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8',
           '(': '9', ')': '0', '_': 'minus', '+': 'equal', '{': 'bracket_left', '}': 'bracket_right',
           '|': 'backslash', ':': 'semicolon', '"': 'apostrophe', '<': 'comma', '>': 'dot',
           '?': 'slash', '~': 'grave_accent'}
PLAIN = {' ': 'spc', '-': 'minus', '=': 'equal', '[': 'bracket_left', ']': 'bracket_right',
         '\\': 'backslash', ';': 'semicolon', "'": 'apostrophe', ',': 'comma', '.': 'dot',
         '/': 'slash', '`': 'grave_accent', '\n': 'ret', '\t': 'tab'}


def keys(name, combos, hold=100):
    for c in combos:
        ks = [{"type": "qcode", "data": k} for k in c.split("-")] if c != "minus" else [{"type": "qcode", "data": "minus"}]
        qmp(name, "send-key", {"keys": ks, "hold-time": hold})
        time.sleep(0.15)


def type_text(name, text):
    for ch in text:
        if ch.isalpha() and ch.isupper():
            seq = ["shift", ch.lower()]
        elif ch.isalnum():
            seq = [ch]
        elif ch in SHIFTED:
            seq = ["shift", SHIFTED[ch]]
        elif ch in PLAIN:
            seq = [PLAIN[ch]]
        else:
            continue
        qmp(name, "send-key", {"keys": [{"type": "qcode", "data": k} for k in seq], "hold-time": 60})
        time.sleep(float(os.environ.get("KITEVM_TYPE_DELAY", "0.12")))


def _abs(x, y):
    return [{"type": "abs", "data": {"axis": "x", "value": int(x * 32767 / (W - 1))}},
            {"type": "abs", "data": {"axis": "y", "value": int(y * 32767 / (H - 1))}}]


def move(name, x, y):
    qmp(name, "input-send-event", {"events": _abs(x, y)})


def click(name, x, y, button="left", double=False):
    move(name, x, y)
    time.sleep(0.2)
    for _ in range(2 if double else 1):
        qmp(name, "input-send-event", {"events": [{"type": "btn", "data": {"down": True, "button": button}}]})
        time.sleep(0.08)
        qmp(name, "input-send-event", {"events": [{"type": "btn", "data": {"down": False, "button": button}}]})
        time.sleep(0.12)


# -------------------------------------------------------------- serial --
def _ser(name):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(p(name, "ser"))
    s.settimeout(1)
    return s


def _read_until(s, pattern, timeout):
    buf = ""
    end = time.time() + timeout
    rx = re.compile(pattern)
    while time.time() < end:
        try:
            d = s.recv(65536).decode("utf-8", "replace")
            buf += d
            if rx.search(buf):
                return buf
        except socket.timeout:
            pass
    raise TimeoutError(f"no match for {pattern!r}; got tail: {buf[-500:]!r}")


def login(name, user, password):
    s = _ser(name)
    s.sendall(b"\n")
    _read_until(s, r"login: ?$", 900)
    s.sendall(user.encode() + b"\n")
    _read_until(s, r"[Pp]assword: ?$", 60)
    s.sendall(password.encode() + b"\n")
    _read_until(s, r"\$ ?$", 120)
    s.sendall(b"export PS1='KVM$ ' TERM=dumb; stty -echo cols 200\n")
    _read_until(s, r"KVM\$ $", 30)
    s.close()
    print("logged in")


def sh(name, command, timeout=300):
    s = _ser(name)
    marker = f"__DONE_{int(time.time() * 1000)}__"
    s.sendall(f"{command}; echo {marker} rc=$?\n".encode())
    out = _read_until(s, marker + r" rc=\d+", float(timeout))
    s.close()
    body, _, tail = out.rpartition(marker)
    rc = int(re.search(r"rc=(\d+)", tail).group(1))
    body = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", body)
    print(body.strip("\r\n "))
    return rc


def usb(name, action, img=None):
    if action == "del":
        qmp(name, "device_del", {"id": "usbdisk"})
        time.sleep(2)
        try:
            qmp(name, "blockdev-del", {"node-name": "usbnode"})
        except RuntimeError:
            pass
    else:
        qmp(name, "blockdev-add", {"node-name": "usbnode", "driver": "raw",
                                   "file": {"driver": "file", "filename": img}})
        qmp(name, "device_add", {"driver": "usb-storage", "id": "usbdisk", "drive": "usbnode", "bus": "xhci.0"})


def stop(name):
    try:
        qmp(name, "quit")
    except Exception:
        pass
    time.sleep(1)


def main():
    if len(sys.argv) < 3:
        print(__doc__); return 2
    cmd, name, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
    if cmd == "start":
        start(name, rest)
    elif cmd == "shot":
        print(shot(name, rest[0]))
    elif cmd == "keys":
        keys(name, rest)
    elif cmd == "type":
        type_text(name, rest[0])
    elif cmd == "click":
        dbl = "--double" in rest
        rest = [r for r in rest if r != "--double"]
        click(name, int(rest[0]), int(rest[1]), rest[2] if len(rest) > 2 else "left", dbl)
    elif cmd == "move":
        move(name, int(rest[0]), int(rest[1]))
    elif cmd == "ocr":
        print(ocr(name))
    elif cmd == "wait":
        ok = wait(name, rest[0], rest[1] if len(rest) > 1 else 600)
        print("found" if ok else "TIMEOUT")
        return 0 if ok else 1
    elif cmd == "find":
        pos = find_text(name, rest[0], "--last" in rest)
        if not pos:
            return 1
        print(*pos)
    elif cmd == "clicktext":
        args = [r for r in rest if r != "--last"]
        dx = dy = 0
        for flag in ("--dx", "--dy"):
            if flag in args:
                i = args.index(flag)
                val = int(args[i + 1]); del args[i:i + 2]
                dx, dy = (val, dy) if flag == "--dx" else (dx, val)
        pos = click_text(name, args[0], args[1] if len(args) > 1 else 60, "--last" in rest, dx, dy)
        if not pos:
            print("NOT FOUND: %s" % args[0], file=sys.stderr)
            return 1
        print("clicked", *pos)
    elif cmd == "login":
        login(name, rest[0], rest[1])
    elif cmd == "sh":
        return sh(name, rest[0], rest[1] if len(rest) > 1 else 300)
    elif cmd == "usb":
        usb(name, rest[0], rest[1] if len(rest) > 1 else None)
    elif cmd == "stop":
        stop(name)
    elif cmd == "qmp":
        m = json.loads(rest[0])
        print(json.dumps(qmp(name, m["execute"], m.get("arguments")), indent=1))
    else:
        print(__doc__); return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
