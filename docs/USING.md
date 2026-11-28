# Using KiteOS

## The desktop

A Windows-style taskbar at the bottom: the **Start** menu, search and your
apps on the left; notifications, volume, tray icons, battery and the clock on
the right. Fluent theme, Papirus-Light icons.

- **Start menu:** tap the **Search** key (or click Start). It is an app
  drawer: just type to search apps and settings (Enter opens the first),
  Esc closes it. Your most recent apps are on top, then all apps in the
  order you arrange them: drag an app to move it, drop it on the middle of
  another to make a folder, hold it over a folder to open it. Settings
  panels and system tools start in the Settings and System folders. Your
  name and the power button (lock, sleep, hibernate, restart, shut down,
  sign out) are at the bottom.
- **Switching windows:** Alt+Tab shows your windows as previews; Tab moves
  along, letting go of Alt switches (Esc stays). A quick three-finger swipe
  sideways does the same: a flick moves one window, a slow slide several,
  lifting your fingers switches.
- **Task view:** the button beside Start, Search+W or a three-finger swipe up
  or down shows every window at once over your wallpaper, with a search box:
  click one to go to it, × closes it, a click on the background goes back.
- **Pinned apps:** Brave, ONLYOFFICE, Files, Terminal, App Centre and Settings.
  Right-click an app to pin or unpin it.
- Lock the screen with **Search + L**.
- **Accent colour:** taken from your wallpaper, as on Windows: selections,
  buttons, switches and check boxes in apps, the Start menu's highlight, the
  mark under the active app on the taskbar and today's date in the calendar
  use it, and window backgrounds and title bars carry a hint of it. The lock
  screen follows your wallpaper too; the login screen takes its accent from
  its own background (Settings → Login Screen). Change the wallpaper and the
  colour follows within a couple of seconds. A wallpaper with hardly any
  colour keeps the standard blue; choosing another theme in Settings →
  Appearance turns this off.
- **Animations:** windows fade in and out with a slight zoom; the Start menu
  slides up from the taskbar and its folders zoom; the calendar and menus
  just fade. They are short on purpose, and resizing,
  maximising and tiling stay instant. To turn them off (XFCE's own compositor
  keeps the shadows), put `ANIMATIONS=0` in `~/.config/kite/display.conf`
  and log in again.
- **Window previews:** point at an app on the taskbar to see its windows
  (also when it has only one); click one to switch to it, or use its ×,
  which shows while you point at that window.
- **Music and video** open in **VLC**.
- **Passwords saved by apps** (VS Code, Brave, Git credential helpers) go into
  the GNOME keyring, which your login password unlocks when you log in; no
  extra password prompt. If you change your password with `passwd`, the
  keyring follows.

To put the desktop back to the KiteOS defaults without logging out:

```bash
kite-layout desktop
```

This replaces the panel, theme and keyboard shortcuts; your files, apps,
fonts and other settings stay as they are.

**Wallpaper:** KiteOS ships twelve, all 1920 × 1200 (sharp on 16:10 and 16:9
screens): Bloom (the default), Aurora,
Waves, Dunes, Lagoon, Nightfall, Horizon, Mist, Mirror, Cabin, Meadow and
Coast. Open
**Settings → Desktop** and pick one from `/usr/share/backgrounds/kite` (the
desktop itself has no right-click menu).

**Task Manager** (Ctrl + Shift + Esc, or Task Manager in the menu): one list
of everything running, each app with everything it started on one row, with
CPU, memory, disk and network shaded by load; click a column to sort the whole
list by it; **End task** quits one. (Network per
app counts TCP traffic: QUIC, which Brave uses for YouTube and Google, cannot
be counted per app on Linux; Performance > Wi-Fi shows all of it.)
**Performance** has live graphs for CPU, memory (with a swap graph and zswap's
compressed memory), every drive (a USB stick or SD card gets its own graph
while it is plugged in), Wi-Fi and the battery; **Startup apps** switches login apps on and off.
**Run as administrator** asks for your password and can then end system
processes too.

