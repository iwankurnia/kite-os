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
check "4 GB machine (3800 MiB visible) -> 5888 MiB swap (RAM + half)" test "$(target_swap_mib 3800)" = 5888
check "8 GB machine -> 12288 MiB swap (RAM + 4 GiB)" test "$(target_swap_mib 8192)" = 12288
check "16 GB machine -> 20480 MiB swap (extra capped at 4 GiB)" test "$(target_swap_mib 16384)" = 20480
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

echo "== patches to Debian packages"
check "patches are numbered, so they apply in the order they were made" bash -c \
    "! ls '$REPO'/patches/*/*.patch | xargs -n1 basename | grep -vE '^[0-9]{2}-'"
check "every patch says what it does (Description, for the changelog)" bash -c \
    "for f in '$REPO'/patches/*/*.patch; do grep -q '^Description: ' \"\$f\" || exit 1; done"

echo "== EC event masks (lid after hibernate)"
EC=$REPO/packages/kite-chromebook/usr/lib/kite/chromebook/kite-ec-events
ecfake() { printf '{"SMI": %d, "SCI": %d, "WAKE": %d}\n' "$1" "$2" "$3" > "$T/ec.json"; }
ec() { KITE_EC_FAKE=$T/ec.json KITE_EC_STATE=$T/ec-masks python3 "$EC" "$@"; }
sci() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["SCI"])' "$T/ec.json"; }
ecfake 1 0x1ffbf 0x60000; ec save >/dev/null
check "save keeps the firmware's masks from a cold boot" grep -qx 'SMI=0x00000001 SCI=0x0001ffbf WAKE=0x00060000' "$T/ec-masks"
ecfake 0 0 0; ec save >/dev/null
check "save never overwrites good masks with the empty ones" grep -qx 'SMI=0x00000001 SCI=0x0001ffbf WAKE=0x00060000' "$T/ec-masks"
ec restore >/dev/null
check "restore after hibernate puts the saved masks back" test "$(sci)" = $((0x1ffbf))
check "restore brings back the wake and SMI masks too" grep -q '"WAKE": 393216' "$T/ec.json"
ecfake 0 3 0; ec restore >/dev/null
check "restore leaves a non-empty SCI mask alone (normal suspend)" test "$(sci)" = 3
rm "$T/ec-masks"; ecfake 0 0 0
check "restore without saved masks does nothing and does not fail" bash -c "KITE_EC_FAKE='$T/ec.json' KITE_EC_STATE='$T/ec-masks' python3 '$EC' restore && test \"\$(python3 -c 'import json; print(json.load(open(\"$T/ec.json\"))[\"SCI\"])')\" = 0"
ecfake 0 3 0
check "show names the lid events" bash -c "KITE_EC_FAKE='$T/ec.json' python3 '$EC' show | grep -q 'SCI .*LID_CLOSED, LID_OPEN'"
HOOK=$REPO/packages/kite-chromebook/usr/lib/systemd/system-sleep/kite-ec-events
check "sleep hook restores only after waking (post)" bash -c "grep -q '\"\$1\" = post' '$HOOK' && grep -q 'kite-ec-events restore' '$HOOK' && test -x '$HOOK'"
U=$REPO/packages/kite-chromebook/usr/lib/systemd/system/kite-ec-events.service
check "boot service saves the masks, only on a Chrome EC" bash -c "grep -qx 'ConditionPathExists=/dev/cros_ec' '$U' && grep -q 'kite-ec-events save' '$U'"
check "kite-chromebook enables the boot service" grep -q 'systemctl enable kite-ec-events.service' "$REPO/packages/kite-chromebook/DEBIAN/postinst"

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

echo "== kite-layout (the KiteOS desktop)"
KL=$REPO/packages/kite-desktop/usr/bin/kite-layout
LH=$T/layout; mkdir -p "$LH/themes/Fluent-Light/gtk-3.0" "$LH/themes/Fluent-Light/xfwm4" "$LH/apps"
for a in brave-browser thunar xfce4-terminal kite-apps; do touch "$LH/apps/$a.desktop"; done
# KITE_DMI_DIR: no DMI data, so not a Chromebook (Windows keys) on any test machine
kl() { env HOME="$LH/home" XDG_CONFIG_HOME="$LH/home/.config" DISPLAY= KITE_DMI_DIR="$LH/no-dmi" KITE_LAYOUT_DATA="$REPO/packages/kite-desktop/usr/share/kite/layouts" \
       KITE_THEMES_DIR="$LH/themes" KITE_APPS_DIR="$LH/apps" python3 "$KL" "$@"; }
X=$LH/home/.config/xfce4/xfconf/xfce-perchannel-xml
# An account left on the dropped mac layout (a menu bar = panel-2, a launcher-4)
mkdir -p "$LH/home/.config/kite" "$X" "$LH/home/.config/xfce4/panel/launcher-4"
echo mac > "$LH/home/.config/kite/layout"
echo '<channel name="xfce4-panel" version="1.0"><property name="panel-2" type="empty"/></channel>' > "$X/xfce4-panel.xml"
kl --first-login
check "first login: an account on the dropped mac layout gets windows" grep -qx windows "$LH/home/.config/kite/layout"
check "nothing of the mac layout left (its launchers)" test ! -d "$LH/home/.config/xfce4/panel/launcher-4"
echo changed > "$LH/home/.config/gtk-3.0/gtk.css"; kl --first-login
check "first login runs only once" grep -qx changed "$LH/home/.config/gtk-3.0/gtk.css"
kl windows >/dev/null
check "kite-layout windows puts the desktop back" bash -c "! grep -qx changed '$LH/home/.config/gtk-3.0/gtk.css'"
check "windows: one taskbar" bash -c "! grep -q '<property name=\"panel-2\"' '$X/xfce4-panel.xml'"
check "windows: Fluent theme and Papirus-Light icons" bash -c "grep -q 'value=\"Fluent-Light\"' '$X/xsettings.xml' && grep -q 'value=\"Papirus-Light\"' '$X/xsettings.xml'"
check "windows: buttons on the right" grep -q 'value="menu:minimize,maximize,close"' "$X/xsettings.xml"
check "no placeholders left" bash -c "! grep -rq '@[A-Z_]*@' '$LH/home/.config'"
check "panel plugins run in their own processes (battery + volume crash the panel together)" grep -q 'name="force-all-internal" type="bool" value="false"' "$X/xfce4-panel.xml"
check "battery on the taskbar" grep -q 'value="power-manager-plugin"' "$X/xfce4-panel.xml"
check "windows: 36 px taskbar, tray in one row" bash -c "grep -q 'name=\"size\" type=\"uint\" value=\"36\"' '$X/xfce4-panel.xml' && grep -q 'name=\"single-row\" type=\"bool\" value=\"true\"' '$X/xfce4-panel.xml'"
check "windows: no pop-up shadows (borders instead)" grep -q 'name="show_popup_shadow" type="bool" value="false"' "$X/xfwm4.xml"
check "windows: Start and Search icons shipped in hicolor" bash -c "grep -qx 'button-icon=kite-start-symbolic' '$LH/home/.config/xfce4/panel/whiskermenu-1.rc' && grep -qx 'Icon=kite-search-symbolic' '$LH/home/.config/xfce4/panel/launcher-2/search.desktop' && test -f '$REPO/packages/kite-desktop/usr/share/icons/hicolor/scalable/actions/kite-start-symbolic.svg' -a -f '$REPO/packages/kite-desktop/usr/share/icons/hicolor/scalable/actions/kite-search-symbolic.svg'"
check "Bluetooth tray applet not hidden for new accounts" test ! -e "$REPO/packages/kite-desktop/etc/skel/.config/autostart/blueman.desktop"
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
rm -rf "$LH/themes/Fluent-Light/xfwm4"          # window theme falls back to Default
env HOME="$LH/home" XDG_CONFIG_HOME="$LH/home/.config" XDG_CACHE_HOME="$LH/cache" DISPLAY=:99 PATH="$LH/fake:$PATH" \
    KITE_LAYOUT_DATA="$REPO/packages/kite-desktop/usr/share/kite/layouts" \
    KITE_THEMES_DIR="$LH/themes" KITE_APPS_DIR="$LH/apps" python3 "$KL" windows >/dev/null
