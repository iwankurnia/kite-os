#!/bin/bash
# Turn a minimal Debian 13 installation into KiteOS (alternative to the ISO).
#
# Install Debian 13 from the netinst image first, choosing only
# "standard system utilities" (no desktop), ext4, and no swap partition
# (or one at least as big as RAM). Then, as root, from this repository:
#
#   scripts/install-on-debian.sh
#
# It uses the same package lists and KiteOS packages as the ISO build.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
LISTS=$REPO/live/config/package-lists
export DEBIAN_FRONTEND=noninteractive

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo $0)" >&2; exit 1; }
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] || { echo "this script is for Debian 13 (trixie); found ${PRETTY_NAME:-?}" >&2; exit 1; }

step() { printf '\n==> %s\n' "$*"; }

step "enabling contrib, non-free and non-free-firmware"
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    sed -i -E 's/^(Components:).*/\1 main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
fi
if [ -f /etc/apt/sources.list ]; then
    sed -i -E '/^deb(-src)? .*debian/ s/ main( contrib)?( non-free)?( non-free-firmware)?$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list
fi

step "slimming: no package docs, no automatic Recommends"
install -D -m 644 "$REPO/live/config/includes.chroot_before_packages/etc/dpkg/dpkg.cfg.d/kite-slim" /etc/dpkg/dpkg.cfg.d/kite-slim

step "build tools for the KiteOS packages"
apt-get update -q
apt-get install -y -q --no-install-recommends dpkg-dev gnupg curl ca-certificates git make gcc libc6-dev file

step "Brave and ONLYOFFICE repositories"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
"$REPO/scripts/fetch-vendor-keys.sh" "$WORK/config" >/dev/null
for name in brave onlyoffice; do
    install -D -m 644 "$WORK/config/archives/$name.key.chroot" "/usr/share/keyrings/kite-$name.gpg"
    sed "s#^deb #deb [signed-by=/usr/share/keyrings/kite-$name.gpg] #; s#\[signed-by=\([^]]*\)\] \[arch=amd64\]#[arch=amd64 signed-by=\1]#" \
        "$WORK/config/archives/$name.list.chroot" > "/etc/apt/sources.list.d/kite-$name.list"
done

step "building keyd / docklike (if Debian lacks them) and the KiteOS packages"
mkdir -p "$WORK/debs"
"$REPO/scripts/build-extra-debs.sh" "$WORK/debs"
"$REPO/scripts/build-packages.sh" "$WORK/debs"

step "installing the desktop, apps and hardware support (this takes a while)"
pkgs=$(cat "$LISTS/kite-base.list.chroot" "$LISTS/kite-desktop.list.chroot" "$LISTS/kite-apps.list.chroot" |
       sed 's/#.*//' | grep -v '^\s*$' | grep -v '^kite-' | grep -vxE 'keyd|xfce4-docklike-plugin' | tr '\n' ' ')
apt-get update -q
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends $pkgs
apt-get install -y --no-install-recommends "$WORK"/debs/*.deb
bash "$REPO/live/config/hooks/normal/0100-kite-optional-packages.hook.chroot"

step "hibernation"
/usr/sbin/kite-hibernate-setup --apply || echo "hibernation setup failed — run 'sudo kite-hibernate-setup' later" >&2

step "existing users get the KiteOS desktop defaults"
for home in /home/*; do
    [ -d "$home" ] || continue
    user=$(stat -c %U "$home")
    if [ ! -e "$home/.config/xfce4/xfconf" ]; then
        cp -a --no-clobber /etc/skel/. "$home/"
        chown -R "$user:" "$home/.config"
    fi
done

systemctl set-default graphical.target
echo
echo "KiteOS is installed. Reboot to start the new desktop: sudo reboot"
