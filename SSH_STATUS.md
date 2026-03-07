# 9010 Status Report (Phoxel / 192.168.1.195)

## Task 1: SSH Server — COMPLETE

- sshd installed: Yes
- sshd running: Yes (Automatic)
- Firewall port 22: Open (OpenSSH-Server-In-TCP rule active)
- Port 22 listening: True (Test-NetConnection TcpTestSucceeded)
- IP Address: 192.168.1.195
- Razer public key installed: Yes
  - Path: C:\ProgramData\ssh\administrators_authorized_keys
  - Key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFd7PqcOPCAJR0gnleLWjl9TGMQvr2ZoXDKkr5QVM8OL clayi@Nostalgia-for-Infinity
  - Permissions: SYSTEM:(R), Administrators:(R), inheritance removed

**Razer can now SSH in:** `ssh clayi@192.168.1.195`

---

## Task 2: ReBAR UEFI Settings — BLOCKED (needs info from Razer)

### Problem
The script uses variable name `"Setup"` with GUID `{EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9}`.
**That variable does not exist on this machine.**

`EC87D643` GUID only has: `NBPlatformData` (not "Setup").

### What works
- SeSystemEnvironmentPrivilege: Can be enabled (fixed struct packing bug in original script)
- UEFI variable read/write: Working once correct name+GUID are provided

