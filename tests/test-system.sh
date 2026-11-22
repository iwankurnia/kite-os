#!/bin/bash
# shellcheck disable=SC1090,SC2016,SC2034  # tests source scripts dynamically and match literal ${...}
# Tests for the hibernation helper, keyboard map generator, splash builder
# and the user-init script. Safe: works only inside a temp directory.
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

echo "== kite-user-init (keyboard shortcuts merge)"
if [ -f /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml ]; then
    HOME=$T/home DISPLAY='' python3 "$REPO/packages/kite-desktop/usr/lib/kite/desktop/kite-user-init"
    f=$T/home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
    check "user shortcut file created" test -f "$f"
    check "valid XML" xmllint --noout "$f"
    check "custom list marked as override" bash -c "xmllint --xpath \"//property[@name='commands']/property[@name='custom']/property[@name='override']/@value\" '$f' | grep -q true"
    check "Super+Space -> launcher" bash -c "xmllint --xpath \"//property[@name='commands']/property[@name='custom']/property[@name='<Super>space']/@value\" '$f' | grep -q kite-launcher"
    n_def=$(xmllint --xpath "count(//property[@name='commands']/property[@name='default']/property)" "$f")
    n_cus=$(xmllint --xpath "count(//property[@name='commands']/property[@name='custom']/property)" "$f")
    check "XFCE defaults kept ($n_def defaults, $n_cus custom)" test "${n_cus%.*}" -gt "${n_def%.*}"
    echo "<marker/>" > "$T/marker"; cp "$f" "$T/before.xml"
    HOME=$T/home DISPLAY='' python3 "$REPO/packages/kite-desktop/usr/lib/kite/desktop/kite-user-init"
    check "never overwrites the user's file" cmp -s "$f" "$T/before.xml"
else
    echo "  skip (xfce4-settings not installed here)"
fi

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

echo
echo "system tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
