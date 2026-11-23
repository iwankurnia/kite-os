#!/bin/bash
# shellcheck disable=SC1090,SC2016,SC2034  # tests source scripts dynamically and match literal ${...}
# Tests for the hibernation helper, keyboard map generator, splash builder,
# the user-init script and App Centre's helpers. Safe: works only inside a temp directory.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { echo "  ok   $*"; pass=$((pass + 1)); }
bad()  { echo "  FAIL $*"; fail=$((fail + 1)); }
check() { local msg=$1; shift; if "$@"; then ok "$msg"; else bad "$msg"; fi; }

echo "== kite-hibernate-setup helpers"
# shellcheck source=/dev/null
. "$REPO/packages/kite-system/usr/sbin/kite-hibernate-setup"
set +e
check "4 GB machine (3800 MiB visible) -> 4864 MiB swap" test "$(target_swap_mib 3800)" = 4864
check "8 GB machine -> 9216 MiB swap" test "$(target_swap_mib 8192)" = 9216
check "never below 2 GiB" test "$(target_swap_mib 512)" = 2048

sample='Filesystem type is: ef53
File size of /swapfile is 5100273664 (1245184 blocks of 4096 bytes)
 ext:     logical_offset:        physical_offset: length:   expected: flags:
   0:        0..    6143:     528384..    534527:   6144:            unwritten
   1:     6144..   38911:     536576..    569343:  32768:     534528: unwritten'
check "filefrag parser reads the first physical block" test "$(parse_filefrag_offset <<< "$sample")" = 528384

FSTAB=$T/fstab
printf 'UUID=1111-root / ext4 defaults,noatime 0 1\nUUID=AAAA /boot/efi vfat umask=0077 0 1\n/swapfile none swap sw 0 0\n' > "$FSTAB"
check "root UUID from fstab" test "$(root_uuid)" = 1111-root
check "root fs type from fstab" test "$(root_fstype)" = ext4
SWAPFILE=/swapfile ensure_fstab_swapfile
check "exactly one swapfile line" test "$(grep -c '^/swapfile ' "$FSTAB")" = 1
check "other fstab lines untouched" grep -q '^UUID=AAAA /boot/efi' "$FSTAB"

RESUME_CONF=$T/initramfs/resume
GRUB_DROPIN=$T/grub.d/kite-resume.cfg
write_resume_config 1111-root 528384 >/dev/null
check "initramfs RESUME written" grep -qx 'RESUME=UUID=1111-root' "$RESUME_CONF"
check "GRUB drop-in appends resume params" grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} resume=UUID=1111-root resume_offset=528384"' "$GRUB_DROPIN"
check "GRUB drop-in is valid shell and expands" test "$(GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'; . "$GRUB_DROPIN"; echo "$GRUB_CMDLINE_LINUX_DEFAULT")" = 'quiet splash resume=UUID=1111-root resume_offset=528384'

LOGIND_DROPIN=$T/logind/70.conf SLEEP_DROPIN=$T/sleep/70.conf UPOWER_CONF=$T/UPower.conf
printf '[UPower]\nCriticalPowerAction=HybridSleep\n' > "$UPOWER_CONF"
enable_hibernate_power_policy
check "lid -> suspend-then-hibernate" grep -qx 'HandleLidSwitch=suspend-then-hibernate' "$LOGIND_DROPIN"
check "UPower critical action -> Hibernate" grep -qx 'CriticalPowerAction=Hibernate' "$UPOWER_CONF"
check "logind drop-in sorts after the package default" test "$(printf '%s\n' 60-kite.conf 70-kite-hibernate.conf | sort | tail -n1)" = 70-kite-hibernate.conf

# Real swap file on this machine's file system (mkswap only, never swapon).
fs=$(stat -f -c %T "$T")
if [ "$fs" = "ext2/ext3" ] && command -v filefrag >/dev/null; then
    SWAPFILE=$T/swapfile
    create_swapfile 64 ext4 >/dev/null
    check "swap file created with swap signature" file_is_swap "$SWAPFILE"
    check "swap file is private (0600)" test "$(stat -c %a "$SWAPFILE")" = 600
    off=$(swapfile_offset "$SWAPFILE" ext4)
    check "resume offset is a positive number ($off)" test "$off" -gt 0
else
    echo "  skip swap file creation test (temp dir is on $fs, not ext4)"
fi
set -e

echo "== keyboard map generator"
GEN=$REPO/packages/kite-chromebook/usr/lib/kite/chromebook/kite-keyd-gen
echo "EA E7 91 92 94 95 A0 AE B0" > "$T/physmap"
python3 "$GEN" --physmap "$T/physmap" -o "$T/kite.conf"
check "Search tap opens launcher" grep -qx 'leftmeta = overload(meta, M-space)' "$T/kite.conf"
check "fullscreen key sends F11" grep -qx 'zoom = f11' "$T/kite.conf"
check "overview key sends Super+W" grep -qx 'scale = M-w' "$T/kite.conf"
check "Search + volume-up = F9 (9-key row)" bash -c "awk '/^\[meta\]/{m=1} m && /^volumeup = f9\$/{f=1} END{exit !f}' '$T/kite.conf'"
check "Search + Backspace = Delete" bash -c "awk '/^\[meta\]/{m=1} /^\[alt\]/{m=0} m && /^backspace = delete\$/{f=1} END{exit !f}' '$T/kite.conf'"
python3 "$GEN" --physmap /nonexistent -o "$T/default.conf"
check "falls back to the classic 10-key row" grep -q '^forward = forward' "$T/default.conf"
check "every section header is known to keyd" bash -c "! grep -E '^\[' '$T/kite.conf' | grep -vxE '\[(ids|main|meta|alt|control\+alt)\]'"

echo "== boot splash builder"
if [ -f /usr/share/plymouth/themes/spinner/spinner.plymouth ]; then
    "$REPO/packages/kite-system/usr/lib/kite/kite-plymouth-theme" /usr/share/plymouth/themes/spinner "$T/kite" \
        "$REPO/packages/kite-system/usr/share/kite/plymouth/watermark.png"
    check "theme file written" test -f "$T/kite/kite.plymouth"
    check "uses the copied images" grep -qx "ImageDir=$T/kite" "$T/kite/kite.plymouth"
    check "KiteOS logo in place" cmp -s "$T/kite/watermark.png" "$REPO/packages/kite-system/usr/share/kite/plymouth/watermark.png"
    check "animation frames copied (not linked)" bash -c "[ -f '$T/kite/throbber-0001.png' ] && [ ! -L '$T/kite/throbber-0001.png' ]"
    check "no duplicate keys" test "$(grep -c '^WatermarkVerticalAlignment=' "$T/kite/kite.plymouth")" = 1
