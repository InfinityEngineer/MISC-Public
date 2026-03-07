# Claude Code Instructions — Dell OptiPlex 9010 BIOS Project

## Current Situation (March 7, 2026)

The 9010 has a working ReBAR BIOS flashed but needs UEFI NVRAM variables set via
setup_var commands in modGRUBShell. The machine boots to Windows fine with stock
defaults, but ReBAR requires specific CSM/4G settings applied manually.

The F12 boot menu is unreachable on warm reboots due to a GPU init timing issue
(WarmBootPei). **Always cold boot** (full power cycle, not restart) to reach F12.

### 9010 Machine Details
- Hostname: IXIONS-HAUNCH
- IP: 192.168.1.195 (may change — check router if unreachable)
- User: clayi
- OS: Windows 11 (TPM bypass via registry key)
- GPU: discrete card in PEG slot (needs PSU power connected)

### Razer (Primary Machine) Details
- No Python (use Perl for scripting)
- No `gh` CLI
- BIOS workspace: C:/Users/clayi/Desktop/9010_BIOS_BACKUP/
- flashrom: C:/Users/clayi/Desktop/9010_BIOS_BACKUP/flashrom/flashrom-1.4/
- Zadig (for CH341A driver): C:/Users/clayi/Downloads/zadig-2.9.exe

---

## Task 1: Set Up SSH to the 9010

SSH lets you run commands on the 9010 remotely from the Razer. This is essential
for diagnostics when the 9010 has display issues.

### On the 9010 (via local keyboard/monitor):

1. Open PowerShell as Administrator
2. Install and start OpenSSH Server:
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```
3. Allow SSH through firewall (usually auto-configured, but verify):
```powershell
Get-NetFirewallRule -Name *ssh*
# If no rule exists:
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

### On the Razer (via bash/terminal):

1. Generate SSH key if none exists:
```bash
ls ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -b 4096
```
2. Copy your public key to the 9010:
```bash
cat ~/.ssh/id_rsa.pub | ssh clayi@192.168.1.195 "mkdir -Force ~\.ssh; Add-Content ~\.ssh\authorized_keys -Value (Read-Host -Prompt 'paste')"
```
Or simpler — just manually append the contents of `~/.ssh/id_rsa.pub` on the
Razer to `C:\Users\clayi\.ssh\authorized_keys` on the 9010.

**Important for Windows OpenSSH admin users:** If clayi is in the Administrators
group, the authorized_keys file goes in `C:\ProgramData\ssh\administrators_authorized_keys`
instead, and needs specific permissions:
```powershell
icacls "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "SYSTEM:(R)" /grant "Administrators:(R)"
```

3. Test connection:
```bash
ssh clayi@192.168.1.195 "hostname"
# Should print: IXIONS-HAUNCH
```

### SSH Gotcha: PowerShell $_ mangling
When running PowerShell commands over SSH through bash, `$_` gets mangled by
bash's extglob. Workarounds:
- Upload .ps1 scripts and execute with `powershell -File script.ps1`
- Avoid `$_` in Where-Object (use `-Filter` parameters instead)
- Use heredoc: `ssh clayi@192.168.1.195 powershell -File - <<'PS1' ... PS1`

---

## Task 2: Apply ReBAR Setup Variables

### Option A: Cold Boot to modGRUBShell (Preferred)

The modGRUBShell is on a USB drive (E:, 16GB FAT32, E:/DOS/).

1. **Fully shut down** the 9010 (Start → Shut Down, NOT restart)
2. **Unplug the power cord** from the wall, wait 5 seconds
3. **Plug cord back in**
4. Press power and **immediately spam F12**
5. Select the USB drive from the boot menu
6. In the GRUB/EFI shell, run these commands:

```
setup_var 0x2 0x1       # Above 4G Decoding = Enabled
setup_var 0xBDE 0x02    # Launch CSM = Never
setup_var 0xBDF 0x02    # Boot option filter = UEFI only
setup_var 0x2D 0x02     # PXE OpROM = UEFI only
setup_var 0x2E 0x02     # Storage OpROM = UEFI only
setup_var 0x2F 0x02     # Video OpROM = UEFI only
```

