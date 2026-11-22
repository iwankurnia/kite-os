#!/bin/bash
# Fetch the Brave and ONLYOFFICE APT signing keys, check them against the
# expected key IDs, and add both repositories to the live-build config.
#   scripts/fetch-vendor-keys.sh [LIVE_CONFIG_DIR]
# If a vendor rotates its key, verify the new fingerprint on the vendor's
# website and re-run with KITE_TRUST_NEW_KEYS=1.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
CFG=${1:-$REPO/live/config}
A=$CFG/archives
mkdir -p "$A"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# name | key URL | expected long key ID (last 16 hex digits of the fingerprint) | APT line
# Brave: DBF1A116C220B8C7164F98230686B78420038257 (brave.com/signing-keys, release channel)
# ONLYOFFICE: E09CA29F6E178040EF22B4098320CA65CB2DE8E5 ("Ascensio System Limited")
VENDORS=(
"brave|https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg|0686B78420038257|deb [arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main"
"onlyoffice|https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE|8320CA65CB2DE8E5|deb https://download.onlyoffice.com/repo/debian squeeze main"
)

for v in "${VENDORS[@]}"; do
    IFS='|' read -r name url keyid line <<< "$v"
    curl -fsSL --retry 3 "$url" -o "$WORK/$name.raw"
    export GNUPGHOME=$WORK/gnupg-$name
    mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
    gpg -q --import "$WORK/$name.raw" 2>/dev/null
    fprs=$(gpg --with-colons --fingerprint | awk -F: '$1 == "fpr" { print $10 }')
    echo "$name key fingerprint(s):"
    while read -r f; do echo "  $f"; done <<< "$fprs"
    if ! grep -qi "${keyid}\$" <<< "$fprs"; then
        if [ "${KITE_TRUST_NEW_KEYS:-0}" != 1 ]; then
            echo "ERROR: $name key does not match the expected ID $keyid." >&2
            echo "Check the fingerprint on the vendor's website, then re-run with KITE_TRUST_NEW_KEYS=1." >&2
            exit 1
        fi
        echo "WARNING: $name key ID changed; continuing because KITE_TRUST_NEW_KEYS=1" >&2
    fi
    gpg --export > "$A/$name.key.chroot"
    cp "$A/$name.key.chroot" "$A/$name.key.binary"
    # The installed system always uses the vendor URL; the build may use a
    # local mirror (KITE_BRAVE_MIRROR / KITE_ONLYOFFICE_MIRROR).
    echo "$line" > "$A/$name.list.binary"
    mirror_var="KITE_$(echo "$name" | tr '[:lower:]' '[:upper:]')_MIRROR"
    if [ -n "${!mirror_var:-}" ]; then
        sed -E "s#https://[^ ]+#${!mirror_var}#" <<< "$line" > "$A/$name.list.chroot"
    else
        echo "$line" > "$A/$name.list.chroot"
    fi
done
echo "vendor repositories added to $A"
