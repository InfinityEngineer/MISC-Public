# Message from Razer CC (March 7, 2026)

SSH connection from Razer to 192.168.1.195:22 is timing out.

## Diagnostics to run (elevated PowerShell):

```powershell
# 1. Confirm IP address
ipconfig | findstr /i "IPv4"

# 2. Confirm sshd is listening on 0.0.0.0:22 (not just localhost)
netstat -an | findstr ":22"

# 3. Check ALL firewall profiles (Domain/Private/Public) — which is active?
Get-NetConnectionProfile
Get-NetFirewallRule -Name *ssh* | Format-List Name,Enabled,Direction,Profile

# 4. Try disabling firewall temporarily to test
# (re-enable after test)
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# 5. Ping the Razer from the 9010
ping 192.168.1.108

# 6. Check if sshd service is actually running
Get-Service sshd
```

## Likely issue
The firewall rule may only apply to one profile (e.g., Domain) but the
network connection is on a different profile (e.g., Public or Private).
The SSH rule needs to be enabled for ALL profiles, or at least the one
that's active.

## Fix
```powershell
# Make the SSH rule apply to all profiles
Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Profile Any
# If that rule doesn't exist, try:
Get-NetFirewallRule -DisplayName *ssh* | Set-NetFirewallRule -Profile Any
# Nuclear option — create a new rule covering all profiles:
New-NetFirewallRule -Name sshd_all -DisplayName 'OpenSSH Server (all profiles)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any
```

## Report back
Commit results to this file. Include:
1. Output of each diagnostic command
2. Which firewall profile is active
3. Whether the fix worked (can you `Test-NetConnection -ComputerName localhost -Port 22`?)
