#!/bin/bash
# Build the Debian packages KiteOS ships with its own patches, from Debian's
# source: the patches in patches/<source package>/ are added to its
# debian/patches, the version gets +kite<N>, and the binary package is
# renamed to a kite-* name that Provides, Conflicts with and Replaces
# Debian's. So an update to Debian's (or upstream's) package never installs
# over KiteOS's, and kite-update carries it like the other kite-* packages.
# Run as root on Debian 13 (build.sh runs it in its container): it enables
# deb-src and installs the build dependencies.
#   scripts/build-patched.sh [OUT_DIR]
# The source version is pinned: when Debian moves on (a security update), the
# download fails here on purpose; check the patches still apply, then update
# the version below and raise the KiteOS revision.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$REPO/out/debs}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# Debian package | its source version the patches are made for | KiteOS revision | KiteOS package name
PATCHED=(
"xfce4-docklike-plugin|0.4.3-1|2|kite-docklike"
)

export DEBIAN_FRONTEND=noninteractive
src=/etc/apt/sources.list.d/debian.sources
if [ -f "$src" ] && ! grep -q '^Types:.*deb-src' "$src"; then
    sed -i 's/^Types: deb$/Types: deb deb-src/' "$src"
fi
apt-get update -q
apt-get install -y -q --no-install-recommends dpkg-dev build-essential

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
for p in "${PATCHED[@]}"; do
    IFS='|' read -r pkg ver rev bin <<< "$p"
    new="$ver+kite$rev"
    echo "==> $bin $new (Debian's $pkg $ver, patched)"
    apt-get build-dep -y -q --only-source "$pkg=$ver"
    (cd "$WORK" && apt-get source -q --only-source "$pkg=$ver")
    dir=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name "$pkg-*" | head -n1)
    mkdir -p "$dir/debian/patches"
    for f in "$REPO/patches/$pkg"/*.patch; do
        cp "$f" "$dir/debian/patches/"
        basename "$f" >> "$dir/debian/patches/series"
    done
    {
        printf '%s (%s) trixie; urgency=medium\n\n' "$pkg" "$new"
        for f in "$REPO/patches/$pkg"/*.patch; do
            printf '  * KiteOS: %s\n' "$(sed -n 's/^Description: //p' "$f")"
        done
        printf '\n -- KiteOS <6760806+iwankurnia@users.noreply.github.com>  %s\n\n' "$(date -R)"
        cat "$dir/debian/changelog"
    } > "$WORK/changelog" && mv "$WORK/changelog" "$dir/debian/changelog"
    # The binary package under its KiteOS name, standing in for Debian's.
    grep -qx "Package: $pkg" "$dir/debian/control"
    sed -i "s/^Package: $pkg\$/Package: $bin\nProvides: $pkg (= $new)\nConflicts: $pkg\nReplaces: $pkg/" "$dir/debian/control"
    sed -i "/^Package: $bin\$/,/^Description:/ s/^\(Description: .*\)\$/\1 (KiteOS build)/" "$dir/debian/control"
    sed -i "s#debian/$pkg/#debian/$bin/#g" "$dir/debian/rules"
    [ -f "$dir/debian/lintian-overrides" ] && sed -i "s/^$pkg:/$bin:/" "$dir/debian/lintian-overrides"
    (cd "$dir" && dpkg-buildpackage -b -us -uc -j"$(nproc)" >"$WORK/$pkg.log" 2>&1) \
        || { tail -n 40 "$WORK/$pkg.log" >&2; exit 1; }
    cp "$WORK/${bin}_${new}_"*.deb "$OUT/"
    echo "built $OUT/$(cd "$WORK" && ls "${bin}_${new}_"*.deb)"
done
