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

echo
echo "system tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
