# 1. Firmware: replacing the Chromebook firmware (one-time)

KiteOS needs **MrChromebox UEFI Full ROM** firmware. With it the Chromebook
boots like a normal UEFI laptop: USB boot, a proper boot menu, and
suspend/hibernate support. Your device is in MrChromebox's supported list:

| | |
|---|---|
| Model | HP Chromebook 11 G8 EE |
| Board name | **VORTICON** (platform: Intel Gemini Lake, "octopus") |
| UEFI Full ROM | supported |
| Write-protect method | CR50 security chip: **battery disconnect** (or a SuzyQ cable) |

> ⚠️ Flashing Full ROM removes ChromeOS. Back up anything you need first.
> **School or company-managed ("enrolled") devices cannot do this**: developer
> mode and write-protect removal are blocked until the owner releases the device.

## Steps

1. **Back up** your files (developer mode wipes the device).
2. **Enable developer mode.** Hold `Esc` + `Refresh` and press `Power`. At the
   recovery screen press `Ctrl+D`, confirm, and wait for the wipe to finish
   (about 5–10 minutes).
3. **Disable hardware write-protect** (this model has a CR50 chip, so use the battery method):
   1. Power off. Remove the bottom cover screws and open the case carefully.
   2. Unplug the **battery connector** from the mainboard.
   3. Close the case loosely, connect the **charger**, and power on. The
      laptop must run from the charger with the battery disconnected.
4. **Open a shell.** At the ChromeOS login screen press `Ctrl+Alt+F2` (the
   key in the F2 position is "Refresh"/"→"), log in as `chronos`.
5. **Run the firmware utility script** (from MrChromebox's documentation):
   ```bash
   cd; curl -LOf https://mrchromebox.tech/firmware-util.sh && sudo bash firmware-util.sh
   ```
   The header should show `Fw WP: Disabled`. If it says Enabled, step 3 did
   not take effect.
6. Choose **"Install/Update UEFI (Full ROM) Firmware"**.
7. When it offers to **back up the stock firmware, do it**, and copy the file
   to a USB stick you keep safe. That backup is the only way back to ChromeOS.
8. If the script offers an **EC firmware update**, accept it. On Gemini Lake it
   makes the top-row keys work properly under Linux.
9. Use the script's **power off** option (don't reboot), **reconnect the
   battery**, close the case.
10. Power on. You now get the UEFI boot screen; press **Esc** for the boot menu.

Keep **Secure Boot disabled** (the default). Debian blocks hibernation while
Secure Boot is on.

Reference: <https://docs.mrchromebox.tech/docs/getting-started.html> and
<https://docs.mrchromebox.tech/docs/firmware/wp/disabling.html>.
