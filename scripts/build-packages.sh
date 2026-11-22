#!/bin/bash
# Build the KiteOS .deb packages from packages/<name>/ into OUT_DIR.
#   scripts/build-packages.sh [OUT_DIR]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$REPO/out/debs}
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for src in "$REPO"/packages/*/; do
    name=$(basename "$src")
    root=$WORK/$name
    cp -a "$src" "$root"
    find "$root" -name '__pycache__' -prune -exec rm -rf {} +

    # Every file under /etc is a conffile (user edits survive upgrades).
    if [ -d "$root/etc" ]; then
        (cd "$root" && find etc -type f | sort | sed 's#^#/#') > "$root/DEBIAN/conffiles"
    fi
    # Normalise permissions.
    find "$root" -type d -exec chmod 755 {} +
    find "$root" -type f ! -perm -u+x -exec chmod 644 {} +
    find "$root" -type f -perm -u+x -exec chmod 755 {} +
    for f in postinst postrm prerm preinst config; do
        [ -f "$root/DEBIAN/$f" ] && chmod 755 "$root/DEBIAN/$f"
    done
    [ -f "$root/DEBIAN/conffiles" ] && chmod 644 "$root/DEBIAN/conffiles"
    [ -f "$root/DEBIAN/triggers" ] && chmod 644 "$root/DEBIAN/triggers"

    size=$(du -sk --exclude=DEBIAN "$root" | cut -f1)
    sed -i "/^Installed-Size:/d" "$root/DEBIAN/control"
    sed -i "s/^Architecture:/Installed-Size: $size\nArchitecture:/" "$root/DEBIAN/control"

    version=$(sed -n 's/^Version: //p' "$root/DEBIAN/control")
    arch=$(sed -n 's/^Architecture: //p' "$root/DEBIAN/control")
    dpkg-deb --root-owner-group -Zxz --build "$root" "$OUT/${name}_${version}_${arch}.deb" >/dev/null
    echo "built $OUT/${name}_${version}_${arch}.deb"
done
