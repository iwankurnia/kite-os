# 3. Installing

## From the live USB

1. Write the ISO to a USB stick (8 GB or more). This **erases the stick**:
   ```bash
   sudo dd if=out/kiteos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   (Or use balenaEtcher / GNOME Disks.) Replace `/dev/sdX` with the stick, not your disk!
2. Plug it into the Chromebook, power on, press **Esc**, choose the USB drive.
3. The live desktop starts by itself (no password needed; if the screen
   ever asks, the live password is `live`). Check that Wi-Fi,
   sound, the touchpad and the keyboard work.
4. Click **Install KiteOS** (first icon on the shelf):
   - **Partitions:** "Erase disk" (ext4 only, which hibernation relies on). No swap
     partition is needed: the installer creates a swap file of RAM + 1 GB.
   - Encryption is offered but **not tested** with hibernation on this device.
5. Reboot when asked and remove the USB stick.

## After installing: check-list

| Check | How |
|---|---|
| Hibernation ready | `sudo kite-hibernate-setup --check` → "Hibernation looks ready" |
| Hibernate + resume | Save some work, run `systemctl hibernate`; power on → your session returns |
| Lid | Close the lid → sleeps; after 60 min it hibernates by itself |
| Keyboard | Tap Search → launcher; top-row volume/brightness; Search+Backspace = Delete |
| Audio | Speakers and headphone jack (`pavucontrol` to pick outputs) |
| Video decode | Brave: `brave://gpu` → "Video Decode: Hardware accelerated"; play a video, then `brave://media-internals` → `kVideoDecoderName` is `VaapiVideoDecoder`. Compare CPU in `top` with the line in `/etc/kite/brave-flags.conf` commented out |
| Memory | `free -h`, `cat /sys/module/zswap/parameters/enabled` → `Y` |
| Animations | Open the launcher: it slides up; open and close a window: it grows in and shrinks away; `pgrep -a picom` shows picom running (if not, XFCE's compositor took over: check `~/.xsession-errors`) |
| Vivid colours | `kite-vivid status` → "supported on eDP-1"; `kite-vivid off` / `kite-vivid on` shows the difference; still vivid after sleep and after hibernate |

If something fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
