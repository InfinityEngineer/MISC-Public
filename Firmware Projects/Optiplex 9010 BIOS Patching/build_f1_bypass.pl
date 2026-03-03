#!/usr/bin/perl
# build_f1_bypass.pl - Build Dell OptiPlex 9010 BIOS with F1 bypass
#
# Patches the DellErrorLogConfig DXE driver to return EFI_SUCCESS immediately
# on entry, disabling the "Alert! Previous fan failure / Press F1" POST screen.
#
# The driver (GUID 038CE287-B806-45B6-A819-514DAF4B91B9) lives inside a
# LZMA-compressed firmware volume (FV2) at BIOS offset 0x1D6AC9.
#
# The patch:
#   1. Changes the driver entry point to: xor eax, eax; ret (return SUCCESS)
#   2. Zeros out the dead .text code and .data string sections
#   3. Recompresses with LZMA (zeroed data compresses smaller -> fits!)
#   4. Fixes the LZMA header (xz writes wrong uncompressed size)
#   5. Replaces the LZMA stream in the BIOS image
#   6. Updates all FFS checksums
#   7. Generates write images for BOTH flash chips
#
# IMPORTANT: The LZMA stream spans both the 8MB and 4MB flash chips!
#   BIOS[0x000000-0x1FFFFF] -> 8MB chip (MX25L6406E) at chip offset 0x600000
#   BIOS[0x200000-0x5FFFFF] -> 4MB chip (MX25L3206E) at chip offset 0x000000
#   The LZMA starts at 0x1D6AC9 (on 8MB chip) and ends at 0x2E6BB6 (on 4MB chip).
#   You MUST flash both chips or the LZMA stream will be half-old/half-new = brick.
#
# Prerequisites:
#   - xz (for LZMA compression/decompression)
#   - flashrom + CH341A programmer
#   - NVME_ONLY.BIN: stock Dell A30 BIOS with NVMe driver injected
#   - A fresh dump of the 8MB chip (for preserving NVRAM/ME/IFD)
#
# Usage:
#   perl build_f1_bypass.pl [8mb_chip_dump.bin]
#
#   If 8mb_chip_dump.bin is provided, generates the 8MB write image too.
#   Otherwise only generates the 6MB BIOS and 4MB chip image.
#
# Flash procedure:
#   1. Clip to 8MB chip: flashrom -p ch341a_spi -c "MX25L6406E/MX25L6408E" -w spi2_f1bypass_write.bin
#   2. Clip to 4MB chip: flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w spi1_f1bypass_write.bin
#   3. Power on, enter BIOS Setup (F2) to verify boot order
#
# Recovery:
#   Flash your original chip dumps back to both chips.

use strict;
use warnings;

my $spi2_dump = $ARGV[0];  # optional 8MB chip dump

my $base_file    = "NVME_ONLY.BIN";
my $output_bios  = "F1_BYPASS.BIN";
my $output_4mb   = "spi1_f1bypass_write.bin";
my $output_8mb   = "spi2_f1bypass_write.bin";

# --- Step 1: Read base BIOS ---
print "Reading $base_file...\n";
open my $fh, "<:raw", $base_file or die "Cannot open $base_file: $!\n";
my $bios;
read($fh, $bios, -s $base_file);
close $fh;
die "Expected 6MB BIOS" unless length($bios) == 6291456;

# --- Step 2: Extract and decompress FV2 ---
print "Extracting compressed FV2...\n";
my $lzma_offset    = 0x1D6AC9;
my $orig_lzma_size = 1114349;
my $orig_lzma      = substr($bios, $lzma_offset, $orig_lzma_size);

# Save the original 13-byte LZMA header (props + dict + uncompressed size)
# xz incorrectly writes 0xFFFFFFFFFFFFFFFF for the uncompressed size field,
# but AMI's UEFI LZMA decoder requires the exact value to allocate its buffer.
my $orig_lzma_header = substr($orig_lzma, 0, 13);

open my $tmp, ">:raw", "tmp_fv2.lzma" or die $!;
print $tmp $orig_lzma;
close $tmp;

system("xz --format=lzma -dk -f tmp_fv2.lzma") == 0
    or die "LZMA decompression failed! Is xz installed?\n";

open $fh, "<:raw", "tmp_fv2" or die $!;
my $fv2;
read($fh, $fv2, -s "tmp_fv2");
close $fh;
printf "Decompressed FV2: %d bytes\n", length($fv2);

# --- Step 3: Patch DellErrorLogConfig driver ---
print "Patching DellErrorLogConfig driver...\n";
my $ffs_start = 0x008E7C;   # FFS file offset in decompressed FV2
my $ffs_size  = 36365;      # FFS file size
my $pe_start  = $ffs_start + 0x61;     # MZ header offset in FV2
my $entry_off = $ffs_start + 0x0301;   # PE entry point in FV2 (RVA 0x2A0)

# Verify we're patching the right bytes
my @orig = map { ord(substr($fv2, $entry_off + $_, 1)) } 0..2;
die sprintf("Entry point mismatch: expected 48 89 5C, got %02X %02X %02X\n" .
    "Wrong BIOS version? This script is for Dell OptiPlex 9010 A30.",
    @orig) unless $orig[0] == 0x48 && $orig[1] == 0x89 && $orig[2] == 0x5C;

# Patch entry point: xor eax, eax; ret  (return EFI_SUCCESS immediately)
substr($fv2, $entry_off, 3, "\x33\xC0\xC3");

# Zero dead .text section (after the ret) - unreachable code
substr($fv2, $pe_start + 0x2A0 + 3, 0x3A0 - 3, "\x00" x (0x3A0 - 3));

