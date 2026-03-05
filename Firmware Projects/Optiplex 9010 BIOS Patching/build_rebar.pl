#!/usr/bin/perl
# build_rebar.pl - Build Dell OptiPlex 9010 BIOS with ReBAR support
#
# Applies 7 ReBAR hex patches (8 replacements) + DSDT patch to compressed FV1
# and inserts ReBarDxe.ffs into Main FV free space.
#
# Base: F1_BYPASS_V4.BIN (NVMe + F1 bypass already present)
# Output: REBAR.BIN (6MB BIOS), spi1_rebar_write.bin (4MB chip),
#         spi2_rebar_write.bin (8MB chip, requires fresh 8MB dump)
#
# === PATCHES APPLIED ===
# FV1 (compressed, 8MB chip):
#   1. PciHostBridge: Remove <4GB BAR size limit (Sandy/Ivy Bridge)
#   3. PciHostBridge: Fix AddMemorySpace call (MMIO ceiling 16GB -> 64GB)
#   4a. PciHostBridge: Remove 4GB PciRootBridgeIo.Mem limit (v1)
#   4b. PciHostBridge: Remove 4GB PciRootBridgeIo.Mem limit (v2)
#   5. PciBus: Remove <16GB BAR limit
#   8. Runtime: Remove 4GB CpuIo2 limit (2 instances)
#   9. PciBus (IvyUSB3): Add Intel 7 Series XHCI to 64-bit blacklist
#   DSDT: Bypass E4GM gate + expand 64-bit MMIO to 36-bit ceiling (in AmiBoardInfo)
#   IFR: Change "Above 4G Decoding" default from Disabled to Enabled (in Setup)
#   IFR: Change CSM defaults: Launch CSM=Never, OpROMs=UEFI only (in Setup)
# FV_BB (uncompressed, 4MB chip):
#   WarmBootPei: Disable warm boot detection (skip _WB_ marker check)
#
# === POST-FLASH STEPS ===
# 1. CMOS reset (IFR defaults: 4G=ON, CSM=Never, OpROMs=UEFI only)
# 2. Boot modGRUBShell, run: setup_var 0x2 0x1 (enable 4G in NVRAM)
#    Also run CSM setup_vars if needed (see NEXT_STEPS.md for full list)
# 3. Boot Windows, run ReBarState.exe, set BAR size to 32
# 4. Reboot, verify with GPU-Z
#
# === CMOS RECOVERY ===
# If no display: Dell CMOS reset requires STANDBY POWER during RTCRST.
# 1. Shut down, unplug cord, hold power 15s
# 2. Move jumper from PSWD to RTCRST (adjacent 2-pin header)
# 3. PLUG CORD BACK IN (don't press power), wait 10s
# 4. Unplug cord, press power once, move jumper back to PSWD
# 5. Plug in, power on

use strict;
use warnings;

my $base_file      = "F1_BYPASS_V4.BIN";
my $rebar_ffs_file = "ReBarDxe.ffs";
my $spi2_dump_file = "spi2_preflight_read1.bin";  # Fresh 8MB dump (do a new read before flashing!)
my $output_bios    = "REBAR.BIN";
my $output_4mb     = "spi1_rebar_write.bin";
my $output_8mb     = "spi2_rebar_write.bin";

# --- Constants ---
my $BIOS_SIZE       = 6291456;       # 6MB
my $FV1_FFS_OFF     = 0x050048;      # FV1 outer FFS in BIOS
my $FV1_LZMA_OFF    = 0x050069;      # LZMA data start
my $FV1_LZMA_SIZE   = 1600057;       # Original compressed size
my $FV1_DECOMP_SIZE = 5259304;       # Expected decompressed size
my $NVME_FFS_OFF    = 0x3564B0;      # NVMe driver FFS
my $NVME_FFS_SIZE   = 6024;          # NVMe driver size
my $REBAR_INSERT_OFF = 0x357C38;     # After NVMe (0x3564B0 + 6024, 8-byte aligned)
my $FREE_SPACE_END  = 0x500000;      # Start of FV_BB
my $SPI2_BIOS_OFF   = 0x600000;      # BIOS region offset in 8MB chip

# SaInitPeim transplant (7010 -> 9010)
my $SAINITPEIM_OFF   = 0x553A10;     # SaInitPeim FFS offset in 9010 BIOS
my $SAINITPEIM_SIZE  = 18818;        # 0x4982 - 9010's total FFS size
my $SA_NEXT_MODULE   = 0x558398;     # Next FFS after SaInitPeim in 9010
my $STOCK_7010_BIOS  = "7010_stock/O7010A29_BIOS.bin";
my $SA7010_OFF       = 0x553A50;     # SaInitPeim FFS offset in 7010 BIOS
my $SA7010_SIZE      = 18626;        # 0x48C2 - 7010's total FFS size
my $SAINITPEIM_GUID  = "\xE7\x6A\x23\xFD\x91\x07\xC4\x48\xB2\x9E\x29\xBD\xEE\xE1\xA8\x11";

