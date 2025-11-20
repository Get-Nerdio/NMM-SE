<#
.SYNOPSIS
    This script automatically configures the paging file for v6 VMs, with temp disks, to be put on that drive on startup.

.DESCRIPTION
    This script came from this blog post (https://smbtothecloud.com/azure-v6-vms-and-avd-automating-page-file-setup-on-temp-storage-with-intune/)
    The original script can be found here: https://github.com/gnon17/MS-Cloud-Scripts/blob/main/AVD/v6VM-SetTempStoragePageFile/SetPageFileOnStartup_v6vm.ps1
    

.EXECUTION MODE NMM
    Individual with Restart

.TAGS
    Nerdio, OS, Paging File, v6 VM, AVD

.NOTES
    When scheduling the script, you'll want to make sure to run when the VM starts up.
    If the VM reboots, the script doesn't run automatically. It's only on VM Startup.

#>

$LogLocation = "C:\Temp\Logs"
$logdatestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = "$LogLocation\PageFileTask-$logdatestamp.log"

if (-not (Test-Path $LogLocation)) {
        New-Item -Path $LogLocation -ItemType Directory -Force | Out-Null
}
function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format s), $Message
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

Write-Log "==== Script Starting... ===="

#Only hold 3 weeks worth of logs
Get-ChildItem -Path $LogLocation -Filter 'PageFileTask-*.log' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-21) } | Remove-Item -Force -ErrorAction SilentlyContinue

#Boot loop guard: detects last 5 reboots and stops script if 4 or more reboots have been detected in the last 12 minutes ---
$bootEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Id=6005} -MaxEvents 5 | Select-Object -ExpandProperty TimeCreated
$recentBoots = $bootEvents | Where-Object { $_ -gt (Get-Date).AddMinutes(-12) }
Write-Log "Running boot loop protection. Found $($recentBoots.Count) restarts in the past 12 minutes. Continuing..."

if ($recentBoots.Count -ge 4) {
    Write-Log "Detected at least $($recentBoots.Count) restarts in the past 12 minutes. Skipping this run to prevent boot loop."
    
    #Logging to EventViewer
    $source = "PageFileScript"
    $logName = "Application"
    if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
        New-EventLog -LogName $logName -Source $source -ErrorAction SilentlyContinue
    }
    Write-EventLog -LogName $logName -Source $source -EventId 9876 -EntryType "Warning" -Message "Boot loop protection triggered. Detected $($recentBoots.Count) restarts in the past 12 minutes. Page File script skipped." -ErrorAction SilentlyContinue
    exit 0
}
#End boot loop guard

#Exit if pagefile is found on D
$usedpagefiles = Get-CimInstance Win32_PageFileUsage |
  ForEach-Object {
    ($_.Name -replace '^(\\\\\?\\\?\\|\\\?\\\?)','')
  }

# Check if any pagefile matches D:\pagefile.sys (handle both array and single value)
$pagefileOnD = if ($usedpagefiles -is [array]) {
    $null -ne ($usedpagefiles | Where-Object { $_ -match '^D:\\pagefile\.sys$' })
} else {
    $usedpagefiles -match '^D:\\pagefile\.sys$'
}

if ($pagefileOnD) {
    Write-Log "Pagefile is correctly set to D: exiting script"
    Write-Log "=== Script Ended ==="
    exit 0
}
else {
    Write-Log "Pagefile is not set to D. Continuing script."
}

#Exit if there is already a D volume
if (Get-Volume -DriveLetter D -ErrorAction SilentlyContinue) {
    Write-Log "D: drive already exists. Exiting script."
    Write-Log "=== Script Ended ==="
    exit 0
}

#Identify Temp Storage Volume with name based on v6 VM
$TempStorage = Get-Disk | Where-Object {$_.PartitionStyle -eq 'RAW' -and $_.OperationalStatus -eq 'Online' -and $_.FriendlyName -eq 'Microsoft NVMe Direct Disk v2'}

#Falls back to alternate method if name ever changes
if (!$TempStorage) {
    $osDiskNumber = (Get-Partition -DriveLetter C | Get-Disk).Number
    $TempStorage = Get-Disk | Where-Object {
        $_.PartitionStyle -eq 'RAW' -and $_.OperationalStatus -eq 'Online' -and $_.Number -ne $osDiskNumber
    }
    if ($TempStorage) {
        Write-Log "Temporary storage identified with fallback method. Friendly name: $($TempStorage.FriendlyName)"
    }
}

#Stop Script if Temp Storage can't be identified
if (!$TempStorage) {
    Write-Log "Temp storage could not be identified. Exiting."
    Write-Log "=== Script Ended ==="
    exit 1
}
else {
    Write-Log "RAW Temporary storage found. Continuing script."
}