else
    echo "  skip (plymouth-themes not installed here)"
fi

echo "== kite-layout (windows and mac desktops)"
KL=$REPO/packages/kite-desktop/usr/bin/kite-layout
LH=$T/layout; mkdir -p "$LH/themes/Fluent-Light/gtk-3.0" "$LH/themes/Fluent-Light/xfwm4" "$LH/apps"
for a in brave-browser thunar xfce4-terminal kite-apps; do touch "$LH/apps/$a.desktop"; done
echo mac > "$LH/system-layout"
kl() { env HOME="$LH/home" XDG_CONFIG_HOME="$LH/home/.config" DISPLAY= KITE_LAYOUT_DATA="$REPO/packages/kite-desktop/usr/share/kite/layouts" \
       KITE_LAYOUT_SYSTEM="$LH/system-layout" KITE_THEMES_DIR="$LH/themes" KITE_APPS_DIR="$LH/apps" python3 "$KL" "$@"; }
X=$LH/home/.config/xfce4/xfconf/xfce-perchannel-xml
kl --first-login
check "first login: system default layout (mac)" grep -qx mac "$LH/home/.config/kite/layout"
check "mac: menu bar + Dock (two panels)" grep -q '<property name="panel-2"' "$X/xfce4-panel.xml"
check "mac: missing Qogir theme falls back to Orchis" grep -q 'value="Orchis-Light-Compact"' "$X/xsettings.xml"
check "mac: window theme falls back to Default" grep -q 'name="theme" type="string" value="Default"' "$X/xfwm4.xml"
check "mac: KiteOS kite as the menu button" grep -qx 'button-icon=kiteos' "$LH/home/.config/xfce4/panel/whiskermenu-1.rc"
echo windows > "$LH/home/.config/kite/layout.keep"; kl --first-login
check "first login runs only once" grep -qx mac "$LH/home/.config/kite/layout"
kl windows >/dev/null
check "switch: windows recorded" grep -qx windows "$LH/home/.config/kite/layout"
check "windows: one taskbar" bash -c "! grep -q '<property name=\"panel-2\"' '$X/xfce4-panel.xml'"
check "windows: Fluent theme and tray pack" bash -c "grep -q 'value=\"Fluent-Light\"' '$X/xsettings.xml' && grep -q 'value=\"KiteOS-Tray-Windows\"' '$X/xsettings.xml'"
check "windows: buttons on the right" grep -q 'value="menu:minimize,maximize,close"' "$X/xsettings.xml"
check "no placeholders left" bash -c "! grep -rq '@[A-Z_]*@' '$LH/home/.config'"
check "nothing of the mac layout left (its launchers)" test ! -d "$LH/home/.config/xfce4/panel/launcher-4"
check "battery on the taskbar" grep -q 'value="power-manager-plugin"' "$X/xfce4-panel.xml"
check "Start menu offers shut down" grep -qx 'show-command-shutdown=true' "$LH/home/.config/xfce4/panel/whiskermenu-1.rc"
check "pins only installed apps, Brave first" grep -qx "pinned=$LH/apps/brave-browser.desktop;$LH/apps/thunar.desktop;$LH/apps/xfce4-terminal.desktop;$LH/apps/kite-apps.desktop;" "$LH/home/.config/xfce4/panel/docklike-20.rc"
check "Start menu favourites: installed apps only" grep -qx "favorites=brave-browser.desktop,thunar.desktop,xfce4-terminal.desktop,kite-apps.desktop" "$LH/home/.config/xfce4/panel/whiskermenu-1.rc"
touch "$LH/apps/kite-install.desktop"; kl windows >/dev/null
check "live session: Install KiteOS pinned first" grep -q "^pinned=$LH/apps/kite-install.desktop;" "$LH/home/.config/xfce4/panel/docklike-20.rc"
if [ -f /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml ]; then
    f=$X/xfce4-keyboard-shortcuts.xml
    check "shortcuts: Search key opens the Start menu" bash -c "xmllint --xpath \"//property[@name='commands']/property[@name='custom']/property[@name='<Super>space']/@value\" '$f' | grep -q xfce4-popup-whiskermenu"
    check "shortcuts: windows tiling keys" bash -c "xmllint --xpath \"//property[@name='xfwm4']/property[@name='custom']/property[@name='<Super>Left']/@value\" '$f' | grep -q tile_left_key"
    n_def=$(xmllint --xpath "count(//property[@name='commands']/property[@name='default']/property)" "$f")
    n_cus=$(xmllint --xpath "count(//property[@name='commands']/property[@name='custom']/property)" "$f")
    check "shortcuts: XFCE defaults kept ($n_def defaults, $n_cus custom)" test "${n_cus%.*}" -gt "${n_def%.*}"
else
    echo "  skip shortcut merge (xfce4-settings not installed here)"
fi
# Live switch with stand-ins: the session owns xfwm4, so kite-layout must never
# start one (v1.3.0 left no window manager); its settings go through xfconf.
mkdir -p "$LH/fake"
for c in xfce4-panel pkill xfconf-query xfsettingsd xfdesktop xfwm4; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$c" "$LH" > "$LH/fake/$c"; chmod 755 "$LH/fake/$c"
done
rm -f "$LH/calls"
env HOME="$LH/home" XDG_CONFIG_HOME="$LH/home/.config" XDG_CACHE_HOME="$LH/cache" DISPLAY=:99 PATH="$LH/fake:$PATH" \
    KITE_LAYOUT_DATA="$REPO/packages/kite-desktop/usr/share/kite/layouts" KITE_LAYOUT_SYSTEM="$LH/system-layout" \
    KITE_THEMES_DIR="$LH/themes" KITE_APPS_DIR="$LH/apps" python3 "$KL" mac >/dev/null