# FFS module locations in decompressed FV1
my %MODULES = (
    PciBus        => { off => 0x04DA24, size => 54681  },
    PciHostBridge => { off => 0x106FAC, size => 11309  },
    Runtime       => { off => 0x033B6C, size => 89825  },
    AmiBoardInfo  => { off => 0x05AFC4, size => 46361  },
    Setup         => { off => 0x3F2E54, size => 426485 },
);

# DSDT location within FV1 (inside AmiBoardInfo FFS)
my $DSDT_FV1_OFF   = 0x05B9E1;   # DSDT ACPI table start in FV1
my $DSDT_SIZE      = 41174;       # DSDT table size
my $DSDT_CK_OFF    = 9;           # Checksum byte offset in DSDT header

# --- Patch definitions ---
# Each: [name, module, find_hex, replace_hex]
my @PATCHES = (
    ["PciHostBridge: Remove <4GB BAR limit",
     "PciHostBridge",
     "77B6488B0F493BCF73AE48FFC1E81BFFFFFF488B1748FFC8483BD0759B",
     "669066909066909066906690909090669090488B176690906690906690"],

    ["PciHostBridge: Fix AddMemorySpace",
     "PciHostBridge",
     "040000004823C1483BC2480F47D04C2BC27411",
     "100000004823C1483BC2480F47D04C2BC26690"],

    ["PciHostBridge: Remove 4GB PciRootBridgeIo v1",
     "PciHostBridge",
     "493B4C24C0771B",
     "66906690669090"],

    ["PciHostBridge: Remove 4GB PciRootBridgeIo v2",
     "PciHostBridge",
     "493B4C24C0771C",
     "66906690669090"],

    ["PciBus: Remove <16GB BAR limit",
     "PciBus",
     "B8FFFFFFFF030000004C3B",
     "B8FFFFFFFFFFFFFF004C3B"],

    ["Runtime: Remove 4GB CpuIo2 limit",
     "Runtime",
     "B9FFFFFFFF490FAFC14903C0483BC1776C",
     "6690669090490FAFC14903C06690906690"],

    ["PciBus (IvyUSB3): XHCI 64-bit blacklist",
     "PciBus",
     "DE10D301FFFF00000B00000014",
     "8680311EFFFF00000B00000010"],
);

# ===================================================================
# Step 1: Read base BIOS
# ===================================================================
print "=" x 60, "\n";
print "ReBAR Build for Dell OptiPlex 9010\n";
print "=" x 60, "\n\n";

print "Reading $base_file...\n";
open my $fh, "<:raw", $base_file or die "Cannot open $base_file: $!\n";
my $bios;
read($fh, $bios, -s $base_file);
close $fh;
die "Expected ${BIOS_SIZE}-byte BIOS, got " . length($bios) unless length($bios) == $BIOS_SIZE;

# ===================================================================
# Step 2: Extract and decompress FV1
# ===================================================================
print "\nExtracting FV1 LZMA ($FV1_LZMA_SIZE bytes at 0x050069)...\n";
my $orig_lzma = substr($bios, $FV1_LZMA_OFF, $FV1_LZMA_SIZE);
my $orig_lzma_header = substr($orig_lzma, 0, 13);  # Save for later
printf "  LZMA header: %s\n", join(" ", map { sprintf "%02X", ord(substr($orig_lzma_header, $_, 1)) } 0..12);

open my $tmp, ">:raw", "tmp_fv1.lzma" or die $!;
print $tmp $orig_lzma;
close $tmp;

system("xz --format=lzma -dk -f tmp_fv1.lzma") == 0
    or die "LZMA decompression failed!\n";

open $fh, "<:raw", "tmp_fv1" or die $!;
my $fv1;
read($fh, $fv1, -s "tmp_fv1");
close $fh;

die sprintf("Decompressed FV1 size mismatch: expected %d, got %d",
    $FV1_DECOMP_SIZE, length($fv1)) unless length($fv1) == $FV1_DECOMP_SIZE;
printf "  Decompressed: %d bytes (OK)\n", length($fv1);

# ===================================================================
# Step 3: Apply hex patches
# ===================================================================
print "\nApplying ReBAR patches...\n";
my %modified_modules;  # Track which modules were modified
my $patch_count = 0;

