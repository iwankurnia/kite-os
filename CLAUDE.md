# KiteOS: notes for Claude Code

KiteOS is a lightweight, ChromeOS-style Debian 13 ("trixie") distribution for
the owner's **HP Chromebook 11 G8 EE** (board VORTICON, Gemini Lake N4020,
4 GB RAM, 32 GB eMMC, MrChromebox UEFI firmware). It is built as a live/installer
ISO with live-build and Calamares.

**Read [docs/HANDOFF.md](docs/HANDOFF.md) first.** It has the full history,
decisions, test results, known issues and the open to-do list from the session
that built this.

## Conventions
- Prose, UI text, comments and docs use **British English**. Code identifiers stay as they are.
- Keep the system light: no Recommends, no docs, nothing always-on that the owner didn't ask for.
- Never commit build output (`out/`, `live/chroot`, `live/binary`, `live/cache`, generated `live/config/*`; see `.gitignore`).
- Vendor signing keys are checked by key ID in `scripts/fetch-vendor-keys.sh`. If a vendor rotates a key, verify it against the vendor's website before updating the ID.

## Commands
```bash
sudo tests/run-all.sh                 # shellcheck + XML/YAML + unit/integration tests (must pass)
sudo ./build.sh                       # build the ISO in a debian:trixie container -> out/
sudo tests/test-packages-chroot.sh trixie https://deb.debian.org/debian   # install test of the .debs
tests/vm/kitevm.py --help             # drive a QEMU test VM (boot, click, type, OCR, serial shell)
```

## Layout
- `packages/kite-*`: the four KiteOS .deb packages (system, chromebook, desktop, storage), built by `scripts/build-packages.sh`
- `live/`: live-build config: package lists, hooks, Calamares config and branding, boot menu theme
- `artwork/`: SVG sources; `render.sh` renders PNGs, `status-icons.py` generates the tray icon theme
- `tests/`: unit tests, VM driver (`tests/vm`), measurement helpers (`tests/measure`)
- `docs/`: user docs, `TEST-REPORT.md`, `HANDOFF.md`