check "live switch: never starts a window manager" bash -c "! grep -q '^xfwm4' '$LH/calls'"
check "live switch: window theme set through xfconf" grep -q '^xfconf-query -c xfwm4 -p /general/theme -n -t string -s Default' "$LH/calls"
check "live switch: mac buttons on the left through xfconf" grep -q '^xfconf-query -c xfwm4 -p /general/button_layout -n -t string -s CHM|' "$LH/calls"
check "live switch: panel quit, then started again" bash -c "grep -n '^xfce4-panel' '$LH/calls' | tr '\n' ' ' | grep -q 'xfce4-panel --quit.*xfce4-panel *\$\|xfce4-panel --quit .*:xfce4-panel '"
check "live switch: settings daemon reloads (shortcuts, theme)" grep -q '^xfsettingsd --replace' "$LH/calls"
# A switch keeps the user's own Files/Terminal settings and fonts.
echo '<channel name="thunar" version="1.0"><property name="mine" type="bool" value="true"/></channel>' > "$X/thunar.xml"
sed -i.bak 's/value="Inter 10"/value="Ubuntu 12"/' "$X/xsettings.xml" && rm -f "$X/xsettings.xml.bak"
kl mac >/dev/null
check "switch keeps the user's Files settings" grep -q 'name="mine"' "$X/thunar.xml"
check "switch keeps the user's font" grep -q 'value="Ubuntu 12"' "$X/xsettings.xml"
check "cursor size is an XSETTINGS key (Gtk/CursorThemeSize)" bash -c "python3 -c 'import sys, xml.etree.ElementTree as E; r = E.parse(sys.argv[1]).getroot(); sys.exit(0 if r.find(\"./property[@name=\x27Gtk\x27]/property[@name=\x27CursorThemeSize\x27]\") is not None and r.find(\"./property[@name=\x27Net\x27]/property[@name=\x27CursorThemeSize\x27]\") is None else 1)' '$X/xsettings.xml'"
check "window theme follows the GTK theme (fallback: Default)" grep -q 'name="theme" type="string" value="Default"' "$X/xfwm4.xml"
kl windows >/dev/null
# Window keys: one key per action (xfwm4 ignores a second key for an action),
# ChromeOS keys on a Chromebook, the layout's own keys elsewhere.
SX=$LH/xdg/xfce4/xfconf/xfce-perchannel-xml; mkdir -p "$SX" "$LH/dmi"
cat > "$SX/xfce4-keyboard-shortcuts.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty"><property name="default" type="empty">
    <property name="&lt;Alt&gt;F2" type="string" value="xfce4-appfinder --collapsed"/>
  </property></property>
  <property name="xfwm4" type="empty"><property name="default" type="empty">
    <property name="&lt;Alt&gt;F4" type="string" value="close_window_key"/>
    <property name="&lt;Alt&gt;Tab" type="string" value="cycle_windows_key"/>
    <property name="&lt;Alt&gt;F9" type="string" value="hide_window_key"/>
    <property name="&lt;Alt&gt;F10" type="string" value="maximize_window_key"/>
    <property name="&lt;Primary&gt;&lt;Alt&gt;d" type="string" value="show_desktop_key"/>
    <property name="&lt;Super&gt;KP_Left" type="string" value="tile_left_key"/>
  </property></property>
</channel>
XML
klk() { env XDG_CONFIG_DIRS="$LH/xdg" KITE_DMI_DIR="$LH/dmi" HOME="$LH/home" XDG_CONFIG_HOME="$LH/home/.config" DISPLAY= KITE_LAYOUT_DATA="$REPO/packages/kite-desktop/usr/share/kite/layouts" \
        KITE_LAYOUT_SYSTEM="$LH/system-layout" KITE_THEMES_DIR="$LH/themes" KITE_APPS_DIR="$LH/apps" python3 "$KL" "$@"; }
wk() { python3 -c 'import sys, xml.etree.ElementTree as E; r = E.parse(sys.argv[1]).getroot(); print("\n".join(p.get("name") for p in r.findall("./property[@name=\x27xfwm4\x27]/property[@name=\x27custom\x27]/property") if p.get("value") == sys.argv[2]))' "$X/xfce4-keyboard-shortcuts.xml" "$1"; }
echo "Generic" > "$LH/dmi/sys_vendor"; rm -f "$LH/home/.config/kite/keys"
klk mac >/dev/null
check "keys (not a Chromebook, mac): Super+Q closes, Alt+F4 no longer bound" test "$(wk close_window_key)" = "<Super>q"
check "keys (mac): Super+Tab is the only switch key" test "$(wk cycle_windows_key)" = "<Super>Tab"
klk windows >/dev/null
check "keys (windows): Super+Left tiles, the keypad key is gone" test "$(wk tile_left_key)" = "<Super>Left"
check "keys (windows): Alt+F4 still closes" test "$(wk close_window_key)" = "<Alt>F4"
echo "Google" > "$LH/dmi/sys_vendor"
klk mac >/dev/null
check "keys (Chromebook detected): ChromeOS close key, one key only" test "$(wk close_window_key)" = "<Primary><Shift>w"
check "keys (Chromebook): Alt+Tab switches in the mac layout too" test "$(wk cycle_windows_key)" = "<Alt>Tab"
check "keys (Chromebook): Alt+[ docks left" test "$(wk tile_left_key)" = "<Alt>bracketleft"
klk keys standard >/dev/null
check "keys: choosing standard on a Chromebook is kept" bash -c "grep -qx standard '$LH/home/.config/kite/keys'"
check "keys: standard on a Chromebook gives the mac keys" test "$(wk close_window_key)" = "<Super>q"
klk keys auto >/dev/null
check "keys: auto goes back to detection" bash -c "test ! -e '$LH/home/.config/kite/keys'"
check "keys: auto on a Chromebook gives the ChromeOS keys again" test "$(wk close_window_key)" = "<Primary><Shift>w"
check "keys: no action has two keys" bash -c "python3 -c 'import sys, xml.etree.ElementTree as E, collections; r = E.parse(sys.argv[1]).getroot(); v = [p.get(\"value\") for p in r.findall(\"./property[@name=\x27xfwm4\x27]/property[@name=\x27custom\x27]/property\") if p.get(\"type\") == \"string\"]; d = [k for k, n in collections.Counter(v).items() if n > 1]; sys.exit(1 if d else 0)' '$X/xfce4-keyboard-shortcuts.xml'"
kl --system windows >/dev/null
check "--system sets the default for new accounts" grep -qx windows "$LH/system-layout"
check "rejects unknown layouts" bash -c "! python3 '$KL' gnome 2>/dev/null"
check "default for the live USB is windows" grep -qx windows "$REPO/packages/kite-desktop/etc/kite/layout"
check "installer: the Desktop choice reaches kite-layout (Calamares 3.3 key = packagechooser_<instance id>)" bash -c "id=\$(grep -oE 'packagechooser@[A-Za-z0-9_-]+' '$REPO/live/config/includes.chroot/etc/calamares/settings.conf' | head -n1 | cut -d@ -f2); grep -q \"^packagechooser_\$id:\" '$REPO/live/config/includes.chroot/etc/calamares/modules/contextualprocess-kite-layout.conf'"
check "login screen uses a light theme" bash -c "grep -q \"theme-name='Fluent-Light'\" '$REPO/packages/kite-desktop/usr/share/glib-2.0/schemas/90_kite-slick-greeter.gschema.override' && ! grep -qi dark '$REPO/packages/kite-desktop/usr/share/glib-2.0/schemas/90_kite-slick-greeter.gschema.override'"
check "installer offers both layouts" bash -c "grep -q 'id: windows' '$REPO/live/config/includes.chroot/etc/calamares/modules/packagechooser-kite-layout.conf' && grep -q 'mac: \"/usr/bin/kite-layout --system mac\"' '$REPO/live/config/includes.chroot/etc/calamares/modules/contextualprocess-kite-layout.conf'"

