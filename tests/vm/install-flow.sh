#!/bin/bash
# Drive the KiteOS installer (Calamares) in a running live VM, the way a person
# would: click through Welcome, Location, Keyboard, Partitions (erase disk),
# fill in the user page, confirm, and wait until it has finished.
#   install-flow.sh VMNAME [FULLNAME LOGIN HOSTNAME PASSWORD]
set -euo pipefail
cd "$(dirname "$0")"
VM=$1
FULL=${2:-Kite Tester} LOGIN=${3:-tester} HOST=${4:-kiteos-test} PASS=${5:-kitepass1}
k() { ./kitevm.py "$@"; }
NEXT_X=1050 NEXT_Y=659

k click "$VM" "${KITE_INSTALL_X:-424}" 746         # "Install KiteOS" on the shelf
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
k click "$VM" $NEXT_X $NEXT_Y                         # -> Summary
sleep 20
k click "$VM" $NEXT_X $NEXT_Y                         # Install
sleep 8
k click "$VM" 873 387                                 # "Install Now"
echo "installing since $(date +%H:%M)"
k wait "$VM" 'All done|Installation Failed|has been installed' 7200 >/dev/null
k ocr "$VM" | grep -iE 'done|fail|error|installed' | head -5
