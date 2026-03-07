# INSTRUCTIONS FOR CLAUDE CODE ON THE OPTIPLEX 9010

**Great diagnostic work! Username is clayi, not clay. Now we need TWO fixes.**

## FIX 1: Re-enable the admin key override in sshd_config

The Match Group administrators block was commented out. We need it BACK so sshd reads the administrators_authorized_keys file (which has correct permissions).

```bash
powershell -Command "(Get-Content C:\ProgramData\ssh\sshd_config) -replace '^#Match Group administrators','Match Group administrators' -replace '^#\s*AuthorizedKeysFile __PROGRAMDATA__','   AuthorizedKeysFile __PROGRAMDATA__' | Set-Content C:\ProgramData\ssh\sshd_config"
```

## FIX 2: Also fix per-user key permissions as backup

```bash
icacls C:\Users\clayi\.ssh\authorized_keys /inheritance:r /grant "clayi:(F)" /grant "NT AUTHORITY\SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)"
```

## FIX 3: Restart sshd to apply config change

```bash
powershell -Command "Restart-Service sshd"
```

## VERIFY: Run these and put output in OPTIPLEX_STATUS.md

```bash
powershell -Command "Get-Service sshd | Format-List Name,Status"
```

```bash
type C:\ProgramData\ssh\sshd_config | findstr /n "Match AuthorizedKeysFile"
```

```bash
icacls C:\Users\clayi\.ssh\authorized_keys
```

```bash
icacls C:\ProgramData\ssh\administrators_authorized_keys
```

**Update OPTIPLEX_STATUS.md with results, commit and push.**

Then tell the user: **"Done. From the Razer run: ssh clayi@192.168.1.195"**