echo "== kite-login-theme (login screen background)"
LT=$REPO/packages/kite-desktop/usr/bin/kite-login-theme; G=$T/greeter/slick-greeter.conf
check "default is frosted" bash -c "KITE_GREETER_CONF='$G' sh '$LT' | grep -q 'frosted (default)'"
KITE_GREETER_CONF=$G sh "$LT" aurora >/dev/null
check "new file gets a [Greeter] background, marked as ours" test "$(cat "$G")" = "$(printf '# Written by kite-login-theme (removed when kite-desktop is purged)\n[Greeter]\nbackground=/usr/share/backgrounds/kite/login-aurora.jpg')"
KITE_GREETER_CONF=$G sh "$LT" dusk >/dev/null
check "marker kept, written once" test "$(grep -c '^# Written by kite-login-theme' "$G")" = 1
# kite-desktop's postrm, pointed at a test copy of the greeter file
DPR=$T/greeter/postrm; sed "s#/etc/lightdm/slick-greeter.conf#$G#" "$REPO/packages/kite-desktop/DEBIAN/postrm" > "$DPR"
sh "$DPR" purge
check "purge removes the greeter file kite-login-theme wrote" test ! -e "$G"
printf '[Greeter]\ntheme-name=X\nbackground=/old.png\n[Other]\nbackground=keep\n' > "$G"; KITE_GREETER_CONF=$G sh "$LT" dusk >/dev/null
check "replaces only the greeter's background" test "$(cat "$G")" = "$(printf '[Greeter]\ntheme-name=X\nbackground=/usr/share/backgrounds/kite/login-dusk.jpg\n[Other]\nbackground=keep')"
sh "$DPR" purge
check "purge keeps a greeter file someone else wrote" test -s "$G"
printf '[Greeter]\ntheme-name=X\n[Other]\na=1\n' > "$G"; KITE_GREETER_CONF=$G sh "$LT" frosted >/dev/null
check "adds it to an existing [Greeter]" test "$(sed -n 3p "$G")" = background=/usr/share/backgrounds/kite/login-frosted.jpg
check "reports the current one" bash -c "KITE_GREETER_CONF='$G' sh '$LT' | grep -q 'login screen: frosted$'"
check "rejects unknown names" bash -c "! KITE_GREETER_CONF='$G' sh '$LT' sunset 2>/dev/null"
check "all three login images ship" bash -c "for l in frosted aurora dusk; do [ -s '$REPO/packages/kite-desktop/usr/share/backgrounds/kite/login-'\$l.jpg ] || exit 1; done"
check "all three wallpapers ship, Bloom by default" bash -c "for w in bloom aurora waves; do [ -s '$REPO/packages/kite-desktop/usr/share/backgrounds/kite/'\$w.jpg ] || exit 1; done; grep -q 'kite/bloom.jpg' '$REPO/packages/kite-desktop/usr/lib/kite/desktop/kite-user-init'"
check "greeter default is frosted" grep -q "login-frosted.jpg" "$REPO/packages/kite-desktop/usr/share/glib-2.0/schemas/90_kite-slick-greeter.gschema.override"
check "postinst looks for Brave itself, not the KiteOS wrapper" bash -c "! grep -q '\[ -x /usr/bin/brave-browser-stable \]' '$REPO/packages/kite-desktop/DEBIAN/postinst' && grep -q '/usr/bin/brave-browser-stable.distrib' '$REPO/packages/kite-desktop/DEBIAN/postinst'"

echo "== Brave flags wrapper"
W=$REPO/packages/kite-desktop/usr/bin/brave-browser-stable
mkdir -p "$T/brave/cfg"
printf '#!/bin/sh\nfor a in "$@"; do echo "$a"; done\n' > "$T/brave/launcher"; chmod 755 "$T/brave/launcher"
brave() { env KITE_BRAVE_LAUNCHER="$T/brave/launcher" XDG_CONFIG_HOME="$T/brave/cfg" "$@"; }
out=$(brave KITE_BRAVE_FLAGS="$REPO/packages/kite-desktop/etc/kite/brave-flags.conf" sh "$W" 'https://example.org/?a=1&b=*')
check "KiteOS default enables hardware video decoding" grep -qx -- '--enable-features=AcceleratedVideoDecodeLinuxGL' <<< "$out"
check "commented-out flags are ignored" test -z "$(grep ZeroCopy <<< "$out")"
check "arguments passed on unchanged (no glob expansion)" test "$(tail -n1 <<< "$out")" = 'https://example.org/?a=1&b=*'
printf -- '--enable-features=A,B  # system\n--ozone-platform=x11\n' > "$T/brave/system.conf"
printf -- '# mine\n--enable-features=C --disable-features=D\n\n--disable-features=E\n' > "$T/brave/cfg/brave-flags.conf"
out=$(brave KITE_BRAVE_FLAGS="$T/brave/system.conf" sh "$W" --incognito)
check "feature lists merged into one switch" test "$(grep -c -- '^--enable-features=' <<< "$out")" = 1
check "system then user features kept" grep -qx -- '--enable-features=A,B,C' <<< "$out"
check "disable-features merged too" grep -qx -- '--disable-features=D,E' <<< "$out"
check "other flags kept" grep -qx -- '--ozone-platform=x11' <<< "$out"
check "own arguments come last" test "$(tail -n1 <<< "$out")" = --incognito
out=$(brave KITE_BRAVE_FLAGS=/nonexistent XDG_CONFIG_HOME=/nonexistent sh "$W" x)
check "no flag files: arguments only" test "$out" = x

echo "== kite-vivid (screen saturation)"
V=$REPO/packages/kite-desktop/usr/bin/kite-vivid
# xrandr (Debian 13) takes CTM as 9 decimal matrix values and encodes them itself;
# pre-encoded S31.32 integers were read as huge coefficients (white screen, v1.2).
check "level 1.0 is the identity matrix" test "$(python3 "$V" --print-ctm 1.0)" = \
    1.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,1.000000
check "level 1.2 matrix" test "$(python3 "$V" --print-ctm 1.2)" = \
    1.157480,-0.143040,-0.014440,-0.042520,1.056960,-0.014440,-0.042520,-0.143040,1.185560