check "live apply: never starts a window manager" bash -c "! grep -q '^xfwm4' '$LH/calls'"
check "live apply: window theme set through xfconf" grep -q '^xfconf-query -c xfwm4 -p /general/theme -n -t string -s Default' "$LH/calls"
check "live apply: window buttons on the right through xfconf" grep -q '^xfconf-query -c xfwm4 -p /general/button_layout -n -t string -s O|HMC' "$LH/calls"
check "live apply: window settings sent before xfconfd reloads (else xfwm4 is not told)" bash -c "a=\$(grep -n '^xfconf-query -c xfwm4' '$LH/calls' | head -n1 | cut -d: -f1); b=\$(grep -n '^xfce4-panel --quit' '$LH/calls' | head -n1 | cut -d: -f1); [ -n \"\$a\" ] && [ -n \"\$b\" ] && [ \"\$a\" -lt \"\$b\" ]"
check "live apply: panel quit, then started again" bash -c "grep -n '^xfce4-panel' '$LH/calls' | tr '\n' ' ' | grep -q 'xfce4-panel --quit.*xfce4-panel *\$\|xfce4-panel --quit .*:xfce4-panel '"
check "live apply: settings daemon reloads (shortcuts, theme)" grep -q '^xfsettingsd --replace' "$LH/calls"
check "live apply without picom: xfwm4's compositor on" grep -q '^xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s true' "$LH/calls"
# With picom running (start-compositor), xfwm4's compositor must stay off.
printf '#!/bin/sh\ncase "$*" in *picom*) exit 0 ;; esac\nexit 1\n' > "$LH/fake/pgrep"; chmod 755 "$LH/fake/pgrep"
rm -f "$LH/calls"
env HOME="$LH/home" XDG_CONFIG_HOME="$LH/home/.config" XDG_CACHE_HOME="$LH/cache" DISPLAY=:99 PATH="$LH/fake:$PATH" \
    KITE_LAYOUT_DATA="$REPO/packages/kite-desktop/usr/share/kite/layouts" \
    KITE_THEMES_DIR="$LH/themes" KITE_APPS_DIR="$LH/apps" python3 "$KL" windows >/dev/null
rm -f "$LH/fake/pgrep"
check "live apply with picom: xfwm4's compositor never switched on" bash -c "! grep -q 'use_compositing .* -s true' '$LH/calls'"
check "live apply with picom: xfwm4's compositor kept off after the reload" bash -c "a=\$(grep -n '^xfce4-panel --quit' '$LH/calls' | head -n1 | cut -d: -f1); b=\$(grep -n 'use_compositing -n -t bool -s false' '$LH/calls' | tail -n1 | cut -d: -f1); [ -n \"\$a\" ] && [ -n \"\$b\" ] && [ \"\$b\" -gt \"\$a\" ]"
# Applying the layout again keeps the user's own Files/Terminal settings and fonts.
echo '<channel name="thunar" version="1.0"><property name="mine" type="bool" value="true"/></channel>' > "$X/thunar.xml"
sed -i.bak 's/value="Inter 10"/value="Ubuntu 12"/' "$X/xsettings.xml" && rm -f "$X/xsettings.xml.bak"
kl windows >/dev/null
check "re-apply keeps the user's Files settings" grep -q 'name="mine"' "$X/thunar.xml"
check "re-apply keeps the user's font" grep -q 'value="Ubuntu 12"' "$X/xsettings.xml"
check "cursor size is an XSETTINGS key (Gtk/CursorThemeSize)" bash -c "python3 -c 'import sys, xml.etree.ElementTree as E; r = E.parse(sys.argv[1]).getroot(); sys.exit(0 if r.find(\"./property[@name=\x27Gtk\x27]/property[@name=\x27CursorThemeSize\x27]\") is not None and r.find(\"./property[@name=\x27Net\x27]/property[@name=\x27CursorThemeSize\x27]\") is None else 1)' '$X/xsettings.xml'"
check "window theme follows the GTK theme (fallback: Default)" grep -q 'name="theme" type="string" value="Default"' "$X/xfwm4.xml"
mkdir -p "$LH/themes/Fluent-Light/xfwm4"
# Window keys: one key per action (xfwm4 ignores a second key for an action),
# ChromeOS keys on a Chromebook, Windows keys elsewhere.
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
        KITE_THEMES_DIR="$LH/themes" KITE_APPS_DIR="$LH/apps" python3 "$KL" "$@"; }
wk() { python3 -c 'import sys, xml.etree.ElementTree as E; r = E.parse(sys.argv[1]).getroot(); print("\n".join(p.get("name") for p in r.findall("./property[@name=\x27xfwm4\x27]/property[@name=\x27custom\x27]/property") if p.get("value") == sys.argv[2]))' "$X/xfce4-keyboard-shortcuts.xml" "$1"; }
echo "Generic" > "$LH/dmi/sys_vendor"; rm -f "$LH/home/.config/kite/keys"
klk windows >/dev/null
check "keys (windows): Super+Left tiles, the keypad key is gone" test "$(wk tile_left_key)" = "<Super>Left"
check "keys (windows): Alt+F4 still closes" test "$(wk close_window_key)" = "<Alt>F4"
echo "Google" > "$LH/dmi/sys_vendor"
klk windows >/dev/null
check "keys (Chromebook detected): ChromeOS close key, one key only" test "$(wk close_window_key)" = "<Primary><Shift>w"
check "keys (Chromebook): Alt+Tab switches windows" test "$(wk cycle_windows_key)" = "<Alt>Tab"
check "keys (Chromebook): Alt+[ docks left" test "$(wk tile_left_key)" = "<Alt>bracketleft"
klk keys standard >/dev/null
check "keys: choosing standard on a Chromebook is kept" bash -c "grep -qx standard '$LH/home/.config/kite/keys'"
check "keys: standard on a Chromebook gives the Windows keys" test "$(wk close_window_key)" = "<Alt>F4"
klk keys auto >/dev/null
check "keys: auto goes back to detection" bash -c "test ! -e '$LH/home/.config/kite/keys'"
check "keys: auto on a Chromebook gives the ChromeOS keys again" test "$(wk close_window_key)" = "<Primary><Shift>w"
check "keys: no action has two keys" bash -c "python3 -c 'import sys, xml.etree.ElementTree as E, collections; r = E.parse(sys.argv[1]).getroot(); v = [p.get(\"value\") for p in r.findall(\"./property[@name=\x27xfwm4\x27]/property[@name=\x27custom\x27]/property\") if p.get(\"type\") == \"string\"]; d = [k for k, n in collections.Counter(v).items() if n > 1]; sys.exit(1 if d else 0)' '$X/xfce4-keyboard-shortcuts.xml'"
check "keyring for apps (VS Code, Brave), unlocked by the login password" bash -c "sed -n '/^Depends:/,/^[A-Z]/p' '$REPO/packages/kite-desktop/DEBIAN/control' | grep -q 'gnome-keyring, libpam-gnome-keyring'"
check "rejects unknown layouts, mac included" bash -c "! python3 '$KL' gnome 2>/dev/null && ! python3 '$KL' mac 2>/dev/null && ! python3 '$KL' --system windows 2>/dev/null"
check "ISO apps: VS Code (Microsoft repo, pinned key) and git" bash -c "grep -qx code '$REPO/live/config/package-lists/kite-apps.list.chroot' && grep -qx git '$REPO/live/config/package-lists/kite-apps.list.chroot' && grep -q '^\"vscode|https://packages.microsoft.com/keys/microsoft.asc|EB3E94ADBE1229CF|deb \[arch=amd64\] https://packages.microsoft.com/repos/code stable main\"' '$REPO/scripts/fetch-vendor-keys.sh'"
check "installer has no Desktop page (one layout)" bash -c "! grep -q packagechooser '$REPO/live/config/includes.chroot/etc/calamares/settings.conf'"
GC=$REPO/packages/kite-desktop/usr/share/lightdm/lightdm-gtk-greeter.conf.d/50-kite.conf
check "login screen: lightdm-gtk-greeter with the KiteOS-Login theme" bash -c "grep -qx 'greeter-session=lightdm-gtk-greeter' '$REPO/packages/kite-desktop/etc/lightdm/lightdm.conf.d/50-kite.conf' && grep -qx 'theme-name=KiteOS-Login' '$GC'"
check "login theme = Fluent-Light + the shared KiteOS card" bash -c "grep -q 'Fluent-Light/gtk-3.0/gtk.css' '$REPO/packages/kite-desktop/usr/share/themes/KiteOS-Login/gtk-3.0/gtk.css' && grep -q 'kite/login/kite-login.css' '$REPO/packages/kite-desktop/usr/share/themes/KiteOS-Login/gtk-3.0/gtk.css'"
check "lock screen imports the same card (desktop gtk.css)" grep -q 'file:///usr/share/kite/login/kite-login.css' "$REPO/packages/kite-desktop/usr/share/kite/layouts/windows/.config/gtk-3.0/gtk.css"
check "card rules are scoped to the greeter/lock widgets" bash -c "! grep -E '^[a-z*]' '$REPO/packages/kite-desktop/usr/share/kite/login/kite-login.css' | grep -v '^ ' >/dev/null"
check "installer picks lightdm-gtk-greeter (Calamares writes it into lightdm.conf)" grep -q 'preferred_greeters: \["lightdm-gtk-greeter.desktop"\]' "$REPO/live/config/includes.chroot/etc/calamares/modules/displaymanager.conf"
LC=$T/lightdm.conf; printf '[Seat:*]\n#greeter-session=example\ngreeter-session=slick-greeter\n' > "$LC"
sed "s#/etc/lightdm/lightdm.conf#$LC#g; s#systemctl#true#; s#update-alternatives#true#g; s#glib-compile-schemas#true#; s#gtk-update-icon-cache#true#; s#/usr/share/icons/#$T/no-icons/#g" "$REPO/packages/kite-desktop/DEBIAN/postinst" > "$T/kd-postinst"
sh "$T/kd-postinst" configure >/dev/null 2>&1
check "postinst moves an installed system's lightdm.conf off slick-greeter" bash -c "grep -qx 'greeter-session=lightdm-gtk-greeter' '$LC' && grep -qx '#greeter-session=example' '$LC'"
check "no slick-greeter left" bash -c "! grep -rq slick-greeter '$REPO/packages/kite-desktop/DEBIAN/control' '$REPO/live/config/package-lists' && [ ! -e '$REPO/packages/kite-desktop/usr/share/glib-2.0/schemas/90_kite-slick-greeter.gschema.override' ]"
check "locked screen shows the wallpaper (screensaver theme)" bash -c "grep -q 'screensavers-kite-wallpaper' '$REPO/packages/kite-desktop/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml' && grep -qx 'Exec=/usr/lib/kite/desktop/kite-lock-picture' '$REPO/packages/kite-desktop/usr/share/applications/screensavers/kite-wallpaper.desktop'"
check "Settings > Login Screen entry" bash -c "grep -q 'X-XFCE-SettingsDialog' '$REPO/packages/kite-desktop/usr/share/applications/kite-login-settings.desktop' && python3 -m py_compile '$REPO/packages/kite-desktop/usr/bin/kite-login-settings'"
check "pkexec message for kite-login-theme" grep -q '/usr/bin/kite-login-theme' "$REPO/packages/kite-desktop/usr/share/polkit-1/actions/org.kiteos.login-theme.policy"

