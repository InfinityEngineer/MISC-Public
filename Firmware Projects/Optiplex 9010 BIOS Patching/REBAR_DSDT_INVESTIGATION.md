# Dell OptiPlex 9010 - ReBAR DSDT Investigation (RESOLVED)

## Status: SOLVED

The warm reboot black screen issue is fully resolved. The root cause was a combination of:
1. **Dead E4GM gate in DSDT** — Dell never wired up E4GM on the 9010
2. **WarmBootPei module** — triggered abbreviated boot path on warm reboots, skipping 64-bit MMIO allocation

Both issues are now patched in `REBAR.BIN`. See `README.md` for full details.

## DSDT Patches Applied

Three patches were applied to the DSDT inside AmiBoardInfo (FV1 0x05B9E1):

### Patch C: E4GM → OSYS (the critical fix)
- **Location:** DSDT+0x1973
- **Problem:** `ElseIf(E4GM)` — E4GM is always zero on Dell 9010, making the 64-bit MMIO resource declaration dead code
- **Fix:** Changed to `ElseIf(OSYS)` — OSYS (OS version year) is always non-zero on modern Windows
- **AML bytes:** `45 34 47 4D` → `4F 53 59 53`

### Patch A: Expand MMIO ceiling
- **Location:** DSDT+0x199B
- **Problem:** `Store(0x0000000400000000, M2LN)` — fixed 16GB length
- **Fix:** `Store(0x0000000FFFFFFFFF, M2MX)` — 36-bit / 64GB ceiling (max for Ivy Bridge)

### Patch B: Reverse calculation
- **Location:** DSDT+0x19CF
- **Problem:** `M2MX = (M2MN + M2LN) - 1` — derived max from length
- **Fix:** `M2LN = (M2MX - M2MN) + 1` — derived length from max

## WarmBootPei Patch

- **Module:** WarmBootPei (GUID B178E5AA-0876-420A-B40F-E39B4E6EE05B)
- **Location:** BIOS 0x570A00 (912 bytes total)
- **Problem:** Checks for `_WB_` (Warm Boot) marker in BIOS data area. When found, calls PPI that triggers `BOOT_ASSUMING_NO_CONFIGURATION_CHANGES`, which causes PciHostBridge DXE to skip 64-bit MMIO allocation.
- **Fix:** JNE → JMP at BIOS 0x570CBB (`75 12` → `EB 12`)
- **Side effect:** Boot is ~2-3 seconds slower (full PCI enumeration every time) — acceptable tradeoff

## Key Insight

The Dell 7010 guide only needed DSDT patches because the 7010 doesn't have WarmBootPei (or it works differently). The 9010 has this extra module that broke warm reboots when 64-bit MMIO was enabled. This is why the 7010 guide didn't work as-is on the 9010.