check "CTM is 9 values, none above 2 (never pre-encoded integers)" python3 -c "
v=[float(x) for x in '$(python3 "$V" --print-ctm 2.0)'.split(',')]
assert len(v) == 9 and all(abs(x) <= 2 for x in v)"
check "greys stay grey (each row sums to 1)" python3 -c "
s=1.3; W=(0.2126,0.7152,0.0722)
assert all(abs(sum(s*(i==j)+(1-s)*W[j] for j in range(3))-1) < 1e-9 for i in range(3))"
check "system default is 1.2" grep -qx 'SATURATION=1.2' "$REPO/packages/kite-desktop/etc/kite/display.conf"
mkdir -p "$T/vivid"; PY=$(command -v python3)    # PATH below hides xrandr, so call python by path
env XDG_CONFIG_HOME="$T/vivid" PATH=/nonexistent "$PY" "$V" off >/dev/null 2>&1 || true
check "kite-vivid off saves 1.0 for the user" grep -qx 'SATURATION=1.0' "$T/vivid/kite/vivid.conf"
check "login run without xrandr exits quietly" env XDG_CONFIG_HOME="$T/vivid" PATH=/nonexistent "$PY" "$V"
check "rejects out-of-range levels" bash -c "! python3 '$V' 5 2>/dev/null"
# A fake xrandr: built-in screen with CTM, plus an external screen to leave alone.
mkdir -p "$T/vivid/bin"
cat > "$T/vivid/bin/xrandr" <<EOF
#!/bin/sh
if [ "\$1" = --prop ]; then
    printf 'Screen 0: minimum 320 x 200, current 1366 x 768\n'
    printf 'eDP-1 connected primary 1366x768+0+0 (normal left inverted right) 256mm x 144mm\n'
    printf '\tEDID: \n\t\t00ffffffffffff00\n\tCTM: 0 1 0 0 0 0 0 0 0 1 0 0 0 0 0 0 \n\t\t0 1 \n'
    printf '   1366x768      60.00*+\n'
    printf 'HDMI-1 connected 1920x1080+1366+0 (normal) 510mm x 290mm\n'
    printf '\tCTM: 0 1 0 0 0 0 0 0 0 1 0 0 0 0 0 0 \n\t\t0 1 \n'
else
    echo "\$*" >> "$T/vivid/calls"
fi
EOF
chmod 755 "$T/vivid/bin/xrandr"
env XDG_CONFIG_HOME="$T/vivid" PATH="$T/vivid/bin:$PATH" python3 "$V" 1.3 >/dev/null
check "sets CTM on the built-in screen" grep -q '^--output eDP-1 --set CTM 1.236220,-0.214560,' "$T/vivid/calls"
check "leaves external screens alone" bash -c "! grep -q HDMI '$T/vivid/calls'"
check "new level saved" grep -qx 'SATURATION=1.3' "$T/vivid/kite/vivid.conf"

echo "== KiteOS drive icons"
D=$REPO/packages/kite-desktop/usr/share/icons/KiteOS/scalable/devices
for n in drive-harddisk-solidstate-sdio drive-removable-media-flash-mmc media-removable drive-harddisk-system drive; do
    check "$n (and -symbolic) -> Papirus 16 px drive" bash -c "[ \"\$(readlink '$D/$n.svg')\" = /usr/share/icons/Papirus/16x16/devices/drive-harddisk.svg ] && [ \"\$(readlink '$D/$n-symbolic.svg')\" = /usr/share/icons/Papirus/16x16/devices/drive-harddisk.svg ]"
done
check "devices folder declared in index.theme" grep -q '^Directories=.*scalable/devices' "$REPO/packages/kite-desktop/usr/share/icons/KiteOS/index.theme"

echo "== kite-update (KiteOS packages from GitHub releases)"
KU=$REPO/packages/kite-system/usr/bin/kite-update
ku_py() { python3 - "$KU" <<PYEOF
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ku", sys.argv[1])
spec = importlib.util.spec_from_loader("ku", loader); ku = importlib.util.module_from_spec(spec); loader.exec_module(ku)
from itertools import zip_longest
def vkey(v): return [int(x) for x in v.split(".")]
newer = lambda a, b: vkey(a) > vkey(b)          # dpkg isn't available everywhere the tests run
installed = {"kite-system": "1.0.0", "kite-desktop": "1.1.5", "kite-storage": "1.0.0"}.get
release = {"tag_name": "v1.3", "assets": [
    {"name": "kiteos-1.3-amd64.iso"}, {"name": "kite-packages.sha256"},
    {"name": "kite-system_1.1.0_all.deb"}, {"name": "kite-desktop_1.1.5_all.deb"},
    {"name": "kite-storage_0.9.0_all.deb"}, {"name": "kite-chromebook_1.0.0_all.deb"}]}
$1
PYEOF
}
check "offers only installed packages with a newer version" ku_py \
    'assert [(p, h, v) for p, h, v, _ in ku.plan(release, installed, newer)] == [("kite-system", "1.0.0", "1.1.0")]'
check "nothing to do when up to date" ku_py \
    'assert ku.plan(release, {"kite-system": "1.1.0"}.get, newer) == []'
check "reads the release checksum list" ku_py \
    'assert ku.checksums("a" * 64 + "  kite-system_1.1.0_all.deb" + chr(10) + "junk line") == {"kite-system_1.1.0_all.deb": "a" * 64}'
check "update source is the KiteOS repository" grep -qx 'REPO=iwankurnia/kite-os' "$REPO/packages/kite-system/etc/kite/update.conf"
check "rejects unknown options" bash -c "! python3 '$KU' --bogus 2>/dev/null"
ku_drop='
import contextlib, io, urllib.error
release["assets"] = [dict(a, browser_download_url="https://x/" + a["name"]) for a in release["assets"]]
ku.plan = lambda r: [("kite-system", "1.0.0", "1.1.0", r["assets"][2])]
ku.os.geteuid = lambda: 0
def run(fail_on):
    def fetch(url, binary=False):
        if url.startswith("https://api."): return __import__("json").dumps(release)
        if url.endswith(fail_on): raise urllib.error.URLError(ConnectionResetError("connection reset"))
        return "a" * 64 + "  kite-system_1.1.0_all.deb"
    ku.fetch = fetch; err = io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
        rc = ku.main([])
    last = err.getvalue().splitlines()[-1]
    assert rc == 1 and last.startswith("Could not reach the KiteOS releases on GitHub: "), (rc, last)
'
check "dropped connection on the checksum list: one plain line, exit 1" ku_py "$ku_drop"'run(".sha256")'
check "dropped connection on a package: one plain line, exit 1" ku_py "$ku_drop"'run(".deb")'

