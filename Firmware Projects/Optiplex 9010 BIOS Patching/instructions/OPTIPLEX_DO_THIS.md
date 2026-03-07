# INSTRUCTIONS FOR CLAUDE CODE ON THE OPTIPLEX 9010

You are running on the Dell OptiPlex 9010. The display on this machine crashes after ~5-30 minutes of idle. Your ONLY job right now is to enable SSH so the Razer laptop can connect remotely.

**TIME IS SHORT. Do not explain anything. Just run each command immediately, one after another.**

## COMMANDS TO RUN (in order, one at a time)

### 1. Create SSH key directory
```bash
powershell -Command "mkdir C:\ProgramData\ssh -Force"
```

### 2. Write the SSH public key
```bash
powershell -Command "Set-Content C:\ProgramData\ssh\administrators_authorized_keys 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity'"
```

### 3. Fix file permissions (SSH ignores the key file without this)
```bash
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "SYSTEM:F" /grant "Administrators:F"
```

### 4. Install SSH server (skip if already installed)
```bash
powershell -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"
```

### 5. Start SSH and set auto-start
```bash
powershell -Command "Start-Service sshd; Set-Service sshd -StartupType Automatic"
```

### 6. Restart SSH to pick up the new key
```bash
powershell -Command "Restart-Service sshd"
```

### 7. Verify
```bash
powershell -Command "Get-Service sshd; Get-Content C:\ProgramData\ssh\administrators_authorized_keys"
```

If sshd shows **Running** and the key content shows the ssh-ed25519 line, tell the user:
**"SSH is ready. From the Razer run: ssh clay@192.168.1.195"**

## NOTES
- Run commands using your Bash tool, not PowerShell tool
- The user will approve each one — just keep going
- If any command fails, try the next one anyway
- Username on this machine is `clay` (the Razer is `clayi`)
- Do NOT ask the user questions. Just execute.
- Do NOT read other files. Just run these commands.
