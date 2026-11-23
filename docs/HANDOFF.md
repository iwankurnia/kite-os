# Handoff: KiteOS

This is the state of the project when it moved from the Claude Code cloud
session that built it to the owner's local machine. Read this before changing
anything.

## What was asked

The owner (a senior IT engineer) asked for:

1. A lightweight Debian-based distro for an **HP Chromebook 11 G8 EE** (very
   limited RAM, CPU and storage).
2. A nice **ChromeOS-like UI**, with boot and login that work well.
3. **Hibernation** (a must).
4. **Brave** as the browser and **ONLYOFFICE** as the office suite.
5. When installing an app, an **option to put it on an external disk**, both
   the program files and the config/data. Install internally first, copy to the
   external disk, then symlink back.

Follow-up requests, all done:

- A ready-to-use ISO with the installer.
- A report of RAM, storage and CPU use while running Brave.
- Remove unneeded apps and scripts.
- Test the external-drive feature.
- Test everything: UI, every app, login, booting.
- Make the tray icons look nice: **KiteOS's own icons at one uniform size**.
- Send the ISO and put the work on GitHub (`iwankurnia/kite-os`).

## Current state

| | |
|---|---|
| Last commit | see `git log` |
| Releases | v1.0 cloud-built (VM-tested); v1.1 Brave VA-API; v1.2 has a vivid white-screen bug (use 1.2.1+); v1.2.2 skipped; **v1.2.3 boots and works on the HP Chromebook 11 G8 EE** from USB (animations, Bluetooth audio, drive icons, vivid colours); v1.2.4 adds picom fades, stronger shadows and touchpad tap-to-click/natural scrolling (not yet on the device); **v1.3.0** (Latest) replaces the shelf and rofi with the windows and mac layouts, and its `xfwm4.xml` (xfwm4's own compositor, no picom) replaces 1.2.4's fades and shadows; **v1.3.1 in progress** (installer Desktop page, light login screen, menu Favourites, App Centre fixes, live `kite-layout` switch without restarting xfwm4). Every release from 1.2.3 carries the kite-*.deb files for `kite-update` |
| Base | Debian 13.8, kernel 6.12.117, XFCE 4.20, Calamares 3.3.14, Brave 1.100.58, ONLYOFFICE 10.0.0 |
| Tests | `sudo tests/run-all.sh`: 38 scripts lint-clean, 35 system and 31 storage checks pass |
| Verified in a VM | Everything in [TEST-REPORT.md](TEST-REPORT.md): boot, live desktop, every app, installer (3 full runs), installed-system boot and login, hibernate and resume, external-drive features, resource use. That report tested the 1.2 shelf build; the 1.3 layouts and the installer's Desktop page have not had a full VM run yet |
| **Not verified** | Anything needing the real Chromebook: keyboard map (Search key, top row), SOF audio, Wi-Fi, brightness keys, lid suspend, real hibernate timing, and the ONLYOFFICE editor (crashes under QEMU emulation only; works natively) |

## Open to-do list

1. ~~Push to GitHub and release v1.0~~: done 2026-11-23.
2. ~~Commit email~~: the owner kept the history as it is; new commits in this
   repository use the GitHub noreply address (repo-local `git config`).
3. **Real-hardware run, in progress.** Live USB on the device works: desktop,
   launcher, Brave, Wi-Fi, Bluetooth audio, animations, vivid colours, drive
   icons. Still to check from [INSTALL.md](INSTALL.md#after-installing-check-list):
   install to the eMMC, hibernate and resume, lid, keyboard top row, speakers
   and headphone jack, brightness keys. After installing, `kite-update` keeps
   it current.
4. **Brave hardware video decoding:** on by default from kite-desktop 1.1.0
   (after the v1.0 ISO): a KiteOS wrapper takes the place of
   `/usr/bin/brave-browser-stable` (dpkg diversion) and adds the flags in
   `/etc/kite/brave-flags.conf` (`--enable-features=AcceleratedVideoDecodeLinuxGL`).
   Still to do on the device: confirm `VaapiVideoDecoder` in
   `brave://media-internals`, measure CPU with and without, and try the
   commented-out `AcceleratedVideoDecodeLinuxZeroCopyGL`. YouTube may pick AV1,
   which the N4020 cannot decode in hardware: check the codec in "Stats for
   nerds" (`av01` = software decode) and, if so, look at blocking AV1.
5. ~~GitHub Actions workflow~~: works since 2026-11-23 (tests ~2 min, ISO
   ~13 min). See "Releasing" below.
6. Optional ideas, not started:
   - trim Papirus icon sizes (~10 MB, low value)
   - an "updates available" notification
   - a check that the keyd map matches the 11 G8 EE top row
7. **App Centre** (`kite-app-centre`, kite-storage 1.1.0, branch
   `wip/app-centre`): one GTK 3 window replaces the yad dialogs of kite-apps
   (Discover, Installed, Storage, Updates; `kite-apps` now just opens it).
   Unit-tested helpers only so far; still to do in a VM: every page in
   Fluent-Light and Qogir-Light at 1366×768, the polkit prompt before the
   progress area, the `sudo -A` fallback with no polkit agent, the taskbar pin
   grouping (WM_CLASS `kite-apps`), and the new `kite-storage remove`.

## How it was built and tested (so you can repeat it)

The cloud sandbox could not reach Debian mirrors directly, so it used a local
HTTP relay (`KITE_MIRROR`, `KITE_SECURITY_MIRROR`, `KITE_BRAVE_MIRROR`,
`KITE_ONLYOFFICE_MIRROR` variables) and `KITE_NATIVE=1` in a Debian 13 chroot.
**On a normal machine none of that is needed:**

```bash
sudo ./build.sh                       # uses Docker/Podman + debian:trixie, ~15–30 min
```

VM testing uses `tests/vm/kitevm.py` (QEMU + OVMF; uses KVM automatically when
`/dev/kvm` is writable, which makes it ~10–30× faster than the sandbox's
emulation). Needs `qemu-system-x86 ovmf imagemagick tesseract-ocr`.

```bash
qemu-img create -f qcow2 emmc.qcow2 32G
KITEVM_RES=1360x768 tests/vm/kitevm.py start live --iso out/kiteos-*.iso --disk emmc.qcow2
tests/vm/kitevm.py shot live screen.png
KITE_LAYOUT=windows tests/vm/install-flow.sh live    # or mac; KITE_INSTALL_X/Y move the taskbar click
tests/vm/kitevm.py start inst --disk emmc.qcow2       # boot the installed system
tests/vm/kitevm.py usb inst add usb.img               # hot-plug a USB disk image
```

Use `KITEVM_RES=1360x768`: QEMU's VGA cannot do 1366×768.

RAM/CPU of the apps was measured by running the unpacked image's own session
natively (`tests/measure/chroot-session.sh` + `measure-procs.py`, pinned to 2
cores). On the device, use `sudo kite-resource-report`.

### Gotchas learned the hard way

- **`set -o pipefail` + `grep -q`** makes the left side fail with SIGPIPE.
  Use `grep … >/dev/null` or `awk`. This broke `build-extra-debs` and `swap_active`.
- **`apt-get --assume-no` exits 1** even when it only reports the size. This
  silently broke `kite-storage install`; it's now wrapped with `|| true`.
- **`dpkg-query -S` once per file is very slow** on a slow CPU (over a minute
  for the app list). Pass all files to one call.
- **Calamares `grubcfg` strips `resume=`** from `/etc/default/grub`, so
  hibernation params live in `/etc/default/grub.d/kite-resume.cfg`.
- **Calamares slideshow** needs `qml6-module-qtquick` **and**
  `qml6-module-qtquick-window`. They are Recommends, so they're not installed with
  `--apt-recommends false`. Both are removed after install via `packages.conf`.
- **Calamares password page** needs `dictcheck=0` (no cracklib dictionary).
- **live-build "optional packages" hook with `first_of`** let apt pick a heavy
  polkit agent (ukui-polkit plus GIS/OpenCV/MySQL). List packages explicitly instead.
- **xfce4-panel `force-all-internal`** saves ~100 MB (no wrapper process per
  plugin). The Bluetooth applet is not autostarted (~90 MB).
- **nm-applet started before the tray** shows two icons. It starts through
  `/usr/lib/kite/desktop/after-tray`, which waits for `org.kde.StatusNotifierWatcher`.
- **Tray icons:** GTK only recolours *fills* of symbolic SVGs, so
  `artwork/status-icons.py` draws filled shapes, not strokes. The systray
  requests `<name>-symbolic` at a forced size. Panel/tray icon sizes: windows
  24/20, mac 18/18 (`xfce4-panel.xml` of each layout). The plain variants are
  near black (`#1b1b1b`) for the light panels.
- **Brave's launcher reads no flags file** (`/opt/brave.com/brave/brave-browser`
  just runs `brave "$@"`); `~/.config/brave-flags.conf` is an Arch packaging
  convention. Hence the diversion and wrapper in kite-desktop. Chromium keeps
  only the last `--enable-features`, so the wrapper merges them.
- **`xrandr --set CTM` takes nine decimal matrix values** (`1,0,0,0,1,0,0,0,1`) on
  Debian 13: xrandr's `ctm_from_string` encodes them to S31.32 itself. The
  18 pre-encoded integers older guides show are read as coefficients in the
  hundreds of millions and turn the screen white (shipped by mistake in v1.2,
  fixed in kite-desktop 1.1.2). The 11 G8 EE does apply CTM in hardware.
- **Brave rotated its apt signing key.** The new release key
  `DBF1A116C220B8C7164F98230686B78420038257` was verified against
  brave.com/signing-keys.
- **VM quirks, not product bugs:**
  - The screen stays black after DPMS blanking under QEMU VGA (`xrefresh` fixes it).
  - OVMF only boots devices that have a `bootindex`.
  - The installed system uses the UK layout, so typed `|` and `@` come out wrong unless you `setxkbmap us`.
  - The mac Dock re-centres when windows open, so click coordinates shift.

## Key design decisions

| Decision | Why |
|---|---|
| XFCE (not GNOME/Plasma), layouts from docker-crd-vstunnel | RAM: idle system 640 MiB total. 1.3 replaced the ChromeOS-style shelf + rofi launcher with the container's two layouts (owner's call, 2026-11-23) |
| Two layouts, chosen at install (Calamares packagechooser → contextualprocess → `kite-layout --system`), switchable with `kite-layout` | Owner wanted both. Layout files live in `/usr/share/kite/layouts/{common,windows,mac}` and are applied to an account at first login (`kite-user-init` → `kite-layout --first-login`), not via `/etc/skel` |
| KiteOS kite as the mac menu button, not WhiteSur's Apple logo | Shipping Apple's logo as an OS's main button would impersonate Apple's branding |
| Tray packs `KiteOS-Tray-*` over `KiteOS` over the layout icon theme | The container packs (generated by `tools/make-tray-icons.py` in docker-crd-vstunnel, copied here) lack NetworkManager's `nm-*` glyphs and the drive-icon fix; the `KiteOS` pack fills those and no longer inherits Papirus itself (it would push Papirus ahead of Papirus-Light) |
| Fluent/Qogir/WhiteSur via a live-build hook from pinned release tags | Not in Debian; same tags as the container. Only new ISOs update them, not `kite-update`. Not checksum-pinned yet |
| Swap **file** sized RAM + 1 GB, ext4 only | Hibernation must work. Calamares' "suspend" swap sizing caps at 10 % of the disk; btrfs swap files are fragile |
| zswap (zstd), not zram | zram can't hold a hibernation image |
| suspend-then-hibernate enabled **only after** resume is configured | A half-configured system must never make the lid do nothing |
| `kite-storage`: move whole package-private dirs and symlink them | dpkg follows directory symlinks on upgrade. APT `Pre-Install-Pkgs` hook refuses to touch apps whose disk is unplugged |
| Fluent-Light (windows) and Qogir-Light (mac) themes; Orchis and the Papirus-inheriting KiteOS icon theme were the 1.2 shelf's | 1.3 layouts; the icon stacking is in the tray-packs row above |
| Brave policy: Rewards/Wallet/VPN/Tor/P3A off | Lighter; owner can change `/etc/brave/policies/managed/kite.json` |

