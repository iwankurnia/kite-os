#!/bin/bash
# Lint + all tests that do not need network access. Run as root.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"
echo "== shellcheck"
# Only the project's own scripts (not live-build's working tree).
mapfile -t files < <(git ls-files -co --exclude-standard | grep -v alsa-ucm-conf-cros |
                     while read -r f; do [ -f "$f" ] && head -c 20 "$f" | grep -qE '^#!/bin/(ba)?sh' && echo "$f"; done)
LC_ALL=C.UTF-8 shellcheck "${files[@]}"
echo "  ok   ${#files[@]} shell scripts"
echo "== XML / YAML / Python"
find packages -name '*.xml' -exec xmllint --noout {} +
python3 - <<'PY'
import glob, yaml
for f in glob.glob("live/config/includes.chroot/etc/calamares/**/*.conf", recursive=True) + \
         glob.glob("live/config/includes.chroot/etc/calamares/**/*.desc", recursive=True):
    yaml.safe_load(open(f))
PY
python3 -m py_compile packages/kite-chromebook/usr/lib/kite/chromebook/kite-keyd-gen packages/kite-desktop/usr/lib/kite/desktop/kite-window-guard packages/kite-chromebook/usr/lib/kite/chromebook/kite-ec-events packages/kite-desktop/usr/lib/kite/desktop/kite-user-init packages/kite-desktop/usr/bin/kite-vivid packages/kite-desktop/usr/bin/kite-layout packages/kite-desktop/usr/bin/kite-tasks packages/kite-desktop/usr/lib/kite/desktop/kite-start packages/kite-desktop/usr/lib/kite/desktop/kite-accent packages/kite-desktop/usr/lib/kite/desktop/kite-switcher packages/kite-desktop/usr/lib/kite/desktop/kite-gestures packages/kite-desktop/usr/bin/kite-login-settings packages/kite-system/usr/bin/kite-update packages/kite-storage/usr/bin/kite-app-centre
find packages -name __pycache__ -prune -exec rm -rf {} +
echo "  ok"
echo "== package build"
d=$(mktemp -d); scripts/build-packages.sh "$d"; rm -rf "$d"
tests/test-system.sh
tests/test-storage.sh
