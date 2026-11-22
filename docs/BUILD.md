# 2. Building the ISO

A ready-made, tested ISO is already in `out/`. Rebuild only if you change
something.

You need a 64-bit Linux PC (or VM) with **Docker or Podman**, about **25 GB
free disk** and Internet access. The build runs inside a `debian:trixie`
container, so the host distribution does not matter.

```bash
git clone <this repository> kiteos && cd kiteos
sudo ./build.sh
```

The result is `out/kiteos-YYYYMMDD-amd64.iso` (about 1.3 GB) with a
`.sha256` next to it. A build takes about 15–30 minutes on a 4-core PC, plus
download time for about 1 GB of packages.

What `build.sh` does:
1. Installs live-build and friends in the container.
2. `scripts/build-packages.sh`: builds `kite-system`, `kite-chromebook`,
   `kite-desktop` and `kite-storage`.
3. `scripts/fetch-vendor-keys.sh`: downloads the Brave and ONLYOFFICE signing
   keys, checks their key IDs, and adds both repositories.
4. Runs `lb build` with `live/auto/config`.

Options:
- `KITE_MIRROR=http://your.mirror/debian/ sudo -E ./build.sh` uses a nearer mirror.
- `KITE_NATIVE=1 sudo ./build.sh` builds directly on a Debian 13 host, without a container.
- If a vendor rotates its signing key, the build stops and prints the new
  fingerprint. Check it on the vendor's website, then re-run with
  `KITE_TRUST_NEW_KEYS=1`.

**Building with GitHub Actions:** push the repository to GitHub, then run the
"Build ISO" workflow (Actions tab → Build ISO → Run workflow). The ISO is
attached to the run as an artifact.

**Tests** (any Debian or Ubuntu machine, as root):
```bash
sudo tests/run-all.sh                                         # lint + unit/integration tests
sudo tests/test-packages-chroot.sh trixie http://deb.debian.org/debian   # install test on Debian 13
tests/preview-ui.sh                                           # screenshots of the desktop and launcher
```

**Testing the ISO in a virtual machine** (QEMU + OVMF; uses KVM if available):
```bash
tests/vm/kitevm.py start live --iso out/kiteos-*.iso --disk emmc.qcow2   # boot the live USB
tests/vm/kitevm.py shot live screen.png                                  # screenshot
tests/vm/install-flow.sh live                                            # click through the installer
```
`kitevm.py` also types, clicks, plugs/unplugs a virtual USB disk and runs
commands over the serial console; see its `--help`. To measure RAM and CPU
use on the real Chromebook, run `sudo kite-resource-report`.
