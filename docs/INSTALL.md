# 3. Installing

## Option A: live USB (recommended)

1. Write the ISO to a USB stick (8 GB or more). This **erases the stick**:
   ```bash
   sudo dd if=out/kiteos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   (Or use balenaEtcher / GNOME Disks.) Replace `/dev/sdX` with the stick, not your disk!
2. Plug it into the Chromebook, power on, press **Esc**, choose the USB drive.
3. The live desktop starts (user `kite`, password `live`). Check that Wi-Fi,
   sound, the touchpad and the keyboard work.
4. Click **Install KiteOS** (first icon on the shelf):
   - **Partitions:** "Erase disk" (ext4 only, which hibernation relies on). No swap
     partition is needed: the installer creates a swap file of RAM + 1 GB.
   - Encryption is offered but **not tested** with hibernation on this device.
5. Reboot when asked and remove the USB stick.

## Option B: on top of a minimal Debian 13 <a id="option-b"></a>

1. Install Debian 13 from the official *netinst* image. Choose **ext4**, **no
   swap partition**, and from the software list tick **only** "standard system
   utilities" (no desktop).
2. Log in, install git, get this repository, and run:
   ```bash
   sudo apt install git
   git clone <this repository> kiteos && cd kiteos
   sudo scripts/install-on-debian.sh
   sudo reboot
   ```

## After installing: check-list

| Check | How |
|---|---|
| Hibernation ready | `sudo kite-hibernate-setup --check` → "Hibernation looks ready" |
| Hibernate + resume | Save some work, run `systemctl hibernate`; power on → your session returns |
| Lid | Close the lid → sleeps; after 60 min it hibernates by itself |
| Keyboard | Tap Search → launcher; top-row volume/brightness; Search+Backspace = Delete |
| Audio | Speakers and headphone jack (`pavucontrol` to pick outputs) |
| Video decode | Brave: open `brave://gpu`; "Video Decode" should say hardware accelerated |
| Memory | `free -h`, `cat /sys/module/zswap/parameters/enabled` → `Y` |

If something fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
