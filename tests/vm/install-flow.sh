#!/bin/bash
# Drive the KiteOS installer (Calamares) in a running live VM, the way a person
# would: click through Welcome, Location, Keyboard, Partitions (erase disk),
# fill in the user page, pick the desktop layout, confirm, and wait until it
# has finished.
#   [KITE_LAYOUT=windows|mac] install-flow.sh VMNAME [FULLNAME LOGIN HOSTNAME PASSWORD]
# KITE_INSTALL_X/Y: where "Install KiteOS" is on the live taskbar.
# KITE_LAYOUT_X, KITE_WINDOWS_Y, KITE_MAC_Y: the Desktop page's list items.
set -euo pipefail
cd "$(dirname "$0")"
VM=$1
FULL=${2:-Kite Tester} LOGIN=${3:-tester} HOST=${4:-kiteos-test} PASS=${5:-kitepass1}
k() { ./kitevm.py "$@"; }
NEXT_X=1050 NEXT_Y=659
LAYOUT=${KITE_LAYOUT:-windows}
case $LAYOUT in
    windows) LAYOUT_NAME='Windows style' LAYOUT_Y=${KITE_WINDOWS_Y:-160} ;;
    mac)     LAYOUT_NAME='Mac style'     LAYOUT_Y=${KITE_MAC_Y:-190} ;;
    *) echo "KITE_LAYOUT must be windows or mac, not '$LAYOUT'" >&2; exit 2 ;;
esac

# The live session uses the windows layout: a 48 px taskbar at the bottom,
# left-aligned, with Start, Search, then the pinned apps; kite-layout pins
# "Install KiteOS" first, so it is the third button.
k click "$VM" "${KITE_INSTALL_X:-120}" "${KITE_INSTALL_Y:-744}"   # "Install KiteOS"
k wait "$VM" 'Welcome to the' 600 >/dev/null
sleep 5
for _ in location keyboard partitions users; do       # Welcome -> ... -> Users
    k click "$VM" $NEXT_X $NEXT_Y
    sleep 25
done
k click "$VM" 445 160; k type "$VM" "$FULL"
k click "$VM" 445 214; k keys "$VM" ctrl-a; k type "$VM" "$LOGIN"
k click "$VM" 445 268; k keys "$VM" ctrl-a; k type "$VM" "$HOST"
k click "$VM" 445 322; k type "$VM" "$PASS"
k click "$VM" 650 322; k type "$VM" "$PASS"
sleep 5
k click "$VM" $NEXT_X $NEXT_Y                         # -> Desktop
k wait "$VM" 'Windows style|Mac style' 120 >/dev/null
sleep 3
k click "$VM" "${KITE_LAYOUT_X:-330}" "$LAYOUT_Y"     # pick the layout in the list
sleep 3
k click "$VM" $NEXT_X $NEXT_Y                         # -> Summary
sleep 20
k ocr "$VM" | grep -i "$LAYOUT_NAME" >/dev/null ||
    echo "warning: Summary does not mention '$LAYOUT_NAME'; check the Desktop page click" >&2
k click "$VM" $NEXT_X $NEXT_Y                         # Install
sleep 8
k click "$VM" 873 387                                 # "Install Now"
echo "installing since $(date +%H:%M)"
k wait "$VM" 'All done|Installation Failed|has been installed' 7200 >/dev/null
k ocr "$VM" | grep -iE 'done|fail|error|installed' | head -5