7. Reboot. Boot into Windows.
8. Run `ReBarState.exe` (in the BIOS backup folder), set BAR size to **32**
9. Reboot and verify with GPU-Z (Advanced tab → Resizable BAR)

### Option B: If F12 Boot Menu Won't Show

The warm reboot black screen is caused by WarmBootPei's warm boot detection
skipping full PCI enumeration. The patched BIOS has a fix (JNE→JMP at 0x570CBB)
but the F12 menu may still be problematic with CSM=Never.

If cold boot + F12 doesn't work:
- Try entering **F2 BIOS Setup** instead (cold boot + spam F2)
- In F2 Setup, change boot order to put USB first
- Save and exit — it should boot the USB drive
- Run setup_var commands above
- Then change boot order back

### Option C: If No Display at All

If the 9010 shows nothing (not even text POST), it may need a CMOS reset:

1. Shut down, **unplug** power cord
2. Hold power button 15-20 seconds
3. Move jumper from **PSWD** to **RTCRST** (adjacent 2-pin header on motherboard)
4. **Plug power cord BACK IN** (don't press power button!)
5. Wait **10 seconds**
6. **Unplug** cord again
7. Press power button once to drain residual
8. Move jumper back to **PSWD** position
9. Plug in, power on

After CMOS reset, the machine boots with stock defaults (CSM=Always, no ReBAR).
Then follow Option A to re-apply setup_var commands.

---

## Flashing Procedure (MANDATORY — always follow this order)

When using the CH341A + SOIC-8 clip to flash SPI chips:

1. **DETECT** — probe to identify which chip is attached:
   ```
   flashrom -p ch341a_spi
   ```
   - 4MB chip: MX25L3206E → `-c "MX25L3206E/MX25L3208E"`
   - 8MB chip: MX25L6406E → `-c "MX25L6406E/MX25L6408E"`

2. **READ** — backup current contents before writing:
   ```
   flashrom -p ch341a_spi -c "<chip>" -r backup_before_write.bin
   ```

3. **WRITE + VERIFY** — flash the new image:
   ```
   flashrom -p ch341a_spi -c "<chip>" -w new_image.bin
   ```

4. **READ AGAIN** — post-flash verification:
   ```
   flashrom -p ch341a_spi -c "<chip>" -r readback_after_write.bin
   ```
   Then compare: `cmp new_image.bin readback_after_write.bin`

### CH341A Driver Notes
- Needs **libusbK** driver via Zadig (C:\Users\clayi\Downloads\zadig-2.9.exe)
- Driver is per-USB-port-path — plugging into a different port/hub needs Zadig again
- Direct USB connection to Razer is more reliable than through a hub
- The 9010 must be **completely unplugged** (no standby power) during flashing

---

## Key Files

| File | Location | Description |
|------|----------|-------------|
| BACKUP.BIN | BIOS backup folder | Original stock BIOS — NEVER modify |
| F1_BYPASS.BIN | BIOS backup folder | Stock + NVMe + F1 bypass (base for builds) |
| REBAR.BIN | BIOS backup folder | Full ReBAR build (latest) |
| build_rebar.pl | BIOS backup folder | Build script for REBAR.BIN |
| spi2_fresh_read.bin | BIOS backup folder | Last known-good 8MB chip dump |
| ifr_9010.txt | BIOS backup folder | Full hidden BIOS settings dump |
| HIDDEN_SETTINGS_REFERENCE.md | BIOS backup folder | Complete settings reference |

## What NOT to Do

- Do NOT set "Enable Legacy Option ROMs = Disabled" via IFR defaults — this
  bricked the system (no POST, no display, no HDD activity). The setting may
  prevent GPU option ROM from loading even in UEFI mode on Dell firmware.
- Do NOT use "Fastboot = Minimal" — ReBAR needs full PCI enumeration (Thorough)
- Do NOT change the Above 4G Decoding IFR patch method (byte+12) even though
  analysis suggests it's QuestionFlags not CBFlags — it works empirically
- Do NOT flash without following the 4-step procedure above
