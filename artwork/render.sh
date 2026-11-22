#!/bin/sh
# Re-render the PNG artwork from the SVG sources (needs rsvg-convert).
set -eu
cd "$(dirname "$0")"
P=../packages
r() { rsvg-convert "$@"; }
mkdir -p $P/kite-desktop/usr/share/backgrounds/kite $P/kite-desktop/usr/share/kite \
         $P/kite-desktop/usr/share/icons/hicolor/scalable/apps $P/kite-desktop/usr/share/icons/hicolor/256x256/apps \
         $P/kite-system/usr/share/kite/plymouth ../live/config/includes.chroot/etc/calamares/branding/kite
r -w 1920 -h 1080 wallpaper.svg -o $P/kite-desktop/usr/share/backgrounds/kite/kite-default.png
r -w 1920 -h 1080 login.svg     -o $P/kite-desktop/usr/share/backgrounds/kite/kite-login.png
r -w 220 greeter-logo.svg       -o $P/kite-desktop/usr/share/kite/greeter-logo.png
r -w 256 logo.svg               -o $P/kite-desktop/usr/share/icons/hicolor/256x256/apps/kiteos.png
cp logo.svg     $P/kite-desktop/usr/share/icons/hicolor/scalable/apps/kiteos.svg
cp launcher.svg $P/kite-desktop/usr/share/icons/hicolor/scalable/apps/kite-launcher.svg
r -w 300 watermark.svg          -o $P/kite-system/usr/share/kite/plymouth/watermark.png
r -w 128 logo.svg               -o ../live/config/includes.chroot/etc/calamares/branding/kite/kite-logo.png
r -w 800 -h 450 wallpaper.svg   -o ../live/config/includes.chroot/etc/calamares/branding/kite/welcome.png
r -w 800 -h 600 live-boot.svg -o ../live/config/bootloaders/grub-pc/splash.png
rm -rf $P/kite-desktop/usr/share/icons/KiteOS/scalable/status
python3 status-icons.py $P/kite-desktop/usr/share/icons/KiteOS/scalable/status
echo "artwork rendered"