for my $p (@PATCHES) {
    my ($name, $mod, $find_hex, $repl_hex) = @$p;
    my $find_bytes = pack("H*", $find_hex);
    my $repl_bytes = pack("H*", $repl_hex);

    die "Find/replace length mismatch for $name" unless length($find_bytes) == length($repl_bytes);

    my $mod_off  = $MODULES{$mod}{off};
    my $mod_size = $MODULES{$mod}{size};
    my $mod_data = substr($fv1, $mod_off, $mod_size);

    # Find all occurrences within the module
    my @positions;
    my $search_pos = 0;
    while ((my $pos = index($mod_data, $find_bytes, $search_pos)) >= 0) {
        push @positions, $pos;
        $search_pos = $pos + 1;
    }

    if (@positions == 0) {
        die "FATAL: Pattern not found for: $name\n";
    }

    for my $pos (@positions) {
        my $abs_off = $mod_off + $pos;
        substr($fv1, $abs_off, length($repl_bytes), $repl_bytes);
        $patch_count++;
        printf "  [%d] %-45s @ fv1 0x%06X\n", $patch_count, $name, $abs_off;
    }

    $modified_modules{$mod} = 1;
}

printf "\nApplied %d patches across %d modules\n", $patch_count, scalar keys %modified_modules;
die "Expected 8 patch applications (CpuIo2 has 2)" unless $patch_count == 8;

# ===================================================================
# Step 3b: Apply DSDT patch (inside AmiBoardInfo)
# ===================================================================
# The DSDT declares a 64-bit PCI memory resource with a fixed 16GB length.
# Sandy/Ivy Bridge needs this expanded to the full 36-bit (64GB) ceiling
# so the OS can allocate above-4G BARs (required by xCuri0/ReBarUEFI).
#
# Change 1: M2LN = 0x0000000400000000 (16GB)  ->  M2MX = 0x0000000FFFFFFFFF (64GB ceiling)
# Change 2: M2MX = (M2MN + M2LN) - 1          ->  M2LN = (M2MX - M2MN) + 1
print "\nApplying DSDT patch (AmiBoardInfo)...\n";

# Verify DSDT signature
die "DSDT signature not found at expected offset"
    unless substr($fv1, $DSDT_FV1_OFF, 4) eq "DSDT";

# Verify DSDT size matches
my $dsdt_len = unpack("V", substr($fv1, $DSDT_FV1_OFF + 4, 4));
die "DSDT size mismatch: expected $DSDT_SIZE, got $dsdt_len" unless $dsdt_len == $DSDT_SIZE;

# Patch C: ElseIf(E4GM) -> ElseIf(OSYS) — bypass dead E4GM gate
# AML at DSDT+0x1973:
#   Old: 45 34 47 4D  ("E4GM" — Enable 4G Memory flag, always zero on Dell 9010)
#   New: 4F 53 59 53  ("OSYS" — OS version year, always non-zero on modern Windows)
# E4GM is a runtime validation flag that Dell never wired up on the 9010.
# Without this fix, the ElseIf branch (containing Patches A+B) never executes.
# OSYS is guaranteed > 0x07D3 by the time we reach this point (outer If checks it).
my $dsdt_pc_off = $DSDT_FV1_OFF + 0x1973;
my $dsdt_pc_old = "\x45\x34\x47\x4D";  # E4GM
my $dsdt_pc_new = "\x4F\x53\x59\x53";  # OSYS

die "DSDT Patch C: E4GM not found at expected offset"
    unless substr($fv1, $dsdt_pc_off, length($dsdt_pc_old)) eq $dsdt_pc_old;
substr($fv1, $dsdt_pc_off, length($dsdt_pc_new), $dsdt_pc_new);
printf "  [C] ElseIf(E4GM) -> ElseIf(OSYS)          @ fv1 0x%06X\n", $dsdt_pc_off;

# Patch A: Store(16GB, M2LN) -> Store(0xFFFFFFFFF, M2MX)
# AML at DSDT+0x199B:
#   Old: 70 0E 00 00 00 00 04 00 00 00 4D 32 4C 4E  (Store QWord 16GB to M2LN)
#   New: 70 0E FF FF FF FF 0F 00 00 00 4D 32 4D 58  (Store QWord 64GB-1 to M2MX)
my $dsdt_p1_off = $DSDT_FV1_OFF + 0x199B;
my $dsdt_p1_old = "\x70\x0E\x00\x00\x00\x00\x04\x00\x00\x00\x4D\x32\x4C\x4E";
my $dsdt_p1_new = "\x70\x0E\xFF\xFF\xFF\xFF\x0F\x00\x00\x00\x4D\x32\x4D\x58";