#Initialize the Disk, Format, and Name Partition
try {
    Write-Log "Initializing disk $($TempStorage.FriendlyName)..."
    Initialize-Disk -Number $TempStorage.Number -PartitionStyle GPT -ErrorAction Stop

    Write-Log "Creating partition and assigning drive letter D on disk $($TempStorage.FriendlyName)..."
    $partition = New-Partition -DiskNumber $TempStorage.Number -UseMaximumSize -DriveLetter D -ErrorAction Stop

    Write-Log "Formatting partition D: as NTFS..."
    Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel 'Temporary Storage' -Confirm:$false -ErrorAction Stop

    Write-Log "Disk initialization, partition, and format completed successfully."
}
catch {
    Write-Log "ERROR in disk initialization, partitioning, or formatting: $($_.Exception.Message)"
    Write-Log "=== Script Ended ==="
    exit 1
}

#set reg values
$regsettings = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$pagefiles = (Get-ItemProperty -Path $regsettings -Name PagingFiles -ErrorAction SilentlyContinue).PagingFiles
$pagefilesarray = @($pagefiles)

# Check if registry already has D:\pagefile.sys configured
$pagefileDConfigured = if ($pagefilesarray -is [array]) {
    $null -ne ($pagefilesarray | Where-Object { $_ -match '^D:\\pagefile\.sys\s+0\s+0$' })
} else {
    $pagefilesarray -match '^D:\\pagefile\.sys\s+0\s+0$'
}

if ($pagefileDConfigured) {
    Try {
        New-ItemProperty -Path $regsettings -Name 'TempPageFile' -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $regsettings -Name 'ExistingPageFiles' -PropertyType MultiString -Value @('D:\pagefile.sys') -Force
        Write-Log "Reg settings are set to use D drive as page file. Setting temp/existing page file values."
    }
    Catch {
        Write-Log "Error updating TempPageFile or ExistingPageFiles registry value: $($_.Exception.Message)"
        Write-Log "=== Script Ended ==="
        exit 1
    }
    }
else {
    Try {
    New-ItemProperty -Path $regsettings -Name 'AutomaticManagedPagefile' -PropertyType DWord -Value 0 -Force
    New-ItemProperty -Path $regsettings -Name 'PagingFiles' -PropertyType MultiString -Value @('D:\pagefile.sys 0 0') -Force
    New-ItemProperty -Path $regsettings -Name 'ExistingPageFiles' -PropertyType MultiString -Value @('D:\pagefile.sys') -Force
    New-ItemProperty -Path $regsettings -Name 'TempPageFile' -PropertyType DWord -Value 0 -Force | Out-Null
    Write-Log "Reg settings are not configured to use D drive as page file. Updating Reg values."
}
Catch {
    Write-Log "Error updating a registry value for AutomaticManagedPagefile, PagingFiles, ExistingPageFiles, or TempPageFile: $($_.Exception.Message)"
    Write-Log "=== Script Ended ==="
    exit 1
}
}

#final checks before reboot
# Re-check pagefile usage (may have changed after registry update)
$usedpagefilesFinal = Get-CimInstance Win32_PageFileUsage |
  ForEach-Object {
    ($_.Name -replace '^(\\\\\?\\\?\\|\\\?\\\?)','')
  }

$pagefileOnDFinal = if ($usedpagefilesFinal -is [array]) {
    $null -ne ($usedpagefilesFinal | Where-Object { $_ -match '^D:\\pagefile\.sys$' })
} else {
    $usedpagefilesFinal -match '^D:\\pagefile\.sys$'
}

if ($pagefileOnDFinal) {
    Write-Log "Pagefile is correctly in use on D:. No reboot needed."
    Write-Log "=== Script Ended ==="
    exit 0
}
else {
    #verify that reg values for Page file are correct prior to reboot
    $regpagefiles = (Get-ItemProperty -Path $regsettings -Name PagingFiles -ErrorAction SilentlyContinue).PagingFiles
    $regpagefilesArray = @($regpagefiles)
    
    $pagefileD = if ($regpagefilesArray -is [array]) {
        $null -ne ($regpagefilesArray | Where-Object { $_ -match '^D:\\pagefile\.sys\s+0\s+0$' })
    } else {
        $regpagefilesArray -match '^D:\\pagefile\.sys\s+0\s+0$'
    }
    
    if ($pagefileD) {
        Write-Log "Registry confirmed set to D:\pagefile.sys 0 0. Rebooting so D pagefile is picked up."
        Restart-Computer -Force
    }
    else {
        Write-Log "Registry check failed: PagingFiles is not set to D:\pagefile.sys 0 0. Skipping reboot."
        Write-Log "=== Script Ended ==="
        exit 1
    }
}