<#
.SYNOPSIS
    Installs or updates the MS Teams client and enables Teams WVD Optimization mode.

.DESCRIPTION
    This script performs the following actions:
    1. Sets a registry value to enable MS Teams to operate in WVD Mode.
    2. Uninstalls existing MS Teams and WebRTC programs, both per-user and machine-wide installations.
    3. Downloads and installs the latest version of MS Teams with a machine-wide installation.
    4. Downloads and installs the August 2024 version of the WebRTC component.
    5. Logs all actions to a specified log directory.
    6. Set the $MarchwebRTC variable to $true to install the March 2024 version of WebRTC.

.EXECUTION MODE NMM
    IndividualWithRestart

.TAGS
    Nerdio, Apps install, MS Teams, WVD Optimization

.NOTES
    - Logs are saved to: $env:TEMP\NerdioManagerLogs\Install-Teams.txt
    - Ensure that the script is run with appropriate privileges for registry modifications and software installation.

#>


# Define script variables
$WebView2InstallerUrl = "https://go.microsoft.com/fwlink/p/?LinkId=212470"
$DLink = "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409"
$MarchwebRTC = $false




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

        [string]$LogName = 'Install-Teams.txt',

        [bool]$throw = $false,

        [bool]$return = $false,

        [bool]$exit = $false,

        [bool]$FirstLogInnput = $false
    )
    
    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType Directory -Path $LogFilePath -Force
        Write-Output "$LogFilePath has been created."
    }
    else {
        if ($FirstLogInnput -eq $true) {
            Add-Content -Path "$($LogFilePath)\$($LogName)" -Value "################# New Script Run #################"
        }
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level]: $Message"
    
    try {
        Add-Content -Path "$($LogFilePath)\$($LogName)" -Value $logEntry

        if ($throw) {
            throw $Message
        }

        if ($return) {
            return $Message
        }

        if ($exit) {
            Write-Output "$($Message)"
            exit 
        }

        if ($WriteOutput) {
            Write-Output "$($Message)"
        }
    }
    catch {
        Write-Error $_.Exception.Message
    }
}
 
try {
    if (!(Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\') -and !(Test-Path 'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\')) {

        NMMLogOutput -Level 'Information' -Message 'Installing WebView2' -return $true -FirstLogInnput $true
    
        $WebView2Installer = "$env:TEMP\NerdioManagerLogs\MicrosoftEdgeWebView2Setup.exe"
    
        Invoke-WebRequest -Uri $WebView2InstallerUrl -OutFile $WebView2Installer -UseBasicParsing
    
        Start-Process $WebView2Installer -ArgumentList '/silent /install' -Wait 2>&1
    }
}
catch {
    NMMLogOutput -Level 'Warning' -Message "WebView2 installation failed with exception $($_.exception.message)" -throw $true
}
 
# Uninstall any previous versions of MS Teams or Web RTC
# Per-user teams uninstall logic

try {
    $TeamsPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'Teams')
    $TeamsUpdateExePath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'Teams', 'Update.exe')

    if ([System.IO.File]::Exists($TeamsUpdateExePath)) {
        NMMLogOutput -Level 'Information' -Message 'Uninstalling Teams process (per-user installation)' -return $true
 
        # Uninstall app
        $proc = Start-Process $TeamsUpdateExePath '-uninstall -s' -PassThru
        $proc.WaitForExit()
    }
    else {
        NMMLogOutput -Level 'Information' -Message 'No per-user Teams install found.' -return $true
    }
    
    NMMLogOutput -Level 'Information' -Message 'Deleting any possible Teams directories (per user installation).' -return $true
    
    Remove-Item -Path $TeamsPath -Recurse -ErrorAction SilentlyContinue
}
catch {
    NMMLogOutput -Level 'Warning' -Message "Uninstall failed with exception $($_.exception.message)" -throw $true
}
 
# Per-Machine teams uninstall logic
$GetTeams = Get-CimInstance -ClassName Win32_Product | Where-Object IdentifyingNumber -Match '{731F6BAA-A986-45A4-8936-7C3AAAAA760B}'