echo "== kite-login-theme (login screen background)"
LT=$REPO/packages/kite-desktop/usr/bin/kite-login-theme; G=$T/greeter/conf.d/90-kite-login-background.conf; GS=$T/greeter/store
lt() { KITE_GREETER_CONF=$G KITE_LOGIN_STORE=$GS sh "$LT" "$@"; }
check "default is frosted" bash -c "KITE_GREETER_CONF='$G' sh '$LT' | grep -q 'frosted (default)'"
lt aurora >/dev/null
check "writes its own greeter file, marked as ours" test "$(cat "$G")" = "$(printf '# Written by kite-login-theme (removed when kite-desktop is purged)\n[greeter]\nbackground=/usr/share/backgrounds/kite/login-aurora.jpg')"
check "reports the current one" bash -c "KITE_GREETER_CONF='$G' sh '$LT' | grep -q 'login screen: aurora$'"
lt "$REPO/packages/kite-desktop/usr/share/backgrounds/kite/waves.jpg" >/dev/null
check "own picture copied where the greeter can read it" bash -c "cmp -s '$GS/login-background.jpg' '$REPO/packages/kite-desktop/usr/share/backgrounds/kite/waves.jpg' && grep -qx 'background=$GS/login-background.jpg' '$G'"
check "reports an own picture" bash -c "KITE_GREETER_CONF='$G' sh '$LT' | grep -q 'own picture'"
echo 'not a picture' > "$T/greeter/fake.jpg"
check "refuses a file that is not a picture" bash -c "! KITE_GREETER_CONF='$G' KITE_LOGIN_STORE='$GS' sh '$LT' '$T/greeter/fake.jpg' 2>/dev/null"
lt dusk >/dev/null
check "a KiteOS picture again removes the copy" bash -c "[ ! -e '$GS/login-background.jpg' ] && grep -q login-dusk.jpg '$G'"
check "rejects unknown names and options" bash -c "! KITE_GREETER_CONF='$G' sh '$LT' sunset 2>/dev/null && ! KITE_GREETER_CONF='$G' sh '$LT' --x 2>/dev/null"
# kite-desktop's postrm, pointed at the test copies
DPR=$T/greeter/postrm
sed "s#/etc/lightdm/lightdm-gtk-greeter.conf.d/90-kite-login-background.conf#$G#; s#/etc/lightdm/slick-greeter.conf#$T/greeter/slick.conf#; s#/var/lib/kite#$GS#g" "$REPO/packages/kite-desktop/DEBIAN/postrm" > "$DPR"
printf '# Written by kite-login-theme (x)\n[Greeter]\n' > "$T/greeter/slick.conf"; lt "$REPO/packages/kite-desktop/usr/share/backgrounds/kite/waves.jpg" >/dev/null
sh "$DPR" purge
check "purge removes what kite-login-theme wrote (both greeters, own picture)" bash -c "[ ! -e '$G' ] && [ ! -e '$T/greeter/slick.conf' ] && [ ! -e '$GS/login-background.jpg' ]"
mkdir -p "$(dirname "$G")"; printf '[greeter]\nbackground=/x.png\n' > "$G"; sh "$DPR" purge
check "purge keeps a greeter file someone else wrote" test -s "$G"
check "all three login images ship" bash -c "for l in frosted aurora dusk; do [ -s '$REPO/packages/kite-desktop/usr/share/backgrounds/kite/login-'\$l.jpg ] || exit 1; done"
check "all twelve wallpapers ship (1920 x 1200), Bloom by default" bash -c "for w in bloom aurora waves dunes lagoon nightfall horizon mist mirror cabin meadow coast; do [ -s '$REPO/packages/kite-desktop/usr/share/backgrounds/kite/'\$w.jpg ] || exit 1; done; grep -q 'kite/bloom.jpg' '$REPO/packages/kite-desktop/usr/lib/kite/desktop/kite-user-init'"
check "greeter default is frosted" grep -qx "background=/usr/share/backgrounds/kite/login-frosted.jpg" "$GC"
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

echo "== compositor (picom animations, xfwm4's compositor as the fallback)"
SC=$REPO/packages/kite-desktop/usr/lib/kite/desktop/start-compositor
PC=$REPO/packages/kite-desktop/etc/kite/picom.conf
C=$T/comp; mkdir -p "$C/bin" "$C/cfg/kite"
printf '#!/bin/sh\necho "xfwm $6" >> "%s/log"\n' "$C" > "$C/bin/xfconf-query"
printf '#!/bin/sh\necho "picom $*" >> "%s/log"\nexit ${FAKE_PICOM_EXIT:-0}\n' "$C" > "$C/bin/picom"
chmod 755 "$C/bin/xfconf-query" "$C/bin/picom"
run_sc() { rm -f "$C/log"; env PATH="$C/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$C/cfg" KITE_DISPLAY_CONF=/nonexistent "$@" sh "$SC" || true; }
run_sc FAKE_PICOM_EXIT=1
check "picom replaces xfwm4 compositing, then hands it back when picom exits" \
    test "$(tr '\n' '|' < "$C/log")" = "xfwm false|picom --config /etc/kite/picom.conf|xfwm true|"
