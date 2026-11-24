# Using KiteOS

## The desktop

A Windows-style taskbar at the bottom: the **Start** menu, search and your
apps on the left; notifications, volume, tray icons, battery and the clock on
the right. Fluent theme, Papirus-Light icons.

- **Menu:** tap the **Search** key (or click Start). Type to search;
  Esc closes it. The menu also has lock, log out, restart and shut down.
- **Window list:** the top-row "overview" key (□|| icon) lists all open windows.
- **Pinned apps:** Brave, ONLYOFFICE, Files, Terminal, App Centre and Settings.
  Right-click an app to pin or unpin it.
- Lock the screen with **Search + L**.

To put the desktop back to the KiteOS defaults without logging out:

```bash
kite-layout windows
```

This replaces the panel, theme and keyboard shortcuts; your files, apps,
fonts and other settings stay as they are.

**Wallpaper:** KiteOS ships three (Bloom, the default; Aurora; Waves). Open
**Settings → Desktop** and pick one from `/usr/share/backgrounds/kite` (the
desktop itself has no right-click menu).

**Login screen:** three backgrounds too. `kite-login-theme` shows the current
one; `sudo kite-login-theme aurora` (or `frosted`, the default, or `dusk`)
changes it.

## Keyboard (ChromeOS habits)

| Keys | Does |
|---|---|
| Tap Search | Open/close the menu |
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

Open **App Centre** (a pinned app, or from the menu). The sidebar has four pages
and, at the bottom, how full the internal and external disks are.

1. **Storage → Set up external disk:** choose your USB/SD partition. A Linux file
   system (ext4) is required because apps need permissions and symlinks. If the
   disk is FAT/exFAT/NTFS it will offer to format it, which **erases it**. The disk
   is then mounted at `/mnt/kite-external` and remounted automatically whenever it
   is plugged in.
2. **Discover:** search, press **Install**, then tick where the app's **program
   files** and its **settings & data** should live. The app is installed on the
   internal disk first, copied to the external disk, verified, and the
   originals are replaced by symlinks.
3. **Installed:** every app shows **Internal** or **External**. **Move to
   external** moves an existing app (for example Brave or ONLYOFFICE) the same
   way, **Bring back** returns it, and **Remove** uninstalls it (your settings
   are kept).
4. **Storage → Move a folder to the external disk** keeps a folder (Downloads,
   Videos, …) there; moved folders are listed with **Bring back**.

Long tasks run at the bottom of the window with a **Details** log; you can
keep browsing meanwhile.

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
sudo kite-storage remove gimp
kite-storage status
```

## Updating

App Centre → Updates → **Update all**, or `sudo kite-storage update`
(it uses the external disk for download space when available).

## Updating KiteOS

```bash
kite-update --check     # what's new in the latest KiteOS release
kite-update             # install it (asks for your password)
sudo apt update && sudo apt upgrade     # Debian, Brave and ONLYOFFICE updates
```

App Centre → Updates shows the same check, with **Update KiteOS**.
`kite-update` installs the newer KiteOS packages (`kite-system`, `kite-desktop`, …)
attached to the latest release on GitHub, after checking them against the
release's checksum list, together with any new Debian packages they need. Your
own changes to files under `/etc` are kept. Log out and in again afterwards.

## Light-weight defaults you may want to change

- `/etc/apt/apt.conf.d/60kite-no-recommends`: Recommends are not installed.
- `/etc/brave/policies/managed/kite.json`: Brave Rewards, Wallet, VPN and Tor are off.
- `/etc/kite/brave-flags.conf`: Brave's command-line flags (hardware video decoding is on).
  Put your own in `~/.config/brave-flags.conf`; `--enable-features` lists from both files are merged.
- `/etc/kite/zswap.conf`: compressed swap cache (zstd, up to 25% of RAM).
- `/etc/kite/display.conf`: "vivid" colours on the built-in screen (1.2× saturation, done by the
  graphics hardware). Change it for yourself with `kite-vivid 1.3`, `kite-vivid off` or `kite-vivid status`.
- `/usr/lib/systemd/system/earlyoom.service.d/kite.conf`: out-of-memory guard.
