<#
.SYNOPSIS
    Installs Windows Updates via the native Windows Update Agent (WUA) COM API—no PSWindowsUpdate required.
    Supports exclusions via variables from Nerdio Manager for Enterprise.

.DESCRIPTION
    This script:
    1. Uses Microsoft.Update.Session (WUA COM) to search, download, and install updates.
    2. Excludes specific KBs, update types (Software/Driver), or category IDs based on variables.
    3. Integrates with Nerdio Manager via InheritedVars (NMM) or SecureVars (NME).
    4. Loops until no applicable updates remain or a reboot is required.

.EXECUTION MODE NMM
    IndividualWithRestart

.TAGS
    Nerdio, Windows Update, WUA, Patching

.NERDIO MANAGER VARIABLES
    NMM: InheritedVars (e.g. $InheritedVars.ExcludeKB).  NME: SecureVars (e.g. $SecureVars.ExcludeKB).
    InheritedVars override SecureVars; both override script parameters.

    ExcludeKB            - Comma-separated KB numbers to exclude. With or without "KB" prefix.
                          Example: "KB5012345,5023456" or "5012345,5023456"
    ExcludeUpdateTypes   - Comma-separated: "Software" or "Driver". Excluded types are not installed.
                          Example: "Driver" to skip all driver updates.
    ExcludeCategoryIds   - Comma-separated Category GUIDs or friendly names. Updates in these categories are excluded.
                          Friendly names: DefinitionUpdates, SecurityUpdates, CriticalUpdates, Updates
                          Example: "DefinitionUpdates" or "EBFC1FC5-71A4-4F7B-9ACA-3B9A503104A0"
    IncludeMicrosoftUpdate - "true"/"false". If true (default), use Microsoft Update (Windows + Office, etc.).
    ExcludeOptional      - "true"/"false". If true, skip optional (BrowseOnly) updates. Default: false.
    SkipUsoScan          - "true"/"false". If false (default), run UsoClient StartScan before WUA search to refresh catalog (Win10/11).
    UsoScanWaitSeconds   - Seconds to wait after UsoClient StartScan before WUA search. Default: 90.

.NOTES
    - Output appears in console (Write-Output) and in Nerdio Manager script output via $Context.Log() when Context is available.
    - Logs: $env:TEMP\NerdioManagerLogs\Install-WindowsUpdates.txt
    - Run with elevated privileges. For NMM IndividualWithRestart, a reboot is performed by NMM after the script exits.
    - Category GUIDs: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ff357803(v=vs.85)
    - If Microsoft Update is not registered (error 0x80248014 / WU_E_DS_UNKNOWNSERVICE), the script automatically falls back to Windows Update only.
#>

#Requires -RunAsAdministrator

param (
    [string]$ExcludeKB = '',
    [string]$ExcludeUpdateTypes = '',
    [string]$ExcludeCategoryIds = '',
    [string]$IncludeMicrosoftUpdate = 'true',
    [string]$ExcludeOptional = 'false',
    [string]$SkipUsoScan = 'false',
    [int]$UsoScanWaitSeconds = 90
)

# Resolve Nerdio Manager variables: params < SecureVars (NME) < InheritedVars (NMM)
if ($SecureVars -and $null -ne $SecureVars.ExcludeKB -and [string]::IsNullOrWhiteSpace($SecureVars.ExcludeKB) -eq $false) { $ExcludeKB = $SecureVars.ExcludeKB }
if ($InheritedVars -and $null -ne $InheritedVars.ExcludeKB -and [string]::IsNullOrWhiteSpace($InheritedVars.ExcludeKB) -eq $false) { $ExcludeKB = $InheritedVars.ExcludeKB }

if ($SecureVars -and $null -ne $SecureVars.ExcludeUpdateTypes -and [string]::IsNullOrWhiteSpace($SecureVars.ExcludeUpdateTypes) -eq $false) { $ExcludeUpdateTypes = $SecureVars.ExcludeUpdateTypes }
if ($InheritedVars -and $null -ne $InheritedVars.ExcludeUpdateTypes -and [string]::IsNullOrWhiteSpace($InheritedVars.ExcludeUpdateTypes) -eq $false) { $ExcludeUpdateTypes = $InheritedVars.ExcludeUpdateTypes }

