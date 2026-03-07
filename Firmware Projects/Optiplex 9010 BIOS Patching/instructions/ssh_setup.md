# SSH Setup for Remote Access to the OptiPlex 9010

Enable SSH so Claude Code (on the Razer) can remotely access the 9010 even when the display is down.

## QUICK VERSION (One Shot)

The display crashes after ~30 min idle. You need to get this done fast.

### Step 1: Reboot the 9010
Power cycle or reboot. You have ~30 minutes before display dies.

### Step 2: Open Admin PowerShell
- Press **Win+X**, then **A** (or click "Windows PowerShell (Admin)")
- If you get a UAC prompt, click Yes

### Step 3: Paste this SINGLE LINE and press Enter
```
mkdir C:\ProgramData\ssh -Force; Set-Content C:\ProgramData\ssh\administrators_authorized_keys "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity"; icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "SYSTEM:F" /grant "Administrators:F"
```

### Step 4: Verify SSH server is running (paste and Enter)
```
Get-Service sshd
```
- If it says **Running** → you're done, go to the Razer and run `ssh clay@192.168.1.195`
- If it says **Stopped** → paste this and press Enter:
```
Start-Service sshd; Set-Service sshd -StartupType Automatic
```
- If it says the service doesn't exist → SSH Server isn't installed. Paste this and wait for it to finish:
```
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd; Set-Service sshd -StartupType Automatic
```

### Step 5: Test from the Razer
```bash
ssh clay@192.168.1.195
```

---

## IF THE DISPLAY DIES MID-SETUP

If you only got partway through, here's what to check after rebooting:

**Did SSH server get installed?**
- If Step 4 `Get-Service sshd` shows "Running" → SSH is installed, you just need the key (Step 3)
- SSH server survived the last attempt — it's already installed and running

**Did the key get added?**
- If `ssh clay@192.168.1.195` from the Razer says "Permission denied" → SSH is running but the key isn't set up. Redo Step 3 only.
- If it says "Connection timed out" → SSH server isn't running. Do Steps 3 + 4.
- If it says "connected" → you're in!

**Current status:** SSH server IS installed and running (confirmed from Razer — it responds on port 22). Only Step 3 (the key) is missing.

---

## ALTERNATIVE: Password Auth (if key auth keeps failing)

If you can't get the key file set up, enable password auth instead:

```powershell
# Edit the SSH config to allow password auth
(Get-Content C:\ProgramData\ssh\sshd_config) -replace '#PasswordAuthentication yes','PasswordAuthentication yes' | Set-Content C:\ProgramData\ssh\sshd_config
Restart-Service sshd
```

Then from the Razer, use `sshpass` or just type the password when prompted:
```bash
ssh clay@192.168.1.195
# Type your Windows password when prompted
```

Note: This requires an interactive terminal on the Razer side. Claude Code's Bash tool can't type passwords interactively, so you'd need to run the ssh command yourself in a separate terminal first to verify, then set up key auth from there.

---

## NUCLEAR OPTION: Let Claude Code on the 9010 do it

If you have Claude Code running on the 9010 side, just tell it:
"Run these commands in admin PowerShell to enable SSH with key auth"

And paste it these commands:
```
mkdir C:\ProgramData\ssh -Force
Set-Content C:\ProgramData\ssh\administrators_authorized_keys "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity"
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "SYSTEM:F" /grant "Administrators:F"
Get-Service sshd
```

It should be able to execute these even without admin PowerShell since Claude Code's Bash tool runs with the user's permissions (and if you're an admin user, that's admin permissions).

---

## Reference
- 9010 IP: `192.168.1.195` (ethernet DHCP — may change after reboot)
- SSH key on Razer: `C:\Users\clayi\.ssh\id_ed25519`
- SSH stays up even when GPU display crashes — that's the whole point