### Full UEFI NVRAM variable list (for reference)
```
TcgMonotonicCounter    {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
PchInit                {E6C2F70A-B604-4877-85BA-DEEC89E117EB}
MonotonicCounter       {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
FPDT_Variable          {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
Lang                   {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
MeBiosExtensionSetup   {1BAD711C-D451-4241-B1F3-8537812E0C70}
M                      {FF2E9FC7-D16F-434A-A24E-C99519B7EB93}
P                      {FF2E9FC7-D16F-434A-A24E-C99519B7EB93}
ConsoleLock            {368CDA0D-CF31-4B9B-8CF6-E7D1BFFF157E}
ConOut                 {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
BootFFFE               {5990C250-676B-4FF7-8A0D-529319D0B254}
BootFFFD               {5990C250-676B-4FF7-8A0D-529319D0B254}
BootFFFC               {5990C250-676B-4FF7-8A0D-529319D0B254}
BootFFFB               {5990C250-676B-4FF7-8A0D-529319D0B254}
TPMPERBIOSFLAGS        {7D3DCEEE-CBCE-4EA7-8709-6E552F1EDBDE}
AMITCGPPIVAR           {A8A2093B-FEFA-43C1-8E62-CE526847265E}
TxtOneTouch            {3D989471-CFAC-46B7-9B1C-08430109402D}
TcgPPIVarAddr          {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
Rc00000000             {FF2E9FC7-D16F-434A-A24E-C99519B7EB93}
Rd00000000             {FF2E9FC7-D16F-434A-A24E-C99519B7EB93}
Ar00000000             {FF2E9FC7-D16F-434A-A24E-C99519B7EB93}
An00000000             {FF2E9FC7-D16F-434A-A24E-C99519B7EB93}
ConIn                  {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
AMITSESetup            {C811FA38-42C8-4579-A9BB-60E94EDDFB34}
GsetLegacyIplDefaultValue {3A21751E-BD32-4825-8754-82A47F01B09B}
GsetUefiIplDefaultValue   {7F3301C7-2405-4765-AA2E-D9ED28AEA950}
db                     {D719B2CB-3D3A-4596-A3BC-DAD00E67656F}
KEK                    {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
PK                     {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
S3CpuThrottle          {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
EfiTime                {9D0DA369-540B-46F8-85A0-2B5F2C301E15}
DIAGEEPROM_VAR         {8EBE3D07-3420-4BFA-8C13-3A4E0FAE6860}
NetworkStackVar        {D1405D16-7AFC-4695-BB12-41459D3695A2}
CurrentPolicy          {77FA9ABD-0359-4D32-BD60-28F4E78F784B}
UnlockIDCopy           {EAEC226F-C9A3-477A-A826-DDC716CDC0E3}
OfflineUniqueIDRandomSeed    {EAEC226F-C9A3-477A-A826-DDC716CDC0E3}
OfflineUniqueIDRandomSeedCRC {EAEC226F-C9A3-477A-A826-DDC716CDC0E3}
MemoryOverwriteRequestControl     {E20939BE-32D4-41BE-A150-897F85D49829}
MemoryOverwriteRequestControlLock {BB983CCF-151D-40E1-A07B-4A17BE168292}
AcpiGlobalVariable     {C020489E-6DB2-4EF2-9AA5-CA06FC11D36A}
OfflineUniqueIDEKPub   {EAEC226F-C9A3-477A-A826-DDC716CDC0E3}
OfflineUniqueIDEKPubCRC {EAEC226F-C9A3-477A-A826-DDC716CDC0E3}
AUTOPILOT_MARKER       {616E2EA6-AF89-7EB3-F2EF-4E47368A657B}
dbx                    {D719B2CB-3D3A-4596-A3BC-DAD00E67656F}
UIT_HEADER             {FE47349A-7F0D-4641-822B-34BAA28ECDD0}
UIT_DATA               {FE47349A-7F0D-4641-822B-34BAA28ECDD0}
Boot0005               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
Boot0006               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
Boot0008               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
Boot0009               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
Boot000A               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
Boot000C               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
Boot000D               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
PBRDevicePath          {A9B5F8D2-CB6D-42C2-BC01-B5FFAAE4335E}
Timeout                {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
ReBarState             {A3C5B77A-C88F-4A93-BF1C-4A92A32C65CE}
Boot0011               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
BugCheckProgress       {BA57E015-65B3-4C3C-B274-659192F699E3}
BugCheckCode           {BA57E015-65B3-4C3C-B274-659192F699E3}
BugCheckParameter1     {BA57E015-65B3-4C3C-B274-659192F699E3}
Boot0001               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
BootOrder              {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
PlatformLang           {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
IccAdvancedSetupDataVar {7B77FB8B-1E0D-4D7E-953F-3980A261E077}
SignatureSupport        {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
SecureBoot             {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
SetupMode              {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
GNVS_PTR               {0A602C5B-05A0-40C4-9181-EDCD891D0003}
PchS3Peim              {E6C2F70A-B604-4877-85BA-DEEC89E117EB}
NBPlatformData         {EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9}
BootList               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
PlatformLangCodes      {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
LangCodes              {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
OsIndicationsSupported {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
ConOutDev              {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
ConInDev               {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
BootOptionSupport      {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
ErrOutDev              {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
ErrOut                 {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
BootCurrent            {8BE4DF61-93CA-11D2-AA0D-00E098032B8C}
AuthLockFlg            {532B6532-6499-428D-ACB1-F6F779C94DF9}
```

### Next step needed from Razer
Check `ifr_9010.txt` for the VarStore definition that contains offsets:
- 0x002 (Above 4G Decoding)
- 0xBDE (Launch CSM)
- 0xBDF (Boot option filter)
- 0x02D/0x02E/0x02F (OpROM settings)

Look for `VarStore` entries and match the GUID + variable name. 
The correct variable name is probably NOT "Setup" on this Dell firmware.
Likely candidates from the NVRAM list above:
- `AMITSESetup` {C811FA38-42C8-4579-A9BB-60E94EDDFB34}
- `GsetUefiIplDefaultValue` {7F3301C7-2405-4765-AA2E-D9ED28AEA950}
- `GsetLegacyIplDefaultValue` {3A21751E-BD32-4825-8754-82A47F01B09B}
- `MeBiosExtensionSetup` {1BAD711C-D451-4241-B1F3-8537812E0C70}

Once Razer identifies the correct VarStore, update `apply_rebar_settings.ps1` and push.
The 9010 will re-check the repo and run the updated script.
