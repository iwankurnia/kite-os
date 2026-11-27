#!/bin/bash
# shellcheck disable=SC1090,SC2012,SC2001  # tests source the tool and list temp dirs
# Tests for kite-storage using a plain directory as the "external disk".
# Needs root (creates a throw-away user "kitetest" for the per-user tests,
# and deletes it again at the end; it used to stay behind on the laptop).
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
KS=$REPO/packages/kite-storage/usr/sbin/kite-storage
T=$(mktemp -d)
chmod 755 "$T"   # like a real mount point: other users may traverse it
made_user=
cleanup() {
    if [ -n "$made_user" ]; then
        # su's PAM session can leave a systemd user manager running as
        # kitetest, and userdel refuses a user with processes.
        loginctl terminate-user kitetest 2>/dev/null || true
        pkill -KILL -u kitetest 2>/dev/null || true
        userdel -r -f kitetest 2>&1 | grep -v 'mail spool' >&2 || true
    fi
    rm -rf "$T"
}
trap cleanup EXIT
pass=0; fail=0
ok()   { echo "  ok   $*"; pass=$((pass + 1)); }
bad()  { echo "  FAIL $*"; fail=$((fail + 1)); }
check() { local msg=$1; shift; if "$@"; then ok "$msg"; else bad "$msg"; fi; }

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

export KITE_STORAGE_CONF=$T/storage.conf
export KITE_STATE_DIR=$T/state
export KITE_EXT_MOUNT=$T/ext
export KITE_TEST_NO_MOUNTCHECK=1
export KITE_APPS_DB=$REPO/packages/kite-storage/usr/share/kite/storage/apps
export KITE_DESKTOP_OVERRIDES=$T/applications
mkdir -p "$T/ext/kite"
echo "machine=test" > "$T/ext/kite/.kite-storage"
printf 'EXT_UUID=test-uuid\nEXT_MOUNT=%s\n' "$T/ext" > "$KITE_STORAGE_CONF"

echo "== move-dir / restore-dir (system folder)"
APP=$T/opt/fakeapp
mkdir -p "$APP/bin" "$APP/share"
head -c 3000000 /dev/urandom > "$APP/share/data.bin"
printf '#!/bin/sh\necho hello-from-fakeapp\n' > "$APP/bin/fakeapp"
chmod 755 "$APP/bin/fakeapp"
ln -s ../share/data.bin "$APP/bin/link"
sum_before=$(sha256sum "$APP/share/data.bin" | cut -d' ' -f1)

"$KS" move-dir "$APP" >/dev/null
check "folder replaced by a symlink" test -L "$APP"
check "symlink points into the external disk" test "$(readlink "$APP")" = "$T/ext/kite/system$APP"
check "program still runs through the link" test "$("$APP/bin/fakeapp")" = hello-from-fakeapp
check "data intact" test "$(sha256sum "$APP/share/data.bin" | cut -d' ' -f1)" = "$sum_before"
check "inner symlink preserved" test -L "$T/ext/kite/system$APP/bin/link"
check "no leftovers" test ! -e "$APP.kite-moving"
check "recorded in state" grep -q "$APP" "$KITE_STATE_DIR/moved.tsv"

"$KS" restore-dir "$APP" >/dev/null
check "restored as a real folder" bash -c "[ -d '$APP' ] && [ ! -L '$APP' ]"
check "data intact after restore" test "$(sha256sum "$APP/share/data.bin" | cut -d' ' -f1)" = "$sum_before"
check "external copy removed" test ! -e "$T/ext/kite/system$APP"
check "state cleared" bash -c "! grep -q '$APP' '$KITE_STATE_DIR/moved.tsv'"

echo "== move-dir refuses dangerous folders"
for d in /boot /etc/ssh /var/lib/apt /home; do
    if "$KS" move-dir "$d" >/dev/null 2>&1; then bad "move-dir $d should be refused"; else ok "move-dir $d refused"; fi
done
check "/boot untouched" test -d /boot -a ! -L /boot
if "$KS" move-dir "$APP" --user root >/dev/null 2>&1; then bad "--user: a folder outside the home should be refused"
else ok "--user: a folder outside the home is refused"; fi
check "refused folder left in place" bash -c "[ -d '$APP' ] && [ ! -L '$APP' ]"
if (unset KITE_TEST_NO_MOUNTCHECK; . "$KS"; mkdir -p "$T/plain"; dir_is_protected "$T/plain") 2>/dev/null; then
    bad "an ordinary folder looked protected"; else ok "an ordinary folder is not protected"; fi
mkdir -p "$T/mnt-parent/inner"
if mount -t tmpfs none "$T/mnt-parent/inner" 2>/dev/null; then
    if (unset KITE_TEST_NO_MOUNTCHECK; . "$KS"; dir_is_protected "$T/mnt-parent"); then ok "a folder with a disk mounted inside is protected"
    else bad "a folder with a disk mounted inside should be protected"; fi
    umount "$T/mnt-parent/inner"
else
    echo "  skip mount-point check (cannot mount tmpfs here)"
fi

echo "== verify / repair"
"$KS" move-dir "$APP" >/dev/null
# Simulate something replacing the link with a real folder.
rm "$APP"; mkdir -p "$APP"; echo new > "$APP/file"
if "$KS" verify >/dev/null 2>&1; then bad "verify should report the broken link"; else ok "verify reports the broken link"; fi
"$KS" verify --repair >/dev/null 2>&1 || true
check "repair moved it back to the external disk" test -L "$APP"
check "repaired content kept" test "$(cat "$APP/file")" = new
"$KS" restore-dir "$APP" >/dev/null

echo "== per-user app data (brave-browser profile)"
if ! id kitetest >/dev/null 2>&1; then
    useradd -m -s /bin/bash kitetest
    made_user=1
