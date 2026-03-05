#!/usr/bin/perl
# build_f1_bypass.pl - Build Dell OptiPlex 9010 BIOS with NVMe + F1 bypass
#
# Patches the DellErrorLogConfig DXE driver to return SUCCESS immediately
# on entry, disabling the "Alert! Previous fan failure / Press F1" POST screen.
# Also injects NVMe driver for NVMe boot support.
#
# The DellErrorLogConfig driver lives inside a LZMA-compressed firmware volume
# (FV2) at BIOS offset 0x1D6AC9. The patch:
#   1. Changes the driver entry point to: xor eax, eax; ret (return SUCCESS)
#   2. Zeros out the dead .text code and .data string sections
#   3. Recompresses with LZMA (zeroed data compresses smaller -> fits!)
#   4. Replaces the LZMA stream in the BIOS image
#   5. Updates all FFS checksums
#
# Base: BACKUP.BIN (stock Dell OptiPlex 9010 A30 BIOS, 6MB)
# Requires: NvmExpressDxe.ffs (NVMe DXE driver, 6024 bytes)
# Output: F1_BYPASS.BIN (6MB BIOS), spi1_f1bypass_write.bin (4MB chip),
#         spi2_f1bypass_write.bin (8MB chip, requires fresh 8MB dump)
#
# The F1 bypass is in FV2 (compressed, spans both chips) — both must be flashed.
#
# Recovery: flash original chip backups to restore stock

use strict;
use warnings;

my $base_file      = "BACKUP.BIN";
my $nvme_ffs_file  = "NvmExpressDxe.ffs";
my $spi2_dump_file = "spi2_preflight_read1.bin";  # Fresh 8MB dump
my $output_bios    = "F1_BYPASS.BIN";
my $output_4mb     = "spi1_f1bypass_write.bin";
my $output_8mb     = "spi2_f1bypass_write.bin";

my $BIOS_SIZE      = 6291456;     # 6MB
my $SPI2_BIOS_OFF  = 0x600000;    # BIOS region offset in 8MB chip
my $NVME_FFS_OFF   = 0x3564B0;    # NVMe injection point
my $NVME_FFS_SIZE  = 6024;

# ===================================================================
# Step 1: Read base BIOS
# ===================================================================
print "=" x 60, "\n";
print "F1 Bypass + NVMe Build for Dell OptiPlex 9010\n";
print "=" x 60, "\n\n";

print "Reading $base_file...\n";
open my $fh, "<:raw", $base_file or die "Cannot open $base_file: $!\n";
my $bios;
read($fh, $bios, -s $base_file);
close $fh;
die "Expected ${BIOS_SIZE}-byte BIOS" unless length($bios) == $BIOS_SIZE;

# ===================================================================
# Step 2: Inject NVMe driver into Main FV
# ===================================================================
print "\nInjecting NVMe driver...\n";

open $fh, "<:raw", $nvme_ffs_file or die "Cannot open $nvme_ffs_file: $!\n";
my $nvme_ffs;
read($fh, $nvme_ffs, -s $nvme_ffs_file);
close $fh;
die "NvmExpressDxe.ffs unexpected size" unless length($nvme_ffs) == $NVME_FFS_SIZE;

# Verify target is free space
for my $i (0 .. $NVME_FFS_SIZE - 1) {
    die sprintf("Non-FF at 0x%06X", $NVME_FFS_OFF + $i)
        unless ord(substr($bios, $NVME_FFS_OFF + $i, 1)) == 0xFF;
}
substr($bios, $NVME_FFS_OFF, $NVME_FFS_SIZE, $nvme_ffs);
printf "  Inserted %d bytes at BIOS 0x%06X\n", $NVME_FFS_SIZE, $NVME_FFS_OFF;