die "DSDT Patch A: pattern not found at expected offset"
    unless substr($fv1, $dsdt_p1_off, length($dsdt_p1_old)) eq $dsdt_p1_old;
substr($fv1, $dsdt_p1_off, length($dsdt_p1_new), $dsdt_p1_new);
printf "  [A] M2LN=16GB -> M2MX=0xFFFFFFFFF     @ fv1 0x%06X\n", $dsdt_p1_off;

# Patch B: Subtract(Add(M2MN,M2LN,0),1,M2MX) -> Add(Subtract(M2MX,M2MN,0),1,M2LN)
# AML at DSDT+0x19CF:
#   Old: 74 72 4D324D4E 4D324C4E 00 01 4D324D58  (M2MX = (M2MN+M2LN)-1)
#   New: 72 74 4D324D58 4D324D4E 00 01 4D324C4E  (M2LN = (M2MX-M2MN)+1)
my $dsdt_p2_off = $DSDT_FV1_OFF + 0x19CF;
my $dsdt_p2_old = "\x74\x72\x4D\x32\x4D\x4E\x4D\x32\x4C\x4E\x00\x01\x4D\x32\x4D\x58";
my $dsdt_p2_new = "\x72\x74\x4D\x32\x4D\x58\x4D\x32\x4D\x4E\x00\x01\x4D\x32\x4C\x4E";

die "DSDT Patch B: pattern not found at expected offset"
    unless substr($fv1, $dsdt_p2_off, length($dsdt_p2_old)) eq $dsdt_p2_old;
substr($fv1, $dsdt_p2_off, length($dsdt_p2_new), $dsdt_p2_new);
printf "  [B] M2MX=(M2MN+M2LN)-1 -> M2LN=(M2MX-M2MN)+1 @ fv1 0x%06X\n", $dsdt_p2_off;

# Fix DSDT ACPI table checksum (byte 9 of header)
# Zero checksum byte, sum all bytes, new checksum = (256 - sum) & 0xFF
my $old_dsdt_ck = ord(substr($fv1, $DSDT_FV1_OFF + $DSDT_CK_OFF, 1));
substr($fv1, $DSDT_FV1_OFF + $DSDT_CK_OFF, 1, chr(0x00));
my $dsdt_sum = 0;
for my $i (0 .. $DSDT_SIZE - 1) {
    $dsdt_sum = ($dsdt_sum + ord(substr($fv1, $DSDT_FV1_OFF + $i, 1))) & 0xFF;
}
my $new_dsdt_ck = (256 - $dsdt_sum) & 0xFF;
substr($fv1, $DSDT_FV1_OFF + $DSDT_CK_OFF, 1, chr($new_dsdt_ck));
printf "  DSDT checksum: 0x%02X -> 0x%02X\n", $old_dsdt_ck, $new_dsdt_ck;

$modified_modules{AmiBoardInfo} = 1;

# ===================================================================
# Step 3c: Change "Above 4G Decoding" IFR default to Enabled (in Setup)
# ===================================================================
# The Setup module contains IFR (Internal Forms Representation) data with a
# CheckBox for "Above 4G Decoding" at VarOffset 0x0002. The Flags byte
# controls the default value (0x00=Disabled, 0x01=Enabled).
# Changing this means CMOS reset defaults to 4G Decoding ON — no need for
# modGRUBShell setup_var anymore.
#
# IFR CheckBox at fv1 0x45ACCA (inside Setup FFS at 0x3F2E54):
#   06 8E 00 00 00 00 AA 03 24 00 02 00 [00] 00
#                                              ^^ Flags byte at fv1+12
print "\nApplying IFR default patch (Setup)...\n";

my $ifr_cb_off = 0x45ACCA;  # CheckBox opcode in decompressed FV1
my $ifr_flags_off = $ifr_cb_off + 12;  # Flags byte within CheckBox

# Verify the CheckBox structure
die "IFR: CheckBox opcode not 0x06" unless ord(substr($fv1, $ifr_cb_off, 1)) == 0x06;
die "IFR: VarOffset not 0x0002"
    unless unpack("v", substr($fv1, $ifr_cb_off + 10, 2)) == 0x0002;
die "IFR: Flags already set"
    unless ord(substr($fv1, $ifr_flags_off, 1)) == 0x00;

substr($fv1, $ifr_flags_off, 1, chr(0x01));
printf "  [IFR] Above 4G Decoding default: Disabled -> Enabled @ fv1 0x%06X\n", $ifr_flags_off;

$modified_modules{Setup} = 1;

