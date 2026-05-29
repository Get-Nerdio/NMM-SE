<#
.SYNOPSIS
    Formats the local NVMe temp disk on an Azure Ev6/Easv6-series VM (e.g. Standard_E8asd_v6)
    and hosts the Windows page file on it.

.DESCRIPTION
    Ev6/Easv6-series VMs expose their ephemeral temp storage as a local NVMe device.
    This script:
      1. Locates the uninitialized (RAW) NVMe disk.
      2. Initializes it GPT, creates a single NTFS partition, assigns a drive letter.
      3. Disables Windows-managed pagefile, removes existing pagefiles.
      4. Creates a new pagefile on the NVMe volume.

    Because the temp disk is wiped on deallocation/stop, this script is intended to be
    re-run at boot (e.g. via a scheduled task at system startup or Nerdio scripted action).

    Writes a timestamped transcript + structured log to $LogDirectory so the run can be
    reviewed on the session host (default C:\Windows\Temp\NVMePagefileSetup).

    NMM-friendly: uses no param() block (NMM prepends its own variable declarations).
    To override defaults, pre-populate these vars as NMM "Pass variables":
        $DriveLetter     (string, D-Z, default 'P')
        $InitialSizeMB   (int, 0 = system-managed)
        $MaximumSizeMB   (int, 0 = system-managed)
        $LogDirectory    (string, default 'C:\Windows\Temp\NVMePagefileSetup')
#>

$ErrorActionPreference = 'Stop'

if (-not $DriveLetter)    { $DriveLetter    = 'P' }
if (-not $InitialSizeMB)  { $InitialSizeMB  = 0 }
if (-not $MaximumSizeMB)  { $MaximumSizeMB  = 0 }
if (-not $LogDirectory)   { $LogDirectory   = 'C:\Windows\Temp\NVMePagefileSetup' }

$DriveLetter   = ([string]$DriveLetter).ToUpper()
$InitialSizeMB = [int]$InitialSizeMB
$MaximumSizeMB = [int]$MaximumSizeMB

if ($DriveLetter -notmatch '^[D-Z]$') { throw "DriveLetter '$DriveLetter' is invalid. Expected a single letter D-Z." }

