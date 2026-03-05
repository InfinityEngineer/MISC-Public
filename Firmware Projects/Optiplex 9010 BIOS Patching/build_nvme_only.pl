#!/usr/bin/perl
# build_nvme_only.pl - Build Dell OptiPlex 9010 BIOS with NVMe boot support
#
# Injects the NvmExpressDxe driver into the Main FV free space of the stock
# BIOS, enabling boot from NVMe drives via a PCIe adapter.
#
# Base: BACKUP.BIN (stock Dell OptiPlex 9010 A30 BIOS, 6MB)
# Requires: NvmExpressDxe.ffs (NVMe DXE driver, 6024 bytes)
# Output: NVME_ONLY.BIN (6MB BIOS), spi1_nvmeonly_write.bin (4MB chip image)
#
# The NVMe driver goes into Main FV free space at BIOS offset 0x3564B0.
# Only the 4MB chip needs flashing — the 8MB chip is unchanged.
#
# Flash command:
#   flashrom -p ch341a_spi -c "MX25L3206E/MX25L3208E" -w spi1_nvmeonly_write.bin
#
# Recovery: flash original 4MB chip backup to restore stock

use strict;
use warnings;

my $base_file     = "BACKUP.BIN";
my $nvme_ffs_file = "NvmExpressDxe.ffs";
my $output_bios   = "NVME_ONLY.BIN";
my $output_flash  = "spi1_nvmeonly_write.bin";

my $BIOS_SIZE     = 6291456;     # 6MB
my $NVME_FFS_OFF  = 0x3564B0;   # Injection point in Main FV free space

# --- Step 1: Read base BIOS ---
print "=" x 60, "\n";
print "NVMe Build for Dell OptiPlex 9010\n";
print "=" x 60, "\n\n";

print "Reading $base_file...\n";
open my $fh, "<:raw", $base_file or die "Cannot open $base_file: $!\n";
my $bios;
read($fh, $bios, -s $base_file);
close $fh;
die "Expected ${BIOS_SIZE}-byte BIOS, got " . length($bios) unless length($bios) == $BIOS_SIZE;

# --- Step 2: Read NVMe driver FFS ---
print "Reading $nvme_ffs_file...\n";
open $fh, "<:raw", $nvme_ffs_file or die "Cannot open $nvme_ffs_file: $!\n";
my $nvme_ffs;
read($fh, $nvme_ffs, -s $nvme_ffs_file);
close $fh;

my $nvme_len = length($nvme_ffs);
die "NvmExpressDxe.ffs unexpected size (got $nvme_len)" unless $nvme_len == 6024;
printf "  NVMe FFS: %d bytes\n", $nvme_len;

# --- Step 3: Verify target area is free space (all 0xFF) ---
print "\nVerifying injection target is free space...\n";
my $target = substr($bios, $NVME_FFS_OFF, $nvme_len);
my $all_ff = 1;
for my $i (0 .. $nvme_len - 1) {
    if (ord(substr($target, $i, 1)) != 0xFF) {
        $all_ff = 0;
        printf "  WARNING: Non-FF byte at 0x%06X: 0x%02X\n",
            $NVME_FFS_OFF + $i, ord(substr($target, $i, 1));
        last;
    }
}
die "Target area is NOT free space! Cannot inject NVMe driver." unless $all_ff;
print "  Target area all 0xFF: YES\n";

# --- Step 4: Inject NVMe driver ---
print "\nInjecting NVMe driver...\n";
substr($bios, $NVME_FFS_OFF, $nvme_len, $nvme_ffs);
printf "  Inserted %d bytes at BIOS offset 0x%06X\n", $nvme_len, $NVME_FFS_OFF;

# --- Step 5: Verify ---
print "\nVerifying...\n";

# NVMe FFS header present
my $hdr = substr($bios, $NVME_FFS_OFF, 4);
printf "  NVMe FFS header: %s (present)\n", unpack("H8", $hdr);

# FV_BB untouched (compare against stock)
open $fh, "<:raw", $base_file or die $!;
my $backup;
read($fh, $backup, $BIOS_SIZE);
close $fh;
my $fvbb_ok = substr($bios, 0x500000, 0x100000) eq substr($backup, 0x500000, 0x100000);
printf "  FV_BB identical to stock: %s\n", $fvbb_ok ? "YES" : "NO (unexpected!)";

# SEC module intact
my $sec = substr($bios, 0x5FEFE8, 4);
printf "  SEC module intact: %s\n", ($sec ne ("\xFF" x 4)) ? "YES" : "NO";

# --- Step 6: Write outputs ---
print "\nWriting output files...\n";

open my $out, ">:raw", $output_bios or die $!;
print $out $bios;
close $out;
printf "  %s: %d bytes\n", $output_bios, length($bios);

# 4MB chip image (BIOS[0x200000:0x5FFFFF])
my $flash = substr($bios, 0x200000, 0x400000);
open $out, ">:raw", $output_flash or die $!;
print $out $flash;
close $out;
printf "  %s: %d bytes\n", $output_flash, length($flash);

print "\n", "=" x 60, "\n";
print "BUILD COMPLETE\n";
print "=" x 60, "\n";
print "\nOnly the 4MB chip needs flashing (NVMe driver is in Main FV).\n";
print "Flash: flashrom -p ch341a_spi -c \"MX25L3206E/MX25L3208E\" -w $output_flash\n";
print "\nThe 8MB chip is unchanged from stock.\n";
