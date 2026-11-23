#!/bin/sh
# Re-render the PNG artwork from the SVG sources (needs rsvg-convert).
set -eu
cd "$(dirname "$0")"
P=../packages
r() { rsvg-convert "$@"; }
# Full-screen images ship as JPEG (soft gradients make multi-MB PNGs).
jpg() {  # jpg SVG OUT.jpg
    rsvg-convert -w 1920 -h 1080 "$1" -o "$2.png"
    if command -v sips >/dev/null; then sips -s format jpeg -s formatOptions 88 "$2.png" --out "$2" >/dev/null
    elif command -v magick >/dev/null; then magick "$2.png" -quality 88 "$2"
    else convert "$2.png" -quality 88 "$2"; fi
    rm -f "$2.png"
}
mkdir -p $P/kite-desktop/usr/share/backgrounds/kite $P/kite-desktop/usr/share/kite \
         $P/kite-desktop/usr/share/icons/hicolor/scalable/apps $P/kite-desktop/usr/share/icons/hicolor/256x256/apps \
         $P/kite-system/usr/share/kite/plymouth ../live/config/includes.chroot/etc/calamares/branding/kite
rm -f $P/kite-desktop/usr/share/backgrounds/kite/*
for w in bloom aurora waves; do jpg wallpaper-$w.svg $P/kite-desktop/usr/share/backgrounds/kite/$w.jpg; done
for l in frosted aurora dusk; do jpg login-$l.svg $P/kite-desktop/usr/share/backgrounds/kite/login-$l.jpg; done
r -w 220 greeter-logo.svg       -o $P/kite-desktop/usr/share/kite/greeter-logo.png
r -w 256 logo.svg               -o $P/kite-desktop/usr/share/icons/hicolor/256x256/apps/kiteos.png
cp logo.svg     $P/kite-desktop/usr/share/icons/hicolor/scalable/apps/kiteos.svg
r -w 300 watermark.svg          -o $P/kite-system/usr/share/kite/plymouth/watermark.png
r -w 128 logo.svg               -o ../live/config/includes.chroot/etc/calamares/branding/kite/kite-logo.png
r -w 800 -h 450 wallpaper-bloom.svg -o ../live/config/includes.chroot/etc/calamares/branding/kite/welcome.png
r -w 800 -h 600 live-boot.svg -o ../live/config/bootloaders/grub-pc/splash.png
rm -rf $P/kite-desktop/usr/share/icons/KiteOS/scalable/status
python3 status-icons.py $P/kite-desktop/usr/share/icons/KiteOS/scalable/status
# Installer pictures of the two desktop layouts (Calamares packagechooser),
# drawn over the Bloom wallpaper.
mkdir -p $P/kite-desktop/usr/share/kite/layouts
r -w 1920 -h 1080 wallpaper-bloom.svg -o layout-wallpaper.png
for l in windows mac; do
    sed 's#LAYOUT_WALLPAPER#layout-wallpaper.png#' layout-$l.svg > layout-$l.tmp.svg
    r -w 640 -h 400 layout-$l.tmp.svg -o $P/kite-desktop/usr/share/kite/layouts/$l.png
    rm -f layout-$l.tmp.svg
done
rm -f layout-wallpaper.png
echo "artwork rendered"