if (-not (Test-Path -LiteralPath $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$timestamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcriptPath = Join-Path $LogDirectory "transcript_$timestamp.log"
$logPath        = Join-Path $LogDirectory "run_$timestamp.log"

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Add-Content -LiteralPath $logPath -Value $line
    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
}

Start-Transcript -Path $transcriptPath -Force | Out-Null
$exitCode = 0

try {
    Write-Log "Starting NVMe pagefile setup on $env:COMPUTERNAME. Params: DriveLetter=$DriveLetter InitialSizeMB=$InitialSizeMB MaximumSizeMB=$MaximumSizeMB"
    Write-Log "PowerShell $($PSVersionTable.PSVersion)  OS $((Get-CimInstance Win32_OperatingSystem).Caption)  User $([Environment]::UserName)"

    Write-Log '--- Disks (before) ---'
    Get-Disk | Select-Object Number, FriendlyName, BusType, PartitionStyle, OperationalStatus, HealthStatus, @{n='SizeGB';e={[math]::Round($_.Size/1GB,0)}} |
        Format-Table -AutoSize | Out-String -Stream | ForEach-Object { $t = $_.TrimEnd(); if ($t) { Write-Log $t } }

    Write-Log '--- Volumes (before) ---'
    Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, DriveType |
        Format-Table -AutoSize | Out-String -Stream | ForEach-Object { $t = $_.TrimEnd(); if ($t) { Write-Log $t } }

    Write-Log '--- Pagefile (before) ---'
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    Write-Log "AutomaticManagedPagefile: $($cs.AutomaticManagedPagefile)"
    Get-CimInstance -ClassName Win32_PageFileSetting | ForEach-Object {
        Write-Log "  Existing pagefile: $($_.Name)  Initial=$($_.InitialSize)  Maximum=$($_.MaximumSize)"
    }

    function Get-AvailableDriveLetter {
        param([string]$Preferred)
        $used = @()
        $used += (Get-Volume).DriveLetter      | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpper() }
        $used += (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Name | ForEach-Object { $_.ToUpper() }
        if ($Preferred -and ($used -notcontains $Preferred.ToUpper())) { return $Preferred.ToUpper() }
        foreach ($l in 'P','Q','R','S','T','U','V','W','X','Y','Z','N','M','L','K','J','I','H','G','F','E','D') {
            if ($used -notcontains $l) { return $l }
        }
        return $null
    }

    function Enable-DiskReadWriteOnline {
        param([Parameter(Mandatory)]$Disk)
        if ($Disk.IsOffline)  { Write-Log "Disk $($Disk.Number) is offline - bringing online."; Set-Disk -Number $Disk.Number -IsOffline $false }
        if ($Disk.IsReadOnly) { Write-Log "Disk $($Disk.Number) is read-only - clearing."; Set-Disk -Number $Disk.Number -IsReadOnly $false }
    }

    $targetLetter = $DriveLetter.ToUpper()
    $rawNvme      = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' -and $_.BusType -eq 'NVMe' } | Select-Object -First 1
    $formattedNvme = Get-Disk | Where-Object { $_.BusType -eq 'NVMe' -and -not $_.IsBoot -and -not $_.IsSystem -and $_.PartitionStyle -ne 'RAW' } | Select-Object -First 1

    if ($rawNvme) {
        Enable-DiskReadWriteOnline -Disk $rawNvme
        $chosen = Get-AvailableDriveLetter -Preferred $targetLetter
        if (-not $chosen) { throw 'No drive letters available to assign.' }
        if ($chosen -ne $targetLetter) {
            Write-Log "Preferred drive letter ${targetLetter}: is in use. Falling back to ${chosen}:" 'WARN'
            $targetLetter = $chosen
        }
        Write-Log "Found RAW NVMe disk $($rawNvme.Number) ($([math]::Round($rawNvme.Size/1GB,0)) GB). Initializing."
        Initialize-Disk -Number $rawNvme.Number -PartitionStyle GPT -Confirm:$false | Out-Null
        New-Partition -DiskNumber $rawNvme.Number -UseMaximumSize -DriveLetter $targetLetter | Out-Null
        Format-Volume -DriveLetter $targetLetter -FileSystem NTFS -NewFileSystemLabel 'TempNVMe' -Confirm:$false | Out-Null
        Write-Log "Formatted NVMe disk as ${targetLetter}:"
    }
    elseif ($formattedNvme) {
        Enable-DiskReadWriteOnline -Disk $formattedNvme
        $part = Get-Partition -DiskNumber $formattedNvme.Number |
                Where-Object { $_.Type -notin 'Reserved','System','Recovery' -and $_.Size -gt 100MB } |
                Sort-Object Size -Descending | Select-Object -First 1
        if (-not $part) { throw "Non-RAW NVMe disk $($formattedNvme.Number) found but no usable data partition." }

        $currentLetter = if ($part.DriveLetter) { ([string]$part.DriveLetter).ToUpper() } else { $null }
        if ($currentLetter -eq $targetLetter) {
            Write-Log "NVMe volume already mounted at ${targetLetter}:. Continuing."
        } else {
            $chosen = Get-AvailableDriveLetter -Preferred $targetLetter
            if (-not $chosen) { throw 'No drive letters available to reassign.' }
            if ($chosen -ne $targetLetter) {
                Write-Log "Preferred ${targetLetter}: in use. Using ${chosen}: instead." 'WARN'
                $targetLetter = $chosen
            }
            if ($currentLetter) {
                Write-Log "NVMe volume is at ${currentLetter}: - reassigning to ${targetLetter}:"
                Set-Partition -DiskNumber $formattedNvme.Number -PartitionNumber $part.PartitionNumber -NewDriveLetter $targetLetter
            } else {
                Write-Log "NVMe partition has no drive letter - assigning ${targetLetter}:"
                Add-PartitionAccessPath -DiskNumber $formattedNvme.Number -PartitionNumber $part.PartitionNumber -AccessPath "${targetLetter}:"
            }
        }
    }
    else {
        Write-Log 'No usable NVMe temp disk found (no RAW, no non-OS NVMe).' 'WARN'
        $anyNvme = Get-Disk | Where-Object BusType -eq 'NVMe'
        if (-not $anyNvme) {
            Write-Log 'No NVMe disks detected at all - is this an Ev6/Easv6-series SKU with a local NVMe temp disk?' 'WARN'
        } else {
            $anyNvme | ForEach-Object { Write-Log "  Disk $($_.Number) PartitionStyle=$($_.PartitionStyle) IsBoot=$($_.IsBoot) IsSystem=$($_.IsSystem)" 'WARN' }
        }
        $exitCode = 1
        return
    }

    if ($cs.AutomaticManagedPagefile) {
        Write-Log 'Disabling automatic pagefile management.'
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false }
    }

    $pageFilePath = "${targetLetter}:\pagefile.sys"
    $pagingEntry  = "$pageFilePath $InitialSizeMB $MaximumSizeMB"
    $mmKey        = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'

    Write-Log '--- PagingFiles registry (before) ---'
    try {
        $existingPf = (Get-ItemProperty -Path $mmKey -Name PagingFiles -ErrorAction Stop).PagingFiles
        foreach ($entry in $existingPf) { Write-Log "  $entry" }
    } catch {
        Write-Log '  (PagingFiles value not present)'
    }

    Set-ItemProperty -Path $mmKey -Name 'PagingFiles' -Value @($pagingEntry) -Type MultiString

    $sizeLabel = if ($InitialSizeMB -eq 0 -and $MaximumSizeMB -eq 0) { 'system-managed' } else { "$InitialSizeMB MB / $MaximumSizeMB MB" }
    Write-Log "Pagefile configured via registry: '$pagingEntry' ($sizeLabel)."

    Write-Log '--- PagingFiles registry (after) ---'
    (Get-ItemProperty -Path $mmKey -Name PagingFiles).PagingFiles | ForEach-Object { Write-Log "  $_" }

    Write-Log 'Reboot required for the pagefile change to take effect.'
} catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" 'ERROR'
    Write-Log $_.ScriptStackTrace 'ERROR'
    $exitCode = 2
    throw
} finally {
    Write-Log "Finished with exit code $exitCode. Logs: $logPath ; $transcriptPath"
    Stop-Transcript | Out-Null
}

exit $exitCode
