#!/bin/bash
# Build the KiteOS installer ISO.
#
#   ./build.sh              build in a Debian 13 container (Docker or Podman)
#   KITE_NATIVE=1 ./build.sh  build directly on a Debian 13 host (as root)
#
# Output: out/kiteos-<date>-amd64.iso
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
cd "$REPO"

if [ "${KITE_IN_CONTAINER:-0}" != 1 ] && [ "${KITE_NATIVE:-0}" != 1 ]; then
    engine=$(command -v docker || command -v podman || true)
    [ -n "$engine" ] || { echo "Install Docker or Podman, or run on Debian 13 with KITE_NATIVE=1" >&2; exit 1; }
    exec "$engine" run --rm --privileged \
        -v "$REPO:/kiteos" -w /kiteos \
        -e KITE_IN_CONTAINER=1 -e KITE_MIRROR -e KITE_SECURITY_MIRROR -e KITE_BRAVE_MIRROR -e KITE_ONLYOFFICE_MIRROR -e KITE_TRUST_NEW_KEYS \
        docker.io/library/debian:trixie ./build.sh "$@"
fi

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] || echo "warning: building on ${PRETTY_NAME:-unknown}, Debian 13 is expected" >&2

echo "==> installing build tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends live-build debootstrap xorriso squashfs-tools \
    dosfstools mtools grub-efi-amd64-bin grub-common dpkg-dev gnupg curl ca-certificates file mount

rm -rf out/debs
mkdir -p out/debs
echo "==> KiteOS packages"
scripts/build-packages.sh out/debs
echo "==> Brave and ONLYOFFICE repositories"
scripts/fetch-vendor-keys.sh live/config

rm -f live/config/packages.chroot/*.deb
cp out/debs/*.deb live/config/packages.chroot/

echo "==> live-build (this takes a while)"
cd live
lb clean --purge
lb config
lb build
cd ..
iso=$(find live -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)
# auto/build pipes lb build through tee (no pipefail in sh), so a failed
# build shows up here as a missing ISO.
[ -n "$iso" ] || { echo "live-build failed, no ISO produced: see live/build.log" >&2; exit 1; }
dest=out/kiteos-$(date +%Y%m%d)-amd64.iso
mv "$iso" "$dest"
# Bare file name, so "sha256sum -c" works next to the downloaded ISO.
(cd out && sha256sum "${dest#out/}" > "${dest#out/}.sha256")
echo "==> done: $dest ($(du -h "$dest" | cut -f1))"
