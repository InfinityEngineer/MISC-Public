# apply_rebar_settings.ps1
# Modifies the Dell 9010 "Setup" UEFI variable from Windows to enable ReBAR.
# Must be run as Administrator (elevated PowerShell).
#
# This is equivalent to running these setup_var commands in modGRUBShell:
#   setup_var 0x2   0x1   (Above 4G Decoding = Enabled)
#   setup_var 0xBDE 0x02  (Launch CSM = Never)
#   setup_var 0xBDF 0x02  (Boot option filter = UEFI only)
#   setup_var 0x2D  0x02  (PXE OpROM = UEFI only)
#   setup_var 0x2E  0x02  (Storage OpROM = UEFI only)
#   setup_var 0x2F  0x02  (Video OpROM = UEFI only)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# --- P/Invoke declarations ---
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class UefiVar
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern uint GetFirmwareEnvironmentVariableExW(
        string lpName, string lpGuid,
        byte[] pBuffer, uint nSize, out uint pdwAttribubutes);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SetFirmwareEnvironmentVariableExW(
        string lpName, string lpGuid,
        byte[] pValue, uint nSize, uint dwAttributes);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(
        IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LookupPrivilegeValue(
        string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(
        IntPtr TokenHandle, bool DisableAll,
        ref TOKEN_PRIVILEGES NewState, uint BufferLength,
        IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    [StructLayout(LayoutKind.Sequential)]
    public struct TOKEN_PRIVILEGES
    {
        public uint PrivilegeCount;
        public long Luid;
        public uint Attributes;
    }

    public static void EnablePrivilege(string privilege)
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x0028, out token))
            throw new Exception("OpenProcessToken failed: " + Marshal.GetLastWin32Error());

        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
        tp.PrivilegeCount = 1;
        tp.Attributes = 0x00000002; // SE_PRIVILEGE_ENABLED
        if (!LookupPrivilegeValue(null, privilege, out tp.Luid))
            throw new Exception("LookupPrivilegeValue failed: " + Marshal.GetLastWin32Error());

        if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero))
            throw new Exception("AdjustTokenPrivileges failed: " + Marshal.GetLastWin32Error());
    }
}
"@

# --- Configuration ---
$VarName  = "Setup"
$VarGuid  = "{EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9}"
$VarSize  = 3291  # 0xCDB bytes

$patches = @(
    @{ Offset = 0x002; Value = 0x01; Desc = "Above 4G Decoding = Enabled" },
    @{ Offset = 0xBDE; Value = 0x02; Desc = "Launch CSM = Never" },
    @{ Offset = 0xBDF; Value = 0x02; Desc = "Boot option filter = UEFI only" },
    @{ Offset = 0x02D; Value = 0x02; Desc = "PXE OpROM = UEFI only" },
    @{ Offset = 0x02E; Value = 0x02; Desc = "Storage OpROM = UEFI only" },
    @{ Offset = 0x02F; Value = 0x02; Desc = "Video OpROM = UEFI only" }
)

# --- Enable privilege ---
Write-Host "Enabling SeSystemEnvironmentPrivilege..."
[UefiVar]::EnablePrivilege("SeSystemEnvironmentPrivilege")

# --- Read current variable ---
Write-Host "Reading UEFI variable '$VarName' ($VarGuid)..."
$buffer = New-Object byte[] $VarSize
[uint32]$attrs = 0

$bytesRead = [UefiVar]::GetFirmwareEnvironmentVariableExW(
    $VarName, $VarGuid, $buffer, [uint32]$VarSize, [ref]$attrs)

if ($bytesRead -eq 0) {
    $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "FAILED to read variable. Win32 error: $err" -ForegroundColor Red
    if ($err -eq 1314) {
        Write-Host "  Error 1314 = privilege not held. Are you running as Administrator?" -ForegroundColor Yellow
    }
    exit 1
}

Write-Host "Read $bytesRead bytes (attributes=0x$($attrs.ToString('X')))"
Write-Host ""

# --- Apply patches ---
$changed = $false
foreach ($p in $patches) {
    $off = $p.Offset
    $want = $p.Value
    $desc = $p.Desc
    $cur = $buffer[$off]

    if ($cur -eq $want) {
        Write-Host ("  [OK]  0x{0:X3} = 0x{1:X2} (correct) - {2}" -f $off, $cur, $desc) -ForegroundColor Green
    } else {
        Write-Host ("  [FIX] 0x{0:X3} = 0x{1:X2} -> 0x{2:X2} - {3}" -f $off, $cur, $want, $desc) -ForegroundColor Yellow
        $buffer[$off] = [byte]$want
        $changed = $true
    }
}

Write-Host ""

if (-not $changed) {
    Write-Host "All settings already correct. Nothing to do." -ForegroundColor Green
    exit 0
}

# --- Write back ---
Write-Host "Writing modified variable..."
$ok = [UefiVar]::SetFirmwareEnvironmentVariableExW(
    $VarName, $VarGuid, $buffer, [uint32]$bytesRead, $attrs)

if (-not $ok) {
    $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "FAILED to write variable. Win32 error: $err" -ForegroundColor Red
    exit 1
}

Write-Host "SUCCESS - settings applied." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Reboot"
Write-Host "  2. Run ReBarState.exe, set BAR size to 32 (unlimited)"
Write-Host "  3. Reboot again"
Write-Host "  4. Verify with GPU-Z (Advanced tab -> Resizable BAR)"