## Releasing

Push a `v*` tag and the Build ISO workflow tests, builds and attaches
`kiteos-<version>-amd64.iso` and its `.sha256` to the release for that tag,
straight from the runner. To write the notes yourself, create the release
first; the workflow then only adds the files:

```bash
gh release create v1.2 --title "KiteOS 1.2" --notes-file notes.md   # creates the tag, starts the build
```

Every release also carries the four `kite-*.deb` files and
`kite-packages.sha256`, which `kite-update` on installed systems uses. So a
fix that needs a new Debian package must add it to a kite package's
`Depends` (as `libspa-0.2-bluetooth` and the Whisker menu are), not only to
`live/config/package-lists`, or installed systems won't get it.

Without a release, a pushed tag gets one with generated notes. Manual runs
(`gh workflow run build-iso.yml`) only leave the ISO as a 90-day artifact.

## Continuing on another machine

Everything needed is in this repository and on GitHub; nothing lives only on
one laptop.

```bash
gh auth login                      # GitHub.com, SSH or HTTPS, browser login
gh repo clone iwankurnia/kite-os && cd kite-os
git config user.name "Iwan Kurnia"
git config user.email "6760806+iwankurnia@users.noreply.github.com"   # repo only, keeps the work address off new commits
claude                             # reads CLAUDE.md, which points here
```

Where things stand (2026-11-24): v1.3.0 is Latest; v1.3.1 is in progress
(see "Current state"). v1.2.3 is the release proven on the device from USB. Next is the
real-hardware run (to-do 3) and the Brave video check on the device (to-do 4).

- Builds: no local build needed. Push a tag or use
  `gh workflow run build-iso.yml` (see "Releasing"); `gh run download <run-id> -n kiteos-iso`
  fetches a manual run's ISO.
- Flashing: on macOS, `diskutil list external` then `sudo dd if=<iso> of=/dev/rdiskN bs=4m`;
  on Windows use Rufus in DD mode (or balenaEtcher). Check that the disk is the
  USB stick first; it is erased.
- Local test runs need Linux as root (`sudo tests/run-all.sh`); on macOS or
  Windows, rely on the workflow's test job.