# ===================================================================
# Step 3d: Change CSM IFR defaults to UEFI-only (in Setup)
# ===================================================================
# After CMOS reset, CSM sub-options default to Legacy mode which conflicts
# with Above 4G Decoding (black screen). Dell's F2 menu only exposes
# "Enable Legacy Option ROMs" and "Boot List Option" — the sub-options
# (Video/Storage/PXE OpROM policies) are hidden and stay at Legacy defaults.
#
# All settings are in VarStore 2 (CSMCORE). Confirmed accessible via setup_var.
#
# Patch each OneOf by moving the DEFAULT flag (bit 0x10) from the old default
# option to the desired option. Also clear MFG_DEFAULT (bit 0x20) where present.
print "\nApplying CSM IFR default patches (Setup)...\n";

my @csm_patches = (
    # [name, remove_default_fv1_off, old_flags, new_flags, add_default_fv1_off, old_flags2, new_flags2]
    ["Launch CSM: Always->Never",
     0x456FB3, 0x30, 0x20,   # Remove DEFAULT from "Always" (val=0x00)
     0x456FC1, 0x00, 0x10],  # Add DEFAULT to "Never" (val=0x02)

    ["Boot option filter: UEFI+Legacy->UEFI only",
     0x456FFF, 0x30, 0x20,   # Remove DEFAULT from "UEFI and Legacy" (val=0x00)
     0x45701B, 0x00, 0x10],  # Add DEFAULT to "UEFI only" (val=0x02)

    ["PXE OpROM: Do not launch->UEFI only",
     0x457051, 0x30, 0x20,   # Remove DEFAULT from "Do not launch" (val=0x00)
     0x45705F, 0x00, 0x10],  # Add DEFAULT to "UEFI only" (val=0x02)

    ["Storage OpROM: Legacy->UEFI only",
     0x4570BF, 0x30, 0x20,   # Remove DEFAULT from "Legacy only" (val=0x01)
     0x4570B1, 0x00, 0x10],  # Add DEFAULT to "UEFI only" (val=0x02)

    ["Video OpROM: Legacy->UEFI only",
     0x457111, 0x30, 0x20,   # Remove DEFAULT from "Legacy only" (val=0x01)
     0x457103, 0x00, 0x10],  # Add DEFAULT to "UEFI only" (val=0x02)
);

for my $p (@csm_patches) {
    my ($name, $rm_off, $rm_old, $rm_new, $add_off, $add_old, $add_new) = @$p;

    # Verify and patch: remove DEFAULT from old default
    my $cur_rm = ord(substr($fv1, $rm_off, 1));
    die "CSM IFR ($name): expected flags 0x${\sprintf('%02X',$rm_old)} at remove offset, got 0x${\sprintf('%02X',$cur_rm)}"
        unless $cur_rm == $rm_old;
    substr($fv1, $rm_off, 1, chr($rm_new));

    # Verify and patch: add DEFAULT to new default
    my $cur_add = ord(substr($fv1, $add_off, 1));
    die "CSM IFR ($name): expected flags 0x${\sprintf('%02X',$add_old)} at add offset, got 0x${\sprintf('%02X',$cur_add)}"
        unless $cur_add == $add_old;
    substr($fv1, $add_off, 1, chr($add_new));

    printf "  [CSM] %-45s @ fv1 0x%06X / 0x%06X\n", $name, $rm_off, $add_off;
}

# No need to mark a new module — these are all inside Setup which is already marked

# ===================================================================
# Step 4: Fix FFS checksums for modified modules
# ===================================================================
print "\nFixing FFS checksums...\n";
for my $mod (sort keys %modified_modules) {
    my $mod_off  = $MODULES{$mod}{off};
    my $mod_size = $MODULES{$mod}{size};

    # Verify attrs bit 0x40 (checksum enabled)
    my $attrs = ord(substr($fv1, $mod_off + 19, 1));
    die "Module $mod does not have checksum flag" unless $attrs & 0x40;

    # Zero the checksum byte before calculating
    my $old_ck = ord(substr($fv1, $mod_off + 17, 1));
    substr($fv1, $mod_off + 17, 1, chr(0x00));

    # Calculate data checksum (bytes 24 through end of FFS)
    my $data_sum = 0;
    for my $i (24 .. $mod_size - 1) {
        $data_sum = ($data_sum + ord(substr($fv1, $mod_off + $i, 1))) & 0xFF;
    }
    my $new_ck = (256 - $data_sum) & 0xFF;
    substr($fv1, $mod_off + 17, 1, chr($new_ck));

    printf "  %-15s checksum: 0x%02X -> 0x%02X\n", $mod, $old_ck, $new_ck;
}

# ===================================================================
# Step 5: Recompress FV1
# ===================================================================
print "\nRecompressing FV1...\n";
open $tmp, ">:raw", "tmp_fv1_rebar" or die $!;
print $tmp $fv1;
close $tmp;

