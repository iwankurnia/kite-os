# 2. Building the ISO

You need a 64-bit Linux PC (or VM) with **Docker or Podman**, about **25 GB
free disk** and Internet access. The build runs inside a `debian:trixie`
container, so the host distribution does not matter.

```bash
git clone <this repository> kiteos && cd kiteos
sudo ./build.sh
```

The result is `out/kiteos-YYYYMMDD-amd64.iso` (about 2.5–3 GB) with a
`.sha256` next to it. The first build takes 30–60 minutes; later builds reuse
the package cache.

What `build.sh` does:
1. Installs live-build and friends in the container.
2. `scripts/build-extra-debs.sh`: if Debian 13 does not package `keyd` or
   `xfce4-docklike-plugin`, builds the pinned upstream releases into `.deb`s.
3. `scripts/build-packages.sh`: builds `kite-system`, `kite-chromebook`,
   `kite-desktop` and `kite-storage`.
4. `scripts/fetch-vendor-keys.sh`: downloads the Brave and ONLYOFFICE signing
   keys, checks their key IDs, and adds both repositories.
5. Runs `lb build` with `live/auto/config`.

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
