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
| Last commit | see `git log` (the ISO was built from the commit before `CLAUDE.md`/`HANDOFF.md` were added; nothing else changed) |
| ISO | `kiteos-20261122-amd64.iso`, 1.3 GB, SHA-256 `54cbb597348b2650f7040e4081a262a06cdc2bbf01beb997dbc2093a68872405` (sent to the owner in 4 parts; not in git) |
| Base | Debian 13.8, kernel 6.12.117, XFCE 4.20, Calamares 3.3.14, Brave 1.100.58, ONLYOFFICE 10.0.0 |
| Tests | `sudo tests/run-all.sh`: 38 scripts lint-clean, 35 system and 31 storage checks pass |
| Verified in a VM | Everything in [TEST-REPORT.md](TEST-REPORT.md): boot, live desktop, every app, installer (3 full runs), installed-system boot and login, hibernate and resume, external-drive features, resource use |
| **Not verified** | Anything needing the real Chromebook: keyboard map (Search key, top row), SOF audio, Wi-Fi, brightness keys, lid suspend, real hibernate timing, and the ONLYOFFICE editor (crashes under QEMU emulation only; works natively) |

## Open to-do list

1. **Push to GitHub** (owner does it from the laptop, see the end of this file),
   then `gh release create v1.0 <iso> <iso>.sha256 --notes-file docs/TEST-REPORT.md`.
2. **Commit email:** commits are authored `Iwan Kurnia <iwan.kurnia@healthmetrics.com>`
   (a work address). The owner may want to rewrite them to a GitHub noreply
   address before pushing publicly.
3. **First real-hardware run** on the Chromebook with the check-list in
   [INSTALL.md](INSTALL.md#after-installing-check-list). Fix whatever it finds.
   The likeliest areas: keyd map from `function_row_physmap`, audio UCM, VA-API.
4. **Brave hardware video decoding:** not enabled by default. It needs a Brave
   flag (`brave://flags/#enable-accelerated-video-decode`, or command-line
   flags via a launcher override). Measure the CPU difference on the device.
5. **GitHub Actions workflow** (`.github/workflows/build-iso.yml`) has never
   run. Check it the first time.
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

## Push from the owner's laptop (what was agreed)

The owner received `kite-os.bundle` (this repository with full history):

```bash
gh auth login && gh auth setup-git
git clone kite-os.bundle kite-os && cd kite-os
git remote set-url origin https://github.com/iwankurnia/kite-os.git
git push -u origin main
gh release create v1.0 ~/Downloads/kiteos-20261122-amd64.iso ~/Downloads/kiteos-20261122-amd64.iso.sha256 \
   --title "KiteOS 1.0" --notes-file docs/TEST-REPORT.md
```

Then continue locally by running `claude` inside the `kite-os` folder. Claude
Code reads `CLAUDE.md`, which points here.