echo ANIMATIONS=0 > "$C/cfg/kite/display.conf"; run_sc
check "ANIMATIONS=0: xfwm4 compositing only" test "$(tr '\n' '|' < "$C/log")" = "xfwm true|"
printf '#!/bin/sh\nexit 0\n' > "$C/bin/pgrep"; chmod 755 "$C/bin/pgrep"; rm "$C/cfg/kite/display.conf"; run_sc
check "second start while picom runs: touches nothing" test ! -e "$C/log"
# picom missing: a PATH with only what start-compositor needs besides picom
# (a real /usr/bin/picom on the test machine must not count).
rm "$C/bin/pgrep" "$C/bin/picom"; mkdir -p "$C/sys"
for t in sed tail id; do ln -sf "$(command -v "$t")" "$C/sys/$t"; done
rm -f "$C/log"; env PATH="$C/bin:$C/sys" XDG_CONFIG_HOME="$C/cfg" KITE_DISPLAY_CONF=/nonexistent "$(command -v sh)" "$SC" || true
check "picom missing: xfwm4 compositing only" test "$(tr '\n' '|' < "$C/log")" = "xfwm true|"
# On battery, animations stay by default (the owner's choice): picom while
# saving power too. With ANIMATIONS_ON_BATTERY=0: xfwm4's compositor while
# saving, picom again once the charger is plugged in.
printf '#!/bin/sh\necho "picom $*" >> "%s/log"\nexit ${FAKE_PICOM_EXIT:-0}\n' "$C" > "$C/bin/picom"; chmod 755 "$C/bin/picom"
echo saving > "$C/power"
rm -f "$C/log"; env PATH="$C/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$C/cfg" XDG_RUNTIME_DIR="$C" KITE_DISPLAY_CONF=/nonexistent KITE_POWER_STATE="$C/power" FAKE_PICOM_EXIT=1 timeout 8 sh "$SC" || true
check "on battery by default: picom and its animations stay" test "$(tr '\n' '|' < "$C/log")" = "xfwm false|picom --config /etc/kite/picom.conf|xfwm true|"
check "animations on battery by default (display.conf)" grep -qx 'ANIMATIONS_ON_BATTERY=1' "$REPO/packages/kite-desktop/etc/kite/display.conf"
echo ANIMATIONS_ON_BATTERY=0 > "$C/cfg/kite/display.conf"
rm -f "$C/log"; env PATH="$C/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$C/cfg" XDG_RUNTIME_DIR="$C" KITE_DISPLAY_CONF=/nonexistent KITE_POWER_STATE="$C/power" timeout 3 sh "$SC" || true
check "ANIMATIONS_ON_BATTERY=0, saving power: xfwm4's compositor, no picom" test "$(tr '\n' '|' < "$C/log")" = "xfwm true|"
rm -f "$C/log"
( sleep 2; echo ac > "$C/power" ) &
env PATH="$C/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$C/cfg" XDG_RUNTIME_DIR="$C" KITE_DISPLAY_CONF=/nonexistent KITE_POWER_STATE="$C/power" FAKE_PICOM_EXIT=1 timeout 12 sh "$SC" || true
wait
check "ANIMATIONS_ON_BATTERY=0, charger plugged in: picom comes back" test "$(tr '\n' '|' < "$C/log")" = "xfwm true|xfwm false|picom --config /etc/kite/picom.conf|xfwm true|"
rm -f "$C/cfg/kite/display.conf" "$C/bin/picom"
check "animations on by default" grep -qx 'ANIMATIONS=1' "$REPO/packages/kite-desktop/etc/kite/display.conf"
# Calm animations: short, a small zoom at most, nothing on resize/maximise
# (picom stretches the old picture), the taskbar and desktop never move.
check "every animation is shorter than 0.16 s" bash -c \
    "! grep -o 'duration = [0-9.]*' '$PC' | awk '{ if (\$3 >= 0.16) bad = 1 } END { exit !bad }'"
check "windows grow from 96 % or more (no big zoom)" bash -c \
    "! grep -o 'scale = [0-9.]*' '$PC' | awk '{ if (\$3 < 0.96) bad = 1 } END { exit !bad }'"
check "no animation on resize, maximise or tiling" bash -c "! grep -q '\"geometry\"' '$PC'"
check "xrender backend (glx left a restarted taskbar invisible)" grep -qx 'backend = "xrender";' "$PC"
check "no picom shadow on windows that draw their own (Brave's pale box)" grep -q 'match = "_GTK_FRAME_EXTENTS@"; shadow = false;' "$PC"
check "taskbar pop-up: rounded card with a shadow" bash -c "grep -A3 \"class_g = 'Wrapper-2.0' && window_type = 'normal'\" '$PC' | grep -q 'corner-radius = 8'"
check "taskbar and desktop: no animation, no shadow" grep -q "window_type = 'dock' || window_type = 'desktop'\"; shadow = false; animations = ();" "$PC"
check "menus and tooltips: no shadow (gtk.css border), fade only" bash -c \
    "grep -A3 'override_redirect ||' '$PC' | grep -q 'shadow = false' && grep -A3 'override_redirect ||' '$PC' | grep -q 'scale = 1.0'"
check "Start menu and calendar (panel pop-ups): fade only" bash -c "grep -A2 \"class_g = 'Wrapper-2.0'\" '$PC' | grep -q 'scale = 1.0'"

echo "== kite-power (saving power on battery) and TLP settings"
KP=$REPO/packages/kite-system/usr/sbin/kite-power
PW=$T/power; mkdir -p "$PW/run" "$PW/bin"
kp_py() { KITE_SYS="$PW/sys" KITE_RUN="$PW/run" KITE_TLP_BOOST="$PW/61-kite-boost.conf" PATH="$PW/bin:$PATH" python3 - "$KP" <<KPEOF
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("kp", sys.argv[1])
spec = importlib.util.spec_from_loader("kp", loader); kp = importlib.util.module_from_spec(spec); loader.exec_module(kp)
def supply(name, **files):
    d = os.path.join(os.environ["KITE_SYS"], "class/power_supply", name); os.makedirs(d, exist_ok=True)
    for k, v in files.items(): open(os.path.join(d, k), "w").write(v + "\n")
def reset():
    import shutil; shutil.rmtree(os.environ["KITE_SYS"], ignore_errors=True)
    for p in [os.path.join(os.environ["KITE_RUN"], f) for f in ("power", "power-full", "../calls")] + [os.environ["KITE_TLP_BOOST"]]:
        if os.path.exists(p): os.remove(p)
def cpus(present, hybrid=False):
    d = os.environ["KITE_SYS"] + "/devices"; os.makedirs(d + "/system/cpu", exist_ok=True)
    open(d + "/system/cpu/present", "w").write(present + "\n")
    if hybrid:
        os.makedirs(d + "/cpu_atom"); os.makedirs(d + "/cpu_core"); open(d + "/cpu_atom/cpus", "w").write("2-3\n"); open(d + "/cpu_core/cpus", "w").write("0-1\n")
def calls():
    p = os.environ["KITE_RUN"] + "/../calls"
    return open(p).read().splitlines() if os.path.exists(p) else []
reset()
$1
KPEOF
}
check "on battery: a laptop battery and no charger online" kp_py \
    'supply("BAT0", type="Battery", present="1"); supply("AC", type="Mains", online="0"); assert kp.on_battery() and kp.mode() == "saving"'
check "plugged in: mains, or a USB-C charger" kp_py \
    'supply("BAT0", type="Battery"); supply("AC", type="Mains", online="1"); assert not kp.on_battery(); reset(); supply("BAT0", type="Battery"); supply("cros-usbpd-charger", type="USB", online="1"); assert not kp.on_battery()'
check "no battery (desktop, VM), or only a wireless mouse's: plugged-in mode" kp_py \
    'assert not kp.on_battery(); supply("hidpp_battery_0", type="Battery", scope="Device"); assert kp.mode() == "ac"'
check "full speed on battery: the flag wins" kp_py \
    'supply("BAT0", type="Battery"); open(kp.FULL, "w").write("1"); assert kp.mode() == "full"'
