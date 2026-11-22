# KiteOS

A lightweight, ChromeOS-style Linux distribution based on **Debian 13 "trixie"**,
built for the **HP Chromebook 11 G8 EE** (board `VORTICON`, Intel Celeron N4020
"Gemini Lake", 4 GB RAM, 32 GB eMMC).

| | |
|---|---|
| **Desktop** | XFCE set up to feel like ChromeOS: a bottom shelf with a launcher button, centred pinned and running apps, and the tray, volume, battery, clock and power buttons on the right. A full-screen app launcher opens when you tap the **Search** key. Materia theme, Papirus icons, Roboto font. |
| **Boot and login** | Hidden GRUB menu, KiteOS splash screen (Plymouth, early Intel KMS), LightDM with Slick Greeter on a matching background. |
| **Hibernation** | A swap file of RAM + 1 GB is created at install time, and `resume=` / `resume_offset=` are set up automatically. Closing the lid suspends; after 60 min the machine hibernates. It also hibernates on critical battery and after 30 min idle on battery. Hibernate is also in the power menu. |
| **Low memory** | zswap (zstd-compressed RAM cache in front of the swap file; unlike zram, it works with hibernation), earlyoom to end the biggest browser tab rather than freeze, a small journal, no Recommends and no docs. |
| **Apps** | **Brave** and **ONLYOFFICE Desktop Editors** from their vendors' official APT repositories. Brave's Rewards, Wallet, VPN and Tor are turned off by policy to keep it light. |
| **External storage** | **Apps & Storage** (`kite-apps`) installs an app to the internal disk, then can copy its program files and/or its settings and data to a USB or SD disk and symlink them back. APT refuses to touch those apps while the disk is unplugged, and their launchers say "connect your disk" instead of failing silently. |
| **Chromebook hardware** | Keyboard via `keyd`: tap Search for the launcher, the top row works as printed, Search + top row = F1–F10, Search + Backspace = Delete, Search + arrows = Home/End/PgUp/PgDn. Audio through SOF with the Chromebook UCM profiles (`alsa-ucm-conf-cros`), and the touchpad ignores input while you type. |
| **Installer** | A live USB with a graphical installer (Calamares). |

## Quick start

1. **Replace the Chromebook firmware (one-time).** Flash MrChromebox's UEFI
   firmware. This model needs its battery disconnected while you do it.
   Follow **[docs/FIRMWARE.md](docs/FIRMWARE.md)** carefully.
2. **Build the ISO** on any Linux PC with Docker or Podman (or let GitHub
   Actions build it). See [docs/BUILD.md](docs/BUILD.md):
   ```bash
   ./build.sh
   ```
3. **Write `out/kiteos-*.iso` to a USB stick**, plug it into the Chromebook,
   power on and press **Esc** to choose the USB drive. The live desktop
   starts. Click **Install KiteOS** (the first icon on the shelf). See
   [docs/INSTALL.md](docs/INSTALL.md).
4. After the first reboot, check hibernation:
   ```bash
   sudo kite-hibernate-setup --check
   ```

There is also an ISO-free route: install minimal Debian 13, then run
`sudo scripts/install-on-debian.sh` (see [docs/INSTALL.md](docs/INSTALL.md#option-b)).

## Using it

- [docs/USING.md](docs/USING.md) covers the keyboard, the launcher, hibernation, and installing apps on an external disk.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) covers audio, keyboard, hibernation, the splash screen, login, and recovery.

## Why these choices

| Constraint | Decision |
|---|---|
| 4 GB RAM, of which Brave needs most | XFCE (X11) instead of GNOME or Plasma. rofi for the launcher, with no daemon running between uses. Docklike shelf plugin. Session saving is off. |
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
  kite-desktop/             ChromeOS-style XFCE config, launcher, login screen, artwork, defaults
  kite-storage/             kite-storage CLI + "Apps & Storage" GUI, APT safety hooks
live/                       live-build config, Calamares installer config and branding
scripts/                    package build, keyd/docklike fallback build, vendor keys, install-on-debian
artwork/                    SVG sources for the logo, wallpaper, splash (render.sh → PNGs)
tests/                      unit/integration tests and a UI preview renderer
```

## Status: what has and hasn't been verified

Verified in the build sandbox (`tests/run-all.sh`):
- **Storage tool:** 31 checks, including a real data round trip through the external-disk symlinks, user file ownership, repair after breakage, the APT guard for an unplugged disk, and launcher wrapping.
- **System:** 35 checks covering swap-file size and `resume_offset` extraction on a real ext4 swap file, the GRUB drop-in, power policy, the keyboard map, the splash theme builder, and the XFCE shortcut merge.
- **Packages:** all four build and install cleanly in a clean Ubuntu 24.04 chroot, a Debian-family stand-in (24 checks, including maintainer scripts, triggers, a strict schema check of the login-screen settings, and apt still working with the KiteOS hooks). Re-run against Debian 13 with `tests/test-packages-chroot.sh trixie`.
- **Desktop:** rendered at 1366×768 in a virtual X display.

Not verified here. The sandbox could not reach Debian's mirrors and has no
Chromebook or KVM, so the first real run will be yours:
- the full `./build.sh` ISO build;
- the from-source fallback builds of `keyd` and the docklike plugin (only used if Debian 13 doesn't package them);
- booting, installing and hibernating on the actual HP Chromebook 11 G8 EE.

Please follow the check-lists in [docs/INSTALL.md](docs/INSTALL.md#after-installing-check-list).

## Credits

- [MrChromebox](https://mrchromebox.tech) UEFI firmware.
- Audio UCM profiles from [WeirdTreeThing/alsa-ucm-conf-cros](https://github.com/WeirdTreeThing/alsa-ucm-conf-cros) (BSD-3-Clause, vendored at a pinned commit).
- Keyboard mapping logic adapted from [WeirdTreeThing/cros-keyboard-map](https://github.com/WeirdTreeThing/cros-keyboard-map) (BSD-3-Clause).
- Debian, XFCE, rofi, keyd, Calamares and Plymouth.

KiteOS is an unofficial personal build. It is not affiliated with Google, HP, Debian, Brave or ONLYOFFICE.
