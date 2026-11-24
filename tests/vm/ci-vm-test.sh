#!/bin/bash
# shellcheck disable=SC2016  # commands in single quotes run inside the VM
# Automated VM test of a KiteOS ISO, for GitHub Actions (KVM) or any Linux
# host with QEMU, OVMF, ImageMagick, tesseract and xorriso:
#
#   tests/vm/ci-vm-test.sh kiteos-X.Y.Z-amd64.iso OUTDIR
#
# Boots the live ISO, runs live-session checks over a serial console, installs
# with the chosen layout (KITE_LAYOUT, default mac) by clicking through the
# installer (OCR), boots the installed system, logs in and checks it.
# Screenshots, logs and report.md (a pass/fail table) go to OUTDIR. Exit
# status: the number of failed checks (0 = all passed), or 100 when the run
# itself broke.
#
# The serial console is test plumbing: the live system is started with its
# own kernel and console=ttyS0 (so no boot menu there; the boot menu gets its
# own screenshot first), and the installed system gets a serial console added
# from the live session before its first boot. Nothing else is changed.
set -uo pipefail
ISO=$(realpath "$1")
OUT=$(mkdir -p "$2" && realpath "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
export KITEVM_DIR=${KITEVM_DIR:-$OUT/run} KITEVM_RES=1360x768 KITEVM_CPU=${KITEVM_CPU:-host}
mkdir -p "$KITEVM_DIR"
VM=kite
LAYOUT=${KITE_LAYOUT:-mac}
FULL="Kite Tester" LOGIN=tester HOST=kiteos-test PASS=kitepass1
REPORT=$OUT/report.md
FAILS=0
T0=$(date +%s)

k() { "$HERE/kitevm.py" "$@"; }
now() { echo "$(( $(date +%s) - T0 ))s"; }
log() { echo "[$(now)] $*"; }
row() {  # row PASS|FAIL|INFO "check" "detail"
    local mark=ℹ️
    [ "$1" = PASS ] && mark=✅
    [ "$1" = FAIL ] && { mark=❌; FAILS=$((FAILS + 1)); }
    printf '| %s | %s | %s |\n' "$2" "$mark" "${3//|/\\|}" >> "$REPORT"
    log "$1: $2${3:+ — $3}"
}
shot() { k shot "$VM" "$OUT/$1.png" >/dev/null 2>&1 || true; }
# Run a command inside the VM (serial console); prints its output. The command
# is sent as base64, so nothing in it is expanded or unquoted on this side.
vm() {
    local b64
    b64=$(printf '%s' "$1" | base64 -w0)
    k sh "$VM" "echo $b64 | base64 -d | bash" "${2:-120}" 2>&1 | tr -d '\r'
}
# GUI environment for commands run from the serial console.
GUI='export DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus;'
short() { tr '\n' ' ' <<< "$1" | sed 's/  */ /g' | cut -c1-200; }
has() {    # has "check" "command in the VM" "regex"   PASS when the output matches
    local out
    out=$(vm "$2" "${4:-120}")
    if grep -qE -- "$3" <<< "$out"; then row PASS "$1" "$(short "$(grep -E -- "$3" <<< "$out" | head -n1)")"
    else row FAIL "$1" "got: $(short "$out")"; fi
}
lacks() {  # lacks "check" "command in the VM" "regex"  PASS when it does not match
    local out
    out=$(vm "$2; echo __RAN__" "${4:-120}")
    if ! grep -q __RAN__ <<< "$out"; then row FAIL "$1" "command did not finish: $(short "$out")"
    elif grep -qE -- "$3" <<< "$out"; then row FAIL "$1" "found: $(short "$(grep -E -- "$3" <<< "$out" | head -n2)")"
    else row PASS "$1" ""; fi
}
ocr_has() {  # ocr_has "check" "regex"
    if k ocr "$VM" | grep -qiE -- "$2"; then row PASS "$1" ""; else row FAIL "$1" "not on screen"; fi
}
die() { row FAIL "run aborted" "$1"; shot "aborted"; k stop "$VM" >/dev/null 2>&1; finish 100; }
finish() {
    { echo; echo "Failed checks: $FAILS. Run time: $(now)."; } >> "$REPORT"
    cp -f "$KITEVM_DIR"/*.serial.log "$OUT"/ 2>/dev/null || true
    exit "${1:-$FAILS}"
}
wait_desktop() {  # until the window manager and the panel run
    local i
    for i in $(seq 90); do
        vm 'pgrep -x xfwm4 >/dev/null && pgrep -x xfce4-panel >/dev/null && echo UP' 15 | grep -q UP && return 0
        sleep 2
    done
    return 1
}

{
    echo "# KiteOS VM test: $(basename "$ISO")"
    echo
    echo "SHA-256 \`$(sha256sum "$ISO" | cut -d' ' -f1)\`, layout picked in the installer: **$LAYOUT**,"
    echo "QEMU $(qemu-system-x86_64 --version | head -n1 | awk '{print $4}'), KVM: $([ -w /dev/kvm ] && echo yes || echo no)."
    echo
    echo "| Check | Result | Detail |"
    echo "|---|---|---|"
} > "$REPORT"

# ------------------------------------------------------------ boot menu --
qemu-img create -q -f qcow2 "$KITEVM_DIR/emmc.qcow2" 32G
k start "$VM" --iso "$ISO" --disk "$KITEVM_DIR/emmc.qcow2" || die "QEMU did not start"
if k wait "$VM" 'Try or install KiteOS|install KiteOS' 120 >/dev/null; then
    shot 01-boot-menu; row PASS "boot menu" "KiteOS entries shown (01-boot-menu.png)"
else shot 01-boot-menu; row FAIL "boot menu" "no 'Try or install KiteOS' entry (01-boot-menu.png)"; fi
k keys "$VM" ret; sleep 2; shot 02-boot-loading
row INFO "boot: screen while Linux loads" "02-boot-loading.png (a black rectangle in 1.3.0)"
sleep 25; shot 03-splash
k stop "$VM"; sleep 2

# ---------------------------------------------------------- live session --
# live-build may name them with the kernel version (vmlinuz-6.12…).
isofind() { xorriso -indev "$ISO" -find /live -name "$1" 2>/dev/null | tr -d "'" | grep '^/live/' | sort | tail -n1; }
KERN=$(isofind 'vmlinuz*') INITRD=$(isofind 'initrd.img*')
log "live kernel: ${KERN:-?}, initrd: ${INITRD:-?}"
[ -n "$KERN" ] && [ -n "$INITRD" ] || die "no kernel/initrd under /live in the ISO"
xorriso -osirrox on -indev "$ISO" -extract "$KERN" "$KITEVM_DIR/vmlinuz" \
        -extract "$INITRD" "$KITEVM_DIR/initrd.img" > "$OUT/xorriso.log" 2>&1 ||
    die "could not extract the live kernel: $(tail -n2 "$OUT/xorriso.log" | tr '\n' ' ')"
APPEND="boot=live components quiet splash username=kite user-fullname=KiteOS hostname=kiteos locales=en_GB.UTF-8 keyboard-layouts=us console=tty0 console=ttyS0,115200"
k start "$VM" --iso "$ISO" --disk "$KITEVM_DIR/emmc.qcow2" --kernel "$KITEVM_DIR/vmlinuz" \
        --initrd "$KITEVM_DIR/initrd.img" --append "$APPEND" || die "live VM did not start"
k login "$VM" kite live >/dev/null || die "no serial login in the live session"
wait_desktop || die "live desktop did not come up"
log "live desktop up"
sleep 8; shot 10-live-desktop
has   "live: windows layout" 'cat ~/.config/kite/layout' '^windows$'
lacks "live: picom not running" 'pgrep -a picom' 'picom'
lacks "live: no add-calamares-desktop-icon error" 'cat ~/.xsession-errors 2>/dev/null' 'add-calamares'
has   "live: panel plugins in their own processes (wrappers)" 'echo wrappers=$(pgrep -c -f "xfce4/panel/wrapper")' 'wrappers=[1-9]'
lacks "live: ONLYOFFICE finds all its libraries" 'cd /opt/onlyoffice/desktopeditors && LD_LIBRARY_PATH=$PWD:$PWD/converter ldd DesktopEditors' 'not found'
has   "live: window keys = standard (not a Chromebook)" 'kite-layout keys' 'standard'
has   "live: one key per window action" 'python3 - <<"PY"
import collections, os, xml.etree.ElementTree as E
r = E.parse(os.path.expanduser("~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml")).getroot()
v = [p.get("value") for p in r.findall("./property[@name=\"xfwm4\"]/property[@name=\"custom\"]/property") if p.get("type") == "string"]
d = [a for a, n in collections.Counter(v).items() if n > 1]
print("duplicates:", ", ".join(d) if d else "none")
PY' 'duplicates: none'
# Whisker menu moves its settings from whiskermenu-1.rc into xfconf on start.
has   "live: menu favourites set" "$GUI"' xfconf-query -c xfce4-panel -lv | grep -i favorites; grep -h ^favorites= ~/.config/xfce4/panel/whiskermenu-*.rc 2>/dev/null' 'brave-browser'

# Layout switching: each switch must keep a window manager, one panel
# process, and actually change the window theme.
for i in 1 2 3 4; do
    L=$([ $((i % 2)) = 1 ] && echo mac || echo windows)
    t=$(date +%s)
    vm "$GUI kite-layout $L" 120 >/dev/null
    took=$(( $(date +%s) - t ))
    sleep 6
    st=$(vm "$GUI"' echo "wm=$(pgrep -cx xfwm4) panels=$(pgrep -cx xfce4-panel) theme=$(xfconf-query -c xfwm4 -p /general/theme) buttons=$(xfconf-query -c xfwm4 -p /general/button_layout)"' 30)
    shot "1$((i + 1))-switch-$i-$L"
    want_theme=$([ "$L" = mac ] && echo Qogir || echo Fluent)
    if grep -q 'wm=1 panels=1' <<< "$st" && grep -q "theme=$want_theme" <<< "$st"; then
        row PASS "live: switch $i to $L" "${took}s, $(short "$st")"
    else
        row FAIL "live: switch $i to $L" "${took}s, $(short "$st") (1$((i + 1))-switch-$i-$L.png)"
    fi
done
vm 'tail -n 30 ~/.cache/kite-layout.log' 30 > "$OUT/kite-layout-log.txt"

# Your own settings stay over a switch (the layout is windows again here).
vm "$GUI"' xfconf-query -c xfce4-terminal -p /font-name -n -t string -s "DejaVu Sans Mono 13"; xfconf-query -c xsettings -p /Gtk/FontName -s "DejaVu Sans 11"' 30 >/dev/null
vm "$GUI kite-layout mac; sleep 4; kite-layout windows" 200 >/dev/null; sleep 6
has "live: Terminal font kept over two switches" "$GUI"' xfconf-query -c xfce4-terminal -p /font-name' 'DejaVu Sans Mono 13'
has "live: desktop font kept over two switches" "$GUI"' xfconf-query -c xsettings -p /Gtk/FontName' 'DejaVu Sans 11'

# Command-line safety (kite-storage) with a throw-away USB disk.
qemu-img create -q -f raw "$KITEVM_DIR/usb.img" 2G
k usb "$VM" add "$KITEVM_DIR/usb.img"; sleep 5
USBDEV=$(vm 'lsblk -dpno NAME,TRAN | awk '"'"'$2 == "usb" { print $1 }'"'"' | head -n1' 30 | grep '^/dev/' | head -n1)
if [ -n "$USBDEV" ]; then
    has "storage: a blank USB stick can be set up ($USBDEV)" "sudo kite-storage setup $USBDEV --format 2>&1" 'external disk ready' 180
else
    row FAIL "storage: USB disk visible" "no USB disk in lsblk"
fi
has "storage: setup refuses the internal disk" 'sudo kite-storage setup /dev/nvme0n1 --format 2>&1; echo rc=$?' 'built-in|internal disk'
has "storage: move-dir /boot refused" 'sudo kite-storage move-dir /boot 2>&1; test -d /boot -a ! -L /boot && echo STILL-THERE' 'STILL-THERE'
has "storage: move-dir /etc/ssh refused" 'sudo kite-storage move-dir /etc/ssh 2>&1' 'system folder'
has "resource report: --seconds 0 is a usage error" 'kite-resource-report --seconds 0 >/dev/null 2>&1; echo rc=$?' 'rc=2'
vm 'sudo umount /mnt/kite-external 2>/dev/null; true' 30 >/dev/null
k usb "$VM" del >/dev/null 2>&1 || true

# ------------------------------------------------------------- installer --
vm "$GUI"' (setsid kite-install >/tmp/kite-install.log 2>&1 &)' 30 >/dev/null
if ! k wait "$VM" 'Welcome to the' 180 >/dev/null; then
    shot 30-inst-welcome
    vm 'cat /tmp/kite-install.log' 30 > "$OUT/kite-install.log"
    die "installer did not open (kite-install.log)"
fi
sleep 4; shot 30-inst-welcome
ocr_has "installer: welcome wording" 'Welcome to the KiteOS'
VER=$(basename "$ISO" | sed -nE 's/kiteos-([0-9.]+)-amd64\.iso/\1/p')
[ -n "$VER" ] && ocr_has "installer: shows version $VER" "${VER//./\\.}"
next() { k clicktext "$VM" 'Next' 60 --last >/dev/null || die "no Next button ($1)"; sleep "${2:-6}"; }
CLOCK1=$(vm 'date +%H:%M' 20 | grep -E '^[0-9]{2}:[0-9]{2}$' | tail -n1)
next welcome; shot 31-inst-location
ocr_has "installer: Location defaults to Jakarta" 'Jakarta'
CLOCK2=$(vm 'date +%H:%M' 20 | grep -E '^[0-9]{2}:[0-9]{2}$' | tail -n1)
if [ -n "$CLOCK1" ] && [ -n "$CLOCK2" ]; then
    h1=${CLOCK1%%:*} h2=${CLOCK2%%:*}
    if [ $(( (10#$h2 - 10#$h1 + 24) % 24 )) -le 1 ]; then row PASS "installer: live clock unchanged" "$CLOCK1 → $CLOCK2"
    else row FAIL "installer: live clock unchanged" "$CLOCK1 → $CLOCK2"; fi
fi
next location; shot 32-inst-keyboard
next keyboard 8
k clicktext "$VM" 'Erase disk' 60 >/dev/null || row FAIL "installer: Erase disk option" "not found by OCR"
sleep 3; shot 33-inst-partitions
next partitions 8; shot 34-inst-users-empty
# The fields' placeholder text is too pale for OCR: click under the question
# (the first field also has the focus already).
k clicktext "$VM" 'What is your name' 60 --dy 26 >/dev/null || die "users page not found"
k type "$VM" "$FULL"
k keys "$VM" tab; k keys "$VM" ctrl-a; k type "$VM" "$LOGIN"
k keys "$VM" tab; k keys "$VM" ctrl-a; k type "$VM" "$HOST"
k keys "$VM" tab; k type "$VM" "$PASS"
k keys "$VM" tab; k type "$VM" "$PASS"
sleep 3; shot 35-inst-users-filled
next users 6; shot 36-inst-desktop-page
PICK=$([ "$LAYOUT" = mac ] && echo 'Mac style' || echo 'Windows style')
k clicktext "$VM" "$PICK" 60 >/dev/null || die "Desktop page: no '$PICK'"
sleep 3; shot 37-inst-desktop-picked
next desktop 8; shot 38-inst-summary
SUMMARY=$(k ocr "$VM")
if grep -q 'English (UK)' <<< "$SUMMARY"; then row FAIL "installer: keyboard stays English (US)" "Summary says English (UK)"
elif grep -q 'English (US)' <<< "$SUMMARY"; then row PASS "installer: keyboard stays English (US)" "on the Summary page"
else row FAIL "installer: keyboard stays English (US)" "keyboard layout not read on the Summary page"; fi
# The sidebar also says "Install": take the button right of "Back".
k clicktext "$VM" '^Back$' 60 --last --dx 86 >/dev/null || die "no Back/Install buttons on the Summary page"
sleep 4; shot 39-inst-confirm
k clicktext "$VM" 'Install Now' 60 >/dev/null || die "no Install Now in the confirm dialog"
TI=$(date +%s)
log "installing"
if k wait "$VM" 'All done|has been installed|Installation Failed' 3600 >/dev/null; then
    shot 40-inst-finished
    k ocr "$VM" | grep -qi 'Installation Failed' && die "installation failed (40-inst-finished.png)"
    row PASS "installer: install finished" "$(( $(date +%s) - TI ))s"
else shot 40-inst-finished; die "install did not finish within an hour"; fi
vm 'sudo cat "$(sudo ls -t /root/.cache/Calamares/session.log /root/.cache/calamares/session.log 2>/dev/null | head -n1)"' 120 > "$OUT/calamares-session.log"
if grep -q 'unknown variable' "$OUT/calamares-session.log"; then row FAIL "installer: Desktop choice reached its job" "$(grep -m1 'unknown variable' "$OUT/calamares-session.log" | cut -c1-200)"
else row PASS "installer: Desktop choice reached its job" "no unknown-variable warning"; fi
if grep -qiE 'hwclock failed|failed to run command .hwclock' "$OUT/calamares-session.log"; then row FAIL "installer: hwclock" "$(grep -m1 -iE 'hwclock' "$OUT/calamares-session.log" | cut -c1-200)"
else row PASS "installer: hwclock" "no hwclock error"; fi

# Give the installed system a serial console (test plumbing), check its files.
ROOTP=$(vm 'lsblk -pnlo NAME,FSTYPE /dev/nvme0n1 | awk '"'"'$2 == "ext4" { print $1 }'"'"' | head -n1' 30 | grep '^/dev/' | head -n1)
vm "sudo mkdir -p /mnt/t && sudo mount $ROOTP /mnt/t && echo MOUNTED" 60 | grep -q MOUNTED || die "could not mount the installed system ($ROOTP)"
has "installed: /etc/kite/layout = $LAYOUT" 'cat /mnt/t/etc/kite/layout' "^$LAYOUT\$"
has "installed: hwclock present" 'test -x /mnt/t/usr/sbin/hwclock && echo yes' '^yes$'
vm 'sudo ln -sf /lib/systemd/system/serial-getty@.service /mnt/t/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
sudo sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"console=tty0 console=ttyS0,115200 /" /mnt/t/etc/default/grub
for d in dev proc sys; do sudo mount --bind /$d /mnt/t/$d; done
sudo chroot /mnt/t update-grub >/dev/null 2>&1; echo grub=$?
for d in dev proc sys; do sudo umount /mnt/t/$d; done
sudo umount /mnt/t' 300 > "$OUT/serial-setup.txt"
k stop "$VM"; sleep 3

# ------------------------------------------------------- installed system --
k start "$VM" --disk "$KITEVM_DIR/emmc.qcow2" || die "installed system did not start"
if k wait "$VM" "$FULL|Password" 600 >/dev/null; then
    sleep 5; shot 50-login; row PASS "installed: login screen" "50-login.png"
else shot 50-login; row FAIL "installed: login screen" "user not shown (50-login.png)"; fi
k type "$VM" "$PASS"; k keys "$VM" ret
k login "$VM" "$LOGIN" "$PASS" >/dev/null || die "no serial login on the installed system"
wait_desktop || row FAIL "installed: desktop came up" "no window manager / panel"
sleep 8; shot 51-desktop
has   "installed: account layout = $LAYOUT" 'cat ~/.config/kite/layout' "^$LAYOUT\$"
[ "$LAYOUT" = mac ] && has "installed: mac layout has the menu bar and the Dock" "$GUI"' xfconf-query -c xfce4-panel -p /panels | tr "\n" " "' '1 2|2 1'
has   "installed: window manager running" 'pgrep -x xfwm4 && echo WM' '^WM$'
has   "installed: no failed services" 'n=$(systemctl --failed --no-legend --plain | grep -vc serial-getty); echo failed=$n; systemctl --failed --no-legend --plain' 'failed=0'
lacks "installed: picom not running" 'pgrep -a picom' 'picom'
has   "installed: hibernation ready" 'grep -o "resume=[^ ]*" /proc/cmdline' 'resume='
has   "installed: login screen light theme" 'grep -h "^theme-name" /usr/share/glib-2.0/schemas/*slick-greeter*.override' 'Fluent-Light'
vm 'tail -n 80 ~/.xsession-errors 2>/dev/null' 30 > "$OUT/installed-xsession-errors.txt"
k stop "$VM"
finish
