# Dell OptiPlex 9010 - Next Steps (for Claude Code on the 9010)

## Status as of 2026-03-05 — CSM MUST BE DISABLED VIA F2 MENU

**CSM (Compatibility Support Module) defaults to ON after CMOS reset, which conflicts with Above 4G Decoding.**

The xCuri0 wiki states: "CSM is off otherwise you might face issues such as black screen."
The Dell 7010 guide says: "Disable Legacy Boot options" and "Set your bios to use uefi boot" — done through the F2 BIOS menu, NOT setup_var.

### IMPORTANT: Do NOT use setup_var for CSM!
- CSM's IFR VarStore (ID=2) is from the CSMCORE module and maps to a DIFFERENT NVRAM variable than the "Setup" variable that `setup_var` writes to
- `setup_var 0xBDE 0x02` writes to the WRONG variable — it corrupts byte 3038 of the Setup variable instead of changing CSM
- CSM must be disabled through the **Dell BIOS F2 menu** (Boot tab → UEFI boot mode)

---

## CORRECT PROCEDURE

### Step 1: CMOS Reset
Full Dell standby power procedure:
1. Shut down, unplug cord, hold power 15-20s
2. Move jumper from PSWD to RTCRST
3. **Plug cord back in** (don't press power), wait 10s
4. Unplug, press power once, move jumper back to PSWD
5. Plug in, power on

### Step 2: Configure BIOS Settings (F2)
On boot, press F2 to enter BIOS Setup. Configure ALL of these:

1. **Boot tab** → **Boot List Option** = **UEFI** (not Legacy)
2. **Boot tab** → **Enable Legacy Option ROMs** = **UNCHECKED / DISABLED**
   - This is THE critical setting — it's separate from Boot List Option!
   - When enabled, Video/Storage OpROMs load in Legacy mode which conflicts with 4G
   - The Dell BIOS string says: "This option is required for Legacy boot mode and is not allowed if Secure Boot is enabled"
3. **Boot tab** → Set boot sequence to include the NVMe drive
4. **Secure Boot** → **OFF**
5. **Save and Exit**

**Why "Enable Legacy Option ROMs" matters:**
The CSM sub-options default to Legacy mode after CMOS reset:
- "Launch Video OpROM policy" defaults to **Legacy only**
- "Launch Storage OpROM policy" defaults to **Legacy only**
- These cause the GPU's Option ROM to load in Legacy mode
- Legacy Video OpROM + Above 4G Decoding = black screen
- Disabling Legacy Option ROMs forces everything to UEFI mode

### Step 3: Enable Above 4G Decoding (modGRUBShell)
1. Boot from USB with modGRUBShell (F12 boot menu)
2. Run: `setup_var 0x2 0x1`
3. Reboot

### Step 4: Verify
- System should boot to Windows with 4G Decoding enabled
- Open GPU-Z → Advanced tab → "Above 4G Decode enabled in BIOS" = YES

### Step 5: Enable Resizable BAR
1. Open cmd/PowerShell as Administrator
2. `cd C:\Users\clayi\Desktop\9010_BIOS_BACKUP`
3. Run `ReBarState.exe`, enter `32` (unlimited)
4. Reboot
5. GPU-Z → Resizable BAR should show **Enabled**

---

## What Went Wrong Previously

| Attempt | Result | Why |
|---------|--------|-----|
| `setup_var 0x2 0x1` (first time, CSM already OFF) | Worked! | CSM was OFF from pre-CMOS-reset config |
| CMOS reset + `setup_var 0x2 0x1` only | Black screen | CMOS reset re-enabled CSM (Legacy boot) |
| `setup_var 0xBDE 0x02` + `setup_var 0x2 0x1` | Worse (no HDD activity) | 0xBDE wrote to wrong NVRAM variable, corrupting an unrelated setting |

The key insight: CSM/Legacy boot must be disabled through the F2 BIOS menu, not setup_var. The 7010 guide does this as a prerequisite before any setup_var commands.

---

## Recovery

If stuck in black screen / no boot:
1. CMOS reset (see Step 1 above)
2. This clears ALL NVRAM → system boots normally
3. Then follow Steps 2-5 in order

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

## Future Build Script Update
- Change CSM IFR default from "Always" to "Never" — but this requires finding the correct VarStore and NVRAM variable for CSMCORE, which is more complex than initially thought
- May not be worth it if the F2 menu approach works reliably
