# INSTRUCTIONS FOR CLAUDE CODE ON THE OPTIPLEX 9010

You are running on the Dell OptiPlex 9010. The display on this machine crashes after ~5-30 minutes of idle. Your ONLY job right now is to enable SSH so the Razer laptop can connect remotely.

## DO THIS NOW — RUN THESE COMMANDS IMMEDIATELY

Run each of these commands. The user will approve them. Do not explain, just execute.

### Command 1: Create the SSH authorized keys directory
```
mkdir C:\ProgramData\ssh -Force
```

### Command 2: Add the Razer's SSH public key
```
Set-Content C:\ProgramData\ssh\administrators_authorized_keys "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity"
```

### Command 3: Fix permissions on the key file (REQUIRED or SSH ignores it)
```
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "SYSTEM:F" /grant "Administrators:F"
```

### Command 4: Make sure SSH server is installed
```
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```
(If it says "already installed" that's fine, keep going)

### Command 5: Start SSH and set it to auto-start on boot
```
Start-Service sshd; Set-Service sshd -StartupType Automatic
```

### Command 6: Verify it's running
```
Get-Service sshd
```
Should say "Running". If it does, you're done. Tell the user "SSH is ready. Go to the Razer and run: ssh clay@192.168.1.195"

## IMPORTANT NOTES FOR THE AI

- The user CANNOT see the screen for long. Be fast. Run commands, don't chat.
- The user will be pressing Enter to approve tool calls. Keep it simple.
- Do NOT ask questions. Just run the commands above one by one.
- If any command fails, try the next one anyway.
- The username on this machine is `clay` (not `clayi` — that's the Razer).
- After all commands succeed, your job is done. The Razer will SSH in and take over.