if ($SecureVars -and $null -ne $SecureVars.ExcludeCategoryIds -and [string]::IsNullOrWhiteSpace($SecureVars.ExcludeCategoryIds) -eq $false) { $ExcludeCategoryIds = $SecureVars.ExcludeCategoryIds }
if ($InheritedVars -and $null -ne $InheritedVars.ExcludeCategoryIds -and [string]::IsNullOrWhiteSpace($InheritedVars.ExcludeCategoryIds) -eq $false) { $ExcludeCategoryIds = $InheritedVars.ExcludeCategoryIds }

if ($SecureVars -and $null -ne $SecureVars.IncludeMicrosoftUpdate -and [string]::IsNullOrWhiteSpace($SecureVars.IncludeMicrosoftUpdate) -eq $false) { $IncludeMicrosoftUpdate = $SecureVars.IncludeMicrosoftUpdate }
if ($InheritedVars -and $null -ne $InheritedVars.IncludeMicrosoftUpdate -and [string]::IsNullOrWhiteSpace($InheritedVars.IncludeMicrosoftUpdate) -eq $false) { $IncludeMicrosoftUpdate = $InheritedVars.IncludeMicrosoftUpdate }

if ($SecureVars -and $null -ne $SecureVars.ExcludeOptional -and [string]::IsNullOrWhiteSpace($SecureVars.ExcludeOptional) -eq $false) { $ExcludeOptional = $SecureVars.ExcludeOptional }
if ($InheritedVars -and $null -ne $InheritedVars.ExcludeOptional -and [string]::IsNullOrWhiteSpace($InheritedVars.ExcludeOptional) -eq $false) { $ExcludeOptional = $InheritedVars.ExcludeOptional }

if ($SecureVars -and $null -ne $SecureVars.SkipUsoScan -and [string]::IsNullOrWhiteSpace($SecureVars.SkipUsoScan) -eq $false) { $SkipUsoScan = $SecureVars.SkipUsoScan }
if ($InheritedVars -and $null -ne $InheritedVars.SkipUsoScan -and [string]::IsNullOrWhiteSpace($InheritedVars.SkipUsoScan) -eq $false) { $SkipUsoScan = $InheritedVars.SkipUsoScan }
if ($SecureVars -and $null -ne $SecureVars.UsoScanWaitSeconds -and [string]::IsNullOrWhiteSpace($SecureVars.UsoScanWaitSeconds) -eq $false) { $UsoScanWaitSeconds = [int]$SecureVars.UsoScanWaitSeconds }
if ($InheritedVars -and $null -ne $InheritedVars.UsoScanWaitSeconds -and [string]::IsNullOrWhiteSpace($InheritedVars.UsoScanWaitSeconds) -eq $false) { $UsoScanWaitSeconds = [int]$InheritedVars.UsoScanWaitSeconds }

# Friendly names to Category GUIDs
$CategoryIdMap = @{
    'DefinitionUpdates' = 'EBFC1FC5-71A4-4F7B-9ACA-3B9A503104A0'
    'SecurityUpdates'   = '0FA1201D-4330-4FA8-8AE9-B877473B6441'
    'CriticalUpdates'   = 'E6CF1350-C01B-414D-A61F-263D14D133B4'
    'Updates'           = 'CD5FFD1E-E932-4E3A-BF74-18BF0B1BBD83'
}

# WUA Type: 1 = Software, 2 = Driver
$UpdateTypeSoftware = 1
$UpdateTypeDriver   = 2

# Output to console and to Nerdio Manager script output (when $Context is available)
function Write-ScriptOutput {
    param([string]$Message = '', [string]$Level = 'INFO')
    Write-Output $Message
    if ([string]::IsNullOrEmpty($Message)) { return }
    try {
        $ctx = Get-Variable -Name Context -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $ctx -and (Get-Member -InputObject $ctx -Name Log -MemberType Method -ErrorAction SilentlyContinue)) {
            $ctx.Log("${Level}: $Message")
        }
    }
    catch { }
}

function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [string]$LogFilePath = "$env:TEMP\NerdioManagerLogs",
        [string]$LogName = 'Install-WindowsUpdates.txt',
        [bool]$FirstLogInput = $false
    )
    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType Directory -Path $LogFilePath -Force | Out-Null
    }
    if ($FirstLogInput) {
        Add-Content -Path (Join-Path $LogFilePath $LogName) -Value "################# New Script Run #################"
    }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path (Join-Path $LogFilePath $LogName) -Value "$ts [$Level]: $Message"
}