check "P/E cores found from the hybrid PMUs; none on the N4020" kp_py \
    'assert kp.e_cores() is None; d = os.environ["KITE_SYS"] + "/devices"; os.makedirs(d + "/cpu_atom"); os.makedirs(d + "/cpu_core"); open(d + "/cpu_atom/cpus", "w").write("12-19\n"); open(d + "/cpu_core/cpus", "w").write("0-11\n"); assert kp.e_cores() == "12-19" and kp.cpu_list("0-3,8") == [0, 1, 2, 3, 8]'
check "Intel GPU capped at 60 % of its range on battery (UHD 600: 200-650 MHz -> 470)" kp_py \
    'assert kp.gpu_cap(200, 650) == 470'
printf '#!/bin/sh\necho "$*" >> "%s/calls"\n' "$PW" > "$PW/bin/systemctl"; chmod 755 "$PW/bin/systemctl"
check "apply on battery: mode written, services on E-cores, GPU capped" kp_py \
    'supply("BAT0", type="Battery"); d = os.environ["KITE_SYS"]; os.makedirs(d + "/devices/cpu_atom"); os.makedirs(d + "/devices/cpu_core"); open(d + "/devices/cpu_atom/cpus", "w").write("12-19"); open(d + "/devices/cpu_core/cpus", "w").write("0-11"); g = d + "/class/drm/card0"; os.makedirs(g); [open(g + "/" + n, "w").write(v) for n, v in (("gt_RPn_freq_mhz", "200"), ("gt_RP0_freq_mhz", "650"), ("gt_max_freq_mhz", "650"), ("gt_boost_freq_mhz", "650"))]; kp.apply(); assert open(kp.STATE).read().strip() == "saving"; assert open(g + "/gt_max_freq_mhz").read() == "470" and open(g + "/gt_boost_freq_mhz").read() == "470"; assert "set-property --runtime system.slice AllowedCPUs=12-19" in open(os.environ["KITE_RUN"] + "/../calls").read()'
check "apply plugged in: every core, GPU full range" kp_py \
    'supply("BAT0", type="Battery"); supply("AC", type="Mains", online="1"); d = os.environ["KITE_SYS"]; os.makedirs(d + "/devices/cpu_atom"); os.makedirs(d + "/devices/cpu_core"); open(d + "/devices/cpu_atom/cpus", "w").write("12-19"); open(d + "/devices/cpu_core/cpus", "w").write("0-11"); g = d + "/class/drm/card0"; os.makedirs(g); [open(g + "/" + n, "w").write(v) for n, v in (("gt_RPn_freq_mhz", "200"), ("gt_RP0_freq_mhz", "650"), ("gt_max_freq_mhz", "470"), ("gt_boost_freq_mhz", "470"))]; kp.apply(); assert open(kp.STATE).read().strip() == "ac" and open(g + "/gt_max_freq_mhz").read() == "650"; assert open(os.environ["KITE_RUN"] + "/../calls").read().splitlines()[-1].endswith("AllowedCPUs=")'
printf '#!/bin/sh\necho "tlp $*" >> "%s/calls"\n' "$PW" > "$PW/bin/tlp"; chmod 755 "$PW/bin/tlp"
check "low-end CPU (N4020: 2 CPUs, no P/E cores): boost kept on battery, once" kp_py \
    'cpus("0-1"); supply("BAT0", type="Battery"); assert kp.low_end(); kp.apply(); t = open(kp.BOOST_CONF).read(); assert "CPU_BOOST_ON_BAT=1" in t and "CPU_HWP_DYN_BOOST_ON_BAT=1" in t and "CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power" in t and "2 logical CPUs" in t; assert calls() == ["tlp start"], calls(); kp.apply(); assert calls() == ["tlp start"], calls()'
check "low-end CPU at full speed: TLP's plugged-in settings stay (tlp ac)" kp_py \
    'cpus("0-3"); supply("BAT0", type="Battery"); open(kp.FULL, "w").write("1"); kp.apply(); assert os.path.exists(kp.BOOST_CONF) and calls() == ["tlp ac"], calls()'
check "other CPUs (8 CPUs, or P/E cores): no boost on battery, drop-in removed" kp_py \
    'cpus("0-7"); open(kp.BOOST_CONF, "w").write("x"); assert not kp.low_end(); kp.apply(); assert not os.path.exists(kp.BOOST_CONF) and calls() == ["tlp start"]; reset(); cpus("0-3", hybrid=True); assert not kp.low_end(); kp.apply(); assert not os.path.exists(kp.BOOST_CONF) and "tlp start" not in calls()'
check "unknown CPU count: left alone" kp_py \
    'assert kp.cpu_count() == 0 and not kp.low_end() and not kp.tune_boost()'
check "kite-system purge removes the boost drop-in" grep -q 'rm -f /etc/tlp.d/61-kite-boost.conf' "$REPO/packages/kite-system/DEBIAN/postrm"
check "kite-power full/auto need root" bash -c "! KITE_RUN='$PW/run' python3 '$KP' full 2>/dev/null || [ \"\$(id -u)\" = 0 ]"
TC=$REPO/packages/kite-system/etc/tlp.d/60-kite.conf
check "TLP on battery: energy policy power, no turbo, no dynamic boost" bash -c \
    "grep -qx 'CPU_ENERGY_PERF_POLICY_ON_BAT=power' '$TC' && grep -qx 'CPU_BOOST_ON_BAT=0' '$TC' && grep -qx 'CPU_HWP_DYN_BOOST_ON_BAT=0' '$TC'"
check "TLP on battery: PCIe powersupersave, runtime PM, Wi-Fi power saving" bash -c \
    "grep -qx 'PCIE_ASPM_ON_BAT=powersupersave' '$TC' && grep -qx 'RUNTIME_PM_ON_BAT=auto' '$TC' && grep -qx 'WIFI_PWR_ON_BAT=on' '$TC'"
check "TLP: Bluetooth adapter never autosuspended (headphones), off on battery only when unused" bash -c \
    "grep -qx 'USB_EXCLUDE_BTUSB=1' '$TC' && grep -qx 'DEVICES_TO_DISABLE_ON_BAT_NOT_IN_USE=\"bluetooth\"' '$TC'"
check "TLP is a kite-system dependency (kite-update brings it)" grep -q 'ca-certificates, tlp$' "$REPO/packages/kite-system/DEBIAN/control"
check "kite-power.service ordered after multi-user.target like tlp.service (no ordering cycle at boot)" \
    grep -qx 'After=multi-user.target tlp.service' "$REPO/packages/kite-system/usr/lib/systemd/system/kite-power.service"
check "plug/unplug runs kite-power through systemd" grep -q 'SUBSYSTEM=="power_supply".*systemctl --no-block start kite-power.service' "$REPO/packages/kite-system/usr/lib/udev/rules.d/90-kite-power.rules"
check "Settings > Battery switches without a password for the person at the laptop" bash -c \
    "grep -q '<allow_active>yes</allow_active>' '$REPO/packages/kite-system/usr/share/polkit-1/actions/org.kiteos.power.policy' && grep -q '/usr/sbin/kite-power' '$REPO/packages/kite-system/usr/share/polkit-1/actions/org.kiteos.power.policy'"
check "Brave's energy saver on battery (policy)" python3 -c "import json, sys; sys.exit(0 if json.load(open('$REPO/packages/kite-desktop/etc/brave/policies/managed/kite.json')).get('BatterySaverModeAvailability') == 2 else 1)"

