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
| Releases | [v1.0](https://github.com/iwankurnia/kite-os/releases/tag/v1.0): the cloud-built ISO, SHA-256 `54cbb597…72405`, fully VM-tested. [v1.1](https://github.com/iwankurnia/kite-os/releases/tag/v1.1) (Latest): first ISO built by GitHub Actions (`6b06667`), adds the Brave flags wrapper, SHA-256 `348415b6…01f72`; not booted yet, flashed to the owner's USB stick 2026-11-23 |
| Base | Debian 13.8, kernel 6.12.117, XFCE 4.20, Calamares 3.3.14, Brave 1.100.58, ONLYOFFICE 10.0.0 |
| Tests | `sudo tests/run-all.sh`: 38 scripts lint-clean, 35 system and 31 storage checks pass |
| Verified in a VM | Everything in [TEST-REPORT.md](TEST-REPORT.md): boot, live desktop, every app, installer (3 full runs), installed-system boot and login, hibernate and resume, external-drive features, resource use |
| **Not verified** | Anything needing the real Chromebook: keyboard map (Search key, top row), SOF audio, Wi-Fi, brightness keys, lid suspend, real hibernate timing, and the ONLYOFFICE editor (crashes under QEMU emulation only; works natively) |

## Open to-do list

1. ~~Push to GitHub and release v1.0~~: done 2026-11-23.
2. ~~Commit email~~: the owner kept the history as it is; new commits in this
   repository use the GitHub noreply address (repo-local `git config`).
3. **First real-hardware run** on the Chromebook with the check-list in
   [INSTALL.md](INSTALL.md#after-installing-check-list). Fix whatever it finds.
   The likeliest areas: keyd map from `function_row_physmap`, audio UCM, VA-API.
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
KITE_INSTALL_X=445 tests/vm/install-flow.sh live     # x of "Install KiteOS" on the shelf
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
  requests `<name>-symbolic` at a forced size. Panel and systray icon size are
  both fixed at 24.
- **Brave's launcher reads no flags file** (`/opt/brave.com/brave/brave-browser`
  just runs `brave "$@"`); `~/.config/brave-flags.conf` is an Arch packaging
  convention. Hence the diversion and wrapper in kite-desktop. Chromium keeps
  only the last `--enable-features`, so the wrapper merges them.
- **Brave rotated its apt signing key.** The new release key
  `DBF1A116C220B8C7164F98230686B78420038257` was verified against
  brave.com/signing-keys.
- **VM quirks, not product bugs:**
  - The screen stays black after DPMS blanking under QEMU VGA (`xrefresh` fixes it).
  - OVMF only boots devices that have a `bootindex`.
  - The installed system uses the UK layout, so typed `|` and `@` come out wrong unless you `setxkbmap us`.
  - The shelf re-centres when windows open, so click coordinates shift.

## Key design decisions

| Decision | Why |
|---|---|
| XFCE + docklike + rofi (not GNOME/Plasma) | RAM: idle system 640 MiB total |
| Swap **file** sized RAM + 1 GB, ext4 only | Hibernation must work. Calamares' "suspend" swap sizing caps at 10 % of the disk; btrfs swap files are fragile |
| zswap (zstd), not zram | zram can't hold a hibernation image |
| suspend-then-hibernate enabled **only after** resume is configured | A half-configured system must never make the lid do nothing |
| `kite-storage`: move whole package-private dirs and symlink them | dpkg follows directory symlinks on upgrade. APT `Pre-Install-Pkgs` hook refuses to touch apps whose disk is unplugged |
| Orchis theme (Materia isn't in Debian 13), KiteOS status icon theme inheriting Papirus | Material/ChromeOS look with uniform tray |
| Brave policy: Rewards/Wallet/VPN/Tor/P3A off | Lighter; owner can change `/etc/brave/policies/managed/kite.json` |

## Releasing

Push a `v*` tag and the Build ISO workflow tests, builds and attaches
`kiteos-<version>-amd64.iso` and its `.sha256` to the release for that tag,
straight from the runner. To write the notes yourself, create the release
first; the workflow then only adds the files:

```bash
gh release create v1.2 --title "KiteOS 1.2" --notes-file notes.md   # creates the tag, starts the build
```

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

Where things stand (2026-11-23): v1.1 is Latest and flashed to the owner's
Kingston USB stick (read-back verified), not booted yet. Next is the
real-hardware run (to-do 3) and the Brave video check on the device (to-do 4).

- Builds: no local build needed. Push a tag or use
  `gh workflow run build-iso.yml` (see "Releasing"); `gh run download <run-id> -n kiteos-iso`
  fetches a manual run's ISO.
- Flashing: on macOS, `diskutil list external` then `sudo dd if=<iso> of=/dev/rdiskN bs=4m`;
  on Windows use Rufus in DD mode (or balenaEtcher). Check that the disk is the
  USB stick first; it is erased.
- Local test runs need Linux as root (`sudo tests/run-all.sh`); on macOS or
  Windows, rely on the workflow's test job.