unlink "tmp_fv1_rebar.lzma";
system("xz --format=lzma --lzma1=dict=8MiB,lc=3,lp=0,pb=2 -k tmp_fv1_rebar") == 0
    or die "LZMA compression failed!\n";

open $fh, "<:raw", "tmp_fv1_rebar.lzma" or die $!;
my $new_lzma;
read($fh, $new_lzma, -s "tmp_fv1_rebar.lzma");
close $fh;

my $new_lzma_size = length($new_lzma);
printf "  New LZMA: %d bytes (original: %d, delta: %+d)\n",
    $new_lzma_size, $FV1_LZMA_SIZE, $new_lzma_size - $FV1_LZMA_SIZE;

if ($new_lzma_size > $FV1_LZMA_SIZE) {
    die sprintf("FATAL: Recompressed LZMA is %d bytes LARGER than original!\n" .
                "Cannot fit in the allocated space. Need to find data to zero or use -9e.\n",
                $new_lzma_size - $FV1_LZMA_SIZE);
}

# ===================================================================
# Step 6: Fix LZMA header
# ===================================================================
# xz writes 0xFFFFFFFFFFFFFFFF for uncompressed size (stream mode).
# AMI UEFI needs the exact uncompressed size in the 13-byte LZMA header.
print "\nFixing LZMA header...\n";
my $xz_header = substr($new_lzma, 0, 13);
printf "  xz wrote:  %s\n", join(" ", map { sprintf "%02X", ord(substr($xz_header, $_, 1)) } 0..12);
printf "  Original:  %s\n", join(" ", map { sprintf "%02X", ord(substr($orig_lzma_header, $_, 1)) } 0..12);

# Restore original 13-byte header
substr($new_lzma, 0, 13, $orig_lzma_header);
printf "  Restored original header (props=0x5D, dict=8MB, size=%d)\n", $FV1_DECOMP_SIZE;

# ===================================================================
# Step 7: Replace LZMA in BIOS image
# ===================================================================
print "\nInserting patched LZMA into BIOS...\n";
substr($bios, $FV1_LZMA_OFF, $new_lzma_size, $new_lzma);

# Pad remainder with 0x00
my $pad = $FV1_LZMA_SIZE - $new_lzma_size;
if ($pad > 0) {
    substr($bios, $FV1_LZMA_OFF + $new_lzma_size, $pad, "\x00" x $pad);
    printf "  Padded %d trailing bytes with 0x00\n", $pad;
}

# Fix outer FFS data checksum (FV1 FFS at 0x050048)
print "  Fixing FV1 outer FFS checksum...\n";
my $fv1_ffs_size = 1600090;  # From FFS header
# Zero checksum byte before calculating
substr($bios, $FV1_FFS_OFF + 17, 1, chr(0x00));
my $data_sum = 0;
for my $i (24 .. $fv1_ffs_size - 1) {
    $data_sum = ($data_sum + ord(substr($bios, $FV1_FFS_OFF + $i, 1))) & 0xFF;
}
my $new_ck = (256 - $data_sum) & 0xFF;
substr($bios, $FV1_FFS_OFF + 17, 1, chr($new_ck));
printf "  Outer FFS checksum: 0x%02X\n", $new_ck;

# ===================================================================
# Step 8: Insert ReBarDxe.ffs into Main FV free space
# ===================================================================
print "\nInserting ReBarDxe.ffs...\n";

open $fh, "<:raw", $rebar_ffs_file or die "Cannot open $rebar_ffs_file: $!\n";
my $rebar_ffs;
read($fh, $rebar_ffs, -s $rebar_ffs_file);
close $fh;

die "ReBarDxe.ffs unexpected size" unless length($rebar_ffs) == 2578;

# Fix state byte: 0x07 -> 0xF8 (erase polarity = 0xFF)
my $state = ord(substr($rebar_ffs, 23, 1));
if ($state == 0x07) {
    substr($rebar_ffs, 23, 1, chr(0xF8));
    printf "  Fixed state byte: 0x%02X -> 0xF8\n", $state;
} elsif ($state == 0xF8) {
    print "  State byte already 0xF8\n";
} else {
    die sprintf("Unexpected state byte 0x%02X in ReBarDxe.ffs", $state);
}

# Verify target area is free space (all 0xFF)
my $insert_off = $REBAR_INSERT_OFF;
my $insert_size = length($rebar_ffs);
my $target = substr($bios, $insert_off, $insert_size);
my $all_ff = 1;
for my $i (0 .. $insert_size - 1) {
    if (ord(substr($target, $i, 1)) != 0xFF) {
        $all_ff = 0;
        printf "  WARNING: Non-FF byte at 0x%06X: 0x%02X\n",
            $insert_off + $i, ord(substr($target, $i, 1));
        last;
    }
}
die "Target area is NOT free space!" unless $all_ff;

