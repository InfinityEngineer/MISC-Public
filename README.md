# MISC-Public

Miscellaneous firmware projects and hardware mods.

## Projects

### [Dell OptiPlex 9010 BIOS Patching](Firmware%20Projects/Optiplex%209010%20BIOS%20Patching/)

NVMe boot, F1 fan error bypass, Above 4G Decoding, and Resizable BAR for the Dell OptiPlex 9010 MT (Ivy Bridge / Q77). All patches applied via Perl build scripts and a CH341A SPI programmer -- no GUI tools required.

Includes a detailed writeup of the warm reboot black screen root cause (WarmBootPei + dead DSDT E4GM gate) that isn't documented anywhere else for this platform.
