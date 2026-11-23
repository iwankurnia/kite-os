#!/bin/bash
# shellcheck disable=SC2016  # commands in single quotes run inside the VM
# Automated VM test of a KiteOS ISO, for GitHub Actions (KVM) or any Linux
# host with QEMU, OVMF, ImageMagick, tesseract and xorriso:
#
#   tests/vm/ci-vm-test.sh kiteos-X.Y.Z-amd64.iso OUTDIR
#
# Boots the live ISO, runs live-session checks over a serial console, installs
# with the Mac layout by clicking through the installer (OCR), boots the
# installed system, logs in and checks it. Screenshots, logs and report.md
# (a pass/fail table) go to OUTDIR. Exit status: the number of failed checks
# (0 = all passed), or 100+ when the run itself broke.
#
# The serial console is test plumbing: the live system is started with its
# own kernel and console=ttyS0 (so no boot menu there; the boot menu gets its
# own screenshot first), and the installed system gets a serial getty added
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
k() { "$HERE/kitevm.py" "$@"; }
REPORT=$OUT/report.md
FAILS=0
T0=$(date +%s)
now() { echo "$(( $(date +%s) - T0 ))s"; }
log() { echo "[$(now)] $*"; }
row() {  # row PASS|FAIL|INFO "check" "detail"
    printf '| %s | %s | %s |\n' "$2" "$([ "$1" = PASS ] && echo ✅ || { [ "$1" = FAIL ] && echo ❌ || echo ℹ️; })" "${3//|/\\|}" >> "$REPORT"
    [ "$1" = FAIL ] && FAILS=$((FAILS + 1))
    log "$1: $2${3:+ — $3}"
}
check() {  # check "name" command...   (PASS when the command succeeds)
    local name=$1; shift
    local out
    if out=$("$@" 2>&1); then row PASS "$name" "$(tail -n1 <<< "$out" | cut -c1-160)"
    else row FAIL "$name" "$(tail -n3 <<< "$out" | tr '\n' ' ' | cut -c1-240)"; fi
}
shot() { k shot "$VM" "$OUT/$1.png" >/dev/null 2>&1 || true; }
s() { k sh "$VM" "$1" "${2:-120}"; }          # run on the serial console, prints output
sq() { s "$1" "${2:-120}" 2>/dev/null; }
die() { row FAIL "run aborted" "$1"; shot "aborted"; k stop "$VM" >/dev/null 2>&1; finish 100; }
finish() {
    { echo; echo "Failed checks: $FAILS. Run time: $(now)."; } >> "$REPORT"
    cp -f "$KITEVM_DIR"/*.serial.log "$OUT"/ 2>/dev/null || true
    exit "${1:-$FAILS}"
}
X="export DISPLAY=:0 XAUTHORITY=\$HOME/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus"

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
qemu-img create -q -f qcow2 "$OUT/run/emmc.qcow2" 32G
k start "$VM" --iso "$ISO" --disk "$OUT/run/emmc.qcow2" || die "QEMU did not start"
if k wait "$VM" 'Try or install KiteOS|install KiteOS' 120 >/dev/null; then
    shot 01-boot-menu; row PASS "boot menu" "KiteOS entries shown (01-boot-menu.png)"
else shot 01-boot-menu; row FAIL "boot menu" "no 'Try or install KiteOS' entry (01-boot-menu.png)"; fi
# Let GRUB start Linux and catch the moment the console box used to show black.
k keys "$VM" ret; sleep 2; shot 02-boot-loading
row INFO "boot: screen while Linux loads" "see 02-boot-loading.png (was a black rectangle in 1.3.0)"
k wait "$VM" 'zzz-never' 25 >/dev/null; shot 03-splash
k stop "$VM"; sleep 2

# ---------------------------------------------------------- live session --
# live-build may name them with the kernel version (vmlinuz-6.12…).
isofind() { xorriso -indev "$ISO" -find /live -name "$1" 2>/dev/null | tr -d "'" | grep '^/live/' | sort | tail -n1; }
KERN=$(isofind 'vmlinuz*') INITRD=$(isofind 'initrd.img*')
log "live kernel: ${KERN:-?}, initrd: ${INITRD:-?}"
[ -n "$KERN" ] && [ -n "$INITRD" ] || die "no kernel/initrd under /live in the ISO"
xorriso -osirrox on -indev "$ISO" -extract "$KERN" "$OUT/run/vmlinuz" \
        -extract "$INITRD" "$OUT/run/initrd.img" > "$OUT/xorriso.log" 2>&1 ||
    die "could not extract the live kernel: $(tail -n2 "$OUT/xorriso.log" | tr '\n' ' ')"
APPEND="boot=live components quiet splash username=kite user-fullname=KiteOS hostname=kiteos locales=en_GB.UTF-8 keyboard-layouts=us console=tty0 console=ttyS0,115200"
k start "$VM" --iso "$ISO" --disk "$OUT/run/emmc.qcow2" --kernel "$OUT/run/vmlinuz" \
        --initrd "$OUT/run/initrd.img" --append "$APPEND" || die "live VM did not start"
k login "$VM" kite live >/dev/null || die "no serial login in the live session"
log "live session up"
for _ in $(seq 60); do sq "$X; xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null && pgrep -x xfce4-panel >/dev/null" 10 >/dev/null && break; sleep 3; done
sleep 8; shot 10-live-desktop
check "live: windows layout" bash -c "[ \"\$($HERE/kitevm.py sh $VM 'cat ~/.config/kite/layout' 20)\" = windows ]"
check "live: picom not running" bash -c "! $HERE/kitevm.py sh $VM 'pgrep -a picom' 20 | grep -q picom"
check "live: no add-calamares-desktop-icon error" bash -c "! $HERE/kitevm.py sh $VM 'cat ~/.xsession-errors 2>/dev/null' 30 | grep -q add-calamares"
check "live: window keys = standard (not a Chromebook)" bash -c "$HERE/kitevm.py sh $VM 'kite-layout keys' 30 | grep -q standard"
KEYCHK="python3 -c 'import collections, xml.etree.ElementTree as E, os; r = E.parse(os.path.expanduser(\"~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml\")).getroot(); v = [p.get(\"value\") for p in r.findall(\"./property[@name=\x27xfwm4\x27]/property[@name=\x27custom\x27]/property\") if p.get(\"type\") == \"string\"]; d = [a for a, n in collections.Counter(v).items() if n > 1]; print(\"duplicates:\", d or \"none\")'"
check "live: one key per window action" bash -c "$HERE/kitevm.py sh $VM \"$KEYCHK\" 30 | grep -q 'duplicates: none'"
check "live: menu favourites set" bash -c "$HERE/kitevm.py sh $VM 'grep ^favorites= ~/.config/xfce4/panel/whiskermenu-1.rc' 20 | grep -q brave"

# Layout switching: each switch must keep a window manager and one panel set.
for i in 1 2 3 4; do
    L=$([ $((i % 2)) = 1 ] && echo mac || echo windows)
    t=$(date +%s)
    sq "$X; kite-layout $L" 120 >/dev/null
    took=$(( $(date +%s) - t ))
    sleep 6
    wm=$(sq "pgrep -cx xfwm4" 20 | tr -dc 0-9)
    panels=$(sq "pgrep -cx xfce4-panel" 20 | tr -dc 0-9)
    shot "1$((i + 1))-switch-$i-$L"
    if [ "${wm:-0}" -ge 1 ] && [ "${panels:-0}" = 1 ]; then
        row PASS "live: switch $i to $L" "${took}s, xfwm4 running, one panel process (1$((i + 1))-switch-$i-$L.png)"
    else
        row FAIL "live: switch $i to $L" "${took}s, xfwm4 processes: ${wm:-0}, panel processes: ${panels:-0} (1$((i + 1))-switch-$i-$L.png)"
    fi
done

# Settings kept over a switch (layout is windows again here).
sq "$X; xfconf-query -c xfce4-terminal -p /font-name -n -t string -s 'DejaVu Sans Mono 13'; xfconf-query -c xsettings -p /Gtk/FontName -s 'DejaVu Sans 11'" 30 >/dev/null
sq "$X; kite-layout mac; sleep 4; kite-layout windows" 200 >/dev/null; sleep 6
check "live: Terminal font kept over two switches" bash -c "$HERE/kitevm.py sh $VM \"$X; xfconf-query -c xfce4-terminal -p /font-name\" 30 | grep -q 'DejaVu Sans Mono 13'"
check "live: desktop font kept over two switches" bash -c "$HERE/kitevm.py sh $VM \"$X; xfconf-query -c xsettings -p /Gtk/FontName\" 30 | grep -q 'DejaVu Sans 11'"

# Command-line safety (kite-storage) with a throw-away USB disk.
qemu-img create -q -f raw "$OUT/run/usb.img" 2G
k usb "$VM" add "$OUT/run/usb.img"; sleep 5
USBDEV=$(sq "lsblk -dpno NAME,TRAN | awk '\$2==\"usb\"{print \$1}' | head -n1" 30 | tail -n1 | tr -d '\r ')
if [ -n "$USBDEV" ]; then
    sq "printf 'label: gpt\n,,L\n' | sudo sfdisk -q $USBDEV" 60 >/dev/null; sleep 2
    check "storage: setup accepts the USB disk ($USBDEV)" bash -c "$HERE/kitevm.py sh $VM 'sudo kite-storage setup ${USBDEV}1 --format 2>&1' 120 | grep -q 'external disk ready'"
else
    row FAIL "storage: USB disk visible" "no usb disk in lsblk"
fi
check "storage: setup refuses the internal disk" bash -c "$HERE/kitevm.py sh $VM 'sudo kite-storage setup /dev/nvme0n1 2>&1' 60 | grep -qiE 'built-in|internal|not a USB'"
check "storage: move-dir /boot refused" bash -c "$HERE/kitevm.py sh $VM 'sudo kite-storage move-dir /boot 2>&1; test -d /boot -a ! -L /boot && echo STILL-THERE' 60 | grep -q STILL-THERE"
check "storage: move-dir /etc/ssh refused" bash -c "$HERE/kitevm.py sh $VM 'sudo kite-storage move-dir /etc/ssh 2>&1' 60 | grep -q 'system folder'"
check "resource report: --seconds 0 is a usage error" bash -c "$HERE/kitevm.py sh $VM 'kite-resource-report --seconds 0 >/dev/null 2>&1; echo rc=\$?' 60 | grep -q 'rc=2'"
k usb "$VM" del >/dev/null 2>&1 || true

# ------------------------------------------------------------- installer --
sq "$X; setsid kite-install >/tmp/kite-install.log 2>&1 &" 30 >/dev/null
if ! k wait "$VM" 'Welcome to the KiteOS installer|Welcome to the' 180 >/dev/null; then
    shot 30-inst-welcome; die "installer did not open"
fi
sleep 4; shot 30-inst-welcome
check "installer: welcome wording" bash -c "$HERE/kitevm.py ocr $VM | grep -qi 'Welcome to the KiteOS installer'"
VER=$(basename "$ISO" | sed -nE 's/kiteos-([0-9.]+)-amd64\.iso/\1/p')
[ -n "$VER" ] && check "installer: shows version $VER" bash -c "$HERE/kitevm.py ocr $VM | grep -q '$VER'"
next() { k clicktext "$VM" '^Next$|Next' 60 --last >/dev/null || die "no Next button ($1)"; sleep "${2:-6}"; }
next welcome; shot 31-inst-location
check "installer: Location defaults to Jakarta" bash -c "$HERE/kitevm.py ocr $VM | grep -qi jakarta"
CLOCK1=$(sq "date +%H:%M" 20 | tail -n1)
next location; shot 32-inst-keyboard
next keyboard 8
k clicktext "$VM" 'Erase disk' 60 >/dev/null || row FAIL "installer: Erase disk option" "not found by OCR"
sleep 3; shot 33-inst-partitions
next partitions 8; shot 34-inst-users-empty
# Users page: type into the first field, then Tab through the others.
k clicktext "$VM" 'Your Full Name|Full Name' 60 >/dev/null || die "users page: no full-name field"
k type "$VM" "$FULL"
k keys "$VM" tab; k keys "$VM" ctrl-a; k type "$VM" "$LOGIN"
k keys "$VM" tab; k keys "$VM" ctrl-a; k type "$VM" "$HOST"
k keys "$VM" tab; k type "$VM" "$PASS"
k keys "$VM" tab; k type "$VM" "$PASS"
sleep 3; shot 35-inst-users-filled
next users 6; shot 36-inst-desktop-page
if [ "$LAYOUT" = mac ]; then k clicktext "$VM" 'Mac style' 60 >/dev/null || die "Desktop page: no 'Mac style'"
else k clicktext "$VM" 'Windows style' 60 >/dev/null || die "Desktop page: no 'Windows style'"; fi
sleep 3; shot 37-inst-desktop-picked
next desktop 8; shot 38-inst-summary
k clicktext "$VM" '^Install$' 60 --last >/dev/null || die "no Install button on the Summary page"
sleep 4; shot 39-inst-confirm
k clicktext "$VM" 'Install Now' 60 >/dev/null || die "no Install Now in the confirm dialog"
log "installing"
CLOCK2=$(sq "date +%H:%M" 20 | tail -n1)
if [ -n "$CLOCK1" ] && [ -n "$CLOCK2" ]; then
    # the live clock must not jump to another time zone while the installer runs
    h1=${CLOCK1%%:*}; h2=${CLOCK2%%:*}
    if [ "$h1" = "$h2" ] || [ $(( (10#$h2 - 10#$h1 + 24) % 24 )) -le 1 ]; then row PASS "installer: live clock unchanged" "$CLOCK1 → $CLOCK2"
    else row FAIL "installer: live clock unchanged" "$CLOCK1 → $CLOCK2"; fi
fi
if k wait "$VM" 'All done|has been installed|Installation Failed' 3600 >/dev/null; then
    shot 40-inst-finished
    if k ocr "$VM" | grep -qi 'Installation Failed'; then die "installation failed (40-inst-finished.png)"; fi
    row PASS "installer: install finished" "$(now) since the start of the run"
else shot 40-inst-finished; die "install did not finish within an hour"; fi
LOGF=$(sq "sudo ls -t /root/.cache/Calamares/session.log /root/.cache/calamares/session.log 2>/dev/null | head -n1" 20 | tail -n1 | tr -d '\r')
sq "sudo cat '$LOGF'" 120 > "$OUT/calamares-session.log" 2>&1 || true
check "installer: no unknown packagechooser variable" bash -c "! grep -q 'unknown variable' '$OUT/calamares-session.log'"
check "installer: hwclock ran" bash -c "! grep -qi 'hwclock failed\|failed to run command .hwclock' '$OUT/calamares-session.log'"

# Give the installed system a serial getty (test plumbing), check its files.
ROOTP=$(sq "lsblk -pnlo NAME,FSTYPE /dev/nvme0n1 | awk '\$2==\"ext4\"{print \$1}' | head -n1" 30 | tail -n1 | tr -d '\r ')
sq "sudo mkdir -p /mnt/t && sudo mount $ROOTP /mnt/t && sudo ln -sf /lib/systemd/system/serial-getty@.service /mnt/t/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service" 60 >/dev/null
check "installed: /etc/kite/layout = $LAYOUT" bash -c "[ \"\$($HERE/kitevm.py sh $VM 'cat /mnt/t/etc/kite/layout' 20 | tail -n1 | tr -d '\r ')\" = $LAYOUT ]"
check "installed: hwclock present" bash -c "$HERE/kitevm.py sh $VM 'test -x /mnt/t/usr/sbin/hwclock && echo yes' 20 | grep -q yes"
sq "sudo grep -q ttyS0 /mnt/t/etc/default/grub || sudo sed -i 's/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"console=tty0 console=ttyS0,115200 /' /mnt/t/etc/default/grub; for d in dev proc sys; do sudo mount --bind /\$d /mnt/t/\$d; done; sudo chroot /mnt/t update-grub >/dev/null 2>&1; for d in dev proc sys; do sudo umount /mnt/t/\$d; done; sudo umount /mnt/t" 300 >/dev/null
k stop "$VM"; sleep 3

# ------------------------------------------------------- installed system --
k start "$VM" --disk "$OUT/run/emmc.qcow2" || die "installed system did not start"
if k wait "$VM" "$FULL|Kite Tester|Password" 600 >/dev/null; then
    sleep 5; shot 50-login; row PASS "installed: login screen" "50-login.png"
else shot 50-login; row FAIL "installed: login screen" "user not shown (50-login.png)"; fi
k type "$VM" "$PASS"; k keys "$VM" ret
sleep 40; shot 51-desktop
k login "$VM" "$LOGIN" "$PASS" >/dev/null || die "no serial login on the installed system"
for _ in $(seq 40); do sq "pgrep -x xfce4-panel >/dev/null" 10 >/dev/null && break; sleep 3; done
sleep 5; shot 51-desktop
check "installed: account layout = $LAYOUT" bash -c "[ \"\$($HERE/kitevm.py sh $VM 'cat ~/.config/kite/layout' 20 | tail -n1 | tr -d '\r ')\" = $LAYOUT ]"
if [ "$LAYOUT" = mac ]; then
    check "installed: mac layout has two panels (menu bar + Dock)" bash -c "$HERE/kitevm.py sh $VM \"$X; xfconf-query -c xfce4-panel -p /panels\" 30 | grep -q 2"
fi
check "installed: window manager running" bash -c "$HERE/kitevm.py sh $VM 'pgrep -x xfwm4' 20 | grep -q '[0-9]'"
check "installed: no failed services" bash -c "[ -z \"\$($HERE/kitevm.py sh $VM 'systemctl --failed --no-legend --plain | grep -v serial-getty' 30 | tr -d '\r\n ')\" ]"
check "installed: picom not running" bash -c "! $HERE/kitevm.py sh $VM 'pgrep -a picom' 20 | grep -q picom"
check "installed: hibernation ready" bash -c "$HERE/kitevm.py sh $VM 'busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>/dev/null; grep -o resume=[^ ]* /proc/cmdline' 30 | grep -q resume="
check "installed: login screen light theme" bash -c "$HERE/kitevm.py sh $VM 'gsettings get x.dm.slick-greeter theme-name 2>/dev/null; grep -h theme-name /usr/share/glib-2.0/schemas/*slick-greeter*.override' 30 | grep -q Fluent-Light"
sq "cat ~/.xsession-errors 2>/dev/null | tail -n 80" 30 > "$OUT/installed-xsession-errors.txt" 2>&1 || true
k stop "$VM"
finish