# ===================================================================
# Step 3: Extract and decompress FV2
# ===================================================================
print "\nExtracting compressed FV2...\n";
my $lzma_offset = 0x1D6AC9;
my $orig_lzma_size = 1114349;
my $orig_lzma = substr($bios, $lzma_offset, $orig_lzma_size);
my $orig_lzma_header = substr($orig_lzma, 0, 13);

open my $tmp, ">:raw", "tmp_fv2.lzma" or die $!;
print $tmp $orig_lzma;
close $tmp;

system("xz --format=lzma -dk -f tmp_fv2.lzma") == 0
    or die "LZMA decompression failed!\n";

open $fh, "<:raw", "tmp_fv2" or die $!;
my $fv2;
read($fh, $fv2, -s "tmp_fv2");
close $fh;
printf "  Decompressed FV2: %d bytes\n", length($fv2);

# ===================================================================
# Step 4: Patch DellErrorLogConfig driver
# ===================================================================
print "\nPatching DellErrorLogConfig driver...\n";
my $ffs_start = 0x008E7C;
my $ffs_size = 36365;
my $entry_off = $ffs_start + 0x0301;  # PE entry point in fv2

# Verify original entry point: 48 89 5C (push rbx; mov [rsp+...])
my @orig = map { ord(substr($fv2, $entry_off + $_, 1)) } 0..2;
die sprintf("Entry point mismatch: expected 48 89 5C, got %02X %02X %02X",
    @orig) unless $orig[0] == 0x48 && $orig[1] == 0x89 && $orig[2] == 0x5C;

# Patch entry: xor eax, eax; ret (return EFI_SUCCESS)
substr($fv2, $entry_off, 3, "\x33\xC0\xC3");
printf "  Entry point: 48 89 5C -> 33 C0 C3 (xor eax,eax; ret)\n";

# Zero .text section (after ret) - dead code
substr($fv2, $ffs_start + 0x2A0 + 3, 0x3A0 - 3, "\x00" x (0x3A0 - 3));

# Zero .data section - dead string data (34KB of error strings)
substr($fv2, $ffs_start + 0x680, 0x8680, "\x00" x 0x8680);
print "  Zeroed dead .text and .data sections for better compression\n";

# Fix inner FFS data checksum
my $data_sum = 0;
for my $i (24 .. $ffs_size - 1) {
    $data_sum = ($data_sum + ord(substr($fv2, $ffs_start + $i, 1))) & 0xFF;
}
my $new_ck = (256 - $data_sum) & 0xFF;
substr($fv2, $ffs_start + 17, 1, chr($new_ck));
printf "  FFS data checksum: 0x%02X\n", $new_ck;

# ===================================================================
# Step 5: Recompress FV2
# ===================================================================
print "\nRecompressing FV2...\n";
open $tmp, ">:raw", "tmp_fv2_patched" or die $!;
print $tmp $fv2;
close $tmp;

unlink "tmp_fv2_patched.lzma";
system("xz --format=lzma --lzma1=dict=8MiB,lc=3,lp=0,pb=2 -k tmp_fv2_patched") == 0
    or die "LZMA compression failed!\n";

open $fh, "<:raw", "tmp_fv2_patched.lzma" or die $!;
my $new_lzma;
read($fh, $new_lzma, -s "tmp_fv2_patched.lzma");
close $fh;

my $new_lzma_size = length($new_lzma);
printf "  New LZMA: %d bytes (original: %d, saved: %d)\n",
    $new_lzma_size, $orig_lzma_size, $orig_lzma_size - $new_lzma_size;
die "FATAL: Recompressed LZMA is larger than original!" if $new_lzma_size > $orig_lzma_size;

# ===================================================================
# Step 6: Fix LZMA header and replace in BIOS
# ===================================================================
print "\nFixing LZMA header and inserting...\n";

# Restore original 13-byte header (xz writes wrong uncompressed size)
substr($new_lzma, 0, 13, $orig_lzma_header);