# Insert
substr($bios, $insert_off, $insert_size, $rebar_ffs);
printf "  Inserted %d bytes at BIOS offset 0x%06X\n", $insert_size, $insert_off;
printf "  Free space remaining: %d bytes (0x%06X to 0x%06X)\n",
    $FREE_SPACE_END - ($insert_off + $insert_size),
    $insert_off + $insert_size, $FREE_SPACE_END;

# ===================================================================
# Step 8b: Patch SaInitPeim in FV_BB (1-byte surgical fix)
# ===================================================================
# The 9010's SaInitPeim has 196 extra bytes vs the 7010 in one function.
# This code does a PPI lookup (GUID 417ACEE0-6FA9-4A82-99D7-F9B1DD271E48)
# and conditionally writes to a config structure based on the result.
# On first boot (full config), the PPI is present → write happens → 4G works.
# On reboot (fast boot), PPI may be absent → write skipped → 4G breaks.
# The 7010 doesn't have this check at all and works fine.
#
# Fix: Change JE (0x74) to JMP (0xEB) at the PPI result check.
# This makes the code always skip the PPI-gated write, matching 7010 behavior.
# SaInitPeim patch DISABLED — both JE→JMP and JE→NOP tested, neither fixed reboots.
# The 196 extra bytes in the 9010's SaInitPeim are not the root cause.
# Keeping stock 9010 SaInitPeim (unmodified).

# ===================================================================
# Step 8c: Disable WarmBootPei warm boot detection (FV_BB)
# ===================================================================
# WarmBootPei (GUID B178E5AA-0876-420A-B40F-E39B4E6EE05B) at BIOS 0x570A00
# checks for a "_WB_" marker in memory to detect warm boot. If found, it
# calls a PPI to optimize the boot path — which may skip full PCI enumeration.
#
# Research shows warm reboot (BOOT_ASSUMING_NO_CONFIGURATION_CHANGES) causes
# PciHostBridge DXE to skip 64-bit MMIO allocation, which is why Above 4G
# Decoding works on first cold boot but fails on subsequent reboots.
#
# Fix: Change JNE (skip) to JMP (always skip) at the _WB_ check.
# This makes the warm boot handler never trigger, forcing full config on reboot.
#
# BIOS 0x570CBB: 75 12 (JNE +0x12) -> EB 12 (JMP +0x12)
print "\nApplying WarmBootPei patch (FV_BB)...\n";

my $WARMBOOT_FFS_OFF  = 0x570A00;  # WarmBootPei FFS in BIOS
my $WARMBOOT_FFS_SIZE = 912;       # 0x390
my $WARMBOOT_JNE_OFF  = 0x570CBB;  # JNE byte location

# Verify the _WB_ comparison and JNE are present
die "WarmBootPei: _WB_ cmp not found"
    unless substr($bios, $WARMBOOT_JNE_OFF - 6, 6) eq "\x81\x39\x5F\x57\x42\x5F";
die "WarmBootPei: JNE 0x75 not found"
    unless ord(substr($bios, $WARMBOOT_JNE_OFF, 1)) == 0x75;

# Patch JNE to JMP
substr($bios, $WARMBOOT_JNE_OFF, 1, chr(0xEB));
printf "  [WB] _WB_ check: JNE -> JMP at BIOS 0x%06X\n", $WARMBOOT_JNE_OFF;

# Fix WarmBootPei FFS checksum (attrs=0x40, checksum enabled)
my $wb_old_ck = ord(substr($bios, $WARMBOOT_FFS_OFF + 17, 1));
substr($bios, $WARMBOOT_FFS_OFF + 17, 1, chr(0x00));
my $wb_sum = 0;
for my $i (24 .. $WARMBOOT_FFS_SIZE - 1) {
    $wb_sum = ($wb_sum + ord(substr($bios, $WARMBOOT_FFS_OFF + $i, 1))) & 0xFF;
}
my $wb_new_ck = (256 - $wb_sum) & 0xFF;
substr($bios, $WARMBOOT_FFS_OFF + 17, 1, chr($wb_new_ck));
printf "  WarmBootPei FFS checksum: 0x%02X -> 0x%02X\n", $wb_old_ck, $wb_new_ck;

# ===================================================================
# Step 9: Verify critical regions
# ===================================================================
print "\nVerifying critical regions...\n";

