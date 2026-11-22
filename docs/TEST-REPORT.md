# KiteOS test report

ISO: `kiteos-20261122-amd64.iso` (1.3 GB), Debian 13.8 "trixie", Linux
6.12.117, Brave 1.100.58, ONLYOFFICE 10.0.0.

## How it was tested

| Test bed | Used for | Limits |
|---|---|---|
| QEMU VM: UEFI (OVMF), 4 GB RAM, 2 vCPUs, 1360×768, 32 GB virtual disk, virtual USB stick | Boot menu, splash, live desktop, every app, installer, installed-system boot, login, lock screen, hibernate and resume, external-drive features | Emulated CPU (no KVM), so it is roughly 10–30× slower than real hardware; no Chromebook keyboard, audio chip or Wi-Fi. |
| The image's own files running natively in a 2-core-pinned session (Xeon 2.1 GHz) | RAM and CPU measurements of the desktop, Brave and ONLYOFFICE | Not the N4020: CPU percentages must be scaled (see below). No systemd services in that session. |
| Unit and integration tests (`tests/run-all.sh`) | Storage tool, hibernation helper, keyboard map, splash, shortcut merge, package scripts | — |

## Results

### Boot, login, desktop

| Check | Result |
|---|---|
| USB boot menu (KiteOS-branded, starts by itself after 5 s) | ✅ |
| Boot splash (KiteOS logo and spinner, no text) on the live USB and the installed system | ✅ |
| Live session logs in by itself, ChromeOS-style shelf | ✅ |
| Launcher (circle button or Search key): full-screen grid with live search | ✅ |
| Window overview (top-row overview key / Super+W) | ✅ |
| Tray: Wi-Fi, volume, battery, clock and power, uniform white icons | ✅ (after fixing a double Wi-Fi icon, see below) |
| Power dialog: Log Out, Restart, Shut Down, Suspend, **Hibernate** | ✅ |
| Installed system: hidden GRUB → splash → login screen (Slick Greeter, KiteOS background) → desktop | ✅ |
| Lock screen after sleep or hibernate | ✅ |

### Apps (each opened from the shelf or launcher)

| App | Result |
|---|---|
| Brave: Wikipedia, BBC, Google, Python docs, Hacker News, The Guardian, 720p video | ✅ |
| ONLYOFFICE: start screen, new document, typing | ✅ natively. ❗ In the emulated VM the editor crashes (`libcef.so` segfault). This is a known problem of Chromium-based apps on emulated CPUs. It ran fine on a real CPU, but check it on the Chromebook. |
| Files (Thunar), Terminal, Settings, Bluetooth, Apps & Storage, text editor, image viewer, archive manager, task manager, screenshot, volume control | ✅ |
| Installer (Calamares): welcome → location → keyboard → erase disk → user → install → restart | ✅ run twice; the final ISO installed with no manual help (33 min in the emulator; expect about 10 min on the Chromebook) |

### Hibernation (installed system)

```
RAM:                 3915 MiB
Active swap:         /swapfile (5119 MiB)
Kernel resume args:  resume=UUID=… resume_offset=6885376
Kernel support:      yes
Kernel lockdown:     [none]
logind CanHibernate: yes
Hibernation looks ready.
```
`systemctl hibernate`, tested on both installs: the image was written and the
machine powered off in 27 s. On power-on it resumed into the same session
(lock screen, then the open terminal with its earlier output) in 94 s. Both
times are emulated; real hardware is much faster.

### Apps on an external drive (16 GB USB stick, FAT32 as bought)

| Step | Result |
|---|---|
| Apps & Storage → Set up an external disk: lists only the USB stick, warns it must be formatted, asks for the password, formats ext4, mounts `/mnt/kite-external` | ✅ |
| Move Brave's program files (489 MiB, `/opt/brave.com`) and its profile/cache to the stick | ✅ Brave starts and runs from the stick |
| Unplug the stick and open Brave | ✅ "External disk needed: connect the disk and open the app again" |
| Unplug and run `apt install --reinstall geany` (app on the stick) | ✅ refused: "Connect the disk and try again (nothing has been changed)" |
| Plug back in | ✅ mounted again automatically, status `[ok]` |
| Install a new app straight to the stick (Geany): download to the stick, install, move program files and settings | ✅ starts from the launcher, settings written to the stick |
| Upgrade/reinstall while on the stick | ✅ |
| Bring an app back to the internal disk | ✅ files, settings and launcher restored |

## Resource use

### Storage (installed on a 32 GB disk)

| | Size |
|---|---|
| ISO download | 1.3 GB |
| KiteOS system and apps | 3.75 GB (`/usr` 1.9 GB, `/opt` 1.5 GB of which ONLYOFFICE 1.0 GB and Brave 0.5 GB, `/var` 0.2 GB, `/boot` 0.1 GB) |
| Hibernation swap file | 5.0 GB (RAM + 1 GB) |
| **Free for your files** | **21 GB of 32 GB** |

Moving ONLYOFFICE and Brave to a USB stick or SD card frees another 1.5 GB.

### RAM, whole installed system at idle (`kite-resource-report`)

```
RAM        640 MiB used of 3916 MiB (3276 MiB available)
  Desktop (XFCE)          200 MiB
  Network & Bluetooth      87 MiB
  Display server (Xorg)    74 MiB
  System & other           56 MiB
  Audio                    17 MiB
CPU        1.0 % busy
```

### RAM with apps (PSS: shared memory divided fairly, so the parts add up)

