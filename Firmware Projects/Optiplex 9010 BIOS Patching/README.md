# Dell OptiPlex 9010 MT - BIOS Patching

Patches for the Dell OptiPlex 9010 MT (Mini Tower) BIOS, version A30.

These were developed with Claude Code (Anthropic's CLI agent) doing binary analysis, reverse engineering, and build scripting. No GUI tools required - everything is done with Perl scripts and command-line utilities.

## Hardware Setup

- **Dell OptiPlex 9010 MT** (Ivy Bridge / Q77 chipset)
- **CH341A USB SPI programmer** (3.3V mod required!)
- **SOIC-8 test clip** for in-circuit flashing

### Flash Chip Layout

The 9010 has **two SPI flash chips**:

| Chip | Part Number | Size | Contents |
|------|-------------|------|----------|
| SPI_1 | MX25L3206E | 4MB | Last 4MB of BIOS (Main FV drivers, boot block) |
| SPI_2/3 | MX25L6406E | 8MB | Flash descriptor + GbE + Intel ME + first 2MB of BIOS |

The 6MB BIOS region spans both chips:
```
BIOS[0x000000-0x1FFFFF] -> 8MB chip at offset 0x600000
BIOS[0x200000-0x5FFFFF] -> 4MB chip at offset 0x000000
```

**This matters!** Some modifications (like the F1 bypass) involve compressed data that crosses the chip boundary. You must flash both chips or you'll get a corrupted LZMA stream and a bricked machine.

## Stock BIOS

`BACKUP.BIN` - Unmodified Dell OptiPlex 9010 A30 BIOS dump (6MB). This is the complete BIOS region extracted from both flash chips.

## Mods

### F1 Fan Failure Bypass (`build_f1_bypass.pl`)

**Problem:** Non-stock fans (or missing Dell fan headers) trigger "Alert! Previous fan failure" at every POST, requiring you to press F1 to continue. This blocks unattended reboots (Windows Updates hang at the F1 prompt).

**Solution:** Patches the `DellErrorLogConfig` DXE driver (GUID `038CE287-B806-45B6-A819-514DAF4B91B9`) to return `EFI_SUCCESS` immediately, preventing the error display routine from ever executing.

**How it works:**
1. Extracts the LZMA-compressed firmware volume (FV2) containing 183 DXE drivers
2. Locates the DellErrorLogConfig FFS file at FV2 offset `0x008E7C`
3. Patches the PE entry point: `48 89 5C` -> `33 C0 C3` (xor eax, eax; ret)
4. Zeros dead `.text` and `.data` sections (34KB of error strings) to improve compression
5. Recompresses with LZMA, fixes the header (xz bug workaround), updates FFS checksums
6. Generates write images for both flash chips

**Prerequisites:**
- Perl 5
- `xz` command-line tool (for LZMA compression)
- `NVME_ONLY.BIN` or stock `BACKUP.BIN` as the base image
- A fresh dump of your 8MB chip (to preserve your NVRAM settings)

**Usage:**
```bash
# Read your 8MB chip first (preserves your NVRAM/boot settings)
flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -r my_8mb_dump.bin

# Build
perl build_f1_bypass.pl my_8mb_dump.bin

# Flash both chips
flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -w spi2_f1bypass_write.bin
flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w spi1_f1bypass_write.bin
```

## Gotchas & Lessons Learned

1. **The LZMA stream spans both chips.** The compressed FV2 starts at BIOS offset `0x1D6AC9` (8MB chip) and ends at `0x2E6BB6` (4MB chip). Flashing only one chip = corrupted LZMA = bricked display output.

2. **xz writes the wrong LZMA header.** When recompressing with `xz --format=lzma`, it writes `0xFFFFFFFFFFFFFFFF` for the uncompressed size (stream mode). AMI's UEFI LZMA decoder needs the exact uncompressed size to allocate its output buffer. The build script fixes this by restoring the original 13-byte LZMA header after recompression.

3. **Use a fresh 8MB chip dump as the base.** The 8MB chip contains NVRAM (boot order, AHCI/RAID mode, etc.). If you use an old dump, you'll overwrite your current settings and may get "no boot device found" on first boot.

4. **FFS checksums must be updated.** Both the inner FFS (DellErrorLogConfig) and outer FFS (the compressed FV2 container) have data checksums that must be recalculated after modification.

5. **CH341A voltage mod is essential.** The stock CH341A outputs 5V on its data lines but these flash chips are 3.3V. You must do the 3.3V mod or use a level shifter.

6. **Always read twice before writing.** If two consecutive reads don't match byte-for-byte, your clip connection is bad.

## Recovery

If anything goes wrong, flash your original chip dumps back:
```bash
# 8MB chip
flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -w your_8mb_backup.bin
# 4MB chip
flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w your_4mb_backup.bin
```

As long as you have your original chip dumps and a working CH341A, the machine is always recoverable.

## Tools

- [flashrom](https://flashrom.org/) - Open-source flash programmer
- [Zadig](https://zadig.akeo.ie/) - USB driver installer (needed for CH341A on Windows)
- `xz` - LZMA compression (included with Git for Windows, or install via package manager)

## Credits

- Reverse engineering and build automation: [Claude Code](https://claude.com/claude-code) (Anthropic)
- DellErrorLogConfig driver identification: Win-Raid community research on Dell 7020
- NVMe mod technique: [Tachytelic guide](https://tachytelic.net/2021/12/dell-optiplex-7010-pcie-nvme/)
