# KiteOS

A lightweight, ChromeOS-style Linux distribution based on **Debian 13 "trixie"**,
built for the **HP Chromebook 11 G8 EE** (board `VORTICON`, Intel Celeron N4020
"Gemini Lake", 4 GB RAM, 32 GB eMMC).

| | |
|---|---|
| **Desktop** | XFCE in two layouts, picked at install and switchable with `kite-layout`: **windows** (Fluent theme, Papirus icons, a taskbar with the Start menu, search and apps on the left) and **mac** (Qogir theme and icons, a menu bar at the top and a Dock). The **Search** key opens the menu in both. KiteOS tray icons, Inter font, three KiteOS wallpapers and three login screens. |
| **Boot and login** | Hidden GRUB menu, KiteOS splash screen (Plymouth, early Intel KMS), LightDM with Slick Greeter on a matching background. |
| **Hibernation** | A swap file of RAM + half of RAM (at most RAM + 4 GB) is created at install time, and `resume=` / `resume_offset=` are set up automatically. Closing the lid suspends; after 60 min the machine hibernates. It also hibernates on critical battery and after 30 min idle on battery. Hibernate is also in the power menu. |
| **Low memory** | zswap (zstd-compressed RAM cache in front of the swap file; unlike zram, it works with hibernation), earlyoom to end the biggest browser tab rather than freeze, a small journal, no Recommends and no docs. |
| **Apps** | **Brave** and **ONLYOFFICE Desktop Editors** from their vendors' official APT repositories. Brave's Rewards, Wallet, VPN and Tor are turned off by policy to keep it light. |
| **External storage** | **App Centre** (`kite-app-centre`) finds, installs and removes apps and installs updates. It installs an app to the internal disk, then can copy its program files and/or its settings and data to a USB or SD disk and symlink them back. APT refuses to touch those apps while the disk is unplugged, and their launchers say "connect your disk" instead of failing silently. |
| **Chromebook hardware** | Keyboard via `keyd`: tap Search for the menu, the top row works as printed, Search + top row = F1–F10, Search + Backspace = Delete, Search + arrows = Home/End/PgUp/PgDn. Audio through SOF with the Chromebook UCM profiles (`alsa-ucm-conf-cros`), and the touchpad ignores input while you type. |
| **Installer** | A live USB with a graphical installer (Calamares). |

## Quick start

1. **Replace the Chromebook firmware (one-time).** Flash MrChromebox's UEFI
   firmware. This model needs its battery disconnected while you do it.
   Follow **[docs/FIRMWARE.md](docs/FIRMWARE.md)** carefully.
2. **Get the ISO**: use the ready-made `out/kiteos-*.iso`, or rebuild it
   with `sudo ./build.sh` (see [docs/BUILD.md](docs/BUILD.md)).
3. **Write the ISO to a USB stick**, plug it into the Chromebook,
   power on and press **Esc** to choose the USB drive. The live desktop
   starts. Click **Install KiteOS** (the first pinned app). See
   [docs/INSTALL.md](docs/INSTALL.md).
4. After the first reboot, check hibernation:
   ```bash
   sudo kite-hibernate-setup --check
   ```


## Using it

- [docs/USING.md](docs/USING.md) covers the layouts, the keyboard, hibernation, and installing apps on an external disk.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) covers audio, keyboard, hibernation, the splash screen, login, and recovery.

## Why these choices

| Constraint | Decision |
|---|---|
| 4 GB RAM, of which Brave needs most | XFCE (X11) instead of GNOME or Plasma, with XFCE's own compositor. Whisker menu and docklike taskbar/Dock plugins inside the panel process. Session saving is off. |
| Hibernation must work | ext4 root and a swap file (not zram), resume configured by `kite-hibernate-setup`. zswap supplies the compression that zram would have. Suspend-then-hibernate only switches on once resume is verified, so a broken setup can't leave the lid doing nothing. |
| 32 GB eMMC | `--no-install-recommends` throughout, no package docs, only the firmware this machine needs, weekly `fstrim` instead of continuous discard, journal capped at 64 MB, and the installer removes itself after installing. |
| Slow eMMC | `noatime`, earlier dirty-page writeback, and `vm.swappiness=100` (swapping into zswap is cheaper than re-reading files from eMMC). |
| Chromebook keyboard and audio | The top-row layout is read from firmware (`function_row_physmap`) at every boot. Audio UCM files are applied only on Google hardware and re-applied after `alsa-ucm-conf` upgrades. |

## Repository layout

```
build.sh                    ISO build entry point (runs live-build in a Debian 13 container)
packages/
  kite-system/              hibernation setup, zswap, memory/OOM tuning, boot splash, GRUB defaults
  kite-chromebook/          keyd keyboard map generator, Chromebook audio UCM, libinput quirk
  kite-desktop/             XFCE layouts (windows, mac), kite-layout, login screens, artwork, defaults
  kite-storage/             kite-storage CLI + App Centre (GTK 3), APT safety hooks
live/                       live-build config, Calamares installer config and branding
scripts/                    package build, vendor repository keys
artwork/                    SVG sources for the logo, wallpaper, splash (render.sh → PNGs)
tests/                      unit/integration tests and a UI preview renderer
```

## Status

**Ready-made ISO:** `out/kiteos-YYYYMMDD-amd64.iso` (1.3 GB) with a
`.sha256` file. You don't need to build anything; to rebuild it yourself, see
[docs/BUILD.md](docs/BUILD.md).

Tested end to end in a UEFI virtual machine (4 GB RAM, 2 CPUs, 1360×768):
boot menu, splash, live desktop, every app, the installer, the installed
system's boot and login, hibernate and resume, and apps on a USB stick
(set up, move, run, unplug guard, install straight to the stick, bring back).
RAM, CPU and disk use were measured with Brave and ONLYOFFICE. The full
results, the 17 problems found and fixed, and what still needs checking on
the real Chromebook (keyboard, audio, Wi-Fi, lid) are in
**[docs/TEST-REPORT.md](docs/TEST-REPORT.md)**.

At a glance: the whole system uses **640 MiB of RAM at idle** (3.3 GB free),
about **950 MiB with Brave and 5 tabs**, and about **1.4 GB with Brave and
ONLYOFFICE** both open. Installed size is **3.75 GB** plus a 5 GB hibernation
swap file, leaving **21 GB free** on the 32 GB eMMC.

## Continuing development

See [docs/HANDOFF.md](docs/HANDOFF.md) for the full project state, decisions,
gotchas and to-do list. `CLAUDE.md` gives Claude Code the same pointers.

## Credits

- [MrChromebox](https://mrchromebox.tech) UEFI firmware.
- Audio UCM profiles from [WeirdTreeThing/alsa-ucm-conf-cros](https://github.com/WeirdTreeThing/alsa-ucm-conf-cros) (BSD-3-Clause, vendored at a pinned commit).
- Keyboard mapping logic adapted from [WeirdTreeThing/cros-keyboard-map](https://github.com/WeirdTreeThing/cros-keyboard-map) (BSD-3-Clause).
- Debian, XFCE, keyd, Calamares and Plymouth.
- Desktop layouts from [docker-crd-vstunnel](https://github.com/iwankurnia/docker-crd-vstunnel); themes by [vinceliuice](https://github.com/vinceliuice) (Fluent, Qogir, WhiteSur; GPL-3.0) and Papirus icons.

KiteOS is an unofficial personal build. It is not affiliated with Google, HP, Debian, Brave or ONLYOFFICE.