# NVMe driver still present
my $nvme_hdr = substr($bios, $NVME_FFS_OFF, 4);
printf "  NVMe FFS header: %s", unpack("H8", $nvme_hdr);
print($nvme_hdr ne ("\xFF" x 4) ? " (present)\n" : " (MISSING!)\n");

# ReBarDxe present
my $rebar_hdr = substr($bios, $insert_off, 4);
printf "  ReBarDxe FFS header: %s", unpack("H8", $rebar_hdr);
print($rebar_hdr ne ("\xFF" x 4) ? " (present)\n" : " (MISSING!)\n");

# FV_BB: verify SaInitPeim is UNCHANGED (stock 9010)
my $sa_stock = substr($bios, 0x554859, 2) eq "\x74\x09";
printf "  FV_BB SaInitPeim: stock JE at 0x554859: %s\n",
    $sa_stock ? "UNCHANGED (OK)" : "MODIFIED!";
die "SaInitPeim is unexpectedly modified!" unless $sa_stock;

# FV_BB: verify WarmBootPei patch
my $wb_patched = ord(substr($bios, $WARMBOOT_JNE_OFF, 1)) == 0xEB;
printf "  FV_BB WarmBootPei: JNE->JMP at 0x570CBB: %s\n",
    $wb_patched ? "APPLIED" : "MISSING!";
die "WarmBootPei patch not applied!" unless $wb_patched;

# SEC module
my $sec = substr($bios, 0x5FEFE8, 4);
printf "  SEC module intact: %s\n", ($sec ne ("\xFF" x 4)) ? "YES" : "NO";

# ===================================================================
# Step 10: Write outputs
# ===================================================================
print "\nWriting output files...\n";

# 6MB BIOS image
open my $out, ">:raw", $output_bios or die $!;
print $out $bios;
close $out;
printf "  %s: %d bytes\n", $output_bios, length($bios);

# 4MB chip image (BIOS[0x200000:0x5FFFFF])
my $spi1 = substr($bios, 0x200000, 0x400000);
open $out, ">:raw", $output_4mb or die $!;
print $out $spi1;
close $out;
printf "  %s: %d bytes\n", $output_4mb, length($spi1);

# 8MB chip image (needs fresh 8MB dump as base)
if (-f $spi2_dump_file) {
    print "\n  Building 8MB image from $spi2_dump_file...\n";
    open $fh, "<:raw", $spi2_dump_file or die $!;
    my $spi2;
    read($fh, $spi2, -s $spi2_dump_file);
    close $fh;
    die "8MB dump wrong size" unless length($spi2) == 8388608;

    # Overlay BIOS[0x000000:0x1FFFFF] at chip offset 0x600000
    substr($spi2, $SPI2_BIOS_OFF, 0x200000, substr($bios, 0, 0x200000));
    open $out, ">:raw", $output_8mb or die $!;
    print $out $spi2;
    close $out;
    printf "  %s: %d bytes\n", $output_8mb, length($spi2);

    print "\n  WARNING: For best results, do a fresh 8MB chip read right before\n";
    print "  flashing and rebuild with that dump to preserve current NVRAM.\n";
} else {
    print "\n  NOTE: $spi2_dump_file not found. 8MB image not built.\n";
    print "  Before flashing, read the 8MB chip fresh and run:\n";
    print "    perl build_spi2_rebar.pl <fresh_8mb_dump.bin>\n";
}

# ===================================================================
# Done
# ===================================================================
print "\n", "=" x 60, "\n";
print "BUILD COMPLETE\n";
print "=" x 60, "\n";
print "\n";
print "Flash commands:\n";
print "  4MB: flashrom -p ch341a_spi -c \"MX25L3206E/MX25L3208E\" -w $output_4mb\n";
print "  8MB: flashrom -p ch341a_spi -c \"MX25L6406E/MX25L6408E\" -w $output_8mb\n";
print "\n";
print "Post-flash:\n";
print "  1. CMOS reset (4G Decoding now defaults to ON via IFR patch)\n";
print "  2. Boot to Windows\n";
print "  3. Run ReBarState.exe, set size to 32\n";
print "  4. Reboot, check GPU-Z Advanced -> Resizable BAR\n";
print "  Note: WarmBootPei patch should fix the warm reboot black screen\n";
print "  Fallback: If still needed, boot GRUB -> setup_var 0x2 0x1\n";
print "\n";
print "Recovery:\n";
print "  Flash spi2_f1bypass_v4_write.bin (8MB) + spi1_f1bypass_v4_write.bin (4MB)\n";
print "\n";

# Cleanup temp files
unlink "tmp_fv1.lzma", "tmp_fv1", "tmp_fv1_rebar", "tmp_fv1_rebar.lzma";

print "Temp files cleaned up.\n";
