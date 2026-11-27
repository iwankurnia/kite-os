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
4. Click **Install KiteOS** (first pinned app on the taskbar):
   - **Partitions:** "Erase disk" (ext4 only, which hibernation relies on). No swap
     partition is needed: the installer creates a swap file of RAM (room to hibernate)
     + max(10 GB − RAM, 2 GB) for apps: 10 GB on a 4 GB laptop, at most 40 % of the disk.
   - Encryption is offered but **not tested** with hibernation on this device.

   The pages run Welcome, Location, Keyboard, Partitions, Users, Summary,
   Install, Finish.
5. Reboot when asked and remove the USB stick.

## After installing: check-list

| Check | How |
|---|---|
| Hibernation ready | `sudo kite-hibernate-setup --check` → "Hibernation looks ready" |
| Hibernate + resume | Save some work, run `systemctl hibernate`; power on → your session returns |
| Lid | Close the lid → sleeps; after 60 min it hibernates by itself |
| Keyboard | Tap Search → menu; top-row volume/brightness; Search+Backspace = Delete |
| Audio | Speakers and headphone jack (`pavucontrol` to pick outputs) |
| Video decode | Brave: `brave://gpu` → "Video Decode: Hardware accelerated"; play a video, then `brave://media-internals` → `kVideoDecoderName` is `VaapiVideoDecoder`. Compare CPU in `top` with the line in `/etc/kite/brave-flags.conf` commented out |
| Memory | `free -h`, `cat /sys/module/zswap/parameters/enabled` → `Y` |
| Desktop | Taskbar at the bottom with Start, search and pinned apps; the menu opens from the Search key; `kite-layout desktop` puts the desktop back without logging out |
| Vivid colours | `kite-vivid status` → "supported on eDP-1"; `kite-vivid off` / `kite-vivid on` shows the difference; still vivid after sleep and after hibernate |
| Battery saving | Unplug: `kite-power` → "On battery: saving power"; `kite-power` → "CPU boost: kept on battery (low-end CPU, 2 logical CPUs)"; `sudo tlp-stat -p` → EPP `balance_power`, `no_turbo = 0`, `hwp_dynamic_boost = 1`, and `grep MHz /proc/cpuinfo` above 1100 while a page loads; `sudo tlp-stat -e` → runtime PM `auto`; `cat /sys/class/drm/card0/gt_max_freq_mhz` lower than plugged in; window animations keep going. Plug in: all back. Settings → Battery → Full speed on battery: `kite-power` says so, until switched off. `sudo powertop` (if installed) or the battery's `power_now` for the discharge rate, saving vs full speed |
| Desktop kept in memory | `systemctl show lightdm -p MemoryLow -p MemorySwapMax` → 268435456 / 0; `systemctl status kite-ui-$(id -u).scope` lists xfwm4 and picom (also after unplugging with `ANIMATIONS_ON_BATTERY=0` and plugging in again); `cat /sys/kernel/mm/lru_gen/enabled /sys/kernel/mm/lru_gen/min_ttl_ms` → `0x0007`, `1000`. Open Brave tabs until swap is in use (`free -m`): the pointer and Alt+Tab stay smooth; `journalctl -k | grep -i oom` shows what was ended, if anything |

If something fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