| Situation | Desktop | Brave | ONLYOFFICE | Session total |
|---|---|---|---|---|
| A. Idle desktop | 235 MiB | — | — | **325 MiB** |
| B. Brave, 1 tab (Wikipedia) | 213 | 303 | — | **604 MiB** |
| C. Brave, 5 tabs | 203 | 345 | — | **636 MiB** |
| D. Brave playing 720p video, 6 tabs | 203 | 353 | — | **644 MiB** |
| G. ONLYOFFICE document + Brave (8 tabs) | 194 | 350 | 454 | **1085 MiB** |

These are the desktop-session processes. For the whole system add the
difference to the idle figure above (640 MiB total vs 325 MiB session),
about 315 MiB for the kernel, Xorg, NetworkManager and audio. So Brave with
5 tabs is roughly 950 MiB in total, and Brave plus ONLYOFFICE about 1.4 GB,
leaving around 2.5 GB free on the 4 GB Chromebook. When memory does run short,
zswap compresses pages in RAM first (zstd, about 3:1), then the swap file
takes over, and earlyoom closes the heaviest Brave tab before the desktop can
freeze.

Brave's RSS (the figure `top` shows) was 889 MiB with 8 tabs, but most of that
is memory shared between its processes. PSS counts it once, which gives 355 MiB.

Trimming found while measuring (now in the ISO): panel plugins run inside the
panel instead of four helper processes (−100 MiB), and the Bluetooth tray
applet, which used 90 MiB all the time, no longer starts by itself (Bluetooth
is in the launcher). Idle went from **537 → 325 MiB**.

### CPU

Measured as % of one core of a 2.1 GHz Xeon. The Celeron N4020 has roughly
half that speed per core and 2 cores, so the "N4020 estimate" column doubles
the figures. Treat it as a guide, not a measurement.

| Situation | Measured | N4020 estimate (of 200 % = both cores) |
|---|---|---|
| Idle desktop | 0 % | ~0 % |
| Brave, pages open but idle | 0.5–6 % | ~1–12 % |
| Loading a news front page | 12 % average over 25 s | ~25 % (pages take a few seconds) |
| 720p VP9 video (software decode) | 34 % (Brave 22.5 + display 11.5) | ~70 %, so 720p plays; 1080p will struggle |
| ONLYOFFICE editing + Brave in background | 15 % | ~30 % |

For video, the N4020's GPU can decode VP9 and H.264 in hardware
(`intel-media-va-driver` is installed). In Brave, open
`brave://flags/#enable-accelerated-video-decode` and check `brave://gpu`;
this cuts video CPU use sharply.

Measure on the real device with:
```bash
sudo kite-resource-report
```

## Problems found by testing, and fixed

1. Materia theme is not in Debian 13 → switched to **Orchis** (same Material style).
2. Optional packages pulled in **unwanted GIS/OpenCV/MySQL libraries** through a "polkit agent" dependency → `mate-polkit` is now chosen explicitly.
3. Live system had no first-user setup (`user-setup`) → added (removed again on install).
4. Live boot printed kernel messages → quiet boot parameters; KiteOS boot menu and branding.
5. Installer **password page could never continue** (dictionary check with no dictionary) → fixed.
6. Installer slideshow was blank: Qt's QtQuick module was missing (not pulled in without Recommends) → added to the live system, removed after install.
7. Launcher listed 47 entries including every settings sub-dialog and duplicates → 15 real apps.
8. **Two Wi-Fi icons** in the tray (startup race) → the applet now waits for the tray.
9. Tray icons were mixed sizes/colours → uniform white symbolic icons, round hover highlight.
10. Apps & Storage: app list took **over a minute** on a slow CPU (one package query per launcher) → one query, instant; the password box could hide behind the progress window → password asked first.
11. Apps & Storage: **installing to the external disk silently did nothing** (`apt-get --assume-no` exits 1 under `pipefail`) → fixed.
12. Apps & Storage: settings of a never-opened app were not moved → its settings folder is created on the external disk up front.
13. Brave key check: Brave rotated its signing key → verified the new key against brave.com/signing-keys before accepting it.
14. ONLYOFFICE key ID verified (E09C A29F 6E17 8040 EF22 B409 8320 CA65 CB2D E8E5).
15. GRUB's install fallback copy to `EFI/BOOT/BOOTX64.EFI` is made explicitly as a safety net.
16. `kite-resource-report` counted its own CPU use → excluded.
17. Live boot menu: GRUB font path fixed (menu editor drew boxes instead of borders).
18. Tray icons came from three different icon sets at three sizes → **KiteOS's own status icon set** (below), all drawn at 24 px.
19. Installer slideshow also needed the QtQuick.Window module → added (and removed after install).

## KiteOS tray icons

![KiteOS status icons](img/tray-icons.png)

Wi-Fi signal (5 levels, also used for the "connecting" animation), no
network, wired, mobile, VPN; volume muted, low, medium, high; microphone;
battery levels, low-battery warning, charging, charged, missing; mains
adapter; launcher and power buttons. They are drawn by
`artwork/status-icons.py` on one 24 px grid with one line weight. They are
"symbolic" icons, so GTK paints them in the shelf's text colour, and the
shelf draws every one at exactly 24 px (panel and tray icon size are both
fixed at 24). They are packaged as the `KiteOS` icon theme, which takes
everything else from Papirus.

## Still to check on the real Chromebook

These cannot be emulated: the Chromebook keyboard map (Search key, top row),
speakers and headphones (SOF audio), Wi-Fi, brightness keys, suspend on
lid close, real hibernate/resume timing, and ONLYOFFICE's editor (see above).
The check-list is in [INSTALL.md](INSTALL.md#after-installing-check-list).