echo "== kite-resource-report options"
RR=$REPO/packages/kite-system/usr/bin/kite-resource-report
for a in "--seconds 0" "--seconds abc" "--seconds=-3" "--seconds" "--bogus"; do
    check "rejects '$a' with usage and status 2" bash -c "bash '$RR' $a >/dev/null 2>'$T/rr.err'; [ \$? = 2 ] && grep -q 'kite-resource-report \\[--seconds N\\]' '$T/rr.err'"
done
check "--help prints only the comment block" bash -c "bash '$RR' --help | grep -q 'sudo kite-resource-report' && ! bash '$RR' --help | grep -q 'set -'"
check "no rofi or light-locker left (KiteOS 1.3 has neither)" bash -c "! grep -qE 'rofi|light-locker' '$RR'"

echo "== maintainer scripts (kite-system, kite-chromebook)"
mkdir -p "$T/mnt/bin" "$T/mnt/etc/default/grub.d" "$T/mnt/var/lib/kite/chromebook"
for c in systemctl update-grub update-alternatives; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/mnt/calls"\n' "$c" "$T" > "$T/mnt/bin/$c"; chmod 755 "$T/mnt/bin/$c"
done
mnt() { env PATH="$T/mnt/bin:$PATH" sh "$@"; }
SP=$REPO/packages/kite-system/DEBIAN
mnt "$SP/prerm" upgrade
check "kite-system prerm: upgrade leaves the units enabled" test ! -e "$T/mnt/calls"
mnt "$SP/prerm" remove
check "kite-system prerm: remove disables zswap and first-boot hibernation" bash -c "grep -qx 'systemctl disable kite-zswap.service' '$T/mnt/calls' && grep -qx 'systemctl disable kite-hibernate-firstboot.service' '$T/mnt/calls'"
sed -e "s#/etc/#$T/mnt/etc/#g" -e "s#/usr/share/plymouth/#$T/mnt/plymouth/#g" "$SP/postrm" > "$T/mnt/system-postrm"
: > "$T/mnt/calls"; mnt "$T/mnt/system-postrm" purge
check "kite-system purge without a resume drop-in skips update-grub" bash -c "! grep -q update-grub '$T/mnt/calls'"
touch "$T/mnt/etc/default/grub.d/kite-resume.cfg"; mnt "$T/mnt/system-postrm" purge
check "kite-system purge drops the resume drop-in and runs update-grub" bash -c "[ ! -e '$T/mnt/etc/default/grub.d/kite-resume.cfg' ] && grep -qx 'update-grub ' '$T/mnt/calls'"
CP=$REPO/packages/kite-chromebook/DEBIAN
check "kite-chromebook prerm no longer waits for a purge dpkg never sends" bash -c "! grep -v '^#' '$CP/prerm' | grep -q purge"
sed -e "s#/etc/#$T/mnt/etc/#g" -e "s#/var/lib/kite/#$T/mnt/var/lib/kite/#g" "$CP/postrm" > "$T/mnt/cb-postrm"
touch "$T/mnt/var/lib/kite/chromebook/ucm-files.list"; mnt "$T/mnt/cb-postrm" purge
check "kite-chromebook purge keeps UCM backups still to restore" test -e "$T/mnt/var/lib/kite/chromebook/ucm-files.list"
rm "$T/mnt/var/lib/kite/chromebook/ucm-files.list"; mnt "$T/mnt/cb-postrm" purge
check "kite-chromebook purge removes its state folder" test ! -e "$T/mnt/var/lib/kite/chromebook"

echo "== kite-app-centre (App Centre helpers; no GTK or display needed)"
AC=$REPO/packages/kite-storage/usr/bin/kite-app-centre
ac_py() { KITE_NO_GTK=1 python3 - "$AC" <<PYEOF
import importlib.machinery, importlib.util, json, sys
loader = importlib.machinery.SourceFileLoader("ac", sys.argv[1])
spec = importlib.util.spec_from_loader("ac", loader); ac = importlib.util.module_from_spec(spec); loader.exec_module(ac)
G = 1024 ** 3
status = """External disk:
  UUID 1234-abcd  mount /mnt/kite-external  (connected)
   Size  Used Avail
    58G  3.4G   52G
Internal disk:
   Size  Used Avail
    29G   20G  7.8G
On the external disk:
  app   gimp                         -          /usr/lib/gimp  [ok]
  data  gimp                         iwan       /home/iwan/.config/GIMP  [ok]
  data  brave-browser                other      /home/other/.config/BraveSoftware  [ok]
  data  folder                       iwan       /home/iwan/My Videos  [disk missing]
  data  folder                       -          /srv/media  [ok]
"""
$1
PYEOF
}
check "loads without GTK" ac_py 'assert ac.Gtk is None and ac.WM_CLASS == "kite-apps"'
check "status: external disk connected" ac_py \
    'e = ac.parse_status(status)["external"]; assert e == {"configured": True, "connected": True, "uuid": "1234-abcd", "mount": "/mnt/kite-external"}, e'
check "status: moved entries, path with a space and state kept" ac_py \
    'm = ac.parse_status(status)["moved"]; assert len(m) == 5; assert m[3] == {"kind": "data", "pkg": "folder", "user": "iwan", "path": "/home/iwan/My Videos", "state": "disk missing"}, m[3]; assert m[0]["user"] == ""'
check "status: not set up, nothing moved" ac_py \
    'r = ac.parse_status("External disk:\n  not set up (run: sudo kite-storage setup /dev/sdXN)\nInternal disk:\n   Size\nOn the external disk:\n  nothing yet\n"); assert r == {"external": {"configured": False, "connected": False, "uuid": "", "mount": ""}, "moved": []}, r'
check "badges: apps on the external disk (other people's data ignored)" ac_py \
    'm = ac.moved_apps(ac.parse_status(status)["moved"], "iwan"); assert m == {"gimp": {"app", "data"}}, m'
check "moved folders: own and system-wide ones" ac_py \
    'f = [e["path"] for e in ac.moved_folders(ac.parse_status(status)["moved"], "iwan")]; assert f == ["/home/iwan/My Videos", "/srv/media"], f'
check "storage.conf parsed like the shell does" ac_py \
    'c = ac.parse_shell_conf("# Written by kite-storage setup\nEXT_UUID=abc\nEXT_MOUNT=\"/mnt/x y\"\nexport EXT_FSTYPE=ext4\nbad line\n"); assert c == {"EXT_UUID": "abc", "EXT_MOUNT": "/mnt/x y", "EXT_FSTYPE": "ext4"}, c'