# Replace LZMA in BIOS
substr($bios, $lzma_offset, $new_lzma_size, $new_lzma);
my $pad = $orig_lzma_size - $new_lzma_size;
substr($bios, $lzma_offset + $new_lzma_size, $pad, "\x00" x $pad) if $pad > 0;

# Fix outer FFS data checksum
my $outer_ffs = 0x1D6AA8;
my $outer_ffs_size = 0x11010E;
$data_sum = 0;
for my $i (24 .. $outer_ffs_size - 1) {
    $data_sum = ($data_sum + ord(substr($bios, $outer_ffs + $i, 1))) & 0xFF;
}
$new_ck = (256 - $data_sum) & 0xFF;
substr($bios, $outer_ffs + 17, 1, chr($new_ck));
printf "  Outer FFS checksum: 0x%02X\n", $new_ck;

# ===================================================================
# Step 7: Verify
# ===================================================================
print "\nVerifying...\n";

# NVMe FFS present
my $nvme_hdr = substr($bios, $NVME_FFS_OFF, 4);
printf "  NVMe FFS header: %s (present)\n", unpack("H8", $nvme_hdr);

# SEC module intact
my $sec = substr($bios, 0x5FEFE8, 4);
printf "  SEC module intact: %s\n", ($sec ne ("\xFF" x 4)) ? "YES" : "NO";

# FV_BB untouched
open $fh, "<:raw", $base_file or die $!;
my $backup;
read($fh, $backup, $BIOS_SIZE);
close $fh;
printf "  FV_BB identical to stock: %s\n",
    substr($bios, 0x500000, 0x100000) eq substr($backup, 0x500000, 0x100000) ? "YES" : "NO";

# ===================================================================
# Step 8: Write outputs
# ===================================================================
print "\nWriting output files...\n";

# 6MB BIOS
open my $out, ">:raw", $output_bios or die $!;
print $out $bios;
close $out;
printf "  %s: %d bytes\n", $output_bios, length($bios);

# 4MB chip image
my $spi1 = substr($bios, 0x200000, 0x400000);
open $out, ">:raw", $output_4mb or die $!;
print $out $spi1;
close $out;
printf "  %s: %d bytes\n", $output_4mb, length($spi1);

# 8MB chip image (needs fresh dump)
if (-f $spi2_dump_file) {
    print "\n  Building 8MB image from $spi2_dump_file...\n";
    open $fh, "<:raw", $spi2_dump_file or die $!;
    my $spi2;
    read($fh, $spi2, -s $spi2_dump_file);
    close $fh;
    die "8MB dump wrong size" unless length($spi2) == 8388608;

    substr($spi2, $SPI2_BIOS_OFF, 0x200000, substr($bios, 0, 0x200000));
    open $out, ">:raw", $output_8mb or die $!;
    print $out $spi2;
    close $out;
    printf "  %s: %d bytes\n", $output_8mb, length($spi2);

    print "\n  WARNING: For best results, do a fresh 8MB chip read right before\n";
    print "  flashing and rebuild with that dump to preserve current NVRAM.\n";
} else {
    print "\n  NOTE: $spi2_dump_file not found. 8MB image not built.\n";
    print "  Read your 8MB chip fresh, save as $spi2_dump_file, and re-run.\n";
}

# Cleanup
unlink "tmp_fv2.lzma", "tmp_fv2", "tmp_fv2_patched", "tmp_fv2_patched.lzma";

print "\n", "=" x 60, "\n";
print "BUILD COMPLETE\n";
print "=" x 60, "\n";
print "\nBoth chips need flashing (F1 bypass modifies compressed FV2 which spans both).\n";
print "Flash:\n";
print "  4MB: flashrom -p ch341a_spi -c \"MX25L3206E/MX25L3208E\" -w $output_4mb\n";
print "  8MB: flashrom -p ch341a_spi -c \"MX25L6406E/MX25L6408E\" -w $output_8mb\n";
print "\nRecovery: flash original chip backups to restore stock.\n";
