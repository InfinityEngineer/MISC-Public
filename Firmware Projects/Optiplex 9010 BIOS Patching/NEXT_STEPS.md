# Dell OptiPlex 9010 - Next Steps (for Claude Code on the 9010)

## Status as of 2026-03-05

The REBAR.BIN is flashed on both SPI chips with ALL patches applied and working:
- NVMe boot: **working**
- F1 fan failure bypass: **working**
- Above 4G Decoding: **WORKING** (confirmed by GPU-Z, survives warm reboots)
- WarmBootPei patch: **WORKING** (warm reboots no longer cause black screen)
- Resizable BAR: **NOT YET ENABLED** (need to run ReBarState.exe)

GPU-Z currently shows:
- Above 4G Decode enabled in BIOS: **YES**
- Resizable BAR enabled in BIOS: **NO**
- GPU hardware support for ReBAR: **YES**

## IMMEDIATE TASK: Enable Resizable BAR

### Step 1: Run ReBarState.exe

1. Open **cmd** or **PowerShell as Administrator**
2. Navigate to the BIOS workspace:
   ```
   cd C:\Users\clayi\Desktop\9010_BIOS_BACKUP
   ```
3. Run:
   ```
   ReBarState.exe
   ```
4. When prompted for BAR size, enter: `32` (this means "unlimited" — the GPU will negotiate the largest size it supports)
5. The tool writes the desired BAR size to a UEFI NVRAM variable that ReBarDxe reads on next boot

### Step 2: Reboot

Just reboot normally. The boot may take a couple extra seconds (the WarmBootPei patch forces full PCI enumeration every boot — this is expected and is what fixed the warm reboot issue).

### Step 3: Verify

After Windows loads:

1. Open **GPU-Z** (should already be installed)
2. Go to the **Advanced** tab
3. Check:
   - "Resizable BAR" → should now show **Enabled**
   - "Above 4G Decode enabled in BIOS" → should still show **YES**
4. If both show yes/enabled, **ReBAR is fully working!**

### What to do if it doesn't work

- If GPU-Z still shows "Resizable BAR: Disabled" after reboot, try running `ReBarState.exe` again and entering a specific size like `8192` instead of `32`
- If the machine doesn't boot after ReBarState, do a CMOS reset (see README.md for the Dell-specific procedure requiring standby power) — this will clear the NVRAM variable ReBarState wrote

## KNOWN ISSUE: Physical Nudge Black Screen

The machine went black after being physically nudged (bumped while plugging in an ethernet cable). This is almost certainly a **loose connection** — RAM stick or GPU not fully seated. This is NOT a BIOS issue.

**Fix:** Follow Recovery Checklist Level 1 in the README:
1. Power off, unplug
2. Reseat ALL 4 RAM sticks (pull out completely, reseat until clips click)
3. Reseat the GPU
4. Check all power cables
5. Plug in, power on

The BIOS mods are fine — they're stored in SPI flash, which isn't affected by physical movement. Once the loose connection is fixed, everything should work exactly as before.

## Files on this machine

| File | Description |
|------|-------------|
| `BACKUP.BIN` | Original stock BIOS (6MB) - KNOWN GOOD |
| `F1_BYPASS_V4.BIN` | NVMe + F1 bypass (base for ReBAR build) |
| `REBAR.BIN` | Full build: all patches (currently flashed) |
| `ReBarDxe.ffs` | ReBAR DXE driver (already in REBAR.BIN) |
| `ReBarState.exe` | **RUN THIS** to set BAR size |
| `build_rebar.pl` | Build script (run on Razer with CH341A) |
| `spi1_rebar_write.bin` | 4MB chip image (for reflashing if needed) |
| `spi2_rebar_write.bin` | 8MB chip image (for reflashing if needed) |

## Research Topics (for overnight investigation)

If time permits, these are interesting areas to explore:

1. **Performance benchmarking**: After ReBAR is enabled, compare game performance with ReBAR on vs off. The RTX 4060 should see 5-15% improvement in some titles (especially those with SAM/ReBAR optimization like Forza Horizon, Assassin's Creed, etc.)

2. **Boot time optimization**: The WarmBootPei JNE→JMP patch forces full PCI enumeration on every boot, adding ~2-3 seconds. Could investigate whether there's a more surgical fix that only forces full enumeration when Above 4G Decoding is enabled, while preserving fast boot for normal restarts.

3. **NVIDIA driver ReBAR profile**: Some NVIDIA drivers have a ReBAR profile that needs to be enabled in the NVIDIA Control Panel or via registry. Check if the current driver version (check `nvidia-smi`) supports ReBAR on the RTX 4060 out of the box or if additional configuration is needed.