if ($null -ne $GetTeams) {
    Start-Process C:\Windows\System32\msiexec.exe -ArgumentList '/x ' { 731F6BAA-A986-45A4-8936-7C3AAAAA760B }' /qn /norestart' -Wait 2>&1

    NMMLogOutput -Level 'Information' -Message 'Teams per-machine Install Found, uninstalling teams' -return $true
}

#Check for New Teams being Installed
$Apps = Get-AppxPackage | Where-Object { $_.Name -like "*Teams*" -and $_.Publisher -like "*Microsoft Corporation*" }
foreach ($App in $Apps) {
    Remove-AppxPackage -Package $App.PackageFullName
}

try {
    # WebRTC uninstall logic
    $GetWebRTC = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "Remote Desktop WebRTC*" -and $_.Vendor -eq "Microsoft Corporation" }

    if ($null -ne $GetWebRTC.IdentifyingNumber) {
        Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetWebRTC.IdentifyingNumber) /qn /norestart" -Wait 2>&1

        NMMLogOutput -Level 'Information' -Message 'WebRTC Install Found, uninstalling Current version of WebRTC' -return $true
    }
}
catch {
    NMMLogOutput -Level 'Warning' -Message "WebRTC uninstall failed with exception $($_.exception.message)" -throw $true
}
 
try {
    # Make directories to hold new install
    New-Item -ItemType Directory -Path 'C:\Windows\Temp\msteams_sa\install' -Force | Out-Null
 
    # Grab MSI installer for MSTeams
    Invoke-WebRequest -Uri $DLink -OutFile 'C:\Windows\Temp\msteams_sa\install\teamsbootstrapper.exe' -UseBasicParsing
 
    # Use installer to install Machine-Wide
    NMMLogOutput -Level 'Information' -Message 'Installing MS Teams' -return $true
    Start-Process 'C:\Windows\Temp\msteams_sa\install\teamsbootstrapper.exe' -ArgumentList '-p' -Wait 2>&1

    # Set registry values for Teams to use VDI optimization
    NMMLogOutput -Level 'Information' -Message 'Setting Teams to WVD Environment mode' -return $true

    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name IsWVDEnvironment -PropertyType DWORD -Value 1 -Force
 
}
catch {
    NMMLogOutput -Level 'Warning' -Message "Teams installation failed with exception $($_.exception.message)" -throw $true
}
 
<#
#Use MS shortcut to WebRTC install
Temporarily adding a fixed version of WebRTC with the March 2024 release.
To roll-back to the latest, set $MarchwebRTC to $false in the script parameters.
#>

try {

    switch ($MarchwebRTC) {
        $true {
            $dlink2 = 'https://aka.ms/msrdcwebrtcsvc/msi'
        }
        $false {
            $dlink2 = 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RW1o9wm'
        }
    }
    
    # Grab MSI installer for WebRTC
    Invoke-WebRequest -Uri $DLink2 -OutFile 'C:\Windows\Temp\msteams_sa\install\MsRdcWebRTCSvc_x64.msi' -UseBasicParsing
 
    # Install Teams WebRTC Websocket Service
    NMMLogOutput -Level 'Information' -Message 'Installing WebRTC component' -return $true

    Start-Process C:\Windows\System32\msiexec.exe `
        -ArgumentList '/i C:\Windows\Temp\msteams_sa\install\MsRdcWebRTCSvc_x64.msi /l*v C:\Windows\temp\NerdioManagerLogs\ScriptedActions\msteams\WebRTC_install_log.txt /qn /norestart' -Wait 2>&1

    NMMLogOutput -Level 'Information' -Message 'Finished running installers. Check C:\Windows\Temp\NerdioManagerLogs for logs on the MSI installations.' -return $true
    NMMLogOutput -Level 'Information' -Message 'All Commands Executed; script is now finished. Allow 5 minutes for teams to appear' -return $true 
}
catch {
    NMMLogOutput -Level 'Warning' -Message "WebRTC installation failed with exception $($_.exception.message)" -throw $true
}