**Login and lock screen:** both show the same frosted card. Open
**Settings → Login Screen** to pick your picture (one of eight KiteOS ones or
your own photo) and the login screen background (Frosted, Aurora, Dusk or
your own picture). The lock screen shows your desktop wallpaper. From a
terminal: `kite-login-theme` shows the current background;
`sudo kite-login-theme aurora` (or `frosted`, `dusk`, or a picture file)
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
| Ctrl + Shift + Esc | Task Manager |
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

## Battery

Two power modes: **Battery saver** and **Best performance**. By default the
mode follows the charger: Battery saver unplugged, Best performance plugged
in. The **Power mode** slider (Batt / Pow) in the battery pop-up on the
taskbar and in **Settings → Battery** chooses the other one, for example
Best performance for heavy work away from the charger, or Battery saver
while plugged in; the choice lasts until you plug in or unplug the charger,
or restart (no password needed). In Battery saver:

- **Processor:** stays at its base speed (no turbo) and its own power
  management is set to save energy (EPP "power"). **Low-end processors**
  (no performance/efficiency split and 4 threads or fewer, like the
  Chromebook's Celeron N4020) keep their boost instead: at its 1.1 GHz base
  speed the web is too slow, so it may still reach 2.8 GHz for a moment and
  only leans towards saving energy (EPP "balance_power"). All cores stay on:
  idle cores sleep by themselves, and switching one off would only make busy
  moments slower.
- **Laptops with performance and efficiency cores** (Intel 12th generation
  and later): system services run on the efficiency cores; your apps may use
  every core, and the energy setting makes the processor prefer the
  efficiency cores anyway.
- **Graphics:** the Intel graphics chip's top speed is lowered to 60 % of its
  range; video decoding has its own hardware and still plays smoothly.
- **Drivers and devices:** PCI Express links use their deepest power states,
  every device's driver may power it down when idle (Wi-Fi, storage
  controllers, audio, USB controllers), idle USB devices (webcam, card
  reader, sticks) are suspended, keyboard, touchpad, mouse, audio devices and
  the Bluetooth adapter excepted, so nothing you touch or hear drops out.
- **Wi-Fi** sleeps between the access point's beacons. **Bluetooth** is
  switched off when you unplug if nothing is connected (switch it on in the
  tray when you need it).
- **Brave's energy saver** throttles background tabs and frame rates.
  Window animations stay on.
- Changed files are written to storage every 60 s instead of 15 s.

Change the details in `/etc/tlp.d/60-kite.conf` (TLP's settings; `sudo
tlp-stat` shows what is in force; on low-end processors kite-power adds
`/etc/tlp.d/61-kite-boost.conf`). `kite-power` shows KiteOS's part.
`ANIMATIONS_ON_BATTERY=0` in `~/.config/kite/display.conf` turns window
animations off while saving power (shadows stay).

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
5. **A downloaded `.deb` file:** double-click it in Files (or open it from
   Brave's downloads). App Centre says what it is, whether it is a new app,
   an upgrade, a reinstall or an older version, what else it brings along,
   and that it does not come from KiteOS's or Debian's app sources; **Install**
   asks for your password. A package made for another kind of computer (such
   as arm64) is refused before anything changes.

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
sudo apt update && sudo apt upgrade     # Debian, Brave, ONLYOFFICE and VS Code updates
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
- The desktop is kept in memory when memory runs low, so the pointer and
  switching between windows stay quick while Brave fills the rest: the X
  server (`lightdm.service.d/kite-ui.conf`), the window manager and picom
  (`kite-ui-<uid>.scope`, made at login by `/usr/lib/kite/kite-ui-protect`)
  are protected from reclaim and never swapped out; the kernel also keeps
  whatever was used in the last second in memory
  (`/usr/lib/tmpfiles.d/kite-memory.conf`). The panel is not protected: the
  apps it starts would inherit the protection.
