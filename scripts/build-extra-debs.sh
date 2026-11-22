#!/bin/bash
# keyd and xfce4-docklike-plugin are not in every Debian release. Run inside
# the Debian 13 build container: for each, if the archive has it, do nothing;
# otherwise build the pinned upstream release into a .deb in OUT_DIR.
#   scripts/build-extra-debs.sh [OUT_DIR]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$REPO/out/debs}
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

KEYD_TAG=v2.5.0
DOCKLIKE_TAG=xfce4-docklike-plugin-0.4.3

in_archive() {
    apt-cache policy "$1" 2>/dev/null | grep -q '^  Candidate: [0-9a-z]'
}

build_keyd() {
    local src=$WORK/keyd root=$WORK/keyd-root ver=${KEYD_TAG#v}
    git clone -q --depth 1 --branch "$KEYD_TAG" https://github.com/rvaiya/keyd "$src"
    make -C "$src" PREFIX=/usr
    make -C "$src" PREFIX=/usr DESTDIR="$root" install
    # keyd's Makefile only installs the unit when systemd is running.
    install -Dm644 "$src/keyd.service" "$root/usr/lib/systemd/system/keyd.service"
    mkdir -p "$root/DEBIAN"
    cat > "$root/DEBIAN/control" <<CTRL
Package: keyd
Version: ${ver}-0kite1
Section: utils
Priority: optional
Architecture: amd64
Maintainer: KiteOS builder <root@localhost>
Depends: libc6
Homepage: https://github.com/rvaiya/keyd
Description: key remapping daemon for Linux (built by KiteOS from upstream ${KEYD_TAG})
CTRL
    cat > "$root/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    getent group keyd >/dev/null || groupadd -r keyd
    systemctl enable keyd.service >/dev/null 2>&1 || true
fi
exit 0
POST
    chmod 755 "$root/DEBIAN/postinst"
    dpkg-deb --root-owner-group --build "$root" "$OUT/keyd_${ver}-0kite1_amd64.deb"
}

build_docklike() {
    local src=$WORK/docklike root=$WORK/docklike-root ver=${DOCKLIKE_TAG##*-}
    apt-get install -y --no-install-recommends build-essential autoconf automake libtool \
        intltool gettext pkg-config xfce4-dev-tools libxfce4panel-2.0-dev libxfce4ui-2-dev \
        libwnck-3-dev libgtk-3-dev libcairo2-dev libx11-dev
    git clone -q --depth 1 --branch "$DOCKLIKE_TAG" https://github.com/xfce-mirror/xfce4-docklike-plugin "$src"
    (cd "$src" && NOCONFIGURE=1 ./autogen.sh &&
        ./configure --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu --disable-static &&
        make -j"$(nproc)" && make DESTDIR="$root" install)
    find "$root" -name '*.la' -delete
    local panel_lib
    panel_lib=$(dpkg-query -W -f='${Package}\n' 'libxfce4panel-2.0-*' | grep -v -- '-dev$' | head -n1)
    mkdir -p "$root/DEBIAN"
    cat > "$root/DEBIAN/control" <<CTRL
Package: xfce4-docklike-plugin
Version: ${ver}-0kite1
Section: xfce
Priority: optional
Architecture: amd64
Maintainer: KiteOS builder <root@localhost>
Depends: xfce4-panel, ${panel_lib:-libxfce4panel-2.0-4}, libxfce4ui-2-0, libwnck-3-0, libgtk-3-0, libcairo2
Homepage: https://docs.xfce.org/panel-plugins/xfce4-docklike-plugin/start
Description: modern taskbar for the Xfce panel (built by KiteOS from upstream ${DOCKLIKE_TAG})
CTRL
    dpkg-deb --root-owner-group --build "$root" "$OUT/xfce4-docklike-plugin_${ver}-0kite1_amd64.deb"
}

apt-get update -q
if in_archive keyd; then echo "keyd: provided by Debian"; else echo "keyd: building ${KEYD_TAG}"; build_keyd; fi
if in_archive xfce4-docklike-plugin; then echo "docklike: provided by Debian"; else echo "docklike: building ${DOCKLIKE_TAG}"; build_docklike; fi
