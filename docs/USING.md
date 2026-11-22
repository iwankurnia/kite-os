# Using KiteOS

## The desktop

- **Launcher:** tap the **Search** key (or click the circle at bottom-left). Type to search; Esc closes it.
- **Overview:** the top-row "overview" key (□|| icon) shows all open windows.
- **Shelf:** pinned apps in the middle (Brave, ONLYOFFICE, Files, Terminal,
  Apps & Storage, Settings). Right-click an app to pin or unpin it.
- **Power button** (bottom-right) lets you suspend, hibernate, restart, shut
  down or log out. Lock the screen with **Search + L**.

## Keyboard (ChromeOS habits)

| Keys | Does |
|---|---|
| Tap Search | Open/close the launcher |
| Top row | Back, Refresh, Full screen, Overview, brightness, volume (as printed) |
| Search + top-row key | F1 … F10 |
| Search + Backspace (or Alt + Backspace) | Delete |
| Search + ← / → / ↑ / ↓ | Home / End / Page Up / Page Down |
| Search + L | Lock |
| Ctrl + Alt + T | Terminal |
| Ctrl + Shift + Esc | Task manager |
| Print key (models that have one) | Screenshot |

The map is generated at every boot from the firmware's description of your top
row (`/etc/keyd/kite-chromebook.conf`). Put your own keyd rules in another file
in `/etc/keyd/`.

## Sleep and hibernation

- Closing the lid suspends. After **60 minutes** asleep (or when the battery
  runs low) it hibernates, so a flat battery never loses your work.
- On battery, 30 minutes of inactivity → hibernate. At critical battery → hibernate.
- Change the delay: `sudo KITE_HIBERNATE_DELAY=30min kite-hibernate-setup`
- Status/diagnosis: `sudo kite-hibernate-setup --check`
- Hibernating and resuming takes roughly 10–30 s on eMMC.

## Apps on an external disk

Open **Apps & Storage** (shelf, or the launcher).

1. **Set up an external disk:** choose your USB/SD partition. A Linux file
   system (ext4) is required because apps need permissions and symlinks. If the
   disk is FAT/exFAT/NTFS it will offer to format it, which **erases it**. The disk
   is then mounted at `/mnt/kite-external` and remounted automatically whenever it
   is plugged in.
2. **Install an app:** search, pick, then tick where the app's **program
   files** and its **settings & data** should live. The app is installed on the
   internal disk first, copied to the external disk, verified, and the
   originals are replaced by symlinks.
3. **Move an existing app** (for example Brave or ONLYOFFICE) the same way, and
   **bring it back** when you like.
4. **Keep a folder** (Downloads, Videos, …) on the external disk.

How it behaves:
- Updates keep working: dpkg follows the symlinks and writes to the external disk.
- If the disk is **unplugged**, opening the app shows "connect your external
  disk", and `apt` refuses to upgrade or remove that app until it is back.
  Nothing is half-changed.
- Unplug only when the app is closed.

Command line (same features): `kite-storage --help`, e.g.
```bash
sudo kite-storage setup /dev/sda1 --format
sudo kite-storage install --app-ext --data-ext --user "$USER" gimp
sudo kite-storage move-app brave-browser
sudo kite-storage move-data brave-browser --user "$USER"
kite-storage status
```

## Updating

Apps & Storage → **Update apps and system**, or `sudo kite-storage update`
(it uses the external disk for download space when available).

## Light-weight defaults you may want to change

- `/etc/apt/apt.conf.d/60kite-no-recommends`: Recommends are not installed.
- `/etc/brave/policies/managed/kite.json`: Brave Rewards, Wallet, VPN and Tor are off.
- `/etc/kite/zswap.conf`: compressed swap cache (zstd, up to 25% of RAM).
- `/usr/lib/systemd/system/earlyoom.service.d/kite.conf`: out-of-memory guard.
