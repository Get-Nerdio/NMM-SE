<#
.SYNOPSIS
    Uninstalls and reinstalls the ShareFile Outlook Plug-in.

.DESCRIPTION
    - Kills Outlook if it's running.
    - Uninstalls existing ShareFile Outlook add-in (all versions).
    - Downloads the latest installer from Citrix.
    - Installs the new version silently.
    - Logs actions to C:\Windows\Temp\NMM\Install-ShareFileOutlook.txt

.NOTES
    Logs: C:\Windows\Temp\NMM\Install-ShareFileOutlook.txt
#>

# Installer URL
$ShareFileInstallerUrl = "https://dl.sharefile.com/sfo-msi"
$InstallerPath = "$env:TEMP\ShareFileOutlookPlugin.msi"
$LogFilePath = "C:\Windows\Temp\NMM"
$LogFile = "Install-ShareFileOutlook.txt"

# Logging function
function Write-LogMessage {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Level = 'Information'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level]: $Message"
    if (!(Test-Path $LogFilePath)) {
        New-Item -ItemType Directory -Path $LogFilePath -Force | Out-Null
    }
    Add-Content -Path "$LogFilePath\$LogFile" -Value $logEntry
    Write-Host $logEntry
}

# Ensure script is running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Log-Message "This script must be run as Administrator." "Error"
    exit 1
}

# Kill Outlook process if running
try {
    $outlook = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
    if ($outlook) {
        Log-Message "Outlook is running. Attempting to close it..." "Information"
        $outlook | Stop-Process -Force
        Start-Sleep -Seconds 5
        Log-Message "Outlook process stopped." "Information"
    } else {
        Log-Message "Outlook is not running." "Information"
    }
} catch {
    Log-Message "Failed to check or kill Outlook: $($_.Exception.Message)" "Warning"
}

# Uninstall existing ShareFile Outlook add-ins
try {
    $installed = Get-CimInstance Win32_Product | Where-Object {
        $_.Name -like "*ShareFile Outlook*" -or $_.Name -like "*Citrix Files for Outlook*"
    }

    if ($installed) {
        foreach ($app in $installed) {
            Log-Message "Uninstalling $($app.Name)..." "Information"
            Start-Process msiexec.exe -ArgumentList "/x $($app.IdentifyingNumber) /qn /norestart" -Wait
            Log-Message "$($app.Name) uninstalled." "Information"
        }
    } else {
        Log-Message "No existing ShareFile Outlook add-in found." "Information"
    }
} catch {
    Log-Message "Uninstall failed: $($_.Exception.Message)" "Error"
    exit 1
}

# Download and install new ShareFile Outlook add-in
try {
    Log-Message "Downloading ShareFile installer..." "Information"
    Invoke-WebRequest -Uri $ShareFileInstallerUrl -OutFile $InstallerPath -UseBasicParsing
    Log-Message "Download complete. Installing..." "Information"

    Start-Process msiexec.exe -ArgumentList "/i `"$InstallerPath`" /qn /norestart" -Wait
    Log-Message "ShareFile Outlook Add-in installed successfully." "Information"
} catch {
    Log-Message "Installation failed: $($_.Exception.Message)" "Error"
    exit 1
}

Log-Message "Script execution completed." "Information"
