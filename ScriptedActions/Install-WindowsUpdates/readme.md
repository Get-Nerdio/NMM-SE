# Install-WindowsUpdates

Installs Windows Updates via the native WUA COM API (no PSWindowsUpdate). Supports exclusions from Nerdio Manager via variables.

- **NMM (Nerdio Manager for MSP):** `$InheritedVars.VariableName` (e.g. `$InheritedVars.ExcludeKB`)
- **NME (Nerdio Manager for Enterprise):** `$SecureVars.Variable_Name` (e.g. `$SecureVars.ExcludeKB`)

InheritedVars override SecureVars; both override script parameters.

## Viewing Script Output in NME

**NME does not display Custom Script Extension output in the portal.** The script writes to stdout (which Azure captures), but NME's UI may not show it. To view the script output:

1. **On the VM (RDP):** Open `C:\Windows\Temp\NerdioManagerLogs\Install-WindowsUpdates.txt` (when run as SYSTEM, `%TEMP%` = `C:\Windows\Temp`).

2. **Azure Portal:** VM → Extensions + applications → Extensions → select the extension → **View detailed status**. The StdOut substatus may contain the log (if Azure captured it).

3. **Run Command (Azure Portal):** VM → Run command → Run PowerShell script → run: `Get-Content C:\Windows\Temp\NerdioManagerLogs\Install-WindowsUpdates.txt` to retrieve the log.

4. **Contact Nerdio support** to request that NME display Custom Script Extension output in the Scripted Action details.

## Nerdio Manager Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `ExcludeKB` | `KB5012345,5023456` | Comma-separated KB numbers to exclude (with or without `KB` prefix). |
| `ExcludeUpdateTypes` | `Driver` | Comma-separated: `Software` or `Driver`. Excluded types are not installed. |
| `ExcludeCategoryIds` | `DefinitionUpdates` | Category GUIDs or friendly names: `DefinitionUpdates`, `SecurityUpdates`, `CriticalUpdates`, `Updates`. |
| `IncludeMicrosoftUpdate` | `true` | Use Microsoft Update (Windows + Office, etc.). Default: `true`. |
| `ExcludeOptional` | `false` | Skip optional (BrowseOnly) updates. Default: `false`. |
| `SkipUsoScan` | `false` | If `true`, skip UsoClient pre-scan (Win10/11). Default: `false`. |
| `UsoScanWaitSeconds` | `90` | Seconds to wait after UsoClient StartScan before WUA search. Default: `90`. |

## Usage

On Windows 10/11, the script runs **UsoClient StartScan** before the WUA search to refresh the update catalog so WUA finds updates (avoids "No updates found" when Settings shows updates). Set `SkipUsoScan=true` to skip this. If WUA still finds nothing, try increasing `UsoScanWaitSeconds` (e.g. 120).

- **Execution mode:** Use **IndividualWithRestart** in Nerdio.
- After a reboot, run the Scripted Action again to continue patching until no updates remain.
- **Logs:** `%TEMP%\NerdioManagerLogs\Install-WindowsUpdates.txt` (on the VM). The script outputs this log to stdout at the end so it may appear in the Custom Script Extension status in the Azure Portal (VM → Extensions → View detailed status). Nerdio Manager may or may not display extension output in its portal.
