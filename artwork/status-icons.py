#!/usr/bin/python3
"""Generate the KiteOS status (tray) icon set.

All icons share one 24×24 grid and one visual weight, and are drawn with
filled shapes only, which is what GTK needs to recolour "symbolic" icons. The
shelf then paints them all in its own text colour at the same size.

  artwork/status-icons.py OUTPUT_DIR      (writes OUTPUT_DIR/*.svg)

Covers the names asked for by nm-applet (Wi-Fi, wired, connecting, VPN),
the volume plugin, UPower/xfce4-power-manager (battery), plus the KiteOS
launcher and power buttons.
"""
import math
import os
import sys

FG = "#bebebe"   # GTK replaces this with the theme's text colour
DIM = 0.3        # opacity of the "empty" part of a level indicator


def svg(*parts):
    body = "\n  ".join(p for p in parts if p)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\n'
            f'  {body}\n</svg>\n')


def path(d, opacity=1.0, evenodd=False):
    attrs = f'd="{d}" fill="{FG}"'
    if opacity < 1:
        attrs += f' opacity="{opacity:g}"'
    if evenodd:
        attrs += ' fill-rule="evenodd"'
    return f"<path {attrs}/>"


def f(x):
    return f"{x:.3f}".rstrip("0").rstrip(".")


