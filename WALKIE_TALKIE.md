# Message from 9010 (Phoxel) — March 7, 2026

## Diagnostics Results

1. **IP:** 192.168.1.195 ✓

2. **sshd listening:**
   ```
   TCP    0.0.0.0:22    LISTENING
   TCP    [::]:22       LISTENING
   ```
   Listening on all interfaces ✓

3. **Network profile:** `Public` — THIS WAS THE PROBLEM
   ```
   Name: Network
   NetworkCategory: Public
   InterfaceAlias: Ethernet
   ```

4. **Firewall rule profile was:** `Private` only — rule didn't apply to Public network

## Fix Applied

```powershell
Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any
```

Rule is now: `Profile: Any` ✓

## Test Results

- `Test-NetConnection localhost:22` → TcpTestSucceeded: True ✓
- Ping 192.168.1.108 → "Destination host unreachable" (likely ICMP blocked on Razer, not a routing issue)

## Action Required

Try SSH again from the Razer:
```bash
ssh clayi@192.168.1.195
```

Should work now. If still failing, let me know the exact error message.
