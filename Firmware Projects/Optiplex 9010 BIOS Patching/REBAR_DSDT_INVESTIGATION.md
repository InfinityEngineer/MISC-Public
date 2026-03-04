# Dell OptiPlex 9010 - ReBAR DSDT Investigation

## Context (from previous Claude Code session on Razer)

The REBAR.BIN is flashed on both SPI chips and boots fine. All 7 UEFIPatch hex patches + ReBarDxe.ffs are applied and verified. However, **enabling Above 4G Decoding (`setup_var 0x2 0x1`) causes a black screen** — no display output after POST starts. Tested with 32GB, 16GB RAM — same result. CMOS reset recovers.

### Root Cause Theory

The Dell 7010 ReBAR guide (same Q77 chipset, confirmed working) includes a **modified AmiBoardInfo.ffs** containing a patched DSDT. In AMI UEFI, AmiBoardInfo provides PCI resource descriptors to PciHostBridge during DXE. If the DSDT only declares 32-bit PCI memory ranges, PciHostBridge has no above-4G address space to allocate into — the hex patches remove limit *checks* but the firmware still sees "no 64-bit memory region available." GPU BAR allocation fails, no display.

### What To Do On This Machine (Dell 9010)

#### Step 1: Dump the current DSDT

Run in an **admin** PowerShell or cmd:

```powershell
# Method A: Direct ACPI table dump (if available)
copy /b "$env:SystemRoot\System32\ACPI\DSDT.aml" "$env:USERPROFILE\Desktop\9010_BIOS_BACKUP\DSDT_dump.aml"

# Method B: If Method A fails, use acpidump (download from iasl/acpica tools)
# Or extract from the BIOS image we already have (see Step 1b below)
```

#### Step 1b: Extract DSDT from BIOS image (alternative)

If direct dump doesn't work, the DSDT is inside the `AmiBoardInfo` module:
- **AmiBoardInfo GUID:** `9F3A0016-AE55-4288-829D-D22FD344C347`
- It's a PE32 executable inside a FFS file
- Location: likely in the compressed FV1 (LZMA at BIOS offset 0x050069) or possibly uncompressed in the DXE FV
- Use UEFITool 0.28.0 (non-NE) to find and extract it

Tools needed (download these):
- **AmiBoardInfoTool**: https://github.com/xCuri0/ReBarUEFI/releases (look in release assets)
- **iasl** (ACPI compiler): https://www.intel.com/content/www/us/en/developer/topic-technology/open/acpica/download.html
- **UEFITool 0.28.0**: https://github.com/LongSoft/UEFITool/releases/download/0.28.0/UEFITool_0.28.0_win32.zip

#### Step 2: Decompile and examine the DSDT

```cmd
iasl DSDT_dump.aml
```

This produces `DSDT_dump.dsl`. Open it in a text editor and search for:

1. **`QWordMemory`** — if this exists in the `_CRS` method of `PCI0`, the DSDT already has 64-bit memory resources
2. **`DWordMemory`** — the 32-bit PCI memory declaration(s)
3. **`M2LN`**, **`M2MN`**, **`M2MX`** — the 64-bit memory range variables
4. **`MM64`** — flag for 64-bit MMIO availability
5. **`TUUD`** — Top of Upper Usable DRAM reference

**What we expect to find (the problem):**
```asl
M2LN = 0x0000000400000000   // Fixed 16GB length
M2MX = ((M2MN + M2LN) - One) // Derived max
```

**What it needs to be changed to:**
```asl
M2MX = 0xFFFFFFFFF          // 36-bit / 64GB ceiling (max for Ivy Bridge)
M2LN = (M2MX - M2MN) + One  // Calculated length
```

#### Step 3: Check Windows PCI resources (quick sanity check)

Open Device Manager → View → Resources by Type → expand "Large Memory"
- If PCI Bus range ends at `FFFFFFFFF` or above → DSDT is already correct (problem is elsewhere)
- If it ends at `FFFFFFFF` (32-bit) → confirms DSDT needs patching

#### Step 4: Report back

Save/copy:
- The `DSDT_dump.dsl` file (decompiled DSDT source)
- Screenshot or text of Device Manager "Large Memory" resources
- Any errors from the dump/decompile process

These go back to the Razer for the next build session.

---

## Files on this machine
- `C:\Users\clayi\Desktop\9010_BIOS_BACKUP\` — main workspace
- `REBAR.BIN` — currently flashed BIOS (6MB, NVMe + F1 bypass + ReBAR patches + ReBarDxe.ffs)
- `F1_BYPASS_V4.BIN` — previous working BIOS (fallback)
- `ReBarDxe.ffs` — already inserted in REBAR.BIN
- `ReBarState.exe` — NOT YET RUN (need 4G Decoding working first)
- USB drive `F:` has modGRUBShell.efi at `EFI/Boot/bootx64.efi`

## Current machine state
- REBAR.BIN flashed on both chips, boots to Windows normally
- Above 4G Decoding: **OFF** (CMOS reset clears it)
- ReBAR: **disabled** (need 4G Decoding + ReBarState first)
- CSM: OFF, Secure Boot: OFF, UEFI boot from GPT NVMe

## What NOT to do
- Do NOT run `setup_var 0x2 0x1` yet — it will cause black screen
- Do NOT reflash anything — wait for the DSDT analysis
- Do NOT run ReBarState.exe yet
