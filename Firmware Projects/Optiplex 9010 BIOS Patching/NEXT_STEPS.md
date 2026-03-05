# Dell OptiPlex 9010 - Next Steps (for Claude Code on the 9010)

## Status as of 2026-03-05 — ROOT CAUSE FOUND

**CSM (Compatibility Support Module) defaults to ON after CMOS reset, which conflicts with Above 4G Decoding.**

The xCuri0 ReBarUEFI wiki explicitly states: "CSM is off otherwise you might face issues such as black screen or unable to enter BIOS."

### Root cause confirmed:
- "Launch CSM" is at `setup_var 0xBDE` (IFR OneOf, VarStore 2)
- Default value after CMOS reset: `0x00` = **"Always"** (CSM ON)
- CSM ON + Above 4G Decoding ON = **black screen** (CSM expects all memory below 4GB)
- First time 4G worked because CSM was already OFF from pre-CMOS-reset config

### IFR values for "Launch CSM" (offset 0xBDE):
| Value | Meaning | Notes |
|-------|---------|-------|
| `0x00` | Always | CSM always launches — **DEFAULT after CMOS reset** |
| `0x01` | Auto | Based on OS detection |
| `0x02` | Never | CSM disabled — **REQUIRED for 4G Decoding** |

---

## IMMEDIATE FIX: Two setup_var Commands

After CMOS reset, boot modGRUBShell from USB and run BOTH commands:

```
setup_var 0xBDE 0x02
setup_var 0x2 0x1
```

This sets:
1. CSM = Never (disabled) — offset 0xBDE = 0x02
2. Above 4G Decoding = Enabled — offset 0x2 = 0x01

Then reboot. The system should boot to Windows with 4G Decoding working.

**Important:** Both commands must be set before rebooting. Setting only 4G without disabling CSM first = black screen.

---

## THEN: Enable Resizable BAR

Once the system boots with 4G Decoding working:

### Step 1: Run ReBarState.exe

1. Open **cmd** or **PowerShell as Administrator**
2. Navigate to:
   ```
   cd C:\Users\clayi\Desktop\9010_BIOS_BACKUP
   ```
3. Run:
   ```
   ReBarState.exe
   ```
4. Enter `32` when prompted (unlimited BAR size)

### Step 2: Reboot

Boot may take a couple extra seconds (WarmBootPei patch forces full PCI enumeration — expected).

### Step 3: Verify with GPU-Z

- "Above 4G Decode enabled in BIOS" → **YES**
- "Resizable BAR" → should now show **Enabled**

---

## FUTURE: Build Script Update Needed

The build script (`build_rebar.pl`) should be updated to also change the CSM IFR default from "Always" (0x00) to "Never" (0x02). This way CMOS resets will default to CSM OFF + 4G ON, and no setup_var commands will be needed at all.

This requires patching the OneOf option Flags in the IFR:
- "Always" option at its Flags byte: remove DEFAULT flag (0x30 → 0x20)
- "Never" option at its Flags byte: add DEFAULT flag (0x00 → 0x10)

This will be done on the Razer in the next build session.

---

## Recovery

If stuck in black screen / no boot:

1. CMOS reset (Dell standby power procedure):
   - Shut down, unplug cord, hold power 15-20s
   - Move jumper from PSWD to RTCRST
   - **Plug cord back in** (don't press power), wait 10s
   - Unplug, press power once, move jumper back to PSWD
   - Plug in, power on

2. This clears ALL NVRAM (including 4G and CSM) → system boots normally

3. Then re-apply both setup_var commands via modGRUBShell

---

## Files on this machine

| File | Description |
|------|-------------|
| `BACKUP.BIN` | Original stock BIOS (6MB) - KNOWN GOOD |
| `F1_BYPASS_V4.BIN` | NVMe + F1 bypass (base for ReBAR build) |
| `REBAR.BIN` | Full build: all patches (currently flashed) |
| `ReBarDxe.ffs` | ReBAR DXE driver (already in REBAR.BIN) |
| `ReBarState.exe` | Set BAR size — run AFTER 4G Decoding works |
| `build_rebar.pl` | Build script (run on Razer with CH341A) |
| `spi1_rebar_write.bin` | 4MB chip image (for reflashing if needed) |
| `spi2_rebar_write.bin` | 8MB chip image (for reflashing if needed) |