# Zero dead .data section - 34KB of error strings that are never referenced
substr($fv2, $pe_start + 0x680, 0x8680, "\x00" x 0x8680);

# Fix inner FFS data checksum (DellErrorLogConfig FFS)
my $data_sum = 0;
for my $i (24 .. $ffs_size - 1) {
    $data_sum = ($data_sum + ord(substr($fv2, $ffs_start + $i, 1))) & 0xFF;
}
my $new_ck = (256 - $data_sum) & 0xFF;
substr($fv2, $ffs_start + 17, 1, chr($new_ck));
printf "  Inner FFS checksum: 0x%02X\n", $new_ck;

# --- Step 4: Recompress FV2 ---
print "Recompressing FV2...\n";
open $tmp, ">:raw", "tmp_fv2_patched" or die $!;
print $tmp $fv2;
close $tmp;

unlink "tmp_fv2_patched.lzma";
# Use matching LZMA parameters: lc=3, lp=0, pb=2, dict=8MB (props byte = 0x5D)
system("xz --format=lzma --lzma1=dict=8MiB,lc=3,lp=0,pb=2 -k tmp_fv2_patched") == 0
    or die "LZMA compression failed!\n";

open $fh, "<:raw", "tmp_fv2_patched.lzma" or die $!;
my $new_lzma;
read($fh, $new_lzma, -s "tmp_fv2_patched.lzma");
close $fh;

my $new_lzma_size = length($new_lzma);
printf "New LZMA: %d bytes (original: %d, saved: %d)\n",
    $new_lzma_size, $orig_lzma_size, $orig_lzma_size - $new_lzma_size;
die "FATAL: Recompressed LZMA is larger than original!\n" .
    "Try zeroing more dead data or using higher compression."
    if $new_lzma_size > $orig_lzma_size;

# *** CRITICAL: Fix LZMA header ***
# xz writes 0xFFFFFFFFFFFFFFFF for uncompressed size (stream mode).
# AMI's UEFI decoder needs the exact uncompressed size to allocate its output buffer.
# Restore the original 13-byte header (props + dict size + uncompressed size).
substr($new_lzma, 0, 13, $orig_lzma_header);

# --- Step 5: Replace LZMA in BIOS image ---
print "Building $output_bios...\n";
substr($bios, $lzma_offset, $new_lzma_size, $new_lzma);
my $pad = $orig_lzma_size - $new_lzma_size;
substr($bios, $lzma_offset + $new_lzma_size, $pad, "\x00" x $pad) if $pad > 0;

# Fix outer FFS data checksum (the FFS containing the compressed FV2)
my $outer_ffs      = 0x1D6AA8;
my $outer_ffs_size = 0x11010E;
$data_sum = 0;
for my $i (24 .. $outer_ffs_size - 1) {
    $data_sum = ($data_sum + ord(substr($bios, $outer_ffs + $i, 1))) & 0xFF;
}
$new_ck = (256 - $data_sum) & 0xFF;
substr($bios, $outer_ffs + 17, 1, chr($new_ck));
printf "  Outer FFS checksum: 0x%02X\n", $new_ck;

# --- Step 6: Write outputs ---
# Full 6MB BIOS
open my $out, ">:raw", $output_bios or die $!;
print $out $bios;
close $out;
printf "Wrote %s (%d bytes)\n", $output_bios, length($bios);

# 4MB chip image (BIOS[0x200000:0x5FFFFF])
my $flash_4mb = substr($bios, 0x200000, 0x400000);
open $out, ">:raw", $output_4mb or die $!;
print $out $flash_4mb;
close $out;
printf "Wrote %s (%d bytes)\n", $output_4mb, length($flash_4mb);

# 8MB chip image (if dump provided)
if ($spi2_dump) {
    print "\nBuilding 8MB chip image from $spi2_dump...\n";
    open $fh, "<:raw", $spi2_dump or die "Cannot open $spi2_dump: $!\n";
    my $spi2;
    read($fh, $spi2, -s $spi2_dump);
    close $fh;
    die "Expected 8MB chip dump" unless length($spi2) == 8388608;

    # Only replace the modified BIOS region (FFS header + LZMA portion)
    # Preserves NVRAM, Intel ME, flash descriptor, and GbE config
    my $bios_patch_start = 0x1D6AA8;  # outer FFS header
    my $bios_patch_end   = 0x200000;  # chip boundary
    my $patch_len = $bios_patch_end - $bios_patch_start;
    my $chip_offset = 0x600000 + $bios_patch_start;

    substr($spi2, $chip_offset, $patch_len,
           substr($bios, $bios_patch_start, $patch_len));

    open $out, ">:raw", $output_8mb or die $!;
    print $out $spi2;
    close $out;
    printf "Wrote %s (%d bytes)\n", $output_8mb, length($spi2);
    print "  (NVRAM/ME/IFD preserved from original dump)\n";
}

# --- Cleanup temp files ---
unlink "tmp_fv2.lzma", "tmp_fv2", "tmp_fv2_patched", "tmp_fv2_patched.lzma";

print "\n=== BUILD COMPLETE ===\n";
print "Flash BOTH chips:\n";
print "  8MB: flashrom -p ch341a_spi -c \"MX25L6406E/MX25L6408E\" -w $output_8mb\n"
    if $spi2_dump;
print "  4MB: flashrom -p ch341a_spi -c \"MX25L3206E/MX25L3208E\" -w $output_4mb\n";
print "\nWARNING: You MUST flash both chips! The LZMA stream spans the chip boundary.\n"
    if $spi2_dump;
print "\nNOTE: 8MB chip image not generated (no dump provided).\n" .
      "  Run: perl $0 <8mb_chip_dump.bin>\n" unless $spi2_dump;
