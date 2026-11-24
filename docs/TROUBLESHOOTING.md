# Troubleshooting

**Show the boot menu / boot messages.** Hold **Esc** right after the firmware
logo for the GRUB menu. Press `e` on an entry and remove `quiet splash` to see
messages.

**Hibernation doesn't work.**
```bash
sudo kite-hibernate-setup --check      # tells you what is missing
sudo kite-hibernate-setup              # (re)creates swap + resume config
sudo reboot
```
- "lockdown is active": Secure Boot is on. Disable it in the firmware setup (Esc → Device Manager).
- Resume starts a fresh boot instead of restoring: check `cat /proc/cmdline` has
  `resume=UUID=… resume_offset=…`, and that `/etc/initramfs-tools/conf.d/resume` exists; then
  `sudo update-initramfs -u -k all`.
- Logs: `journalctl -b -1 -u systemd-hibernate`.

**No sound.**
- `sudo /usr/lib/kite/chromebook/kite-chromebook-setup` then reboot.
- `aplay -l` should list a `sof-glk…` card. If not: `sudo dmesg | grep -i sof`;
  `firmware-sof-signed` must be installed, and Intel ME must not be disabled in the firmware.
- Pick the right output in `pavucontrol`.
- Upstream help: <https://github.com/WeirdTreeThing/chromebook-linux-audio>.

**Keyboard keys wrong.** `sudo keyd monitor` shows what each key sends.
Regenerate the map with `sudo systemctl restart kite-chromebook-setup keyd`.
To switch it off: `sudo systemctl disable --now keyd`.

**Black screen / login loop after the splash.** Switch to a text console with
Ctrl+Alt+(top-row key 2), log in, and check `journalctl -b -u lightdm` and
`~/.xsession-errors`. Resetting your desktop settings:
`mv ~/.config/xfce4 ~/.config/xfce4.bak && rm -f ~/.config/kite/layout`, then log in again
(the KiteOS desktop is set up afresh).

**Menu does not open with the Search key.** Check that
`~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml` has `xfce4-popup-whiskermenu`.
If not, run `kite-layout windows` to reset the desktop's shortcuts.

**External disk app won't start.** `kite-storage status` shows each moved
folder's state; `sudo kite-storage verify --repair` fixes links. To bring
everything back: `sudo kite-storage restore-app <pkg>`.

**Running low on memory.** Close Brave tabs (use Brave's Memory Saver), check
`cat /sys/kernel/debug/zswap/*` (as root) and `journalctl -u earlyoom`.

**Go back to ChromeOS.** Use the stock-firmware backup with the MrChromebox
script ("Restore stock firmware"), then a ChromeOS recovery USB.
