# Claude Code Instructions — Dell OptiPlex 9010 (Run on the 9010)

You are running on the Dell OptiPlex 9010 (hostname: IXIONS-HAUNCH).
The user (clayi) is coordinating from their Razer laptop via this repo.

---

## Current Status

- SSH: WORKING (sshd running, Razer key installed, port 22 open)
- ReBAR UEFI settings: NOT YET APPLIED

## Why the PowerShell Script Didn't Work

The "Setup" UEFI variable (GUID EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9) has
**Boot Services only** attributes (NV+BS, no Runtime). Windows can only access
variables with the Runtime attribute. This is an AMI BIOS limitation — the
variable is intentionally hidden from the OS.

The `setup_var` command in modGRUBShell works because it runs in the UEFI
pre-boot environment where Boot Services variables ARE accessible.

**There is no way to modify these settings from Windows.** The user must
cold-boot to the USB drive ONE TIME to apply them.

---

## Task: Apply ReBAR Settings via Cold Boot + USB

The modGRUBShell is on a USB drive. The user needs to do this physically
at the 9010 — it cannot be done remotely.

### Steps (for the user):

1. **Fully shut down** the 9010 (Start -> Shut Down, NOT restart)
2. **Unplug the power cord** from the wall, wait 5 seconds
3. **Plug cord back in**
4. Press power and **immediately spam F12**
5. Select the USB drive from the boot menu
6. In the GRUB/EFI shell, run these commands:

```
setup_var 0x2 0x1       # Above 4G Decoding = Enabled
setup_var 0xBDE 0x02    # Launch CSM = Never
setup_var 0xBDF 0x02    # Boot option filter = UEFI only
setup_var 0x2D 0x02     # PXE OpROM = UEFI only
setup_var 0x2E 0x02     # Storage OpROM = UEFI only
setup_var 0x2F 0x02     # Video OpROM = UEFI only
```

7. Type `reboot` or power cycle

### After Reboot (can be done via SSH from Razer):

Once Windows boots, the Razer can SSH in and run:

```powershell
# Run ReBarState.exe to set BAR size to 32 (unlimited)
& "C:\path\to\ReBarState.exe"
# Enter 32 when prompted

# Reboot
Restart-Computer
```

Then verify with GPU-Z (Advanced tab -> Resizable BAR).

### If F12 Boot Menu Won't Show

The warm reboot black screen is caused by WarmBootPei. Always **cold boot**
(full power off, unplug, replug, power on + F12).

If cold boot + F12 still doesn't work:
- Try **F2 BIOS Setup** instead (cold boot + spam F2)
- In F2 Setup, change boot order to put USB first
- Save and exit — it should boot the USB drive
- Run setup_var commands above
- Then change boot order back

---

## SSH Access (for reference)

From the Razer:
```bash
ssh clayi@192.168.1.195
```

Key auth is configured. No password needed.

---

## What NOT to Do

- Do NOT set "Enable Legacy Option ROMs = Disabled" — this bricks the system
- Do NOT use "Fastboot = Minimal" — ReBAR needs full PCI enumeration
- Do NOT try to modify the Setup UEFI variable from Windows — it's BS-only