echo "== desktop kept in memory (kite-ui-protect, Xorg, MGLRU)"
UP=$REPO/packages/kite-desktop/usr/lib/kite/kite-ui-protect
U=$T/uiprot; mkdir -p "$U/bin" "$U/proc"
me=$(id -u)
mkproc() {      # pid, program, cgroup
    mkdir -p "$U/proc/$1"; ln -sfn "$2" "$U/proc/$1/exe"; echo "0::$3" > "$U/proc/$1/cgroup"
}
mkproc 101 /usr/bin/xfwm4 "/user.slice/user-$me.slice/session-2.scope"
mkproc 102 /usr/bin/picom "/user.slice/user-$me.slice/session-2.scope"
mkproc 103 /opt/brave.com/brave/brave "/user.slice/user-$me.slice/session-2.scope"
mkproc 104 /usr/bin/picom "/user.slice/user-$me.slice/kite-ui-$me.scope"
mkproc 105 /tmp/xfwm4 "/user.slice/user-$me.slice/session-2.scope"
mkproc 106 /usr/bin/xfwm4 "/user.slice/user-4242.slice/session-3.scope"; chown 4242 "$U/proc/106"
printf '#!/bin/sh\n[ "$1" = is-active ] && exit ${FAKE_ACTIVE:-1}\nexit 0\n' > "$U/bin/systemctl"
printf '#!/bin/sh\necho "$*" >> "%s/calls"\n[ "$5" = StartTransientUnit ] && exit ${FAKE_START_EXIT:-0}\nexit 0\n' "$U" > "$U/bin/busctl"
chmod 755 "$U/bin/systemctl" "$U/bin/busctl"
up() { rm -f "$U/calls"; env PATH="$U/bin:/usr/bin:/bin" KITE_PROC="$U/proc" PKEXEC_UID="$me" "$@" sh "$UP"; }
up; check "the caller's xfwm4 and picom go into a protected scope (no swap); Brave, renamed programs, other users' and already moved ones do not" \
    test "$(cat "$U/calls")" = "call org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager StartTransientUnit ssa(sv)a(sa(sv)) kite-ui-$me.scope fail 5 PIDs au 2 101 102 Slice s user-$me.slice Description s KiteOS desktop kept in memory (window manager, compositor) MemoryLow t 134217728 MemorySwapMax t 0 0"
up FAKE_ACTIVE=0; check "scope already there (picom restarted): attached" \
    test "$(cat "$U/calls")" = "call org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager AttachProcessesToUnit ssau kite-ui-$me.scope  2 101 102"
up FAKE_START_EXIT=1; check "two calls at login race: the loser attaches" \
    test "$(tail -n1 "$U/calls" | cut -d' ' -f5-6)" = "AttachProcessesToUnit ssau"
rm -rf "$U/proc/101" "$U/proc/102"; up; check "nothing to move: no systemd call" test ! -e "$U/calls"
check "kite-ui-protect only through pkexec" bash -c "! env -u PKEXEC_UID sh '$UP' 2>/dev/null && ! PKEXEC_UID='0 1' sh '$UP' 2>/dev/null"
check "polkit: no password at the laptop, nobody else" bash -c \
    "p='$REPO/packages/kite-desktop/usr/share/polkit-1/actions/org.kiteos.ui-protect.policy'; grep -q '<allow_active>yes</allow_active>' \"\$p\" && grep -q '<allow_any>no</allow_any>' \"\$p\" && grep -q '<allow_inactive>no</allow_inactive>' \"\$p\" && grep -q '>/usr/lib/kite/kite-ui-protect<' \"\$p\""
D=$REPO/packages/kite-desktop/usr/lib/systemd/system
check "X server (pointer) kept in memory: lightdm.service protected, no swap, and its slice passes it on" bash -c \
    "grep -qx 'MemoryLow=256M' '$D/lightdm.service.d/kite-ui.conf' && grep -qx 'MemorySwapMax=0' '$D/lightdm.service.d/kite-ui.conf' && grep -qx 'MemoryLow=256M' '$D/system.slice.d/kite-ui.conf'"
check "user slices pass on the desktop scope's 128 MiB" bash -c \
    "grep -qx 'MemoryLow=128M' '$D/user.slice.d/kite-ui.conf' && grep -qx 'MemoryLow=128M' '$D/user-.slice.d/kite-ui.conf' && grep -q 'low=\$((128 \* 1024 \* 1024))' '$UP'"
printf '#!/bin/sh\necho protect >> "%s/protect"\n' "$U" > "$U/bin/protect-ui"; chmod 755 "$U/bin/protect-ui"
printf '#!/bin/sh\nexit 0\n' > "$U/bin/xfconf-query"; printf '#!/bin/sh\nexec sleep 30\n' > "$U/bin/picom"; chmod 755 "$U/bin/xfconf-query" "$U/bin/picom"
rm -f "$U/protect"; env PATH="$U/bin:/usr/bin:/bin" XDG_RUNTIME_DIR="$U" KITE_DISPLAY_CONF=/nonexistent KITE_POWER_STATE=/nonexistent KITE_PROTECT_UI="$U/bin/protect-ui" timeout 5 sh "$SC" || true
sleep 1; pkill -f "^sleep 30$" || true
check "start-compositor asks for the protection at login and after picom starts" test "$(wc -l < "$U/protect")" -eq 2
check "MGLRU on with a 1 s working-set guard (as on ChromeOS)" bash -c \
    "grep -qx 'w- /sys/kernel/mm/lru_gen/enabled - - - - y' '$REPO/packages/kite-system/usr/lib/tmpfiles.d/kite-memory.conf' && grep -qx 'w- /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000' '$REPO/packages/kite-system/usr/lib/tmpfiles.d/kite-memory.conf'"
check "kite-desktop depends on pkexec" grep -q 'procps, pkexec,' "$REPO/packages/kite-desktop/DEBIAN/control"

echo "== kite-tasks (Task Manager)"
KT=$REPO/packages/kite-desktop/usr/bin/kite-tasks
FP=$T/tasks/proc; FA=$T/tasks/apps; FS=$T/tasks/autostart-sys; FU=$T/tasks/autostart-user
python3 - "$FP" "$FA" "$FS" <<'TASKS_FIXTURE'
import os, sys
proc, apps, sysauto = sys.argv[1:4]
def mk(pid, comm, ppid, uid, exe, argv, ticks=0, anon=1000):
    d = os.path.join(proc, str(pid)); os.makedirs(d)
    open(d + "/stat", "w").write("%d (%s) S %d 0 0 0 0 0 0 0 0 0 %d 0 0 0 20 0 1 0 %d 0 0" % (pid, comm, ppid, ticks, 100 + pid))
    open(d + "/status", "w").write("Name:\t%s\nUid:\t%d\t%d\t%d\t%d\nRssAnon:\t%d kB\n" % (comm, uid, uid, uid, uid, anon))
    open(d + "/cmdline", "w").write("\0".join(argv) + "\0")
    os.symlink(exe, d + "/exe")
mk(1, "systemd", 0, 0, "/usr/lib/systemd/systemd", ["/sbin/init"])
mk(50, "xfce4-session", 1, 1000, "/usr/bin/xfce4-session", ["xfce4-session"])
mk(100, "xfce4-panel", 50, 1000, "/usr/bin/xfce4-panel", ["xfce4-panel"])
mk(101, "wrapper-2.0", 100, 1000, "/usr/lib/x/wrapper-2.0", ["wrapper-2.0", "/x/libdocklike.so", "20", "1", "docklike", "Docklike Taskbar"])
mk(200, "code", 101, 1000, "/usr/share/code/code", ["/usr/share/code/code"], anon=200000)
mk(201, "code", 200, 1000, "/usr/share/code/code", ["/usr/share/code/code", "--type=renderer"], anon=300000)
mk(300, "brave-browser-s", 50, 1000, "/usr/bin/bash", ["/bin/bash", "/usr/bin/brave-browser-stable.distrib"])
mk(301, "brave", 300, 1000, "/opt/brave.com/brave/brave", ["/opt/brave.com/brave/brave"])
mk(400, "nm-applet", 50, 1000, "/usr/bin/nm-applet", ["nm-applet"])
mk(450, "Thunar", 50, 1000, "/usr/bin/thunar", ["thunar", "--daemon"])
mk(500, "NetworkManager", 1, 0, "/usr/sbin/NetworkManager", ["/usr/sbin/NetworkManager"])
open(proc + "/meminfo", "w").write("MemTotal: 4000 kB\nMemAvailable: 1000 kB\nZswap: 10 kB\nZswapped: 40 kB\n")
open(proc + "/200/io", "w").write("rchar: 9\nwchar: 9\nread_bytes: 4096\nwrite_bytes: 8192\n")
open(proc + "/stat", "w").write("cpu  100 0 100 700 100 0 0 0 0 0\n")
os.makedirs(apps); os.makedirs(sysauto)
for name, body in (("code", "Name=Visual Studio Code\nExec=/usr/share/code/code %F\nIcon=vscode"),
                   ("brave-browser", "Name=Brave Web Browser\nExec=/usr/bin/brave-browser-stable %U\nIcon=brave-browser"),
                   ("thunar-bulk-rename", "Name=Bulk Rename\nExec=thunar --bulk-rename %F"),
                   ("thunar", "Name=Thunar File Manager\nExec=thunar %F"),
                   ("nm-applet", "Name=Network\nExec=nm-applet\nNoDisplay=true")):
    open("%s/%s.desktop" % (apps, name), "w").write("[Desktop Entry]\nType=Application\n" + body + "\n")