function Resolve-ExcludeCategoryGuids {
    param ([string]$InputIds)
    if ([string]::IsNullOrWhiteSpace($InputIds)) { return @() }
    $out = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in ($InputIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($CategoryIdMap.ContainsKey($id)) {
            [void]$out.Add($CategoryIdMap[$id])
        } else {
            [void]$out.Add($id)
        }
    }
    return @($out)
}

function Resolve-ExcludeKbNumbers {
    param ([string]$InputKb)
    if ([string]::IsNullOrWhiteSpace($InputKb)) { return @() }
    $list = @()
    foreach ($v in ($InputKb -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $n = $v -replace '^KB', ''
        if ($n -match '^\d+$') { $list += $n }
    }
    return $list
}

function Resolve-ExcludeTypes {
    param ([string]$InputTypes)
    if ([string]::IsNullOrWhiteSpace($InputTypes)) { return @() }
    $types = @()
    foreach ($t in ($InputTypes -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        switch ($t) {
            'Software' { $types += $UpdateTypeSoftware }
            'Driver'   { $types += $UpdateTypeDriver }
            default    { }
        }
    }
    return $types
}

function Test-UpdateExcluded {
    param (
        $Update,
        [string[]]$ExcludeKbNums,
        [int[]]$ExcludeTypes,
        [string[]]$ExcludeCatGuids
    )
    # Exclude by Type (1=Software, 2=Driver)
    if ($ExcludeTypes.Count -gt 0 -and $Update.Type -in $ExcludeTypes) {
        return $true
    }
    # Exclude by KB
    if ($ExcludeKbNums.Count -gt 0) {
        $title = [string]$Update.Title
        foreach ($kb in $ExcludeKbNums) {
            if ($title -match "\b$kb\b") { return $true }
        }
        try {
            foreach ($kbId in $Update.KBArticleIDs) {
                $k = [string]$kbId -replace '^KB', ''
                if ($ExcludeKbNums -contains $k) { return $true }
            }
        } catch { }
    }
    # Exclude by Category
    if ($ExcludeCatGuids.Count -gt 0) {
        try {
            foreach ($cat in $Update.Categories) {
                $cid = [string]$cat.CategoryID
                foreach ($g in $ExcludeCatGuids) {
                    if ($cid -eq $g) { return $true }
                }
            }
        } catch { }
    }
    return $false
}

# Parse exclusions once
$ExcludeKbNums   = Resolve-ExcludeKbNumbers -InputKb $ExcludeKB
$ExcludeTypes    = Resolve-ExcludeTypes -InputTypes $ExcludeUpdateTypes
$ExcludeCatGuids = Resolve-ExcludeCategoryGuids -InputIds $ExcludeCategoryIds
$UseMicrosoftUpdate = ($IncludeMicrosoftUpdate -eq 'true' -or $IncludeMicrosoftUpdate -eq '1' -or $IncludeMicrosoftUpdate -eq 'True')
$SkipOptional   = ($ExcludeOptional -eq 'true' -or $ExcludeOptional -eq '1' -or $ExcludeOptional -eq 'True')

NMMLogOutput -Level Information -Message "Install-WindowsUpdates started. ExcludeKB=$ExcludeKB; ExcludeUpdateTypes=$ExcludeUpdateTypes; ExcludeCategoryIds=$ExcludeCategoryIds; IncludeMicrosoftUpdate=$UseMicrosoftUpdate; ExcludeOptional=$SkipOptional" -FirstLogInput $true
Write-ScriptOutput "Install-WindowsUpdates started. Searching for updates..."

# Pre-scan with UsoClient (Win10/11) to refresh the update catalog so WUA Search() finds updates
$RunUsoScan = ($SkipUsoScan -ne 'true' -and $SkipUsoScan -ne '1' -and $SkipUsoScan -ne 'True')
$UsoClientPath = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
if ($RunUsoScan -and (Test-Path -LiteralPath $UsoClientPath)) {
    Write-ScriptOutput "Running Windows Update scan (UsoClient StartScan) to refresh catalog... waiting $UsoScanWaitSeconds seconds."
    NMMLogOutput -Level Information -Message "Running UsoClient StartScan, waiting $UsoScanWaitSeconds seconds."
    try {
        $proc = Start-Process -FilePath $UsoClientPath -ArgumentList 'StartScan' -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds $UsoScanWaitSeconds
    }
    catch {
        NMMLogOutput -Level Warning -Message "UsoClient StartScan failed: $($_.Exception.Message)"
        Write-ScriptOutput "UsoClient StartScan failed (continuing anyway): $($_.Exception.Message)" -Level 'WARNING'
    }
    Write-ScriptOutput "Pre-scan wait complete. Searching for updates via WUA..."
}
elseif ($RunUsoScan -and -not (Test-Path -LiteralPath $UsoClientPath)) {
    Write-ScriptOutput "UsoClient not found at $UsoClientPath (skipping pre-scan)."
    NMMLogOutput -Level Information -Message "UsoClient not found, skipping pre-scan."
}

try {
    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    # Force online search so WUA contacts the update service (avoids empty results when Settings shows updates)
    $Searcher.Online = $true

    # 2 = ssWindowsUpdate, 3 = ssOthers (used with ServiceID for Microsoft Update)
    if ($UseMicrosoftUpdate) {
        $Searcher.ServerSelection = 3
        $Searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
        NMMLogOutput -Level Information -Message "Using Microsoft Update service."
    } else {
        $Searcher.ServerSelection = 2
        NMMLogOutput -Level Information -Message "Using Windows Update only."
    }

    $criteria = 'IsInstalled=0 and IsHidden=0'
    if ($SkipOptional) {
        $criteria += ' and BrowseOnly=0'
    }

    $totalInstalled = 0
    $maxRounds = 50
    $round = 0
    # 0x80248014 = WU_E_DS_UNKNOWNSERVICE (Microsoft Update service not in data store); fall back to Windows Update only
    $WU_E_DS_UNKNOWNSERVICE = [int32]0x80248014
    $microsoftUpdateFallbackUsed = $false

    while ($round -lt $maxRounds) {
        $round++
        NMMLogOutput -Level Information -Message "Search round $round : $criteria"

        try {
            $Result = $Searcher.Search($criteria)
        }
        catch {
            $hResult = if ($_.Exception.HResult) { $_.Exception.HResult } else { 0 }
            if (-not $microsoftUpdateFallbackUsed -and ($hResult -eq $WU_E_DS_UNKNOWNSERVICE -or $_.Exception.Message -match '0x80248014')) {
                NMMLogOutput -Level Warning -Message "Microsoft Update service not available (0x80248014). Falling back to Windows Update only."
                Write-ScriptOutput "Microsoft Update service not available (0x80248014). Falling back to Windows Update only." -Level 'WARNING'
                # Create a fresh searcher for Windows Update (avoids carrying over bad state)
                $Searcher = $Session.CreateUpdateSearcher()
                $Searcher.Online = $true
                $Searcher.ServerSelection = 2  # ssWindowsUpdate
                $microsoftUpdateFallbackUsed = $true
                try {
                    $Result = $Searcher.Search($criteria)
                }
                catch {
                    # Some systems require a valid ServiceID even when ServerSelection=2
                    if ($_.Exception.Message -match '0x800706A9|UUID|universal unique') {
                        $Searcher.ServiceID = '9482f4b4-e343-43b6-b170-9a65bc822c77'  # Windows Update GUID
                        $Result = $Searcher.Search($criteria)
                    }
                    else { throw }
                }
            }
            else {
                throw
            }
        }
        $Updates = $Result.Updates

        if ($Updates.Count -eq 0) {
            NMMLogOutput -Level Information -Message "No more updates found. Exiting."
            Write-ScriptOutput "No updates found."
            if ($round -eq 1) {
                Write-ScriptOutput "Tip: The script runs UsoClient StartScan first (unless SkipUsoScan=true). If still no updates, try increasing UsoScanWaitSeconds (default 90)."
            }
            break
        }

        $ToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($U in $Updates) {
            if (Test-UpdateExcluded -Update $U -ExcludeKbNums $ExcludeKbNums -ExcludeTypes $ExcludeTypes -ExcludeCatGuids $ExcludeCatGuids) {
                NMMLogOutput -Level Information -Message "Excluded: $($U.Title)"
                continue
            }
            [void]$ToInstall.Add($U)
        }

        if ($ToInstall.Count -eq 0) {
            NMMLogOutput -Level Information -Message "All $($Updates.Count) update(s) were excluded by filters. No applicable updates to install."
            Write-ScriptOutput "All $($Updates.Count) update(s) were excluded by filters. No applicable updates to install."
            break
        }

        NMMLogOutput -Level Information -Message "To install: $($ToInstall.Count) update(s)."
        Write-ScriptOutput ""
        Write-ScriptOutput "=== Available/Applicable updates to install ($($ToInstall.Count)) ==="
        for ($i = 0; $i -lt $ToInstall.Count; $i++) {
            $u = $ToInstall.Item($i)
            Write-ScriptOutput "  - $($u.Title)"
        }
        Write-ScriptOutput ""

        # Download
        $Downloader = $Session.CreateUpdateDownloader()
        $Downloader.Updates = $ToInstall
        $DlResult = $Downloader.Download()
        # Download result: 0=NotStarted,1=InProgress,2=Succeeded,3=SucceededWithErrors,4=Failed,5=Aborted
        if ($DlResult.ResultCode -eq 4 -or $DlResult.ResultCode -eq 5) {
            NMMLogOutput -Level Error -Message "Download failed or aborted. ResultCode=$($DlResult.ResultCode)."
            Write-ScriptOutput "Download failed or aborted. ResultCode=$($DlResult.ResultCode)." -Level 'ERROR'
            break
        }

        # Install
        $Installer = $Session.CreateUpdateInstaller()
        $Installer.Updates = $ToInstall
        $InstResult = $Installer.Install()
        # 0=NotStarted,1=InProgress,2=Succeeded,3=SucceededWithErrors,4=Failed,5=Aborted
        NMMLogOutput -Level Information -Message "Install ResultCode=$($InstResult.ResultCode). RebootRequired=$($InstResult.RebootRequired)."
        Write-ScriptOutput "=== Installed ($($ToInstall.Count)) ==="
        Write-ScriptOutput "ResultCode: $($InstResult.ResultCode) (2=Succeeded, 3=SucceededWithErrors, 4=Failed, 5=Aborted). RebootRequired: $($InstResult.RebootRequired)"
        for ($i = 0; $i -lt $ToInstall.Count; $i++) {
            $u = $ToInstall.Item($i)
            NMMLogOutput -Level Information -Message "  - $($u.Title)"
            Write-ScriptOutput "  - $($u.Title)"
        }
        Write-ScriptOutput ""
        $totalInstalled += $ToInstall.Count

        if ($InstResult.RebootRequired) {
            NMMLogOutput -Level Information -Message "Reboot required. Exiting so NMM (IndividualWithRestart) can perform the restart. Run the script again after reboot to continue patching."
            Write-ScriptOutput "Reboot required. Run the script again after reboot to continue patching."
            break
        }

        if ($InstResult.ResultCode -eq 4 -or $InstResult.ResultCode -eq 5) {
            NMMLogOutput -Level Warning -Message "Install failed or aborted. Stopping."
            Write-ScriptOutput "Install failed or aborted. ResultCode=$($InstResult.ResultCode)." -Level 'WARNING'
            break
        }
    }

    NMMLogOutput -Level Information -Message "Install-WindowsUpdates finished. Total updates installed this run: $totalInstalled."
    Write-ScriptOutput "=== Summary ==="
    Write-ScriptOutput "Total updates installed this run: $totalInstalled"
}
catch {
    NMMLogOutput -Level Error -Message "Exception: $($_.Exception.Message)"
    throw
}
finally {
    # Output log file to stdout so Custom Script Extension captures it (NME may not display it in portal)
    $logFile = Join-Path "$env:TEMP\NerdioManagerLogs" "Install-WindowsUpdates.txt"
    if (Test-Path -LiteralPath $logFile) {
        $logContent = Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue
        if ($logContent) {
            Write-Output ""
            Write-Output "=== Script Log (from $logFile) ==="
            Write-Output $logContent
            try { [Console]::Out.Flush() } catch { }
        }
    }
}