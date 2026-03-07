# Claude Code Instructions — Dell OptiPlex 9010 (Run on the 9010)

You are running on the Dell OptiPlex 9010 (hostname: IXIONS-HAUNCH).
The user (clayi) is coordinating from their Razer laptop via this repo.

There are TWO tasks below. Do them in order. Report results by committing
a status update to this repo.

---

## Task 1: Set Up SSH Server

The Razer needs SSH access to this machine. Set up OpenSSH Server.

### Step 1a: Install and start sshd

Run these in an **elevated PowerShell** (Admin):

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

### Step 1b: Open firewall port 22

```powershell
# Check if rule exists:
Get-NetFirewallRule -Name *ssh* -ErrorAction SilentlyContinue
# If not, create it:
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

### Step 1c: Install the Razer's SSH public key

The user `clayi` is in the Administrators group, so the authorized_keys file
must go in `C:\ProgramData\ssh\administrators_authorized_keys`.

Create the file with this exact content (the Razer's public key):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity
```

Then set permissions (required — sshd ignores the file without this):

```powershell
icacls "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "SYSTEM:(R)" /grant "Administrators:(R)"
```

### Step 1d: Verify sshd is listening

```powershell
Test-NetConnection -ComputerName localhost -Port 22
# TcpTestSucceeded should be True
```

Also confirm the IP address:
```powershell
(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike '*Loopback*' }).IPAddress
```

### Step 1e: Report status

Commit a file called `SSH_STATUS.md` to this repo with:
- Whether sshd is running
- The machine's current IP address
- Whether Test-NetConnection succeeded

---

## Task 2: Apply ReBAR UEFI Settings from Windows

This machine has a modded BIOS that supports Resizable BAR, but after a CMOS
reset the NVRAM settings reverted to stock defaults. We need to set 6 UEFI
variables **from Windows** using the PowerShell script in this repo.

### Step 2a: Run the script

The script `apply_rebar_settings.ps1` is in this repo. Run it from an
**elevated PowerShell**:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\path\to\apply_rebar_settings.ps1"
```

(Replace the path with wherever you cloned/downloaded this repo.)

The script reads the "Setup" UEFI variable, patches 6 byte offsets, and
writes it back. It will show `[OK]` for values already correct and `[FIX]`
for values it changes. It must say `SUCCESS` at the end.

### Step 2b: Report the output

Append the full script output to `SSH_STATUS.md` and commit it.

**Do NOT reboot yet** — wait for the user to confirm via the Razer.

---

## What NOT to Do

- Do NOT reboot the machine without user confirmation
- Do NOT modify any UEFI variables other than the 6 listed in the script
- Do NOT set "Enable Legacy Option ROMs = Disabled" — this bricks the system
- Do NOT install Python unless needed — prefer PowerShell for everything
