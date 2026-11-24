#!/bin/sh
# Re-render the PNG/JPEG artwork from the SVG sources (needs rsvg-convert and
# python3-gi with the GdkPixbuf SVG loader).
set -eu
cd "$(dirname "$0")"
P=../packages
r() { rsvg-convert "$@"; }
# Full-screen images (wallpapers, login backgrounds) ship as JPEG, rendered
# by render-wallpapers.py (soft gradients make multi-MB PNGs).
mkdir -p $P/kite-desktop/usr/share/backgrounds/kite $P/kite-desktop/usr/share/kite \
         $P/kite-desktop/usr/share/icons/hicolor/scalable/apps $P/kite-desktop/usr/share/icons/hicolor/256x256/apps \
         $P/kite-system/usr/share/kite/plymouth ../live/config/includes.chroot/etc/calamares/branding/kite
rm -f $P/kite-desktop/usr/share/backgrounds/kite/*
# Wallpapers and login backgrounds: 1920 x 1200, sharp on 16:10 monitors too
python3 render-wallpapers.py $P/kite-desktop/usr/share/backgrounds/kite
r -w 220 greeter-logo.svg       -o $P/kite-desktop/usr/share/kite/greeter-logo.png
r -w 256 logo.svg               -o $P/kite-desktop/usr/share/icons/hicolor/256x256/apps/kiteos.png
cp logo.svg     $P/kite-desktop/usr/share/icons/hicolor/scalable/apps/kiteos.svg
# "Install KiteOS" (live session only): the kite with an install badge
r -w 256 install.svg            -o ../live/config/includes.chroot/usr/share/icons/hicolor/256x256/apps/kiteos-install.png
cp install.svg  ../live/config/includes.chroot/usr/share/icons/hicolor/scalable/apps/kiteos-install.svg
r -w 300 watermark.svg          -o $P/kite-system/usr/share/kite/plymouth/watermark.png
r -w 128 logo.svg               -o ../live/config/includes.chroot/etc/calamares/branding/kite/kite-logo.png
r -w 800 -h 450 wallpaper-bloom.svg -o ../live/config/includes.chroot/etc/calamares/branding/kite/welcome.png
r -w 800 -h 600 live-boot.svg -o ../live/config/bootloaders/grub-pc/splash.png
echo "artwork rendered"