def pt(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def sector(cx, cy, r, a0, a1):
    """Filled pie slice from angle a0 to a1 (degrees, 0 = east, clockwise)."""
    x0, y0 = pt(cx, cy, r, a0)
    x1, y1 = pt(cx, cy, r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{f(cx)} {f(cy)}L{f(x0)} {f(y0)}A{f(r)} {f(r)} 0 {large} 1 {f(x1)} {f(y1)}Z"


def ring_arc(cx, cy, r_in, r_out, a0, a1):
    """Filled band between two radii, from angle a0 to a1, with round ends."""
    xo0, yo0 = pt(cx, cy, r_out, a0)
    xo1, yo1 = pt(cx, cy, r_out, a1)
    xi1, yi1 = pt(cx, cy, r_in, a1)
    xi0, yi0 = pt(cx, cy, r_in, a0)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    cap = (r_out - r_in) / 2
    return (f"M{f(xo0)} {f(yo0)}"
            f"A{f(r_out)} {f(r_out)} 0 {large} 1 {f(xo1)} {f(yo1)}"
            f"A{f(cap)} {f(cap)} 0 0 1 {f(xi1)} {f(yi1)}"
            f"A{f(r_in)} {f(r_in)} 0 {large} 0 {f(xi0)} {f(yi0)}"
            f"A{f(cap)} {f(cap)} 0 0 1 {f(xo0)} {f(yo0)}Z")


def circle(cx, cy, r):
    return (f"M{f(cx - r)} {f(cy)}A{f(r)} {f(r)} 0 1 0 {f(cx + r)} {f(cy)}"
            f"A{f(r)} {f(r)} 0 1 0 {f(cx - r)} {f(cy)}Z")


def rrect(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    return (f"M{f(x + r)} {f(y)}H{f(x + w - r)}A{f(r)} {f(r)} 0 0 1 {f(x + w)} {f(y + r)}"
            f"V{f(y + h - r)}A{f(r)} {f(r)} 0 0 1 {f(x + w - r)} {f(y + h)}"
            f"H{f(x + r)}A{f(r)} {f(r)} 0 0 1 {f(x)} {f(y + h - r)}"
            f"V{f(y + r)}A{f(r)} {f(r)} 0 0 1 {f(x + r)} {f(y)}Z")


def cross(cx, cy, size, t=2.0):
    """A small × made of two rounded bars (filled)."""
    h = size / 2
    d = t / 2 / math.sqrt(2)
    pts1 = [(cx - h - d, cy - h + d), (cx - h + d, cy - h - d), (cx + h + d, cy + h - d), (cx + h - d, cy + h + d)]
    pts2 = [(cx + h - d, cy - h - d), (cx + h + d, cy - h + d), (cx - h + d, cy + h + d), (cx - h - d, cy + h - d)]
    return ["M" + "L".join(f"{f(x)} {f(y)}" for x, y in p) + "Z" for p in (pts1, pts2)]


# --------------------------------------------------------------- Wi-Fi --
# A ChromeOS-style filled fan: the bright part shows signal strength.
WIFI_C = (12, 19.5)
WIFI_R = 14.0
WIFI_A = (225, 315)


def wifi(level):  # level 0..4
    radii = [0, 6.5, 9.0, 11.5, WIFI_R]
    parts = [path(sector(*WIFI_C, WIFI_R, *WIFI_A), DIM)]
    if level > 0:
        parts.append(path(sector(*WIFI_C, radii[level], *WIFI_A)))
    return parts


def wifi_off():
    return [path(sector(*WIFI_C, WIFI_R, *WIFI_A), DIM)] + [path(d) for d in cross(18.5, 18, 4.5)]


# --------------------------------------------------------------- wired --
def wired():
    d = [rrect(8.5, 3, 7, 6, 1.5),              # top box
         rrect(2.5, 15, 7, 6, 1.5),             # bottom left
         rrect(14.5, 15, 7, 6, 1.5),            # bottom right
         rrect(11, 8.5, 2, 4.5, 0),             # stem
         rrect(5, 12, 14, 2, 1),                # bar
         rrect(5, 12, 2, 3.5, 0),
         rrect(17, 12, 2, 3.5, 0)]
    return [path(x) for x in d]


def cellular(level):  # 0..4 ascending bars
    parts = []
    for i in range(4):
        h = 4 + i * 4.5
        parts.append(path(rrect(3 + i * 5, 21 - h, 3.5, h, 1), 1 if i < level else DIM))
    return parts


def padlock():
    return [path(rrect(5.5, 10.5, 13, 10.5, 2)),
            path(ring_arc(12, 10.5, 3.5, 5.5, 180, 360)),
            path(rrect(6.5, 10, 2, 1.5, 0)), path(rrect(15.5, 10, 2, 1.5, 0))]


# --------------------------------------------------------------- volume --
SPEAKER = "M2.5 9.5Q2.5 8.5 3.5 8.5H6.5L11 4.5V19.5L6.5 15.5H3.5Q2.5 15.5 2.5 14.5Z"


def volume(level):  # 0 muted, 1 low, 2 medium, 3 high
    if level == 0:
        return [path(SPEAKER)] + [path(d) for d in cross(17.5, 12, 6)]
    parts = [path(SPEAKER)]
    bands = [(3.2, 5.0), (6.2, 8.0), (9.2, 11.0)]
    for i, (ri, ro) in enumerate(bands):
        parts.append(path(ring_arc(11.5, 12, ri, ro, -48, 48), 1 if i < level else DIM))
    return parts


def microphone(level):
    parts = [path(rrect(9, 3, 6, 11, 3)),
             path(ring_arc(12, 11, 5, 6.8, 20, 160)),
             path(rrect(11.1, 17, 1.8, 3.5, 0)),
             path(rrect(8, 19.5, 8, 1.8, 0.9))]
    if level == 0:
        parts = [p.replace(f'fill="{FG}"', f'fill="{FG}" opacity="{DIM}"') for p in parts]
        parts += [path(d) for d in cross(12, 12, 13, 2.2)[:1]]
    return parts


# -------------------------------------------------------------- battery --
def battery(percent, charging=False, missing=False):
    body = rrect(6.5, 4, 11, 18, 2.5) + rrect(8.5, 6, 7, 14, 1)   # outline (even-odd)
    parts = [path(body, evenodd=True), path(rrect(9.5, 2, 5, 2.5, 1))]
    if missing:
        parts += [path(d) for d in cross(12, 13, 4.5)]
        return parts
    inner_h = 12
    h = round(inner_h * percent / 100, 2)
    if charging:
        parts.append(path(rrect(9.5, 7, 5, inner_h, 0.5), DIM))
        if h > 0:
            parts.append(path(rrect(9.5, 7 + inner_h - h, 5, h, 0.5), 0.55))
        parts.append(path("M13 7.5L9.5 13.5H11.7L10.8 18.5L14.5 12.2H12.2L13 7.5Z"))
    elif h > 0:
        parts.append(path(rrect(9.5, 7 + inner_h - h, 5, h, 0.5)))
    if not charging and percent <= 10:
        parts.append(path(rrect(11.1, 9, 1.8, 5.5, 0.9)))   # "!" for low battery
        parts.append(path(circle(12, 16.6, 1)))
    return parts


def ac_adapter():
    return [path(rrect(6.5, 7, 11, 8, 2.5)),
            path(rrect(8.5, 2.5, 2, 5, 1)), path(rrect(13.5, 2.5, 2, 5, 1)),
            path(rrect(11, 14.5, 2, 4, 0)),
            path(rrect(8, 18.5, 8, 2.5, 1.25))]


# -------------------------------------------------------- KiteOS buttons --
def power_button():
    return [path(ring_arc(12, 13, 6.6, 8.6, -55, 235)),
            path(rrect(11, 2.5, 2, 9.5, 1))]


def launcher():
    return [path(circle(12, 12, 8.3) + circle(12, 12, 6.3), evenodd=True)]


# ----------------------------------------------------------------- write --
def build():
    icons = {}
    sig = {"00": 0, "25": 1, "50": 2, "75": 3, "100": 4}
    for name, lvl in sig.items():
        icons[f"nm-signal-{name}"] = wifi(lvl)
        icons[f"nm-signal-{name}-secure"] = wifi(lvl)
        icons[f"network-wireless-signal-{['none', 'weak', 'ok', 'good', 'excellent'][lvl]}"] = wifi(lvl)
    icons["nm-device-wireless"] = wifi(4)
    icons["nm-no-connection"] = wifi_off()
    icons["network-wireless-offline"] = wifi_off()
    icons["network-offline"] = wifi_off()
    for stage in (1, 2, 3):
        for step in range(1, 12):
            icons[f"nm-stage{stage:02d}-connecting{step:02d}"] = wifi(step % 4 + 1)
    for step in range(1, 15):
        icons[f"nm-vpn-connecting{step:02d}"] = padlock()
    for n in ("nm-device-wired", "nm-device-wired-secure", "nm-adhoc", "network-wired"):
        icons[n] = wired()
    for n, lvl in (("nm-device-wwan", 4), ("nm-wwan-tower", 4), ("nm-mb-roam", 2)):
        icons[n] = cellular(lvl)
    for n in ("nm-vpn-active-lock", "nm-secure-lock"):
        icons[n] = padlock()

    for n, lvl in (("muted", 0), ("low", 1), ("medium", 2), ("high", 3), ("overamplified", 3)):
        icons[f"audio-volume-{n}"] = volume(lvl)
    for n, lvl in (("muted", 0), ("low", 1), ("medium", 2), ("high", 3)):
        icons[f"microphone-sensitivity-{n}"] = microphone(lvl)

    for p in range(0, 101, 10):
        icons[f"battery-level-{p}"] = battery(p)
        icons[f"battery-level-{p}-charging"] = battery(p, charging=True)
    icons["battery-level-100-charged"] = battery(100, charging=True)
    icons["battery-full-charged"] = battery(100, charging=True)
    for n, p in (("full", 100), ("good", 70), ("low", 30), ("caution", 10), ("empty", 0)):
        icons[f"battery-{n}"] = battery(p)
        icons[f"battery-{n}-charging"] = battery(p, charging=True)
    icons["battery-missing"] = battery(0, missing=True)
    icons["ac-adapter"] = ac_adapter()

    icons["kite-power"] = power_button()
    icons["kite-launcher"] = launcher()
    return icons


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "status"
    os.makedirs(out, exist_ok=True)
    icons = build()
    for name, parts in icons.items():
        text = svg(*parts)
        # Symbolic variant (recoloured by GTK) and plain variant (light
        # grey, for programs that don't ask for symbolic icons; the shelf
        # is dark).
        with open(os.path.join(out, f"{name}-symbolic.svg"), "w") as fh:
            fh.write(text)
        with open(os.path.join(out, f"{name}.svg"), "w") as fh:
            fh.write(text.replace(FG, "#e8eaed"))
    print(f"{len(icons)} icons ({2 * len(icons)} files) written to {out}")


if __name__ == "__main__":
    main()
