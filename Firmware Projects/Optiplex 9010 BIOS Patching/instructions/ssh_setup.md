# SSH Setup for Remote Access to the OptiPlex 9010

Enable SSH so Claude Code (on the Razer) can remotely access the 9010 even when the display is down.

## On the 9010 (Admin PowerShell)

### 1. Install and start OpenSSH Server
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic
```

### 2. Add the Razer's SSH public key
```powershell
mkdir C:\Users\clay\.ssh -Force
Add-Content C:\Users\clay\.ssh\authorized_keys "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity"
```

### 3. If your account is an admin (likely), also add to the admin keys file
```powershell
Add-Content C:\ProgramData\ssh\administrators_authorized_keys "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity"
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "SYSTEM:F" /grant "Administrators:F"
```

## From the Razer

```bash
ssh clay@192.168.1.195
```

## Notes
- The 9010's IP is `192.168.1.195` (ethernet, DHCP — may change after reboot)
- SSH key lives at `C:\Users\clayi\.ssh\id_ed25519` on the Razer
- SSH stays up even when GPU display output crashes — that's the whole point
