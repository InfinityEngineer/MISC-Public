# Dell OptiPlex 9010 - Next Steps (for Claude Code on the 9010)

## Status as of 2026-03-05 (UPDATED — PROBLEM RECURRED)

**Above 4G Decoding is NOT reliably working.** It worked once, then stopped after a CMOS reset cycle.

### Timeline of events:
1. REBAR.BIN flashed on both chips with all patches (WarmBootPei, DSDT, IFR, hex patches)
2. Booted to Windows with 4G Decoding OFF — works fine
3. Ran `setup_var 0x2 0x1` (enable Above 4G Decoding) — **IT WORKED!** Warm reboots worked, GPU-Z confirmed Above 4G Decode = YES
4. Physical nudge while plugging in ethernet → lost display
5. CMOS reset (full Dell standby power procedure) → boots to Windows again (4G OFF)
6. Ran `setup_var 0x2 0x1` again → **BLACK SCREEN / NO BOOT**
7. Cannot recover without another CMOS reset

### Key observation:
The FIRST time 4G was enabled (step 3), all other NVRAM settings were intact from normal usage.
The SECOND time (step 6), CMOS reset had cleared ALL NVRAM — so the only variable set was 4G Decoding.

**This means another NVRAM variable (cleared by CMOS reset) is REQUIRED for 4G Decoding to work.**

### Most likely culprit: CSM (Compatibility Support Module)
- CSM must be OFF for Above 4G Decoding to work (they conflict — CSM expects all memory below 4GB)
- After CMOS reset, CSM may default to ON on the Dell 9010
- The first time it worked because CSM was already OFF from the pre-CMOS-reset state
- After CMOS reset, CSM went back to ON, and enabling 4G Decoding without disabling CSM first = black screen

### Other possible variables:
- Primary Display setting (PEG vs Auto vs IGD)
- PCIe link speed / generation settings
- Memory remap settings
- Any Dell-specific PCIe configuration variables

---

## RESEARCH TASKS (Priority Order)

### Task 1: Find the CSM setup_var offset
**Goal:** Find the NVRAM offset for CSM (Compatibility Support Module) enable/disable.

**Approach:** The Setup IFR data in the BIOS contains all setup variables. Search for "CSM" or "Compatibility" in the IFR strings. The CheckBox or OneOf opcode will have a VarOffset that corresponds to the setup_var offset.

**Known info:**
- Setup FFS is at FV1 offset 0x3F2E54 (426,485 bytes)
- HII Forms package at FV1 0x44A063 (69,581 bytes)
- Above 4G Decoding is at VarOffset 0x0002
- The IFR data is inside a COMPRESSION section (comp_type=0, not actually compressed)

**To extract and search:**
1. Read build_rebar.pl for the LZMA decompression procedure
2. Decompress FV1 from REBAR.BIN (or F1_BYPASS_V4.BIN)
3. Search decompressed FV1 for UTF-16LE "CSM" or "Compatibility"
4. Find the corresponding IFR opcode and VarOffset
5. Determine current default value and what it should be set to

### Task 2: Find ALL setup variables that interact with 4G Decoding
**Goal:** Map out every NVRAM variable that could affect PCI memory mapping.

Search the IFR for these keywords (UTF-16LE):
- "CSM"
- "Above 4G" (already found: VarOffset 0x0002)
- "PCI" / "PCIe"
- "Memory Remap"
- "TOLUD" / "REMAPBASE"
- "Primary Display" / "PEG"
- "Boot Mode"
- "64" / "64-bit"

### Task 3: Research Dell 7010/9010 CSM + 4G interaction
**Goal:** Find community documentation on which settings must be configured.

Check:
- Dell 7010 ReBAR guide (https://github.com/jrdoughty/Dell-7010-rebar-guide) — does it mention CSM?
- xCuri0/ReBarUEFI common issues (https://github.com/xCuri0/ReBarUEFI/wiki/Common-issues-(and-fixes))
- Win-Raid forum threads on Dell 7010/9010 ReBAR
- Any mention of required setup_var changes beyond 4G Decoding

### Task 4: Check if IFR default patch is actually working
**Goal:** Verify whether CMOS reset actually defaults 4G Decoding to ON.

After CMOS reset, boot modGRUBShell and check:
```
setup_var 0x2
```
- If value = 0x01 → IFR default is working, 4G is ON by default, problem is elsewhere
- If value = 0x00 → IFR default is NOT working, Dell's Setup DXE ignores IFR flags

### Task 5: Consider hardcoding 4G Decoding in firmware
**Goal:** If NVRAM-based approaches are unreliable, explore patching the consumer code.

The Setup DXE driver reads VarOffset 0x0002 to decide whether to enable 4G Decoding. Instead of relying on NVRAM, we could patch the code that reads this variable to always return 1 (enabled). This would make 4G Decoding always ON regardless of NVRAM state.

This requires finding the code in the Setup or PciHostBridge DXE that reads the Setup variable and uses the 4G Decoding flag.

---

## IMMEDIATE WORKAROUND TO TRY

Before doing deep research, try this sequence after CMOS reset:

1. CMOS reset (full Dell procedure with standby power)
2. Boot to BIOS Setup (F2)
3. In BIOS Setup, manually disable CSM if visible (Dell may hide it, but check)
4. Save and reboot
5. Boot modGRUBShell, check CSM variable: look for a setup_var related to CSM
6. Run `setup_var 0x2 0x1` (enable 4G Decoding)
7. Reboot

If CSM is the issue, disabling it before enabling 4G should fix it.

If Dell's BIOS Setup doesn't expose CSM, use setup_var to disable it directly once we find the offset (Task 1).

---

## Files on this machine

| File | Description |
|------|-------------|
| `BACKUP.BIN` | Original stock BIOS (6MB) - KNOWN GOOD |
| `F1_BYPASS_V4.BIN` | NVMe + F1 bypass (base for ReBAR build) |
| `REBAR.BIN` | Full build: all patches (currently flashed) |
| `ReBarDxe.ffs` | ReBAR DXE driver (already in REBAR.BIN) |
| `ReBarState.exe` | Set BAR size (DO NOT RUN until 4G Decoding works reliably) |
| `build_rebar.pl` | Build script (run on Razer with CH341A) |
| `spi1_rebar_write.bin` | 4MB chip image (for reflashing if needed) |
| `spi2_rebar_write.bin` | 8MB chip image (for reflashing if needed) |

## Recovery

If stuck in non-booting state, do a CMOS reset:
1. Shut down, unplug power cord
2. Hold power button 15-20 seconds
3. Move jumper from PSWD to RTCRST
4. **Plug power cord BACK IN** (don't press power), wait 10 seconds
5. Unplug cord, press power once, move jumper back to PSWD
6. Plug in, power on

This clears 4G Decoding (and everything else) and gets back to bootable state.
