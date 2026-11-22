#!/bin/bash
# Render the KiteOS desktop and launcher in a virtual screen and save
# screenshots. Uses the XFCE installed on the build host plus the configs from
# packages/kite-desktop (nothing is installed system-wide).
#
#   tests/preview-ui.sh [output-dir]
#
# Needs: xvfb, xfwm4, xfce4-panel, xfdesktop4, xfce4-settings, rofi,
#        materia-gtk-theme, papirus-icon-theme, imagemagick, dbus-x11, x11-xserver-utils
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$REPO/tests/out}
PKG=$REPO/packages/kite-desktop
RES=${KITE_PREVIEW_RES:-1366x768}
mkdir -p "$OUT"
WORK=$(mktemp -d)
export HOME=$WORK/home
mkdir -p "$HOME"
cp -a "$PKG/etc/skel/." "$HOME/"
mkdir -p "$HOME/.local/share/rofi/themes"
cp "$PKG"/usr/share/rofi/themes/*.rasi "$HOME/.local/share/rofi/themes/"

# Fake XDG dirs so the package's icons, wallpaper and launcher are found.
export XDG_CONFIG_DIRS=$PKG/etc/xdg:/etc/xdg
export XDG_DATA_DIRS=$PKG/usr/share:/usr/local/share:/usr/share
export PATH=$PKG/usr/bin:$PATH

# The docklike plugin may not exist on the build host: swap it for the
# standard task list plus pinned launchers, for the preview only.
if [ ! -e /usr/share/xfce4/panel/plugins/docklike.desktop ]; then
    python3 - "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('<property name="plugin-3" type="string" value="docklike"/>',
 '''<property name="plugin-3" type="string" value="tasklist">
      <property name="show-labels" type="bool" value="false"/>
      <property name="flat-buttons" type="bool" value="true"/>
    </property>''')
open(p, "w").write(s)
PY
    echo "note: docklike not installed here, previewing with the task list plugin"
fi

# Wallpaper path in the skel config points at /usr/share; redirect it.
sed -i "s#/usr/share/backgrounds/kite#$PKG/usr/share/backgrounds/kite#g" \
    "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"

DISP=:57
Xvfb $DISP -screen 0 "${RES}x24" -nolisten tcp >"$WORK/xvfb.log" 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null || true; rm -rf "$WORK"' EXIT
export DISPLAY=$DISP
sleep 1

# kite-user-init runs before XFCE, as it would from Xsession.d.
"$PKG/usr/lib/kite/desktop/kite-user-init"
sed -i "s#/usr/share/backgrounds/kite#$PKG/usr/share/backgrounds/kite#g" \
    "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"

eval "$(dbus-launch --sh-syntax)"
trap 'kill $XVFB $DBUS_SESSION_BUS_PID 2>/dev/null || true; rm -rf "$WORK"' EXIT
xfsettingsd --replace >"$WORK/xfsettingsd.log" 2>&1 &
sleep 1
xfwm4 --replace >"$WORK/xfwm4.log" 2>&1 &
sleep 1
xfdesktop >"$WORK/xfdesktop.log" 2>&1 &
xfce4-panel >"$WORK/panel.log" 2>&1 &
sleep 5
# A couple of windows so the shelf has something running.
xfce4-terminal --geometry=90x24+180+120 >/dev/null 2>&1 &
sleep 3
import -window root "$OUT/desktop.png"
echo "saved $OUT/desktop.png"

kite-launcher >"$WORK/rofi.log" 2>&1 &
sleep 3
import -window root "$OUT/launcher.png"
echo "saved $OUT/launcher.png"
pkill -u "$(id -u)" -x rofi || true

for f in "$WORK"/*.log; do
    if grep -qiE 'critical|error' "$f"; then
        echo "--- $(basename "$f")"; grep -iE 'critical|error' "$f" | head -5
    fi
done
grep -c 'override' "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" >/dev/null &&
    echo "keyboard shortcuts generated: $(grep -c 'kite-launcher\|kite-overview' "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml") KiteOS bindings"
