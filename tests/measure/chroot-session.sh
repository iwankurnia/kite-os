#!/bin/bash
# Run a KiteOS desktop session from an unpacked image root against a host X
# server (Xvfb), as user "meas". Used for native (non-emulated) app tests and
# CPU measurements.
#   chroot-session.sh ROOT DISPLAY start|run CMD...|stop
set -euo pipefail
ROOT=$1 DISP=$2 ACTION=$3
shift 3
MUID=$(chroot "$ROOT" id -u meas)
as_user() {
    chroot "$ROOT" /usr/sbin/runuser -u meas -- env -i HOME=/home/meas USER=meas LOGNAME=meas \
        PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" LANG=en_GB.UTF-8 \
        XDG_RUNTIME_DIR="/run/user/$MUID" XDG_CURRENT_DESKTOP=XFCE \
        XDG_DATA_DIRS=/usr/local/share:/usr/share/kite/xdg:/usr/share \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$MUID/bus" "$@"
}
case "$ACTION" in
    start)
        mkdir -p "$ROOT/run/user/$MUID"
        chroot "$ROOT" chown meas:meas "/run/user/$MUID"
        chmod 700 "$ROOT/run/user/$MUID"
        as_user /usr/lib/kite/desktop/kite-user-init || true
        # shellcheck disable=SC2016  # expanded by the inner shell
        as_user sh -c 'dbus-daemon --session --address=$DBUS_SESSION_BUS_ADDRESS --fork --nopidfile'
        as_user sh -c 'nohup xfce4-session > /tmp/session.log 2>&1 &'
        ;;
    run)
        as_user sh -c "nohup $* > /tmp/run-\$\$.log 2>&1 &"
        ;;
    stop)
        chroot "$ROOT" pkill -u meas || true
        ;;
esac