check "external disk state: none / missing / ready" ac_py \
    'assert ac.external_state({}) == "none"; assert ac.external_state({"EXT_UUID": "a"}, lambda p: False) == "missing"; assert ac.external_state({"EXT_UUID": "a"}, lambda p: p == "/mnt/kite-external/kite/.kite-storage") == "ready"'
check "df -B1 output parsed" ac_py \
    'd = ac.parse_df("1B-blocks Used Avail Mounted on\n31138512896 21582062387 8000000000 /\n62277025792 3650722201 55000000000 /mnt/kite-external\n"); assert d["/"] == (31138512896, 21582062387, 8000000000) and "/mnt/kite-external" in d, d'
check "sidebar: each disk's figure under its own bar" ac_py \
    'c = ac.sidebar_lines((29 * G, int(20.1 * G) + 1, 8 * G), "ready", (58 * G, int(3.4 * G) + 1, 52 * G)); assert c == ("20.1 of 29 GB", "3.4 of 58 GB"), c'
check "sidebar: external not set up / not connected (never the internal figure)" ac_py \
    'assert ac.sidebar_lines((29 * G, 20 * G, 9 * G), "none", None) == ("20.0 of 29 GB", "Not set up"); assert ac.sidebar_lines(None, "missing", None) == ("Unknown", "Not connected")'
check "usage bar uses used / (used + free), like df" ac_py \
    'assert ac.used_fraction((100, 30, 30)) == 0.5 and ac.used_fraction((0, 0, 0)) == 0.0'
check "apt-cache search: exact, then prefix, then the rest; installed marked" ac_py \
    'r = ac.parse_apt_search("libgimp2.0 - libraries for GIMP\ngimp-data - data files for GIMP\ngimp - GNU Image Manipulation Program\nbroken line\n", "GIMP", {"gimp-data"}); assert [(x["name"], x["installed"]) for x in r] == [("gimp", False), ("gimp-data", True), ("libgimp2.0", False)], r; assert r[0]["summary"] == "GNU Image Manipulation Program"'
check "apt-cache search: at most 300 results" ac_py \
    'assert len(ac.parse_apt_search("".join("p%d - x\n" % i for i in range(400)), "p")) == 300'
check "Discover: help, translations, data and libraries hidden, apps kept" ac_py \
    'rows = [{"name": n} for n in ("gimp", "gimp-data", "gimp-data-extras", "gimp-help-ca", "gimp-help-common", "libgimp2.0", "libreoffice-writer", "libreoffice-l10n-id", "python3-gimp", "gimp-plugin-registry")]; a, t = ac.split_results(rows, "gimp"); assert [r["name"] for r in a] == ["gimp", "libreoffice-writer", "gimp-plugin-registry"], a; assert len(t) == 7, t'
check "Discover: an exact or only-technical search still shows them" ac_py \
    'a, t = ac.split_results([{"name": "libgimp2.0"}], "libgimp2.0"); assert [r["name"] for r in a] == ["libgimp2.0"] and t == []; a, t = ac.split_results([{"name": "libfoo1"}, {"name": "libfoo-dev"}], "foo"); assert len(a) == 2 and t == []'
check "Updates: friendly error, not the raw SSL text" ac_py \
    'm = ac.friendly_update_error("Could not reach the KiteOS releases on GitHub: <urlopen error [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed>"); assert "secure connection" in m and "SSL" not in m, m; assert "online" in ac.friendly_update_error("Could not reach the KiteOS releases on GitHub: timed out"); assert ac.friendly_update_error("") == "Could not check for KiteOS updates."'
check "dpkg-query -W: installed packages (held too, removed ones not)" ac_py \
    'assert ac.parse_installed("ii \tgimp\nrc \told\nhi \theld\nun \tnever\n") == {"gimp", "held"}'
check "apt list --upgradable parsed" ac_py \
    'r = ac.parse_upgradable("Listing...\nfirefox-esr/stable-security 128.5.0esr-1~deb13u1 amd64 [upgradable from: 128.4.0esr-1~deb13u1]\nbrave-browser/stable 1.73.97 amd64 [upgradable from: 1.73.91]\n"); assert [(x["name"], x["version"], x["old"]) for x in r] == [("firefox-esr", "128.5.0esr-1~deb13u1", "128.4.0esr-1~deb13u1"), ("brave-browser", "1.73.97", "1.73.91")], r; assert r[0]["suite"] == "stable-security"'
check "kite-update --check: up to date" ac_py \
    'assert ac.parse_kite_update_check("KiteOS is up to date (latest release v1.2.4).\n", 0) == {"state": "current", "tag": "v1.2.4", "packages": [], "message": ""}'
check "kite-update --check: updates listed" ac_py \
    'r = ac.parse_kite_update_check("Updates in KiteOS v1.3:\n  kite-desktop     1.1.5 -> 1.2.0\n  kite-storage     1.0.0 -> 1.1.0\n", 0); assert r["state"] == "updates" and r["tag"] == "v1.3" and r["packages"] == [("kite-desktop", "1.1.5", "1.2.0"), ("kite-storage", "1.0.0", "1.1.0")], r'
check "kite-update --check: offline is an error with the reason" ac_py \
    'r = ac.parse_kite_update_check("Could not reach the KiteOS releases on GitHub: timed out\n", 1); assert r["state"] == "error" and "timed out" in r["message"], r'
check "launchers: hidden and settings dialogs are not apps" ac_py \
    'assert ac.launcher_visible("[Desktop Entry]\nName=GIMP\nCategories=Graphics;\n"); assert not ac.launcher_visible("[Desktop Entry]\nNoDisplay=true\n"); assert not ac.launcher_visible("[Desktop Entry]\nCategories=GTK;Settings;\n")'
check "desktop entry: main group only" ac_py \
    'e = ac.parse_desktop_entry("[Desktop Entry]\nName=Files\nComment=Browse\nIcon=org.xfce.thunar\n[Desktop Action New]\nName=New window\n"); assert e == {"Name": "Files", "Comment": "Browse", "Icon": "org.xfce.thunar"}, e'
check "dpkg-query -S: shared files, arch suffix, diversions" ac_py \
    'r = ac.parse_dpkg_search("gimp: /usr/share/applications/gimp.desktop\nlibreoffice-writer, libreoffice-core: /x.desktop\nthunar:amd64: /usr/share/applications/thunar.desktop\ndiversion by kite-desktop from: /y.desktop\n"); assert r == [("gimp", "/usr/share/applications/gimp.desktop"), ("libreoffice-writer", "/x.desktop"), ("thunar", "/usr/share/applications/thunar.desktop")], r'
