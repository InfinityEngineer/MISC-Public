# INSTRUCTIONS FOR CLAUDE CODE ON THE OPTIPLEX 9010

You are running on the Dell OptiPlex 9010. The display on this machine crashes after ~5-30 minutes of idle. Your ONLY job right now is to enable SSH so the Razer laptop can connect remotely.

**TIME IS SHORT. Do not explain anything. Just run each command immediately, one after another.**

## STEP 1: DIAGNOSE — Run these and show the user the output

```bash
type C:\ProgramData\ssh\administrators_authorized_keys
```

```bash
icacls C:\ProgramData\ssh\administrators_authorized_keys
```

```bash
type C:\ProgramData\ssh\sshd_config | findstr -i "AuthorizedKeysFile Match administrators"
```

```bash
powershell -Command "Get-Service sshd | Format-List Name,Status,StartType"
```

**Show the user ALL output from the above commands. This is critical for debugging.**

## STEP 2: FIX — Run these commands in order

### 2a. Delete and recreate the key file cleanly (no BOM, no quotes)
```bash
powershell -Command "Remove-Item C:\ProgramData\ssh\administrators_authorized_keys -Force -ErrorAction SilentlyContinue; [System.IO.File]::WriteAllText('C:\ProgramData\ssh\administrators_authorized_keys', 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity' + [char]10)"
```

### 2b. Fix permissions — remove ALL inherited ACLs, grant ONLY System and Administrators
```bash
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /remove "BUILTIN\Users" /remove "NT AUTHORITY\Authenticated Users" /grant "NT AUTHORITY\SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)"
```

### 2c. Also set up the per-user key file as a fallback
```bash
powershell -Command "mkdir C:\Users\clay\.ssh -Force; [System.IO.File]::WriteAllText('C:\Users\clay\.ssh\authorized_keys', 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity' + [char]10)"
```

### 2d. Comment out the admin override in sshd_config so it checks BOTH key files
```bash
powershell -Command "(Get-Content C:\ProgramData\ssh\sshd_config) -replace '^Match Group administrators','#Match Group administrators' -replace '^\s*AuthorizedKeysFile __PROGRAMDATA__','#   AuthorizedKeysFile __PROGRAMDATA__' | Set-Content C:\ProgramData\ssh\sshd_config"
```

### 2e. Restart SSH server
```bash
powershell -Command "Restart-Service sshd"
```

## STEP 3: VERIFY — Run these and show the user

```bash
type C:\ProgramData\ssh\administrators_authorized_keys
```

```bash
icacls C:\ProgramData\ssh\administrators_authorized_keys
```

```bash
type C:\Users\clay\.ssh\authorized_keys
```

```bash
powershell -Command "Get-Service sshd"
```

**Tell the user: "Done. From the Razer run: ssh clay@192.168.1.195"**

## NOTES
- The user will approve each command — just keep going
- If any command fails, try the next one anyway
- Username on this machine is `clay` (the Razer is `clayi`)
- Do NOT ask questions. Just execute.
- SHOW ALL OUTPUT to the user so they can relay it if needed
