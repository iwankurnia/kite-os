#!/bin/bash
# Install the KiteOS packages into a throw-away chroot and check that their
# maintainer scripts, triggers and APT hooks behave.
#
#   sudo tests/test-packages-chroot.sh [SUITE] [MIRROR]
#   e.g. sudo tests/test-packages-chroot.sh trixie http://deb.debian.org/debian
#
# Packages missing from SUITE (e.g. keyd on older releases) are replaced by
# empty stand-ins so the rest can still be tested.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SUITE=${1:-trixie}
MIRROR=${2:-http://deb.debian.org/debian}
case "$SUITE" in
    noble|jammy|oracular|plucky) COMPONENTS=main,universe ;;
    *) COMPONENTS=main,contrib,non-free,non-free-firmware ;;
esac
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
command -v mmdebstrap >/dev/null || { echo "install mmdebstrap"; exit 1; }

W=$(mktemp -d)
CH=$W/chroot
pass=0; fail=0
ok()  { echo "  ok   $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
in_ch() { chroot "$CH" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 "$@"; }
check() { local msg=$1; shift; if "$@"; then ok "$msg"; else bad "$msg"; fi; }
cleanup() {
    for m in dev/pts dev proc sys; do umount -l "$CH/$m" 2>/dev/null || true; done
    rm -rf "$W"
}
trap cleanup EXIT
[ -n "${KITE_KEEP_CHROOT:-}" ] && trap 'for m in dev/pts dev proc sys; do umount -l "$CH/$m" 2>/dev/null || true; done; echo "chroot kept at $CH"' EXIT

echo "== bootstrapping $SUITE"
mmdebstrap -q --variant=apt --components="$COMPONENTS" --include=ca-certificates "$SUITE" "$CH" "$MIRROR"
for m in proc sys dev dev/pts; do mount --bind "/$m" "$CH/$m"; done
# Services must not start inside the chroot.
printf '#!/bin/sh\nexit 101\n' > "$CH/usr/sbin/policy-rc.d"; chmod 755 "$CH/usr/sbin/policy-rc.d"

"$REPO/scripts/build-packages.sh" "$CH/tmp/debs" >/dev/null
in_ch apt-get update -q >/dev/null

echo "== stand-ins for packages $SUITE does not have"
for p in keyd xfce4-docklike-plugin firmware-sof-signed; do
    if ! in_ch apt-cache policy "$p" | grep '^  Candidate: [0-9a-z]' >/dev/null; then
        d=$W/stub-$p; mkdir -p "$d/DEBIAN"
        printf 'Package: %s\nVersion: 0.0-stub\nArchitecture: all\nMaintainer: test <t@localhost>\nDescription: test stand-in\n' "$p" > "$d/DEBIAN/control"
        dpkg-deb --root-owner-group --build "$d" "$CH/tmp/debs/stub-$p.deb" >/dev/null
        echo "  stand-in: $p"
    fi
done

echo "== installing KiteOS packages and their dependencies"
if in_ch bash -c 'apt-get install -y -q --no-install-recommends /tmp/debs/*.deb' > "$W/install.log" 2>&1; then
    ok "all packages installed"
else
    bad "installation failed"; tail -30 "$W/install.log"
fi
check "no maintainer-script errors" bash -c "! grep -E 'returned error exit status|dpkg: error' '$W/install.log'"
check "all four packages configured" bash -c "[ \$(chroot '$CH' dpkg-query -W -f='\${db:Status-Abbrev} \${Package}\n' 'kite-*' | grep -c '^ii ') = 4 ]"

echo "== kite-system"
check "boot splash theme built" test -f "$CH/usr/share/plymouth/themes/kite/kite.plymouth"
check "splash selected as default" bash -c "grep -qx 'Theme=kite' '$CH/etc/plymouth/plymouthd.conf' 2>/dev/null || [ \"\$(readlink -f '$CH/etc/alternatives/default.plymouth')\" = '$CH/usr/share/plymouth/themes/kite/kite.plymouth' ] || [ \"\$(readlink '$CH/etc/alternatives/default.plymouth')\" = /usr/share/plymouth/themes/kite/kite.plymouth ]"
check "zswap service enabled" test -L "$CH/etc/systemd/system/sysinit.target.wants/kite-zswap.service"
check "first-boot hibernation service enabled" test -L "$CH/etc/systemd/system/multi-user.target.wants/kite-hibernate-firstboot.service"
check "GRUB defaults drop-in is a conffile" bash -c "chroot '$CH' dpkg-query -W -f='\${Conffiles}' kite-system | grep -q /etc/default/grub.d/kite.cfg"
check "i915 is loaded early" grep -qx i915 "$CH/usr/share/initramfs-tools/modules.d/kite.conf"
check "earlyoom options quoted (one variable, not split)" grep -q '^Environment="KITE_EARLYOOM_ARGS=-m 4 ' "$CH/usr/lib/systemd/system/earlyoom.service.d/kite.conf"

echo "== kite-desktop"
check "login screen settings valid (strict schema compile)" in_ch glib-compile-schemas --strict --dry-run /usr/share/glib-2.0/schemas
check "slick-greeter is the greeter" grep -q '^greeter-session=slick-greeter' "$CH/etc/lightdm/lightdm.conf.d/50-kite.conf"
check "desktop layout installed (windows only)" bash -c "[ -f '$CH/usr/share/kite/layouts/windows/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml' ] && [ ! -e '$CH/usr/share/kite/layouts/mac' ]"
check "Start menu and app search installed" test -x "$CH/usr/bin/xfce4-popup-whiskermenu" -a -x "$CH/usr/bin/xfce4-appfinder"
check "Start and Search button icons installed" test -f "$CH/usr/share/icons/hicolor/scalable/actions/kite-start-symbolic.svg" -a -f "$CH/usr/share/icons/hicolor/scalable/actions/kite-search-symbolic.svg"
check "kite-layout sets up a new account" in_ch env HOME=/tmp/lh python3 /usr/bin/kite-layout --first-login
check "new account got the default (windows) layout" grep -qx windows "$CH/tmp/lh/.config/kite/layout"
check "Xsession hook is valid sh" in_ch sh -n /etc/X11/Xsession.d/45kite-user-init
# A stand-in Brave package installed after kite-desktop. (The ISO build
# unpacks Brave first; dpkg-divert --rename handles that order too.)
d=$W/stub-brave; mkdir -p "$d/DEBIAN" "$d/opt/brave.com/brave" "$d/usr/bin"
printf 'Package: brave-browser\nVersion: 0.0-stub\nArchitecture: all\nMaintainer: test <t@localhost>\nDescription: test stand-in\n' > "$d/DEBIAN/control"
printf '#!/bin/sh\necho "$@" > /tmp/brave-args\n' > "$d/opt/brave.com/brave/brave-browser"; chmod 755 "$d/opt/brave.com/brave/brave-browser"
ln -s /opt/brave.com/brave/brave-browser "$d/usr/bin/brave-browser-stable"
dpkg-deb --root-owner-group --build "$d" "$CH/tmp/stub-brave.deb" >/dev/null
check "Brave installs alongside the launcher diversion" in_ch dpkg -i /tmp/stub-brave.deb
check "Brave's launcher diverted to .distrib" test "$(readlink "$CH/usr/bin/brave-browser-stable.distrib")" = /opt/brave.com/brave/brave-browser
check "KiteOS wrapper in its place" bash -c "head -n1 '$CH/usr/bin/brave-browser-stable' | grep -qx '#!/bin/sh'"
in_ch env HOME=/root /usr/bin/brave-browser-stable https://example.org >/dev/null 2>&1 || true
check "wrapper starts Brave with the KiteOS flags" grep -qx -- '--enable-features=AcceleratedVideoDecodeLinuxGL https://example.org' "$CH/tmp/brave-args"

echo "== kite-storage"
check "kite-storage runs" in_ch kite-storage status
check "polkit policy installed" test -f "$CH/usr/share/polkit-1/actions/org.kiteos.storage.policy"
check "App Centre's GTK 3 bindings installed" in_ch python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk'
check "App Centre starts its command line" in_ch kite-app-centre --help
if in_ch apt-get install -y -q --no-install-recommends hello > "$W/apt.log" 2>&1; then
    ok "apt still installs packages with the KiteOS APT hooks active"
else
    bad "apt broken by the hooks"; tail -20 "$W/apt.log"
fi
check "no hook errors during apt run" bash -c "! grep -iE 'kite-storage.*(error|not found)|Sub-process.*kite' '$W/apt.log'"
in_ch apt-get purge -y -q hello >/dev/null 2>&1 && ok "apt removes packages with the hooks active" || bad "apt removal broken"

echo "== kite-chromebook"
check "setup service enabled" test -L "$CH/etc/systemd/system/multi-user.target.wants/kite-chromebook-setup.service"
check "keyboard map generator runs" in_ch /usr/lib/kite/chromebook/kite-keyd-gen
if in_ch apt-get install -y -q --reinstall alsa-ucm-conf > "$W/trigger.log" 2>&1; then
    check "UCM trigger fires on alsa-ucm-conf upgrade" grep -q 'kite-chromebook' "$W/trigger.log"
fi
check "purge works" in_ch apt-get purge -y -q kite-chromebook
check "setup service link gone after purge" test ! -e "$CH/etc/systemd/system/multi-user.target.wants/kite-chromebook-setup.service"

echo "== kite-desktop removal"
in_ch kite-login-theme aurora >/dev/null 2>&1 || true
in_ch apt-get purge -y -q kite-desktop >/dev/null 2>&1 && ok "kite-desktop purged" || bad "kite-desktop purge failed"
check "Brave gets its own launcher back" test "$(readlink "$CH/usr/bin/brave-browser-stable")" = /opt/brave.com/brave/brave-browser
check "no diversion left behind" bash -c "[ -z \"\$(chroot '$CH' dpkg-divert --listpackage /usr/bin/brave-browser-stable)\" ]"
check "purge removes the login screen file kite-login-theme wrote" test ! -e "$CH/etc/lightdm/slick-greeter.conf"

echo
echo "package tests ($SUITE): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