fi
H=$(getent passwd kitetest | cut -d: -f6)
rm -rf "$H/.config/BraveSoftware" "$H/.cache/BraveSoftware" "$T/ext/kite/home"
install -d -o kitetest -g kitetest "$H/.config/BraveSoftware/Brave-Browser/Default"
echo '{"pref":1}' > "$H/.config/BraveSoftware/Brave-Browser/Default/Preferences"
chown -R kitetest:kitetest "$H/.config"

"$KS" move-data brave-browser --user kitetest >/dev/null
check "profile folder is a link" test -L "$H/.config/BraveSoftware"
check "cache folder created and linked (app not run yet)" test -L "$H/.cache/BraveSoftware"
check "profile readable through the link" grep -q pref "$H/.config/BraveSoftware/Brave-Browser/Default/Preferences"
check "external folders owned by the user" test "$(stat -c %U "$T/ext/kite/home/kitetest/.config")" = kitetest
check "user can write through the link" setpriv --reuid=kitetest --regid=kitetest --init-groups sh -c "touch '$H/.config/BraveSoftware/written-by-user'"

"$KS" restore-data brave-browser --user kitetest >/dev/null
check "profile back on internal disk" bash -c "[ -d '$H/.config/BraveSoftware' ] && [ ! -L '$H/.config/BraveSoftware' ]"
check "file written while external survived" test -f "$H/.config/BraveSoftware/written-by-user"
check "ownership kept after restore" test "$(stat -c %U "$H/.config/BraveSoftware/written-by-user")" = kitetest

echo "== APT pre-install hook"
printf 'app\tfakepkg\t-\t/opt/fakepkg\t%s\n' "$T/ext/kite/system/opt/fakepkg" >> "$KITE_STATE_DIR/moved.tsv"
hook_input() {
    printf 'VERSION 2\nAPT::Architecture=amd64\n\n'
    printf 'fakepkg 1.0 < 1.1 /var/cache/apt/archives/fakepkg_1.1_all.deb\n'
    printf 'otherpkg - < 2.0 /var/cache/apt/archives/otherpkg_2.0_all.deb\n'
}
if hook_input | "$KS" apt-pre-install >/dev/null 2>&1; then ok "allows upgrade while the disk is connected"; else bad "should allow upgrade while connected"; fi
mv "$T/ext/kite/.kite-storage" "$T/ext/kite/.kite-storage.off"
if hook_input | "$KS" apt-pre-install 2>/dev/null; then bad "should block upgrade while disconnected"; else ok "blocks upgrade while the disk is disconnected"; fi
printf 'VERSION 2\n\nfakepkg 1.0 > - **REMOVE**\n' | "$KS" apt-pre-install 2>/dev/null && bad "should block removal while disconnected" || ok "blocks removal while the disk is disconnected"
printf 'VERSION 2\n\notherpkg - < 2.0 /x/otherpkg_2.0_all.deb\n' | "$KS" apt-pre-install 2>/dev/null && ok "unrelated packages are not blocked" || bad "unrelated packages must not be blocked"
mv "$T/ext/kite/.kite-storage.off" "$T/ext/kite/.kite-storage"

echo "== remove"
if "$KS" remove kite-system >/dev/null 2>&1; then bad "remove must refuse KiteOS packages"; else ok "remove refuses KiteOS packages"; fi
if "$KS" remove no-such-package-kitetest >/dev/null 2>&1; then bad "remove must refuse packages that are not installed"; else ok "remove refuses packages that are not installed"; fi
if "$KS" remove --purge >/dev/null 2>&1; then bad "remove must refuse unknown options"; else ok "remove refuses unknown options"; fi

echo "== launcher overrides"
# awk reads everything (head would SIGPIPE dpkg-query under pipefail), and
# dpkg-query exits 1 when any launcher has no owner, as on CI runners.
pkg=$(dpkg-query -S /usr/share/applications/*.desktop 2>/dev/null |
      awk -F': ' 'NR == 1 { sub(/[,:].*/, "", $1); print $1 }' || true)
if [ -n "$pkg" ]; then
    # shellcheck source=/dev/null
    ( . "$KS"; write_desktop_overrides "$pkg" )
    f=$(ls "$KITE_DESKTOP_OVERRIDES"/*.desktop 2>/dev/null | head -n1 || true)
    check "override written for $pkg" test -n "$f"
    check "Exec wrapped with kite-ext-run" grep -q '^Exec=/usr/bin/kite-ext-run ' "$f"
    ( . "$KS"; remove_desktop_overrides "$pkg" )
    check "override removed" bash -c "! ls '$KITE_DESKTOP_OVERRIDES'/*.desktop >/dev/null 2>&1"
fi

echo "== candidate detection on real packages"
out=$("$KS" candidates dpkg coreutils 2>&1)
check "never proposes shared system folders" bash -c "! grep -Eq '  /(usr|usr/share|usr/lib|opt|etc)$' <<< \"\$1\"" _ "$out"
lo=$(dpkg-query -W -f='${Package}\n' 'libreoffice-core*' 2>/dev/null | head -n1 || true)
if [ -n "$lo" ]; then
    out=$("$KS" candidates "$lo" 2>&1)
    echo "$out" | sed 's/^/     /'
    check "shared folder /usr/lib/libreoffice not offered for one package" bash -c "! grep -q '/usr/lib/libreoffice$' <<< \"\$1\"" _ "$out"
fi

echo
echo "== clean-up"
cleanup; made_user=
check "throw-away user kitetest removed (not left on the laptop or its login screen)" bash -c "! id kitetest >/dev/null 2>&1 && [ ! -e /home/kitetest ]"

echo
echo "storage tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
