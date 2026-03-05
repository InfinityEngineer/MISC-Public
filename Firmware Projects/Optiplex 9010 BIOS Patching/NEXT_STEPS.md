# Dell OptiPlex 9010 - Next Steps

## Status as of 2026-03-05 — RESIZABLE BAR FULLY WORKING

Above 4G Decoding and Resizable BAR are both **confirmed enabled** in GPU-Z.
Warm reboots work (WarmBootPei patch). System is stable.

---

## Remaining Task: Rebuild REBAR.BIN with CSM IFR Default Patches

### Why
The current REBAR.BIN on the chips does NOT have CSM IFR default patches.
The working state is maintained via `setup_var` NVRAM values. If a CMOS reset
ever happens (battery removal, jumper, etc.), CSM defaults would revert to
Legacy mode, requiring the full setup_var procedure again.

### What Changed in build_rebar.pl
Step 3d was added to patch CSM IFR defaults inside the decompressed FV1:

| Setting | Default Before | Default After | Remove-DEFAULT offset | Add-DEFAULT offset |
|---------|---------------|---------------|----------------------|-------------------|
| Launch CSM | 0x00 Always | 0x02 Never | fv1 0x456FB3 | fv1 0x456FC1 |
| Boot option filter | 0x00 UEFI+Legacy | 0x02 UEFI only | fv1 0x456FFF | fv1 0x45701B |
| PXE OpROM | 0x00 Do not launch | 0x02 UEFI only | fv1 0x457051 | fv1 0x45705F |
| Storage OpROM | 0x01 Legacy | 0x02 UEFI only | fv1 0x4570BF | fv1 0x4570B1 |
| Video OpROM | 0x01 Legacy | 0x02 UEFI only | fv1 0x457111 | fv1 0x457103 |

Each patch changes the IFR OneOf Flags byte: remove bit 0x10 (DEFAULT) from old
default option, add bit 0x10 to desired option.

### How to Rebuild
On the Razer (has CH341A + flashrom):
```bash
cd C:/Users/clayi/Desktop/9010_BIOS_BACKUP/
perl build_rebar.pl
```

This produces a new `REBAR.BIN`. Then build chip images and flash:
```bash
# Build chip write images (script outputs spi1/spi2 files)
# Flash 8MB chip:
flashrom/flashrom-1.4/flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -w spi2_rebar_write.bin
# Flash 4MB chip:
flashrom/flashrom-1.4/flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w spi1_rebar_write.bin
```

**Important:** Read fresh 8MB chip dump first (preserves NVRAM). The build script
handles this — it uses the fresh dump as the 8MB base.

### After Reflash
After flashing, a CMOS reset + `setup_var 0x2 0x1` should be all that's needed.
The CSM settings will default to UEFI-only from the IFR patches. The Above 4G
Decoding IFR default is already patched to Enabled, but setup_var confirms it.

---

## Recovery Procedure

If stuck in black screen / no boot:
1. CMOS reset (Dell standby power procedure — see README.md)
2. System boots normally (NVRAM cleared)
3. Boot modGRUBShell from USB (F12 → UEFI: USB)
4. Run all setup_var commands:
   ```
   setup_var 0x2F 0x02     # Video OpROM = UEFI only
   setup_var 0x2E 0x02     # Storage OpROM = UEFI only
   setup_var 0x2D 0x02     # PXE OpROM = UEFI only
   setup_var 0xBDF 0x02    # Boot option filter = UEFI only
   setup_var 0xBDE 0x02    # Launch CSM = Never
   setup_var 0x2 0x1       # Above 4G Decoding = Enabled
   ```
5. Reboot → should boot to Windows with 4G + ReBAR enabled
6. If ReBAR not showing, run `ReBarState.exe` with size `32` and reboot

---

## What Went Wrong During Development

| Attempt | Result | Root Cause |
|---------|--------|------------|
| `setup_var 0x2 0x1` (first time) | Worked! | CSM happened to be OFF from pre-reset config |
| CMOS reset + `setup_var 0x2 0x1` only | Black screen | CMOS reset re-enabled CSM → Legacy Video OpROM + 4G = conflict |
| `setup_var 0xBDE 0x02` + `0x2 0x1` | Worse (no HDD) | Disabled CSM but sub-options still Legacy → no storage |
| ALL 6 setup_var commands | **Success!** | All CSM sub-options set to UEFI-only simultaneously |

The critical insight: "Launch CSM = Never" alone is not enough. The 5 CSM
sub-options (Video/Storage/PXE OpROM policies, Boot option filter, Launch CSM)
ALL must be set to UEFI-only mode. These are hidden settings not exposed in
the Dell F2 BIOS menu.

---

## Files

| File | Description |
|------|-------------|
| `BACKUP.BIN` | Original stock BIOS (6MB) - KNOWN GOOD |
| `F1_BYPASS_V4.BIN` | NVMe + F1 bypass (base for ReBAR build) |
| `REBAR.BIN` | Full build: all patches (currently flashed, no CSM IFR patches yet) |
| `ReBarDxe.ffs` | ReBAR DXE driver (already in REBAR.BIN) |
| `ReBarState.exe` | Set BAR size — run AFTER 4G Decoding works |
| `build_rebar.pl` | Build script (UPDATED with CSM IFR patches, needs rebuild) |
| `spi1_rebar_write.bin` | 4MB chip image (current, pre-CSM-IFR) |
| `spi2_rebar_write.bin` | 8MB chip image (current, pre-CSM-IFR) |
