#!/bin/bash
# Render the KiteOS desktop in a virtual screen and save screenshots of the
# desktop and of the open Start menu. Uses the XFCE and themes installed on the
# host plus the files from packages/kite-desktop (nothing is installed
# system-wide). For a true look, the host needs the Fluent theme; without it
# kite-layout falls back to Orchis.
#
#   tests/preview-ui.sh [output-dir]
#
# Needs: xvfb, xfwm4, xfce4-panel, xfdesktop4, xfce4-settings,
#        python3-gi, gir1.2-gtk-3.0, papirus-icon-theme, imagemagick, dbus-x11,
#        x11-xserver-utils
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$REPO/tests/out}
PKG=$REPO/packages/kite-desktop
RES=${KITE_PREVIEW_RES:-1366x768}
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Fake XDG dirs so the package's icons, wallpapers and launchers are found.
export XDG_CONFIG_DIRS=$PKG/etc/xdg:/etc/xdg
export XDG_DATA_DIRS=$PKG/usr/share:/usr/local/share:/usr/share
export PATH=$PKG/usr/bin:$PATH
export KITE_LAYOUT_DATA=$PKG/usr/share/kite/layouts

DISP=:57
layout=windows
export HOME=$WORK/home-$layout
mkdir -p "$HOME"
cp -a "$PKG/etc/skel/." "$HOME/"

Xvfb $DISP -screen 0 "${RES}x24" -nolisten tcp >"$WORK/xvfb-$layout.log" 2>&1 &
XVFB=$!
export DISPLAY=$DISP
sleep 1
# kite-user-init runs before XFCE, as it would from Xsession.d; it sets up
# the layout (kite-layout --first-login) and the wallpaper.
"$PKG/usr/lib/kite/desktop/kite-user-init"
sed -i "s#/usr/share/backgrounds/kite#$PKG/usr/share/backgrounds/kite#g" \
    "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"

eval "$(dbus-launch --sh-syntax)"
pids=""
xfsettingsd --replace >"$WORK/xfsettingsd-$layout.log" 2>&1 & pids="$pids $!"
sleep 1
xfwm4 --replace >"$WORK/xfwm4-$layout.log" 2>&1 & pids="$pids $!"
sleep 1
xfdesktop >"$WORK/xfdesktop-$layout.log" 2>&1 & pids="$pids $!"
xfce4-panel >"$WORK/panel-$layout.log" 2>&1 & pids="$pids $!"
sleep 5
# A window so the taskbar has something running.
xfce4-terminal --disable-server --geometry=90x24+180+120 >/dev/null 2>&1 & pids="$pids $!"
sleep 3
import -window root "$OUT/desktop-$layout.png"
echo "saved $OUT/desktop-$layout.png"
"$PKG/usr/lib/kite/desktop/kite-start" >/dev/null 2>&1 & pids="$pids $!"
sleep 2
import -window root "$OUT/menu-$layout.png"
echo "saved $OUT/menu-$layout.png"

# Only what this script started (never the user's own session).
# shellcheck disable=SC2086
kill $pids "$DBUS_SESSION_BUS_PID" 2>/dev/null || true
kill $XVFB 2>/dev/null || true
sleep 1

for f in "$WORK"/*.log; do
    if grep -qiE 'critical|error' "$f"; then
        echo "--- $(basename "$f")"; grep -iE 'critical|error' "$f" | head -5
    fi
done
