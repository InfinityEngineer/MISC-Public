# Dell OptiPlex 9010 MT - BIOS Patching

Patches for the Dell OptiPlex 9010 MT (Mini Tower) BIOS, version A30.

These were developed with Claude Code (Anthropic's CLI agent) doing binary analysis, reverse engineering, and build scripting. No GUI tools required - everything is done with Perl scripts and command-line utilities.

## Status: Complete

| Feature | Status |
|---------|--------|
| NVMe Boot | Working |
| F1 Fan Failure Bypass | Working |
| Above 4G Decoding | Working |
| Resizable BAR (ReBAR) | Working (8GB BAR confirmed) |

All features confirmed working with RTX 4060 8GB. ReBAR verified via `nvidia-smi` (BAR1 = 8192 MiB) and `ReBarState.exe` with BAR size 32 (unlimited). Stable across warm reboots and power cycles.

## Hardware Setup

- **Dell OptiPlex 9010 MT** (Ivy Bridge / Q77 chipset)
- **NVIDIA RTX 4060 8GB** (native ReBAR support)
- **32GB DDR3 RAM** (4x8GB)
- **CH341A USB SPI programmer** (3.3V mod required!)
- **SOIC-8 test clip** for in-circuit flashing

### Flash Chip Layout

The 9010 has **two SPI flash chips** (combined 12MB):

| Chip | Part Number | Size | Contents |
|------|-------------|------|----------|
| SPI_1 | MX25L3206E | 4MB | Last 4MB of BIOS (Main FV drivers, boot block) |
| SPI_2/3 | MX25L6406E | 8MB | Flash descriptor + GbE + Intel ME + first 2MB of BIOS |

The 6MB BIOS region spans both chips:
```
BIOS[0x000000-0x1FFFFF] -> 8MB chip at offset 0x600000
BIOS[0x200000-0x5FFFFF] -> 4MB chip at offset 0x000000
```

**This matters!** Some modifications involve compressed data that crosses the chip boundary. You must flash both chips or you'll get a corrupted LZMA stream and a bricked machine.

## Stock BIOS

`BACKUP.BIN` - Unmodified Dell OptiPlex 9010 A30 BIOS dump (6MB). This is the complete BIOS region extracted from both flash chips.

---

## Mods (Pick Your Tier)

Each tier builds on the previous. Pick whichever level suits your needs:

| Tier | Script | What It Does | Chips to Flash |
|------|--------|-------------|----------------|
| 1 | `build_nvme_only.pl` | NVMe boot support | 4MB only |
| 2 | `build_f1_bypass.pl` | NVMe + F1 fan error bypass | Both (4MB + 8MB) |
| 3 | `build_rebar.pl` | NVMe + F1 bypass + ReBAR + Above 4G | Both (4MB + 8MB) |

### Tier 1: NVMe Boot (`build_nvme_only.pl`)

**Problem:** The stock 9010 BIOS has no NVMe driver, so NVMe SSDs in PCIe adapters aren't bootable.

**Solution:** Injects `NvmExpressDxe.ffs` into Main FV free space at BIOS offset `0x3564B0`.

**Simple mod** — only the 4MB chip needs flashing, no LZMA recompression needed.

```bash
perl build_nvme_only.pl
flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w spi1_nvmeonly_write.bin
```

### Tier 2: F1 Fan Failure Bypass (`build_f1_bypass.pl`)

**Problem:** Non-stock fans (or missing Dell fan headers) trigger "Alert! Previous fan failure" at every POST, requiring you to press F1 to continue. This blocks unattended reboots (Windows Updates hang at the F1 prompt).

**Solution:** Patches the `DellErrorLogConfig` DXE driver (GUID `038CE287-B806-45B6-A819-514DAF4B91B9`) to return `EFI_SUCCESS` immediately, preventing the error display routine from ever executing. Also includes NVMe driver injection.

**How it works:**
1. Injects NVMe driver into Main FV free space
2. Extracts the LZMA-compressed firmware volume (FV2) containing 183 DXE drivers
3. Locates the DellErrorLogConfig FFS file at FV2 offset `0x008E7C`
4. Patches the PE entry point: `48 89 5C` -> `33 C0 C3` (xor eax, eax; ret)
5. Zeros dead `.text` and `.data` sections (34KB of error strings) to improve compression
6. Recompresses with LZMA, fixes the header (xz bug workaround), updates FFS checksums
7. Generates write images for both flash chips

```bash
perl build_f1_bypass.pl
flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w spi1_f1bypass_write.bin
flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -w spi2_f1bypass_write.bin
```

### Tier 3: Resizable BAR (`build_rebar.pl`)

**Problem:** The Dell 9010 BIOS doesn't support Resizable BAR or Above 4G Decoding. Modern GPUs (RTX 3000/4000 series) benefit from ReBAR for 5-15% better performance in some games.

**Solution:** Applies 8 hex patches + 3 DSDT patches + 1 IFR patch + 1 WarmBootPei patch, plus injects the ReBarDxe.ffs driver. This was the result of weeks of reverse engineering to solve a warm reboot black screen issue unique to the 9010 platform.

#### All Patches Applied

**FV1 (compressed, LZMA at BIOS 0x050069, on 8MB chip):**

| # | Module | Description | FV1 Offset |
|---|--------|-------------|------------|
| 1 | PciHostBridge | Remove <4GB BAR size limit | 0x107F6C |
| 2 | PciHostBridge | Fix AddMemorySpace (MMIO ceiling 16GB→64GB) | 0x107645 |
| 3 | PciHostBridge | Remove 4GB PciRootBridgeIo.Mem limit (v1) | 0x108822 |
| 4 | PciHostBridge | Remove 4GB PciRootBridgeIo.Mem limit (v2) | 0x1088CA |
| 5 | PciBus | Remove <16GB BAR limit | 0x0557D0 |
| 6a | Runtime | Remove 4GB CpuIo2 limit (instance 1) | 0x03CAAF |
| 6b | Runtime | Remove 4GB CpuIo2 limit (instance 2) | 0x03CB8B |
| 7 | PciBus | IvyUSB3 XHCI 64-bit blacklist fix | 0x05A415 |

**DSDT Patches (in AmiBoardInfo, DSDT at FV1 0x05B9E1):**

| Patch | DSDT Offset | Description |
|-------|-------------|-------------|
| C | +0x1973 | `ElseIf(E4GM)` → `ElseIf(OSYS)` — bypass dead E4GM gate |
| A | +0x199B | `Store(16GB, M2LN)` → `Store(0xFFFFFFFFF, M2MX)` — expand to 64GB ceiling |
| B | +0x19CF | `M2MX=(M2MN+M2LN)-1` → `M2LN=(M2MX-M2MN)+1` — reverse calculation |

**IFR Defaults (in Setup FFS at FV1 0x3F2E54):**
- Above 4G Decoding: CheckBox at FV1 0x45ACCA, Flags byte at 0x45ACD6: `0x00` → `0x01` (default Enabled)
- CSM defaults (all OneOf, move DEFAULT flag to UEFI-only option):
  - Launch CSM: fv1 0x456FB3 (remove DEFAULT) / 0x456FC1 (add DEFAULT to "Never")
  - Boot option filter: fv1 0x456FFF / 0x45701B ("UEFI only")
  - PXE OpROM: fv1 0x457051 / 0x45705F ("UEFI only")
  - Storage OpROM: fv1 0x4570BF / 0x4570B1 ("UEFI only")
  - Video OpROM: fv1 0x457111 / 0x457103 ("UEFI only")

**FV_BB (uncompressed, on 4MB chip):**
- WarmBootPei at BIOS 0x570A00: `75 12` (JNE) → `EB 12` (JMP) at 0x570CBB
- Disables warm boot marker detection → forces full PCI enumeration every boot

**Main FV (uncompressed, on 4MB chip):**
- NVMe driver injected at BIOS 0x3564B0 (6024 bytes)
- ReBarDxe.ffs injected at BIOS 0x357C38 (2578 bytes)

---

## Root Cause Analysis: Warm Reboot Black Screen

This was the hardest problem to solve. Enabling Above 4G Decoding would work on the first cold boot, but warm reboots would produce a black screen with no display output.

### The Root Cause Chain

1. **E4GM gate (DSDT)**: Dell never wired up the `E4GM` (Enable 4G Memory) variable on the 9010. The DSDT has a conditional branch `ElseIf(E4GM)` that declares 64-bit PCI memory resources, but since E4GM is always zero, this branch was dead code. **Fix: Patch C** — change `E4GM` to `OSYS` (OS version year), which is always non-zero on modern Windows.

2. **WarmBootPei (PEI module)**: A 912-byte PEI module checks for a `_WB_` (Warm Boot) marker in BIOS data area memory (address 0x40E). When found, it calls a PPI to signal warm boot, which triggers `BOOT_ASSUMING_NO_CONFIGURATION_CHANGES` mode. **Fix:** JNE→JMP at BIOS 0x570CBB — the warm boot handler never triggers.

3. **PciHostBridge DXE**: In `BOOT_ASSUMING_NO_CONFIGURATION_CHANGES` mode, PciHostBridge skips full 64-bit MMIO allocation. The GPU's above-4G BAR isn't allocated, display initialization fails, black screen.

4. **CSM sub-options (post-CMOS reset)**: After CMOS reset, five hidden CSM settings default to Legacy mode: Launch CSM=Always, Boot option filter=UEFI+Legacy, Video/Storage OpROM=Legacy, PXE OpROM=Do not launch. Legacy Video OpROM + Above 4G Decoding = black screen at POST. **Fix:** `setup_var` commands to set all 5 CSM settings to UEFI-only + IFR default patches in build script (Step 3d).

### What We Tried (and Ruled Out)

| Attempt | Result | Why It Failed |
|---------|--------|---------------|
| SaInitPeim transplant (7010→9010) | Hard PEI hang | Incompatible despite same hardware |
| SaInitPeim JE→JMP patch | Made first boot worse | Skipped needed config write |
| SaInitPeim JE→NOP NOP patch | No effect on reboots | Not the root cause |
| Option B (MM64 removal, 4G OFF) | Won't work | Consumer GPUs need 4G Decoding on LGA1155 |
| PchS3Peim | Red herring | Was never modified by 7010 guide |

The breakthrough was finding WarmBootPei — a tiny module that most BIOS modders never look at.

---

## CMOS Reset Procedure (Dell 9010)

**Dell requires STANDBY POWER during reset!** This is different from most motherboards.

The 4 pins are TWO separate 2-pin headers in a 2x2 layout:
- **PSWD** (password) — default: jumper installed on pins 1-2
- **RTCRST** (RTC reset) — default: open (no jumper)

### Steps

1. Shut down, **unplug** power cord completely
2. Hold power button 15-20 seconds (drain capacitors)
3. Move jumper from PSWD to RTCRST
4. **Plug power cord BACK IN** (don't press power button)
5. Wait **10 seconds** — 5V standby rail signals CMOS to clear
6. **Unplug** cord again
7. Press power button once to drain residual
8. Move jumper back to PSWD position
9. Plug in, power on

**Notes:**
- Battery removal alone does NOT reliably clear NVRAM on 9010 (PCH has internal RTC)
- RTCRST clears ALL setup_var values, boot order, passwords — everything in CMOS/NVRAM
- RTCRST does NOT affect SPI flash contents (your mods are preserved)
- With the IFR patch, CMOS reset now defaults to 4G Decoding ON

---

## Recovery Checklist

Work through these in order. Stop when it boots.

### Level 1: Reseat Everything (most likely after physical contact)

- Power off, unplug power cord completely
- Reseat ALL 4 RAM sticks — pull each one fully out, reseat firmly until both clips click
- Reseat the GPU — pull it out, reseat firmly, make sure the PCIe latch clicks
- Check all power cables — 24-pin motherboard, 8-pin CPU, GPU power (if any)
- Check video cable connection (both ends)
- Plug power cord back in, power on

### Level 2: Minimal Boot Config

- Power off, unplug
- Remove GPU entirely
- Use ONLY 1 RAM stick in slot closest to CPU (DIMM1 / blue slot)
- Connect monitor to motherboard video output (VGA/DisplayPort on rear I/O)
- CMOS reset (see procedure above)
- Plug in, power on
- If this boots: power off, add RAM sticks one at a time, testing each
- Once all RAM works: add GPU back, move video cable to GPU

### Level 3: Extended Power Drain

- Power off, unplug power cord
- CMOS reset jumper to clear position
- Hold the front power button for 30 seconds
- Wait 5 full minutes with jumper in clear position
- Move jumper back to normal position
- Plug in, power on

### Level 4: Reflash (nuclear option)

If nothing above works and you suspect BIOS/NVRAM corruption:

```bash
cd C:\Users\clayi\Desktop\9010_BIOS_BACKUP\flashrom\flashrom-1.4

# 4MB chip (closest to you)
flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w spi1_rebar_write.bin

# 8MB chip
flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -w spi2_rebar_write.bin
```

Or to go fully stock, use the original backups.

### Diagnostic Beeps / LEDs

- Listen for beep codes on power-on (no RAM = continuous beeps, bad RAM = 3 beeps)
- Solid amber power LED = hardware fault; solid/blinking green = normal POST
- Fans spin but no display = POST-related, not dead hardware

---

## Building from Source

### Prerequisites

- **Perl 5** (included with Git for Windows, or install Strawberry Perl)
- **`xz`** command-line tool (for LZMA compression, included with Git for Windows)
- **CH341A USB SPI programmer** with 3.3V mod + SOIC-8 test clip
- **flashrom** (Windows build)
- **`BACKUP.BIN`** — your own stock BIOS dump (included in this repo as reference)

All other dependencies (`NvmExpressDxe.ffs`, `ReBarDxe.ffs`, `ReBarState.exe`) are included in this repo.

### Build Chain

The scripts form a dependency chain. Each tier includes everything from the previous tier:

```
BACKUP.BIN ──→ build_nvme_only.pl ──→ NVME_ONLY.BIN  (Tier 1)
BACKUP.BIN ──→ build_f1_bypass.pl ──→ F1_BYPASS.BIN   (Tier 2, self-contained)
F1_BYPASS.BIN ─→ build_rebar.pl ───→ REBAR.BIN        (Tier 3, needs Tier 2 output)
```

**For Tier 3 (ReBAR), build Tier 2 first:**

```bash
# Step 1: Dump your 8MB chip (preserves NVRAM)
flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -r spi2_preflight_read1.bin

# Step 2: Build F1 bypass (includes NVMe)
perl build_f1_bypass.pl

# Step 3: Build ReBAR (includes everything)
perl build_rebar.pl

# Step 4: Flash both chips
flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -w spi2_rebar_write.bin
flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w spi1_rebar_write.bin
```

### Post-Flash (Tier 3 / ReBAR only)

1. CMOS reset (IFR patches make 4G Decoding and CSM settings default correctly)
2. Boot modGRUBShell from USB:
   - Get modGRUBShell.efi from [datasone/grub-mod-setup_var](https://github.com/datasone/grub-mod-setup_var/releases)
   - Place as `EFI/Boot/bootx64.efi` on a FAT32 USB drive
   - **Option A:** Cold boot (full power cycle) + spam F12 → select USB
   - **Option B (no F12 needed):** From Windows, run:
     ```
     bcdedit /enum firmware    # find the USB drive's GUID
     bcdedit /set {fwbootmgr} bootsequence {guid-here}
     shutdown /s /t 0          # full shutdown (NOT restart)
     ```
     Then press the power button — it boots straight to USB.
3. Run setup_var commands (needed even with IFR patches if NVRAM existed before):
   ```
   setup_var 0x2 0x1       # Above 4G Decoding = Enabled
   setup_var 0xBDE 0x02    # Launch CSM = Never
   setup_var 0xBDF 0x02    # Boot option filter = UEFI only
   setup_var 0x2D 0x02     # PXE OpROM = UEFI only
   setup_var 0x2E 0x02     # Storage OpROM = UEFI only
   setup_var 0x2F 0x02     # Video OpROM = UEFI only
   ```
4. Type `reboot` → Boot to Windows
5. Run `ReBarState.exe`, set BAR size to `32` (unlimited)
6. Reboot, verify with GPU-Z (Advanced tab → Resizable BAR) or `nvidia-smi -q` (BAR1 = 8192 MiB)

### Repo Contents

| File | Size | Description |
|------|------|-------------|
| `BACKUP.BIN` | 6MB | Stock Dell OptiPlex 9010 A30 BIOS dump |
| `NvmExpressDxe.ffs` | 6KB | NVMe DXE driver (FFS format, ready to inject) |
| `ReBarDxe.ffs` | 2.5KB | ReBAR DXE driver from [xCuri0/ReBarUEFI v0.3](https://github.com/xCuri0/ReBarUEFI/releases) |
| `ReBarState.exe` | 20KB | Windows utility to set ReBAR size in NVRAM |
| `build_nvme_only.pl` | — | Tier 1: NVMe boot only |
| `build_f1_bypass.pl` | — | Tier 2: NVMe + F1 fan error bypass |
| `build_rebar.pl` | — | Tier 3: Full ReBAR (all patches) |

---

## FV1 Key Modules

| Module | GUID | FV1 Offset | Size |
|--------|------|------------|------|
| PciBus | 3C1DE39F-D207-408A-AACC-731CFB7F1DD7 | 0x04DA24 | 54,681 |
| PciHostBridge | 8D6756B9-E55E-4D6A-A3A5-5E4D72DDF772 | 0x106FAC | 11,309 |
| Runtime | CBC59C4A-383A-41EB-A8EE-4498AEA567E4 | 0x033B6C | 89,825 |
| AmiBoardInfo | 9F3A0016-AE55-4288-829D-D22FD344C347 | 0x05AFC4 | 46,361 |
| Setup | 899407D7-99FE-43D8-9A21-79EC328CAC21 | 0x3F2E54 | 426,485 |

## FV_BB Key PEI Modules

| Module | GUID | BIOS Offset | Size |
|--------|------|-------------|------|
| MemoryInit | 3B42EF57-... | 0x500048 | 160,358 |
| SBPEI | C1FBD624-... | 0x5443F0 | 18,904 |
| SaInitPeim | FD236AE7-...A811 | 0x553A10 | 18,818 (stock, unmodified) |
| WarmBootPei | B178E5AA-0876-420A-B40F-E39B4E6EE05B | 0x570A00 | 912 (JNE→JMP patch) |

---

## Gotchas & Lessons Learned

1. **The LZMA stream spans both chips.** The compressed FV2 starts at BIOS offset `0x1D6AC9` (8MB chip) and ends at `0x2E6BB6` (4MB chip). Flashing only one chip = corrupted LZMA = bricked display output.

2. **xz writes the wrong LZMA header.** When recompressing with `xz --format=lzma`, it writes `0xFFFFFFFFFFFFFFFF` for the uncompressed size (stream mode). AMI's UEFI LZMA decoder needs the exact uncompressed size. The build script restores the original 13-byte LZMA header after recompression.

3. **Use a fresh 8MB chip dump as the base.** The 8MB chip contains NVRAM (boot order, AHCI/RAID mode, etc.). If you use an old dump, you'll overwrite your current settings.

4. **FFS checksums must be updated.** Any FFS with attrs bit 0x40 has a data checksum at header byte 17 that must be recalculated after modification.

5. **CH341A voltage mod is essential.** The stock CH341A outputs 5V on its data lines but these flash chips are 3.3V. You must do the 3.3V mod or use a level shifter.

6. **Always read twice before writing.** If two consecutive reads don't match byte-for-byte, your clip connection is bad. Plug the CH341A directly into the computer — USB hubs cause disconnections.

7. **Dell CMOS reset requires standby power** (plugged in but off) during RTCRST.

8. **E4GM is always zero on Dell 9010** — DSDT patches inside `ElseIf(E4GM)` are dead code without the E4GM→OSYS fix.

9. **WarmBootPei is the root cause of warm reboot black screen** — disabling its `_WB_` check forces full PCI enumeration on every boot.

10. **IFR default changes only take effect after NVRAM wipe** — existing NVRAM values take precedence.

11. **7010 and 9010 share the SAME physical motherboard** (confirmed by Libreboot/Dasharo). Stock DXE modules are byte-for-byte identical. Patched modules from the 7010 guide work on the 9010 without modification.

12. **SaInitPeim transplant from 7010 causes hard PEI hang** despite identical hardware. Not the root cause — avoid this.

13. **Dell BIOS .exe files use PFS format** — extract with biosutilities DellPfsExtract.

14. **UEFITool can silently displace fixed-location modules** — always inject into FREE SPACE.

15. **CSM sub-options (Video/Storage OpROM) default to Legacy after CMOS reset** — not just "Launch CSM", ALL sub-options must be UEFI-only.

16. **CSM ON + Above 4G Decoding ON = black screen** (POST level failure) — Legacy Video OpROM conflicts with 64-bit MMIO.

17. **All CSM settings are in VarStore 2**, accessible via `setup_var` at offsets 0x2D-0x2F (OpROM policies), 0xBDE (Launch CSM), 0xBDF (Boot option filter).

18. **"Enable Legacy Option ROMs = Disabled" via IFR defaults BRICKS the system** — no POST, no display, no HDD activity. Dell firmware apparently needs this enabled even in UEFI-only mode for GPU option ROM to load. Do NOT bake this into IFR defaults.

19. **The "Setup" UEFI variable is Boot Services only (NV+BS, no Runtime).** You cannot read or modify it from Windows using `GetFirmwareEnvironmentVariable`. The `setup_var` command only works from the UEFI pre-boot environment (modGRUBShell). However, you can use `bcdedit /set {fwbootmgr} bootsequence` from Windows to boot the USB drive without needing F12.

20. **Follow the 4-step flash procedure**: detect chip → read backup → write+verify → read again. Never skip the pre-write backup or post-write verification read.

---

## Tools & References

- [flashrom](https://flashrom.org/) - Open-source flash programmer
- [Zadig](https://zadig.akeo.ie/) - USB driver installer (needed for CH341A on Windows)
- [xCuri0/ReBarUEFI](https://github.com/xCuri0/ReBarUEFI) - ReBAR DXE driver + ReBarState utility
- [Dell 7010 ReBAR guide](https://github.com/jrdoughty/Dell-7010-rebar-guide) - Reference (same Q77 chipset)
- [DSDT Patching wiki](https://github.com/xCuri0/ReBarUEFI/wiki/DSDT-Patching) - xCuri0's DSDT docs
- [Common issues](https://github.com/xCuri0/ReBarUEFI/wiki/Common-issues-(and-fixes)) - ReBarUEFI troubleshooting

## Credits

- Reverse engineering and build automation: [Claude Code](https://claude.com/claude-code) (Anthropic)
- DellErrorLogConfig driver identification: Win-Raid community research on Dell 7020
- NVMe mod technique: [Tachytelic guide](https://tachytelic.net/2021/12/dell-optiplex-7010-pcie-nvme/)
- ReBAR tooling: [xCuri0/ReBarUEFI](https://github.com/xCuri0/ReBarUEFI)
