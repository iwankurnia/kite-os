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
| Last commit | see `git log` |
| Releases | v1.0 cloud-built (VM-tested); v1.1 Brave VA-API; v1.2 has a vivid white-screen bug (use 1.2.1+); v1.2.2 skipped; **v1.2.3 boots and works on the HP Chromebook 11 G8 EE** from USB (animations, Bluetooth audio, drive icons, vivid colours); v1.2.4 adds picom fades, stronger shadows and touchpad tap-to-click/natural scrolling (not yet on the device); **v1.3.0** (Latest) replaces the shelf and rofi with the windows and mac layouts, and its `xfwm4.xml` (xfwm4's own compositor, no picom) replaces 1.2.4's fades and shadows; **v1.3.1** (2026-11-24) fixes everything the 1.3.0 VM test and code review found (installer Desktop choice, live switch without restarting xfwm4, `/boot` move guard, light login screen, Chromebook/standard window keys); **v1.3.2** (2026-11-24, newest) fixes what the 1.3.1 VM test found (US keyboard kept, live switch really changes the window theme, `kite-layout keys` applies at once, panel plugins back inside the panel for RAM, App Centre chooser and blank USB sticks, plain menu names, windows moved out from under the mac menu bar). v1.3.2 was released without a re-test; it was installed on the device on 2026-11-24. **v1.4.0** (2026-11-24, Latest, newest) is the `laptop-fixes` branch below (windows layout only, Papirus icons, lightdm-gtk-greeter login and lock screen, Task Manager, VS Code and git, keyring); VM test 34/34 passed, not yet on the device. Every release from 1.2.3 carries the kite-*.deb files for `kite-update` |
| Base | Debian 13.8, kernel 6.12.117, XFCE 4.20, Calamares 3.3.14, Brave 1.100.58, ONLYOFFICE 10.0.0 |
| Tests | `sudo tests/run-all.sh`: 38 scripts lint-clean, 35 system and 31 storage checks pass |
| Verified in a VM | 1.2 shelf build: everything in [TEST-REPORT.md](TEST-REPORT.md). 1.3.0 and 1.3.1: full VM runs by a cloud Claude session (live, every installer page, Mac-style install, installed boot, layout switches, keys, App Centre, kite-storage safety) and by the GitHub "VM test" workflow (below). 1.3.2: not VM-tested. 1.4.0: GitHub VM test passed, 34 of 34 checks (run 45430760357, 2026-11-24); screenshots of the live desktop, installer Summary, login screen and installed desktop looked right |
| **Not verified** | Anything needing the real Chromebook: keyboard map (Search key, top row), SOF audio, Wi-Fi, brightness keys, lid suspend, real hibernate timing, and the ONLYOFFICE editor (crashes under QEMU emulation only; works natively) |

## Changes carried over from the installed laptop (2026-11-24)

KiteOS v1.3.2 was installed on the HP Chromebook 11 G8 EE that morning. The fixes
made on the device were brought into the repository (kite-desktop 1.3.0,
kite-system 1.2.2, branch `laptop-fixes`), released as **v1.4.0** the same day:

- **The mac layout is gone** (owner's call, 2026-11-24: focus on the windows
  layout). Removed: `layouts/mac`, the `KiteOS-Tray-Mac` icons, the
  installer's Desktop page (packagechooser + contextualprocess), `kite-layout
  --system` and `/etc/kite/layout`, the move-windows-below-the-menu-bar code
  (and the `wmctrl` dependency), Qogir and WhiteSur in the themes hook, the
  installer layout pictures (`artwork/layout-*.svg`). `kite-layout` stays: it
  sets up new accounts, `kite-layout keys`, and `kite-layout windows` puts the
  desktop back. An account still on mac gets windows at its next login (its
  state file says `mac`, which no longer counts as set up). The VM test has no
  `layout` input any more.
- Panel plugins in their own processes again (`force-all-internal` false):
  fixes the panel crash above. Costs RAM (six wrappers, ~200 MB).
- `libxcb-shape0` in kite-desktop's Depends and the ISO list, so ONLYOFFICE starts.
- Hibernation swap: RAM + min(RAM/2, 4 GiB). Existing installs keep their
  swap file until `sudo kite-hibernate-setup` is run again (it grows it; swap
  in use must fit in RAM, or add a temporary swap file first).
- Papirus-Light icons, tray included. The `KiteOS-Tray-Windows` and `KiteOS`
  icon themes (and `artwork/status-icons.py`) are gone too; kite-desktop's
  postinst clears the icon caches the ISO build left in their folders. The
  `KiteOS` pack's drive-icon links are not needed: Papirus resolves those names
  through GTK's fallbacks (`drive-harddisk-solidstate-sdio` →
  `drive-harddisk-solidstate`). Start and Search use
  `kite-start-symbolic` and `kite-search-symbolic` from hicolor (the tray
  pack's glyphs, which fill the button; Papirus' own look small).
- Bluetooth tray applet starts at login again (the skel file hiding it is gone;
  ~106 MB of RAM measured on the device).
- Taskbar 36 px (was 48), tray in one row with `square-icons` off and narrow
  tray buttons in `gtk.css`.
- Borders instead of pop-up shadows: 1 px line along the top of the taskbar
  and around menus and pop-overs, `show_popup_shadow` false. No border on the
  Whisker menu (owner's call). xfce4-panel has no per-panel CSS name, so a
  rule on `.xfce4-panel.background` hits every panel.
- Clock calendar pop-up restyled in `gtk.css`: roomy rows,
  quiet day names and arrows, no week numbers (`show-week-numbers` false in
  `xfce4-panel.xml`), today as a blue number with a short bar under it.
  GtkCalendar (GTK 3.24 `gtkcalendar.c`) draws its parts on child CSS nodes,
  so the rules are `window.background > calendar > calendar.header` etc.
  (`window > calendar.header` never matches); cell padding goes on the
  `.day-number` / `.day-name` classes. It draws each number at the TOP of its
  cell, so the room is added below the numbers, and a filled "today" tile
  would show the number off-centre: hence the bar (a `linear-gradient`
  background image). Font size and weight of the parts are ignored, and the
  window cannot have round corners (no alpha channel). Its shadow stays: it
  follows `show_frame_shadow`.
- `border-spacing` is not a GTK 3 CSS property (the tray rule had it; removed).
- **Login and lock screen, one look.** slick-greeter is replaced by
  `lightdm-gtk-greeter` (0.6 MB vs 1.8 MB): xfce4-screensaver's lock dialog is
  built from the same widget names (`login_box`, `content_frame`,
  `prompt_entry`, `login_button`, `buttonbox_frame`, `panel_window`, under a
  `.lightdm-gtk-greeter` node), so `/usr/share/kite/login/kite-login.css`
  styles both: the greeter through the `KiteOS-Login` GTK theme (Fluent-Light
  + that file), the lock dialog through an `@import` at the end of the
  desktop's `gtk.css` (a trailing `@import` works in GTK 3). Frosted card
  with a border (a `box-shadow` gets clipped at the card's holder and leaves
  square corners). Greeter config: `/usr/share/lightdm/lightdm-gtk-greeter.conf.d/50-kite.conf`
  (sorts after Debian's `01_debian.conf`; read order is `/usr/share`, then
  `/etc/xdg`, then `/etc/lightdm/...conf.d`, last wins). `lightdm --test-mode`
  previews it in Xephyr, but LightDM clears the greeter's environment: a
  `greeter-wrapper` script can set `XDG_DATA_DIRS`/`XDG_CONFIG_DIRS`.
- Lock screen picture: the lock dialog draws the desktop wallpaper of its
  monitor (`/backdrop/screen0/monitor<name>/workspace0/last-image`), which CSS
  cannot replace (GtkOverlay draws no CSS background). So the locked screen
  shows the wallpaper too: screensaver theme `screensavers-kite-wallpaper`
  (`/usr/lib/kite/desktop/kite-lock-picture`, the stock slideshow on a folder
  holding only the wallpaper; ~0.6 % CPU, ~80 MB while locked), mode 2 in
  the skel `xfce4-screensaver.xml`. The dialog is a GtkPlug: to preview it,
  embed it in a GtkSocket (it prints `WINDOW ID=`).
- Settings > Login Screen (`kite-login-settings`, Python GTK): your picture
  (eight KiteOS avatars in `/usr/share/kite/avatars`, or your own; cropped to
  256 px, `~/.face` + AccountsService `SetIconFile`, no password: the greeter
  cannot read a 700 home) and the login background (`pkexec
  kite-login-theme`, polkit action `org.kiteos.login-theme`). kite-login-theme
  writes `/etc/lightdm/lightdm-gtk-greeter.conf.d/90-kite-login-background.conf`;
  your own picture is copied to `/var/lib/kite/` (checked by its first bytes).
  Existing installs keep slick-greeter installed (it was in the ISO list);
  `sudo apt purge slick-greeter` after updating.
- **Calamares writes the greeter into `/etc/lightdm/lightdm.conf`**
  (`greeter-session=`, the first greeter it finds), and LightDM reads that file
  *after* `lightdm.conf.d`, so it beats `50-kite.conf`. Removing slick-greeter
  on the device left a blank login screen (the owner reinstalled it from a
  console). Fixed: `preferred_greeters` in `displaymanager.conf`, and
  kite-desktop's postinst rewrites that one line on installed systems. Check
  with `sudo lightdm --show-config | grep greeter-session` before removing a
  greeter.
- **Keyring, first login:** the login keyring that PAM *creates* (first login
  after gnome-keyring is installed) was not published on D-Bus in that
  session (`/org/freedesktop/secrets/collection/login` listed but "does not
  exist"), so VS Code said the keyring was unavailable. From the next login it
  is loaded from disk, unlocked by PAM and published. On a new install that
  first login is the first session; not worked around yet.
- Nine new wallpapers next to Bloom, Aurora and Waves: Dunes, Lagoon,
  Nightfall, Horizon, and (subjects and palettes from Unsplash's wallpaper
  section, as reference only; the art is original) Mist, Mirror, Cabin, Meadow,
  Coast. All wallpapers and login backgrounds are 1920 x 1200 now (the owner
  has a 1920 x 1200 monitor; a 1920 x 1080 picture would be enlarged 11 %
  there, while 16:9 screens just trim a band of a 16:10 one):
  `artwork/render-wallpapers.py` renders the 1920 x 1080 SVGs 1200 high and
  crops the sides around each subject (`FOCUS`). 53-143 KB each, 1.1 MB in
  all. It uses GdkPixbuf's SVG loader, so it runs without rsvg-convert.
- **Task Manager** (`kite-tasks`, Python GTK, replaces xfce4-taskmanager and
  its Ctrl+Shift+Esc): Processes grouped like Windows (walk up the parents to
  a launcher in `DESKTOP_SHELL`: panel `wrapper-2.0`, `xfce4-session`,
  `xfsettingsd`...; apps launched from the taskbar are children of the panel
  plugin wrapper), a group is an app when a process has a window
  (`_NET_CLIENT_LIST` + `_NET_WM_PID` via ctypes libX11), named and iconed
  from its .desktop file (exact desktop id wins: thunar.desktop over
  thunar-bulk-rename; launcher suffixes like `.distrib` dropped). Memory =
  `RssAnon` from `/proc/PID/status` (cheap, readable for everyone; PSS from
  `smaps_rollup` took 0.2 s a refresh on the N4020). Performance (CPU, memory
  + swap + zswap from `/proc/meminfo`, eMMC from diskstats, Wi-Fi, battery),
  Startup apps (Hidden= in ~/.config/autostart; KiteOS essentials locked).
  Disk per process: `/proc/PID/io` read_bytes + write_bytes (others' only as
  root: "—"). Network per process: TCP byte counters from `ss -tinpH state
  established` (55-130 ms, run asynchronously, only while Processes is
  shown); UDP/QUIC has no counters on Linux without packet capture (nethogs
  needs root and libpcap), so Brave's YouTube/Google traffic is missing there,
  as the column's tooltip says. Labels in Performance have fixed widths: a
  changing width resized the tile list and moved the graph card each second.
  Run as administrator: pkexec with `exec.allow_gui` (polkit
  `org.kiteos.tasks`), `PKEXEC_UID` says whose apps are "yours". The data code
  runs without GTK (`kite-tasks --dump`; tests on a fake /proc).
- **VS Code and git on the ISO** (owner's request). VS Code from
  `packages.microsoft.com/repos/code`, key `microsoft.asc`
  (BC528686B50D79E339D3721CEB3E94ADBE1229CF, pinned as EB3E94ADBE1229CF in
  `fetch-vendor-keys.sh`; fingerprint checked on learn.microsoft.com/linux/packages
  and the repo's InRelease verified with it, 2026-11-24). Microsoft's
  `microsoft-2025.asc` is for repositories made after April 2025; watch for the
  code repository moving to it. The archive is named `vscode` on purpose:
  VS Code's postinst then sees the repository listed and adds no second
  copy (it only writes `/usr/share/keyrings/microsoft.gpg`; no `set -e`, so a
  missing gpg cannot fail the build). VS Code adds roughly 100 MB to the ISO
  and 400 MB installed; it is a Start menu favourite (kite-layout). Existing
  installs: `sudo apt install code git` (the laptop has both).
- Keyring: `gnome-keyring` + `libpam-gnome-keyring` in kite-desktop's Depends
  (10 small packages, nothing always-on: the daemon is socket/D-Bus
  activated). VS Code found no Secret Service at all. Debian's LightDM PAM file
  already has `-auth`/`-session optional pam_gnome_keyring.so auto_start`
  (the `-` skips a missing module), so the login password creates the "login"
  keyring at the first login and unlocks it at every login, no prompt; the
  package's pam-config adds it to `common-password` so `passwd` keeps them in
  step. The live session logs in without a password, so there an app that
  wants the keyring will ask.

Layout files reach an account only at first login or on `kite-layout windows`, so
`kite-update` alone does not change an existing desktop.

## Changes on 2026-11-25 (Windows laptop, not released yet)

kite-desktop 1.4.0, kite-system 1.2.3, kite-storage 1.1.3:

- **Animations are back: xfwm4 + picom** (owner's call). The owner first asked
  for Compiz; a full port was built and tried in a Debian 13 container
  (gtk-window-decorator drawing Fluent-Light's Metacity theme, keys mapped
  from xfwm4's, xfwm4 fallback), then he chose xfwm4 + picom instead. None of
  the Compiz work is in the repository. Worth knowing if it comes up again:
  Compiz used ~125 MB (with its decorator) against xfwm4's 66 MB under
  software OpenGL, Fluent's Metacity theme centres titles (`x=` of each
  `<title>`, both the `version="< 3.1"` and `">= 3.1"` ones), and the
  decorator needs `librsvg2-common` for the theme's SVG buttons.
- picom 12.5 setup is the 1.2.x one brought back (`start-compositor` from
  `/etc/X11/Xsession.d/46kite-compositor` and XDG autostart; xfwm4's
  compositor off while picom runs, back on when picom is missing, exits or
  `ANIMATIONS=0` in `/etc/kite/display.conf` or `~/.config/kite/display.conf`),
  with a new `/etc/kite/picom.conf` for the windows layout. The owner asked
  that the animations "not look weird": windows fade in/out with a 96 % zoom
  in 0.15/0.12 s (also minimise/restore); panel pop-ups (`Wrapper-2.0`: Start
  menu, calendar) and notifications only fade; menus and tooltips fade in
  0.08 s with no shadow; the taskbar and desktop never move and have no
  shadow; **no `geometry` animation** (picom stretches the window's old
  picture while it resizes, maximises or tiles, which looked wrong);
  full-screen windows are unredirected. Shadows follow xfwm4.xml's rules
  (none under the taskbar or menus). Tests in `test-system.sh` hold those
  rules (every duration < 0.16 s, scale ≥ 0.96, no geometry trigger).
- `kite-layout windows` / `keys` with picom running leave xfwm4's compositor
  off (the layout's xfwm4.xml says `use_compositing` true for the fallback).
- **Saving power on battery** (after 6cf3296; owner's choices: TLP + KiteOS
  settings, strong saving with a way out, services on E-cores, all cores
  kept on). kite-system depends on Debian's **tlp 1.8.0**;
  `/etc/tlp.d/60-kite.conf` on battery: EPP `power`, turbo and HWP dynamic
  boost off, platform profile low-power, PCIe ASPM powersupersave, runtime PM
  auto, USB autosuspend (TLP itself skips usbhid input devices, audio,
  printers; KiteOS also skips btusb so Bluetooth audio does not drop),
  Wi-Fi power saving, Bluetooth off on unplug when unused, NMI watchdog off,
  60 s write-back. `/usr/sbin/kite-power` (Python, fake-/sys tests) does the
  rest on each power_supply change (`90-kite-power.rules` → oneshot
  `kite-power.service`, also at boot after tlp.service; it needs
  `After=multi-user.target` like tlp.service itself, or multi-user.target
  orders itself after it and systemd drops the boot start as an ordering
  cycle: v1.5.0 shipped with that, fixed in kite-system 1.2.4, and the VM
  test now checks `/run/kite/power` after boot): Intel hybrid CPUs
  (`/sys/devices/cpu_atom/cpus`) get `system.slice AllowedCPUs=<E-cores>`
  (runtime) while saving; i915 `gt_max/boost_freq_mhz` at RPn + 60 % of the
  range (UHD 600: 470 of 650 MHz); `/run/kite/power` = ac / saving / full.
  **Low-end CPUs keep their boost on battery** (owner, 2026-11-25: 1.1 GHz
  is not enough for the web): no P/E split and ≤ 4 logical CPUs
  (`/sys/devices/system/cpu/present`; the N4020 has 2) → kite-power writes
  `/etc/tlp.d/61-kite-boost.conf` (BOOST_ON_BAT=1, HWP_DYN_BOOST_ON_BAT=1,
  EPP balance_power) and re-runs `tlp start` once (first boot on that CPU;
  `tlp ac` if at full speed); other CPUs get it removed; postrm removes it.
  `kite-power full` (TLP's manual AC mode, `tlp ac`, + a flag in /run) and
  `auto` (`tlp start`) are behind Settings → Battery (`kite-power-settings`,
  polkit `org.kiteos.power`, allow_active yes). `start-compositor` is now a
  loop: picom on battery too by default (owner, 2026-11-25:
  `ANIMATIONS_ON_BATTERY=1` in display.conf); with `ANIMATIONS_ON_BATTERY=0`
  xfwm4's compositor while saving (checked every 5 s), picom again plugged
  in or at full speed; one
  copy per session (flock), and after each picom start it re-sets
  `_GTK_FRAME_EXTENTS` on open windows: picom 12.5 checks rules on windows
  open at its start before reading their properties, and neither its
  SIGUSR1 reset nor waiting fixes Brave's pale box; re-setting the property
  does (measured). Brave policy `BatterySaverModeAvailability: 2`.
  kite-desktop depends on x11-utils (xprop). **Only the device can confirm**
  that the N4020's intel_pstate offers EPP (HWP), the real discharge rates
  and that nothing (Wi-Fi, Bluetooth audio, the touchpad) misbehaves with
  the deeper power states; the checks are in INSTALL.md's list. Tried in
  the container: kite-power with no battery, the compositor switch both ways
  with Brave open (no pale box), Settings → Battery; pkexec is not there.
- **Desktop kept in memory** (owner, 2026-11-25: the pointer and moving
  between apps must not lag when memory is low). The X server lives in
  lightdm.service (lightdm spawns it; the session has its own scope):
  drop-in `MemoryLow=256M`, `MemorySwapMax=0`, and `system.slice` gets
  `MemoryLow=256M` because protection is handed down the tree. xfwm4 and
  picom live in the session scope with every app, and the user manager may
  not move processes out of a logind scope (common ancestor
  user-<uid>.slice is root's), so `/usr/lib/kite/kite-ui-protect` (root via
  pkexec, polkit `org.kiteos.ui-protect`, allow_active yes, any/inactive no)
  moves the caller's own `/usr/bin/xfwm4` and `/usr/bin/picom` (exe checked,
  nothing from argv) into `kite-ui-<uid>.scope` (StartTransientUnit in
  user-<uid>.slice, MemoryLow 128 MiB, MemorySwapMax 0; AttachProcesses
  when it exists or the login race is lost); `user.slice.d` and
  `user-.slice.d` pass the 128 MiB down. `start-compositor` runs
  `protect-ui` (waits ≤ 30 s for xfwm4, then pkexec) at login and after each
  picom start. Not protected on purpose: xfce4-panel, xfdesktop,
  xfsettingsd, xfce4-session, as apps started from them inherit the cgroup.
  An xfwm4 respawned by xfce4-session is unprotected until the next picom
  start or login. kite-system adds MGLRU with `min_ttl_ms=1000`
  (tmpfiles, ChromeOS's thrashing guard: shared library pages charged to
  other cgroups stay in memory while used). Tested with fake /proc, busctl
  and systemctl only; **only the device can confirm** the cgroup values and
  the feel under pressure (INSTALL.md list).
- **Task Manager, compact and flatter** (after 77102ba, owner's requests):
  opens at 720 x 500 (was 980 x 640, really 980 x 691 because of the graph
  heights), 16 px icons and tight rows, smaller paddings, graphs and figures
  on every tab. No Apps / Background / System sections: one list of groups,
  every column sorts all of it. Performance: a tile and graph for every drive
  (`disks()`: /sys/block without loop, zram, ram, dm, optical, eMMC boot
  areas or empty readers; system disk first, "USB drive (sda)", "SD card
  (mmcblk1)"), re-checked every 2 s so a USB stick appears and disappears
  while the window is open (tested on a fake /sys); used/free over each
  drive's mounted partitions. kite-desktop now depends on python3-gi-cairo:
  the graphs need it (until now it came in through another package).
- **Double-clicking a .deb installs it through App Centre** (owner's request):
  `kite-install-package.desktop` (kite-storage, NoDisplay, the default for
  `application/vnd.debian.binary-package` and `application/x-deb` in
  `/etc/xdg/mimeapps.list`) runs `kite-app-centre --install-file FILE`. App
  Centre (now `HANDLES_OPEN`, so a file reaches an already-open window) reads
  the file with `dpkg-deb -f`, refuses another architecture, compares with
  the installed version (install / upgrade / reinstall / downgrade), runs a
  non-root `apt-get -s install FILE` for extra packages, removals (a kite-*
  removal is refused) and unmet dependencies, then asks with a trust warning;
  the external-disk choice as for other apps. `kite-storage install` takes
  `.deb` files (copied to a 755 temp folder for apt's sandbox user, removed
  afterwards; moves use the package name) and `--reinstall` /
  `--allow-downgrades`. Tried in the container: install, upgrade 1.0 → 1.1,
  reinstall, arm64 refused, all in one App Centre window.
- **Debian's own picom autostart is switched off**: picom's
  `/etc/xdg/autostart/picom.desktop` would start a second, plain picom at
  login (racing start-compositor; it lost in tests but could win). KiteOS
  hides it with `/usr/share/kite/xdg-config/autostart/picom.desktop`
  (Hidden=true), found first because `45kite-user-init` puts that folder
  before /etc/xdg in XDG_CONFIG_DIRS (startxfce4 keeps a pre-set value);
  Task Manager's Startup list leaves such entries out. A conffile in /etc is
  not edited or diverted.
- **VLC** on the ISO (Debian, no Recommends; VA-API through
  intel-media-va-driver) and the default for audio and video files
  (`/etc/xdg/mimeapps.list`). It is in the ISO list only, not a kite-desktop
  Depends (an app, like Brave): existing installs need `sudo apt install vlc`.
- picom is a kite-desktop Depends, so `kite-update` brings it; it starts at
  the next login with no `kite-layout` run needed.
- **picom backend xrender, not glx.** With glx, a taskbar started while
  picom ran (`kite-layout windows`/`keys`, a panel crash) stayed invisible
  until picom restarted, every time; not a config issue (a bare `backend =
  "glx"` did it), not damage tracking (`use-damage = false` did not help),
  not `xrender-sync-fence` or `glx-no-rebind-pixmap`; egl is missing
  `EGL_KHR_image_pixmap` under Mesa's software GL and is experimental. xrender
  showed the taskbar every time and draws the same animations; on the device
  X's glamor runs it on the GPU (measure CPU there).
- **Shadows matched to xfwm4's by measurement**: under xrender picom's
  shadows came out ~1/3 as strong as glx's; radius 22, opacity 0.70, a 3 px
  drop gives 48/37/23/11/3 levels darker at 3/6/10/15/20 px below a window
  against xfwm4's 50/39/26/12/2.
- **Taskbar window pop-up, Windows 11 style** (owner's design steps): a light
  grey card (`#ececec`) so the often white previews stand out, rounded 8 px
  and with a shadow by a picom rule (GTK cannot: no alpha channel), plain
  tiles grey on hover, the close button only on the hovered window, titles
  never bold or italic ("KiteOS Plain", `/etc/fonts/conf.d/45-kite-plain.conf`:
  Inter at regular weight whatever is asked; docklike writes `<b>`/`<i>`
  markup that CSS cannot undo), also for apps with one window
  (`noWindowsListIfSingle=false`). Previews a fixed 120 px high, width from
  the window's shape between 160 and 264 px, each tile as wide as its
  preview: that needed a patch to docklike (below). GTK gives the pop-up
  window no `popup` class, so `window.popup …` rules never matched; the patch
  gives it `.docklike-popup`.
- **kite-docklike**: Debian's xfce4-docklike-plugin 0.4.3-1 with
  `patches/xfce4-docklike-plugin/01-kite-preview-height.patch` (new setting
  `previewHeight`; the pop-up's style class), built from Debian's source by
  `scripts/build-patched.sh` (in `build.sh`, so in the ISO build), as the
  binary package `kite-docklike` 0.4.3-1+kite1 that Provides, Conflicts with
  and Replaces `xfce4-docklike-plugin` (owner: renamed so an update from
  Debian or upstream never replaces it). It is in the release's kite-*.deb
  files; `kite-update` offers it where Debian's plugin is installed
  (`TAKES_PLACE_OF`). kite-desktop depends on it. The source version is
  pinned: when Debian updates the plugin, the build fails until the patch is
  checked and the version and revision raised. An explicit `apt install
  xfce4-docklike-plugin` would swap Debian's back; `apt upgrade` does not.
- **Brave's "pale box" under picom (solved).** Brave draws its own frame and
  soft shadow in a transparent 16/16/10/32 px margin (`_GTK_FRAME_EXTENTS`).
  picom added its own shadow round the whole window, margin included, so
  Brave's soft margin sat inside a dark rim with a hard edge and read as a
  pale box. Brave's pixels are identical under both compositors (read with
  their alpha), and inside the margin picom's output equals xfwm4's; only
  outside the window picom was darker (193/214 against 235). The rule
  `{ match = "_GTK_FRAME_EXTENTS@"; shadow = false; }` fixes it: with picom
  started first and Brave opened later (the order at login), the pixels
  outside Brave equal the background (235/234), also after minimise and
  restore. Gotcha that hid it for a while: picom 12.5 checks its rules on
  windows already open at its start before it has read their properties
  (trace: `Property _GTK_FRAME_EXTENTS not found`, `result = 0`, then
  `result = 1` once the window changed), so testing by restarting picom with
  Brave open shows the box again until Brave is minimised and restored.
  Measure from the screen, not by eye: the box was a shadow, not the margin.
  ONLYOFFICE and VS Code draw their own frames with no margin and look right.
- Tried in a Docker container (Debian 13, Xvfb + noVNC, software OpenGL),
  frame by frame at x6 slow motion: window open/close/minimise/restore,
  dialogs (fade + 96 % zoom), maximise/tile (instant), Start menu, calendar,
  notifications, tooltips, menus (fade only), Alt+Tab (xfwm4's own blue
  outline box also under its own compositor), the taskbar pop-up, Thunar,
  Ristretto, Settings, App Centre, Task Manager, Login Screen, App Finder,
  Mousepad, Terminal (all with xfwm4 frames), Brave, ONLYOFFICE, VS Code,
  VLC (full screen covers the taskbar, no shadow). picom starts from the
  Xsession hook, xfwm4's compositor goes off, a picom crash and
  `ANIMATIONS=0` give xfwm4's back, the live layout switch keeps it off.
  `tests/run-all.sh` there: shellcheck clean, system 213/213, storage 41/41.
  picom used ~90 MB PSS under software OpenGL; on the device it should be
  far less: measure with `sudo kite-resource-report`. VLC's default video
  output needs real GL (in the container only its X11 output worked);
  ONLYOFFICE must be started through its launcher (it sets its own Qt
  library path; VLC brings the system Qt 5). Not built into an ISO or
  VM-tested yet.

## v1.5.2 (2026-11-25, from the device itself)

The session now runs on the Chromebook (installed on the eMMC, Claude Code
in `~/Project/kite-os`). Its first look at the checklist found that the
installer had **never applied our mount options**: `/` was `relatime` and the
ESP was world-readable. `fstab.conf` used the Calamares 3.2 `mountOptions`
key, which 3.3 ignores; 3.3 reads them from `mount.conf`. v1.5.2 ships a
`mount.conf` (`noatime` for ext4, `umask=0077` for the ESP; its `extraMounts`
are upstream 3.3.14's, because the file replaces Debian's whole) and a
3.3-format `fstab.conf`. The VM test checks both on the installed system.
Systems installed before 1.5.2 keep their `/etc/fstab`; this device's was
fixed by hand. No kite package changed, so `kite-update` has nothing new.

**Taskbar pop-up peek (kite-docklike 0.4.3-1+kite2, tried on the device
2026-11-25).** `patches/xfce4-docklike-plugin/02-kite-hover-peek.patch`:
hovering a preview 300 ms brings its window forward, leaving without a click
puts the previous window back (and re-minimises), a click keeps it and closes
the pop-up. Things that only showed on the device: xfwm4 raises the peeked
window over the (unmanaged) pop-up, which sent docklike a false "leave" and
closed it, so the pop-up is re-raised and leaves while the pointer is still
inside it are ignored; and docklike hides every other button's pop-up when one
opens, so a peek belongs to the pop-up it started in (that cancelled the first
hover). Patches are now numbered (`01-`, `02-`): `build-patched.sh` applies
them in name order. Built on the device itself (build toolchain installed
2026-11-25, ~400 MB; remove with his word).

**Taskbar, 2026-11-26 (kite-docklike 0.4.3-1+kite3, tried on the device).**
`03-kite-webapp-buttons.patch`: docklike groups a window by its first class
id, and Brave web-app windows are class `Brave-browser` (instance
`crx_<app id>`), so every web app joined Brave's button; now a window whose
instance name is exactly an installed launcher's `StartupWMClass` goes to that
launcher. `04-kite-new-window.patch`: "New window" first in the right-click
menu (as Shift+click), skipped when the launcher has its own "New Window"
action (Brave). `02-kite-hover-peek.patch` gained two fixes: a "leave" is
ignored only within 600 ms of a peek raise (a fast real leave reports the
pointer on the pop-up's edge, which had kept a pop-up open), and hovering
another button closes every other pop-up. Restarting the panel from a `!`
shell with `xfce4-panel -r` once left no panel at all; restart it with
`setsid -f xfce4-panel -r` (detached) instead.

**App Centre pin did nothing (kite-storage 1.1.4).** The .deb handler
`kite-install-package.desktop` also had `StartupWMClass=kite-apps`, and
docklike resolves a pin by window class before the launcher id, so the pin ran
`kite-app-centre --install-file` with no file. The handler has no window class
now; a test fails if two KiteOS launchers share one.

**Lid dead after hibernation (fixed in kite-chromebook 1.0.2, tested on the
device 2026-11-25).** After a resume from hibernation the lid did nothing
until a reboot. The lid sensor and `_LID` were fine (`/proc/acpi/button/lid`
followed the lid), but the EC never raised its ACPI interrupt (GPE 0x14
counter frozen), so logind never heard "lid closed". Cause: the EC's
host-event masks read back **all zero** after the resume; MrChromebox sets
them at a cold boot only (cold boot on this device: `SMI=0 SCI=0x14e601fb
WAKE=0`, i.e. lid, AC, battery, thermal/throttle, PD, MKBP, mode change; so
charger and battery events were lost after hibernation too). Re-enabling the
GPE in Linux and re-probing `cros_ec_lpcs` did not help; writing the SCI mask
back did. `kite-ec-events.service` saves the firmware's masks at boot
(`/var/lib/kite/chromebook/ec-masks`, never empty ones) and the system-sleep
hook `kite-ec-events` writes them back after any wake that left SCI at zero.
`sudo /usr/lib/kite/chromebook/kite-ec-events show` prints the masks. Commands
come from the kernel's `cros_ec_commands.h` (0x88/0x89/0x8D get, 0x8A/0x8B/0x8E
set) through `/dev/cros_ec`.

## Open to-do list

0. **Next session:** release the 2026-11-25 changes (picom animations, VLC;
   v1.4.1 or 1.5.0): the tag build now runs the VM test by itself; look at its
   report (picom running, xfwm4 compositor off, VLC default) and screenshots.
   Then bring the device from v1.3.2 to the new release (`sudo
   kite-update`, then `kite-layout windows` for the new layout files, `sudo apt
   install code git` if missing, and `sudo apt purge slick-greeter` only after
   `sudo lightdm --show-config | grep greeter-session` names
   lightdm-gtk-greeter), or flash the 1.4.0 ISO and do the eMMC install (to-do 3).
   Things only a person can see: new keys work right after `kite-layout keys
   chromebook`, the second account's name on the Frosted login screen, the
   keyring in VS Code at the first login (known gap above).
   Done 2026-11-24/25: `laptop-fixes` released as v1.4.0; its GitHub VM test
   passed 34/34 (the install flow reaches the Summary without a Desktop page)
   and the screenshots were checked.

1. ~~Push to GitHub and release v1.0~~: done 2026-11-23.
2. ~~Commit email~~: the owner kept the history as it is; new commits in this
   repository use the GitHub noreply address (repo-local `git config`).
3. **Real-hardware run, in progress.** Live USB on the device works: desktop,
   launcher, Brave, Wi-Fi, Bluetooth audio, animations, vivid colours, drive
   icons. **Installed on the eMMC and checked on 2026-11-25:** zswap, the
   memory guards, battery saving, vivid colours, keyd running, SOF card found,
   no failed services, and **hibernate and resume work** (`systemctl
   hibernate` from a live session: 1.27 GB image, 16 s to free memory first,
   session, Wi-Fi, Bluetooth, picom and vivid colours all back). Still to
   check from [INSTALL.md](INSTALL.md#after-installing-check-list): the lid's
   hibernate after 60 min (lid suspend works, also after a hibernate with
   kite-chromebook 1.0.2), keyboard top row, speakers and
   headphone jack, brightness keys. After installing, `kite-update` keeps
   it current.
4. **Brave hardware video decoding:** on by default from kite-desktop 1.1.0
   (after the v1.0 ISO): a KiteOS wrapper takes the place of
   `/usr/bin/brave-browser-stable` (dpkg diversion) and adds the flags in
   `/etc/kite/brave-flags.conf` (`--enable-features=AcceleratedVideoDecodeLinuxGL`).
   Still to do on the device: confirm `VaapiVideoDecoder` in
   `brave://media-internals`, measure CPU with and without, and try the
   commented-out `AcceleratedVideoDecodeLinuxZeroCopyGL`. YouTube may pick AV1,
   which the N4020 cannot decode in hardware: check the codec in "Stats for
   nerds" (`av01` = software decode) and, if so, look at blocking AV1.
5. ~~GitHub Actions workflow~~: works since 2026-11-23 (tests ~2 min, ISO
   ~13 min). See "Releasing" below.
6. Optional ideas, not started:
   - trim Papirus icon sizes (~10 MB, low value)
   - an "updates available" notification
   - a check that the keyd map matches the 11 G8 EE top row
7. **App Centre** (`kite-app-centre`): VM-tested in 1.3.1 (all four pages,
   Move a folder guard, disk setup). Still open: the `sudo -A` fallback with no
   polkit agent; Discover still lists some packages that are not apps.
8. **GitHub VM test** (`.github/workflows/vm-test.yml`,
   `tests/vm/ci-vm-test.sh`): KVM on the runner, a full live + install +
   installed-system run takes ~7 min (the install itself 161 s; 38 min in an
   emulated cloud VM). Since 2026-11-25 it runs on its own after the ISO build
   on every `v*` tag (the `vm-test` job in `build-iso.yml`); it can still be
   run by hand with `gh workflow run vm-test.yml -f tag=<tag>`. A failed check
   fails that job, not the release. It checks settings, not pixels, so a look
   at its screenshots is still needed. The boot-menu screenshot is the frame the
   OCR matched (GRUB boots after 5 s, so a fresh shot was black); `03-splash`
   usually shows the desktop already under KVM.
9. ~~Installer Summary cannot show the Desktop choice~~: the Desktop page is gone.

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
tests/vm/install-flow.sh live                         # KITE_INSTALL_X/Y move the taskbar click
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
- **xfce4-panel `force-all-internal` crashes the panel.** It saves ~200 MB (no
  wrapper process per plugin), but `xfce4-power-manager-plugins` 4.20 and
  `xfce4-pulseaudio-plugin` 0.4.9 both register a GObject type called
  `ScaleMenuItem`. In one process, opening the battery menu and then the volume
  menu (or the other way round) crashes the panel, and the session restarts it
  (`cannot register existing type 'ScaleMenuItem'` in `~/.xsession-errors`).
  Off since kite-desktop 1.2.4.
- **ONLYOFFICE needs `libxcb-shape0`** but does not depend on it. Without it,
  `DesktopEditors` exits at once (`libxcb-shape.so.0: cannot open shared object
  file`). The "crashes under QEMU" note from earlier VM runs may be this too.
- **xfwm4 shadows:** `show_popup_shadow` covers only override-redirect windows
  (GTK menus). The Whisker menu and the clock calendar are ordinary managed
  windows, so they follow `show_frame_shadow`, the same setting as app
  windows (xfwm4 4.20 `compositor.c`). The owner chose to keep window shadows.
- **nm-applet started before the tray** shows two icons. It starts through
  `/usr/lib/kite/desktop/after-tray`, which waits for `org.kde.StatusNotifierWatcher`.
- **Tray icons:** GTK only recolours *fills* of symbolic SVGs (why the old
  KiteOS tray icons were drawn as filled shapes). The systray requests
  `<name>-symbolic` at a forced size. Panel/tray icon sizes: 24/20
  (`xfce4-panel.xml`).
- **Brave's launcher reads no flags file** (`/opt/brave.com/brave/brave-browser`
  just runs `brave "$@"`); `~/.config/brave-flags.conf` is an Arch packaging
  convention. Hence the diversion and wrapper in kite-desktop. Chromium keeps
  only the last `--enable-features`, so the wrapper merges them.
- **`xrandr --set CTM` takes nine decimal matrix values** (`1,0,0,0,1,0,0,0,1`) on
  Debian 13: xrandr's `ctm_from_string` encodes them to S31.32 itself. The
  18 pre-encoded integers older guides show are read as coefficients in the
  hundreds of millions and turn the screen white (shipped by mistake in v1.2,
  fixed in kite-desktop 1.1.2). The 11 G8 EE does apply CTM in hardware.
- **Brave rotated its apt signing key.** The new release key
  `DBF1A116C220B8C7164F98230686B78420038257` was verified against
  brave.com/signing-keys.
- **VM quirks, not product bugs:**
  - The screen stays black after DPMS blanking under QEMU VGA (`xrefresh` fixes it).
  - OVMF only boots devices that have a `bootindex`.
  - The installed system uses the UK layout, so typed `|` and `@` come out wrong unless you `setxkbmap us`.

## Key design decisions

| Decision | Why |
|---|---|
| XFCE (not GNOME/Plasma), windows layout from docker-crd-vstunnel | RAM: idle system 640 MiB total. 1.3 replaced the ChromeOS-style shelf + rofi launcher with the container's two layouts (owner's call, 2026-11-23); the mac one was dropped on 2026-11-24 (owner's call: focus on windows) |
| One layout, applied by `kite-layout` | Layout files live in `/usr/share/kite/layouts/{common,windows}` and are applied to an account at first login (`kite-user-init` → `kite-layout --first-login`), not via `/etc/skel`; `kite-layout windows` puts them back |
| Standard Papirus-Light icons, tray included (since 2026-11-24, owner's call) | Until then the KiteOS-Tray-* packs over the `KiteOS` pack over the layout icon theme (copied from docker-crd-vstunnel, plus NetworkManager glyphs and a drive-icon fix); all removed. The Start and Search glyphs live on as `kite-start-symbolic` / `kite-search-symbolic` in hicolor |
| Fluent via a live-build hook from a pinned release tag | Not in Debian; same tags as the container. Only new ISOs update them, not `kite-update`. Not checksum-pinned yet |
| Swap **file** sized RAM + min(RAM/2, 4 GiB), ext4 only | Hibernation must work. RAM + 1 GB (until kite-system 1.2.2) left too little room on the device once ~2 GB was already swapped out; the owner set the new rule. Calamares' "suspend" swap sizing caps at 10 % of the disk; btrfs swap files are fragile |
| zswap (zstd), not zram | zram can't hold a hibernation image |
| suspend-then-hibernate enabled **only after** resume is configured | A half-configured system must never make the lid do nothing |
| `kite-storage`: move whole package-private dirs and symlink them | dpkg follows directory symlinks on upgrade. APT `Pre-Install-Pkgs` hook refuses to touch apps whose disk is unplugged |
| Fluent-Light theme, Papirus-Light icons; Orchis and the Papirus-inheriting KiteOS icon theme were the 1.2 shelf's | Orchis-Light-Compact is still the fallback when Fluent is missing |
| xfwm4 + picom for animations (2026-11-25, owner's call), not Compiz | Keeps xfwm4's Fluent theme, window keys and settings as they are; picom only composites. Calm animations (short, small zoom, none on resize). xfwm4's compositor is the fallback. Compiz was built and tried first, then dropped by the owner |
| Brave policy: Rewards/Wallet/VPN/Tor/P3A off | Lighter; owner can change `/etc/brave/policies/managed/kite.json` |

## Releasing

Push a `v*` tag and the Build ISO workflow tests, builds and attaches
`kiteos-<version>-amd64.iso` and its `.sha256` to the release for that tag,
straight from the runner. To write the notes yourself, create the release
first; the workflow then only adds the files:

```bash
gh release create v1.2 --title "KiteOS 1.2" --notes-file notes.md   # creates the tag, starts the build
```

Every release also carries the four `kite-*.deb` files and
`kite-packages.sha256`, which `kite-update` on installed systems uses. So a
fix that needs a new Debian package must add it to a kite package's
`Depends` (as `libspa-0.2-bluetooth` and the Whisker menu are), not only to
`live/config/package-lists`, or installed systems won't get it.

Without a release, a pushed tag gets one with generated notes. Manual runs
(`gh workflow run build-iso.yml`) only leave the ISO as a 90-day artifact.

## Continuing on another machine

Everything needed is in this repository and on GitHub; nothing lives only on
one laptop.

```bash
gh auth login                      # GitHub.com, SSH or HTTPS, browser login
gh repo clone iwankurnia/kite-os && cd kite-os
git config user.name "Iwan Kurnia"
git config user.email "6760806+iwankurnia@users.noreply.github.com"   # repo only, keeps the work address off new commits
claude                             # reads CLAUDE.md, which points here
```

Where things stand (2026-11-25): v1.5.2 is the newest release (see above). Before it: v1.4.0, VM-tested
(34/34); v1.3.2 is installed on the device. The Windows laptop has a clone in
`Code\Personal\kite-os`. Next: to-do 0 (the device to 1.4.0 and what only a
person can see), the eMMC run (to-do 3), then the Brave video check (to-do 4).

To pick up in Claude Code on the other laptop, start a **fresh** session in the
cloned folder (not a moved one) and say: "Read CLAUDE.md and docs/HANDOFF.md,
then continue with the open to-do list". On the Windows laptop the clone goes
in `Code\Personal\kite-os`; first time there, run the clone and git config
lines above. The skills repo's memory (`notes/memory/project-kiteos.md`) has
the same pointers.

- Builds: no local build needed. Push a tag or use
  `gh workflow run build-iso.yml` (see "Releasing"); `gh run download <run-id> -n kiteos-iso`
  fetches a manual run's ISO.
- Flashing: on macOS, `diskutil list external` then `sudo dd if=<iso> of=/dev/rdiskN bs=4m`;
  on Windows use Rufus in DD mode (or balenaEtcher). Check that the disk is the
  USB stick first; it is erased.
- Local test runs need Linux as root (`sudo tests/run-all.sh`); on macOS or
  Windows, rely on the workflow's test job.