for name, body in (("blueman", "Name=Blueman Applet\nExec=blueman-applet"),
                   ("xfsettingsd", "Name=Xfce Settings Daemon\nExec=xfsettingsd\nOnlyShowIn=XFCE;"),
                   ("gnome-only", "Name=GNOME thing\nExec=x\nOnlyShowIn=GNOME;")):
    open("%s/%s.desktop" % (sysauto, name), "w").write("[Desktop Entry]\nType=Application\n" + body + "\n")
TASKS_FIXTURE
# Drives for the Performance tab: the eMMC (system), a USB stick, an SD card,
# and devices that are not drives (loop, zram, an eMMC boot area, a CD
# drive, an empty card reader).
python3 - "$FP" "$T/tasks/sys" <<'DISKS_FIXTURE'
import os, sys
proc, sysd = sys.argv[1:3]
def drive(path, dev, size, files=None, parts=()):
    d = os.path.join(sysd, "devices", path, dev)
    os.makedirs(os.path.join(d, "device"), exist_ok=True)
    open(d + "/size", "w").write(str(size))
    for k, v in (files or {}).items():
        open(os.path.join(d, "device", k), "w").write(v + "\n")
    for p in parts:
        os.makedirs(os.path.join(d, p), exist_ok=True)
        open(os.path.join(d, p, "partition"), "w").write("1")
        os.makedirs(os.path.join(sysd, "class/block"), exist_ok=True)
        os.symlink(os.path.join(d, p), os.path.join(sysd, "class/block", p))
    os.makedirs(os.path.join(sysd, "block"), exist_ok=True)
    os.symlink(d, os.path.join(sysd, "block", dev))
drive("platform/mmc0", "mmcblk0", 61071360, {"type": "MMC", "name": "DA4032"}, ("mmcblk0p1", "mmcblk0p2"))
drive("pci0/usb1/1-1/host0/target0", "sda", 30310400, {"vendor": "Kingston", "model": "DataTraveler 3.0"}, ("sda1",))
drive("platform/mmc1", "mmcblk1", 3000000, {"type": "SD", "name": "SD32G"})
drive("platform/mmc2", "mmcblk2", 0, {"type": "SD"})                # empty reader
drive("virtual", "loop0", 1000)
drive("virtual", "zram0", 1000)
drive("platform/mmc0", "mmcblk0boot0", 8192)
drive("pci0/ata1", "sr0", 1000)
os.makedirs(os.path.join(proc, "self"), exist_ok=True)
open(os.path.join(proc, "self/mounts"), "w").write(
    "/dev/mmcblk0p2 / ext4 rw 0 0\n/dev/sda1 /media/kite/USB\\040STICK vfat rw 0 0\nproc /proc proc rw 0 0\n")
DISKS_FIXTURE
kt_py() { KITE_PROC=$FP KITE_SYS=$T/tasks/sys KITE_APP_DIRS=$FA KITE_AUTOSTART_SYSTEM=$FS KITE_AUTOSTART_USER=$FU python3 - "$KT" <<TASKS_PY
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("kt", sys.argv[1])
spec = importlib.util.spec_from_loader("kt", loader); kt = importlib.util.module_from_spec(spec); loader.exec_module(kt)
procs = kt.list_procs(); idx = kt.AppIndex()
def groups(windows=None, admin=False):
    return {g["name"]: g for g in kt.group_processes(procs, 1000, idx, windows, admin)}
$1
TASKS_PY
}
check "an app with everything it started is one row (VS Code, 2 processes)" kt_py \
    'g = groups({201})["Visual Studio Code"]; assert g["kind"] == "app" and g["pids"] == [200, 201], g'
check "app memory is the private memory of all its processes" kt_py \
    'assert sum(procs[p].mem for p in groups({201})["Visual Studio Code"]["pids"]) == 500000 * 1024'
check "Brave through its launcher script is still Brave" kt_py \
    'g = groups({301})["Brave Web Browser"]; assert g["kind"] == "app" and g["pids"] == [300, 301], g'
check "no window: a background process, even with a .desktop file" kt_py \
    'assert groups(set())["Visual Studio Code"]["kind"] == "background"'
check "Thunar is Thunar, not Bulk Rename (same program)" kt_py \
    'assert "Thunar File Manager" in groups({450}) and "Bulk Rename" not in groups({450})'
check "panel plugins by their own name, not ended from here" kt_py \
    'g = groups(set())["Panel: Docklike Taskbar"]; assert g["kind"] == "background" and not g["endable"]'
check "the desktop itself and system processes cannot be ended" kt_py \
    'gs = groups(set()); assert not gs["xfce4-session"]["endable"] and not gs["NetworkManager"]["endable"] and gs["NetworkManager"]["kind"] == "system"'
check "as administrator, system processes can be ended (never init)" kt_py \
    'gs = groups(set(), admin=True); assert gs["NetworkManager"]["endable"] and not gs["systemd"]["endable"]'
check "memory figures in bytes, zswap included" kt_py \
    'm = kt.meminfo(); assert m["MemTotal"] == 4096000 and m["Zswapped"] == 40960 and kt.cpu_ticks() == (200, 1000)'
check "disk counters: read + written, unknown when not readable" kt_py \
    'assert kt.io_bytes(200) == 12288 and kt.io_bytes(201) is None'
check "TCP traffic per process from ss (QUIC/UDP has no counters)" kt_py \
    's = "0  0  10.0.0.2:5000  1.2.3.4:443 users:((\"brave\",pid=301,fd=68))\n\t cubic bytes_sent:500 bytes_acked:400 bytes_received:7000 segs_out:9\n0  0  10.0.0.2:5001  5.6.7.8:443 users:((\"code\",pid=200,fd=3))\n\t cubic bytes_received:10\n"; assert kt.parse_ss(s) == {("10.0.0.2:5000", "1.2.3.4:443"): (301, 500, 7000), ("10.0.0.2:5001", "5.6.7.8:443"): (200, 0, 10)}, kt.parse_ss(s)'
check "sizes read well" kt_py \
    'assert (kt.fmt_bytes(500), kt.fmt_bytes(1536 * 1024), kt.fmt_bytes(3 * 1024 ** 3)) == ("500 B", "1.5 MB", "3.0 GB")'
check "startup apps: XFCE ones only, essentials marked" kt_py \
    'e = {x["file"]: x for x in kt.startup_entries()}; assert set(e) == {"blueman.desktop", "xfsettingsd.desktop"} and e["xfsettingsd.desktop"]["essential"] and not e["blueman.desktop"]["essential"]'
kt_py 'kt.set_startup("blueman.desktop", False)' >/dev/null
check "switching one off writes Hidden=true to your own autostart" bash -c "grep -qx 'Hidden=true' '$FU/blueman.desktop' && grep -qx 'Name=Blueman Applet' '$FU/blueman.desktop'"
check "and the list shows it off" kt_py \
    'assert not {x["file"]: x for x in kt.startup_entries()}["blueman.desktop"]["enabled"]'
kt_py 'kt.set_startup("blueman.desktop", True)' >/dev/null
check "on again: Hidden=false, written once" bash -c "[ \"\$(grep -c '^Hidden=' '$FU/blueman.desktop')\" = 1 ] && grep -qx 'Hidden=false' '$FU/blueman.desktop'"
# Debian's plain picom autostart entry is switched off by KiteOS's copy
# (start-compositor runs picom): not a startup app, not started twice.
printf '[Desktop Entry]\nType=Application\nName=picom\nExec=picom\n' > "$FS/picom.desktop"
check "KiteOS's switched-off entries are not listed (Debian's plain picom)" bash -c \
    "KITE_AUTOSTART_KITE='$REPO/packages/kite-desktop/usr/share/kite/xdg-config/autostart' KITE_PROC=$FP KITE_SYS=$T/tasks/sys KITE_APP_DIRS=$FA KITE_AUTOSTART_SYSTEM=$FS KITE_AUTOSTART_USER=$FU python3 -c 'import importlib.machinery, importlib.util, sys; l = importlib.machinery.SourceFileLoader(\"kt\", \"$KT\"); s = importlib.util.spec_from_loader(\"kt\", l); kt = importlib.util.module_from_spec(s); l.exec_module(kt); sys.exit(0 if \"picom.desktop\" not in {x[\"file\"] for x in kt.startup_entries()} else 1)'"