check "installed apps: desktop parts hidden, launcher named after the package wins" ac_py '
A = "/usr/share/applications/"
owners = [("thunar", A + "thunar-bulk-rename.desktop"), ("thunar", A + "thunar.desktop"), ("kite-desktop", A + "kite-x.desktop"),
          ("xfce4-terminal", A + "xfce4-terminal.desktop"), ("vlc", A + "vlc.desktop"), ("ghost", A + "ghost.desktop")]
entries = {A + "thunar-bulk-rename.desktop": {"Name": "Bulk Rename"}, A + "thunar.desktop": {"Name": "Files", "Comment": "Browse"},
           A + "kite-x.desktop": {"Name": "X"}, A + "xfce4-terminal.desktop": {"Name": "Terminal"}, A + "vlc.desktop": {"Name": "VLC media player", "GenericName": "Media player", "Icon": "vlc"}}
r = ac.pick_installed_apps(owners, entries)
assert [(a["pkg"], a["name"], a["summary"]) for a in r] == [("thunar", "Files", "Browse"), ("vlc", "VLC media player", "Media player")], r'
check "apt-get -s remove: packages that would go" ac_py \
    'assert ac.parse_simulated_removal("NOTE: This is only a simulation!\nRemv gimp [2.10.38-1]\nRemv gimp-data [2.10.38-1]\n") == ["gimp", "gimp-data"]'
check "set-up partitions: unpluggable disks only, never the system disk or live stick" ac_py '
j = json.dumps({"blockdevices": [
    {"name": "/dev/mmcblk0", "size": "29G", "fstype": None, "label": None, "type": "disk", "pkname": None, "tran": None, "rm": False, "hotplug": False},
    {"name": "/dev/mmcblk0p2", "size": "28G", "fstype": "ext4", "label": None, "type": "part", "pkname": "/dev/mmcblk0"},
    {"name": "/dev/mmcblk1", "size": "64G", "fstype": None, "label": None, "type": "disk", "pkname": None, "tran": None, "rm": False, "hotplug": False},
    {"name": "/dev/mmcblk1p1", "size": "64G", "fstype": "ext4", "label": "SD", "type": "part", "pkname": "/dev/mmcblk1"},
    {"name": "/dev/nvme0n1", "size": "32G", "fstype": None, "label": None, "type": "disk", "pkname": None, "tran": "nvme", "rm": False, "hotplug": False},
    {"name": "/dev/nvme0n1p1", "size": "32G", "fstype": "ext4", "label": None, "type": "part", "pkname": "/dev/nvme0n1"},
    {"name": "/dev/sda", "size": "58G", "fstype": None, "label": None, "type": "disk", "pkname": None, "tran": "usb", "rm": "1", "hotplug": "1"},
    {"name": "/dev/sda1", "size": "58G", "fstype": None, "label": None, "type": "part", "pkname": "/dev/sda"},
    {"name": "/dev/sdb", "size": "16G", "fstype": None, "label": None, "type": "disk", "pkname": None, "tran": "usb", "rm": True, "hotplug": True},
    {"name": "/dev/sdb1", "size": "16G", "fstype": "vfat", "label": "STICK", "type": "part", "pkname": "/dev/sdb"},
    {"name": "/dev/sdc", "size": "31G", "fstype": None, "label": None, "type": "disk", "pkname": None, "tran": "usb", "rm": True, "hotplug": True},
    {"name": "/dev/sdc2", "size": "3M", "fstype": "vfat", "label": "KiteOS", "type": "part", "pkname": "/dev/sdc"},
    {"name": "/dev/loop0p1", "size": "1G", "fstype": "ext4", "label": None, "type": "part", "pkname": "/dev/loop0"}]})
r = ac.external_partitions(j, "mmcblk0", "/dev/sdc", {"mmcblk1"})
assert [x["name"] for x in r] == ["/dev/mmcblk1p1", "/dev/sda1", "/dev/sdb1"], r
assert r[1] == {"name": "/dev/sda1", "size": "58G", "fstype": "none", "label": "-"}, r
assert [x["name"] for x in ac.external_partitions(j, "", "", ())] == ["/dev/sda1", "/dev/sdb1", "/dev/sdc2"]
assert ac.external_partitions("not json", "") == []'
check "root steps match the kite-storage commands" ac_py '
KS = "/usr/sbin/kite-storage"
assert ac.install_steps("gimp", "iwan", True, False) == [[KS, "install", "--app-ext", "--user", "iwan", "gimp"]]
assert ac.install_steps("gimp", "iwan", False, False) == [[KS, "install", "--user", "iwan", "gimp"]]
assert ac.move_steps("gimp", "iwan", True, True) == [[KS, "move-app", "gimp"], [KS, "move-data", "gimp", "--user", "iwan"]]
assert ac.move_steps("gimp", "iwan", False, True) == [[KS, "move-data", "gimp", "--user", "iwan"]]
assert ac.restore_steps("gimp", "iwan") == [[KS, "restore-app", "gimp"], [KS, "restore-data", "gimp", "--user", "iwan"]]'
check "every root command App Centre uses exists in kite-storage" bash -c \
    "for c in ping install move-app move-data restore-app restore-data move-dir restore-dir setup update remove status; do grep -qE \"^        \$c\\) \" '$REPO/packages/kite-storage/usr/sbin/kite-storage' || { echo \"missing: \$c\"; exit 1; }; done"
check "rejects unknown options" bash -c "! KITE_NO_GTK=1 python3 '$AC' --bogus 2>/dev/null"
check "says what is missing without GTK" bash -c "KITE_NO_GTK=1 python3 '$AC' 2>&1 | grep -q 'needs GTK 3'"
check "kite-apps still opens App Centre" grep -qx 'exec /usr/bin/kite-app-centre "\$@"' "$REPO/packages/kite-storage/usr/bin/kite-apps"
D=$REPO/packages/kite-storage/usr/share/applications/kite-apps.desktop
check "launcher: App Centre, grouped as kite-apps" bash -c "grep -qx 'Name=App Centre' '$D' && grep -qx 'Exec=kite-app-centre' '$D' && grep -qx 'StartupWMClass=kite-apps' '$D'"
check "kite-storage depends on Python GTK 3" grep -qE '^Depends:.*python3-gi, gir1.2-gtk-3.0' "$REPO/packages/kite-storage/DEBIAN/control"

echo "== touchpad defaults"
TP=$REPO/packages/kite-desktop/etc/X11/xorg.conf.d/50-kite-touchpad.conf
check "tap to click" grep -q 'Option "Tapping" "on"' "$TP"
check "natural scrolling" grep -q 'Option "NaturalScrolling" "true"' "$TP"
check "touchpads only" grep -q 'MatchIsTouchpad "on"' "$TP"

echo
echo "system tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
