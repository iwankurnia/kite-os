#!/usr/bin/python3
"""Render the KiteOS wallpapers and login backgrounds from their SVG sources
as 1920 x 1200 JPEGs.

1920 x 1200 (16:10) is pixel-sharp on 16:10 monitors; on 16:9 screens (the
Chromebook's 1366 x 768, 1920 x 1080) the desktop's zoom trims a thin band at
the top and bottom and scales down, which stays sharp. A 1920 x 1080 picture
would instead be enlarged 11 % on a 1920 x 1200 monitor. The sources are
1920 x 1080: they are rendered 1200 high and cropped at the sides, around
each picture's subject.

  artwork/render-wallpapers.py OUTPUT_DIR [NAME...]

NAME is a wallpaper (wallpaper-NAME.svg -> NAME.jpg) or login-NAME
(login-NAME.svg -> login-NAME.jpg). Uses GdkPixbuf's SVG loader (librsvg).
"""
import os
import sys

import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = ("bloom", "aurora", "waves", "dunes", "lagoon", "nightfall", "horizon",
         "mist", "mirror", "cabin", "meadow", "coast",
         "login-frosted", "login-aurora", "login-dusk")
SIZE = (1920, 1200)
# Where the subject is, across the 1920-wide source (default: the middle);
# the side crop keeps it in view.
FOCUS = {"dunes": 1250, "horizon": 1150, "mist": 1300, "cabin": 1100,
         "meadow": 1180, "coast": 1220}
QUALITY = "88"


def render(name, out):
    src = os.path.join(HERE, (name if name.startswith("login-") else "wallpaper-" + name) + ".svg")
    w, h = SIZE
    scale = h / 1080                                   # sources are 1920 x 1080
    big = GdkPixbuf.Pixbuf.new_from_file_at_scale(src, round(1920 * scale), h, False)
    centre = FOCUS.get(name, 960) * scale
    x = int(min(max(centre - w / 2, 0), big.get_width() - w))
    big.new_subpixbuf(x, 0, w, h).savev(os.path.join(out, name + ".jpg"), "jpeg",
                                        ["quality"], [QUALITY])


def main(argv):
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    out, names = argv[0], argv[1:] or NAMES
    os.makedirs(out, exist_ok=True)
    for n in names:
        render(n, out)
        print("rendered", n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