rm -f "$FS/picom.desktop"
check "the session finds KiteOS's autostart copies first" bash -c \
    "grep -q '^XDG_CONFIG_DIRS=\"/usr/share/kite/xdg-config:' '$REPO/packages/kite-desktop/etc/X11/Xsession.d/45kite-user-init' && grep -qx 'Hidden=true' '$REPO/packages/kite-desktop/usr/share/kite/xdg-config/autostart/picom.desktop'"
check "Task Manager opens compact (720 x 500)" grep -q 'self.set_default_size(720, 500)' "$KT"
check "Performance: every drive, system disk first, USB stick and SD card named" kt_py \
    'd = kt.disks(); assert [(x["dev"], x["kind"], x["name"]) for x in d] == [("mmcblk0", "system", "Disk (system)"), ("mmcblk1", "sd", "SD card"), ("sda", "usb", "USB drive")], d'
check "Performance: a drive's mount points (spaces decoded) and model" kt_py \
    'd = {x["dev"]: x for x in kt.disks()}; assert d["mmcblk0"]["mounts"] == ["/"] and d["sda"]["mounts"] == ["/media/kite/USB STICK"] and d["sda"]["model"] == "Kingston DataTraveler 3.0" and d["mmcblk1"]["mounts"] == [], d'
check "processes: one list, no Apps / Background / System sections" bash -c "! grep -q 'SECTIONS\|section:' '$KT'"
check "Ctrl+Shift+Esc opens it" grep -q '"<Primary><Shift>Escape": "kite-tasks"' "$REPO/packages/kite-desktop/usr/bin/kite-layout"
check "administrator mode through pkexec, with a window" bash -c "grep -q 'exec.allow_gui\">true' '$REPO/packages/kite-desktop/usr/share/polkit-1/actions/org.kiteos.tasks.policy' && grep -q '/usr/bin/kite-tasks' '$REPO/packages/kite-desktop/usr/share/polkit-1/actions/org.kiteos.tasks.policy'"
check "xfce4-taskmanager replaced" bash -c "! grep -q xfce4-taskmanager '$REPO/packages/kite-desktop/DEBIAN/control' '$REPO/live/config/package-lists/kite-desktop.list.chroot'"

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
check "offers kite-docklike in place of Debian's plugin, nothing from Debian itself" ku_py \
    'release["assets"] += [{"name": "kite-docklike_0.4.3-1+kite1_amd64.deb"}, {"name": "xfwm4_4.20.0-1_amd64.deb"}]
p = ku.plan(release, {"xfce4-docklike-plugin": "0.4.3-1+b1", "xfwm4": "4.18.0-1"}.get, lambda a, b: a != b)
assert [(x[0], x[1]) for x in p] == [("kite-docklike", "xfce4-docklike-plugin 0.4.3-1+b1")], p'
check "kite-docklike not offered where neither docklike is installed" ku_py \
    'release["assets"] += [{"name": "kite-docklike_0.4.3-1+kite1_amd64.deb"}]
assert ku.plan(release, {}.get, newer) == []'
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
check "a release still building (no packages yet) says so, not up to date" ku_py '
import contextlib, io
release["assets"] = []
ku.fetch = lambda url, binary=False: __import__("json").dumps(release)
out = io.StringIO()
with contextlib.redirect_stdout(out):
    rc = ku.main(["--check"])
assert rc == 0 and "still being built" in out.getvalue() and "up to date" not in out.getvalue(), (rc, out.getvalue())'
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
# A .deb file double-clicked in Files or a download
check ".deb: dpkg-deb fields read, long description left out" ac_py \
    'f = ac.parse_deb_fields("Package: foo\nVersion: 1.2-1\nArchitecture: amd64\nInstalled-Size: 2048\nDescription: Foo tool\n Long text.\n .\n More.\n"); assert f == {"Package": "foo", "Version": "1.2-1", "Architecture": "amd64", "Installed-Size": "2048", "Description": "Foo tool"}, f'
check ".deb: install / upgrade / reinstall / downgrade" ac_py \
    'n = lambda a, b: a > b; assert [ac.deb_action(i, "2", n) for i in (None, "1", "2", "3")] == ["install", "upgrade", "reinstall", "downgrade"]'
check ".deb: architecture must match (or all)" ac_py \
    'assert ac.deb_arch_ok("amd64", "amd64") and ac.deb_arch_ok("all", "amd64") and not ac.deb_arch_ok("arm64", "amd64")'
check ".deb: apt's simulation gives extra packages, removals and errors" ac_py \
    's = "Inst libbar (1.0 Debian:13 [amd64])\nInst foo (1.2-1 local-deb [amd64])\nRemv oldfoo [0.9]\nConf foo (1.2-1)\n"; assert ac.parse_simulated_install(s, "foo") == (["libbar"], ["oldfoo"], []); e = " foo : Depends: libqux (>= 3) but it is not installable\nE: Unable to correct problems, you have held broken packages.\n"; assert len(ac.parse_simulated_install(e, "foo")[2]) == 2'
check ".deb: the question names the change, the extras and the trust warning" ac_py \
    'q, v = ac.deb_question({"Package": "foo", "Version": "2", "Description": "Foo & co", "Installed-Size": "2048"}, "upgrade", "1", ["libbar"], []); assert v == "Upgrade" and "from 1 to 2" in q and "Foo &amp; co" in q and "2.0 MB" in q and "libbar" in q and "trust" in q, q'
check ".deb: reinstall and downgrade pass apt the right option" ac_py \
    'assert ac.install_steps("/home/u/foo.deb", "u", False, False, ["--reinstall"])[0][-4:] == ["--reinstall", "--user", "u", "/home/u/foo.deb"]'
check ".deb: double-click opens App Centre's installer, and it is the default" bash -c \
    "grep -qx 'Exec=kite-app-centre --install-file %f' '$REPO/packages/kite-storage/usr/share/applications/kite-install-package.desktop' && grep -q 'application/vnd.debian.binary-package' '$REPO/packages/kite-storage/usr/share/applications/kite-install-package.desktop' && grep -qx 'application/vnd.debian.binary-package=kite-install-package.desktop' '$REPO/packages/kite-desktop/etc/xdg/mimeapps.list'"
check ".deb handler claims no window class (the taskbar pin must find App Centre's launcher)" bash -c \
    "! grep -q '^StartupWMClass=' '$REPO/packages/kite-storage/usr/share/applications/kite-install-package.desktop'"
check "no two KiteOS launchers share a window class (docklike matches pins by it first)" bash -c \
    "! grep -h '^StartupWMClass=' '$REPO'/packages/*/usr/share/applications/*.desktop | sort | uniq -d | grep -q ."
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
    {"name": "/dev/sdd", "size": "4G", "fstype": None, "label": None, "type": "disk", "pkname": None, "tran": "usb", "rm": True, "hotplug": True},
    {"name": "/dev/loop0p1", "size": "1G", "fstype": "ext4", "label": None, "type": "part", "pkname": "/dev/loop0"}]})
r = ac.external_partitions(j, "mmcblk0", "/dev/sdc", {"mmcblk1"})
assert [x["name"] for x in r] == ["/dev/mmcblk1p1", "/dev/sda1", "/dev/sdb1", "/dev/sdd"], r
assert r[3] == {"name": "/dev/sdd", "size": "4G", "fstype": "none", "label": "blank disk"}, r
assert r[1] == {"name": "/dev/sda1", "size": "58G", "fstype": "none", "label": "-"}, r
assert [x["name"] for x in ac.external_partitions(j, "", "", ())] == ["/dev/sda1", "/dev/sdb1", "/dev/sdc2", "/dev/sdd"]
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
