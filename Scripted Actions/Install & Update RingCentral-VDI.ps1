<#
.SYNOPSIS
    Installs or updates the RingCentral Client and enables VDI Optimization mode.
    

.DESCRIPTION
    This script performs the following actions:
    1. Unistalls existing RingCentral Desktop App and RingCentral App VDI Service
    2. Downloads and installs the latest version of RingCentral Desktop App and RingCentral App VDI Service
    3. Logs all actions to a specified log directory.


.EXECUTION MODE NMM
    IndividualWithRestart

.TAGS
    Nerdio, Apps install, RingCentral, WVD Optimization

.NOTES
    - This script is based on this RingCentral Article: https://support.ringcentral.com/article-v2/Using-Microsoft-Azure-VDI-integration-in-RingCentral-app.html?brand=RingCentral&product=RingEX&language=en_US
    - Logs are saved to: $env:TEMP\NerdioManagerLogs\Install-RingCentral.txt
    - Ensure that the script is run with appropriate privileges for registry modifications and software installation.

#>


# Define script variables
$RingCentralDesktopApp = "https://app.ringcentral.com/download/RingCentral-x64.msi"
$RingCentralAppVDIService = "https://app.ringcentral.com/download/RingCentral-App-VdiUniversalService.msi"
$InstallerPath = "C:\Windows\Temp\RingCentral\install"



function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [string]$LogFilePath = "$Env:WinDir\Temp\NerdioManagerLogs",

        [string]$LogName = 'Install-RingCentral.txt',

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
 

# Uninstall any previous versions of Ring Central App and Ring Central VDI Service
#Uninstall RingCentral VDI Service
try {
    $GetRingCentralVDI = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "RingCentral App VDI*" -and $_.Vendor -eq "RingCentral" }

    if ($null -ne $GetRingCentralVDI.IdentifyingNumber) {
    Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetRingCentralVDI.IdentifyingNumber) /qn /norestart" -Wait 2>&1

    NMMLogOutput -Level 'Information' -Message 'RingCentral VDI Install Found, uninstalling RingCentral VDI' -return $true
    }
}
catch {
    NMMLogOutput -Level 'Warning' -Message "RingCentral VDI uninstall failed with exception $($_.exception.message)" -throw $true
}

#Uninstall RingCentral App
try {
    
    $GetRingCentralApp = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -eq "RingCentral" -and $_.Vendor -eq "RingCentral" }

    if ($null -ne $GetRingCentralApp.IdentifyingNumber) {
        Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetRingCentralApp.IdentifyingNumber) /qn /norestart" -Wait 2>&1

        NMMLogOutput -Level 'Information' -Message 'RingCentral App Install Found, uninstalling RingCentral App' -return $true
    }
}
catch {
    NMMLogOutput -Level 'Warning' -Message "RingCentral App uninstall failed with exception $($_.exception.message)" -throw $true
}
 
#Remove previous installers
Get-ChildItem -Path $InstallerPath -Recurse | Remove-Item -Force -Recurse | Out-Null
Remove-Item $InstallerPath -Force | Out-Null

try {
    # Make directories to hold new install
    New-Item -ItemType Directory -Path $InstallerPath -Force | Out-Null
 
    # Grab MSI installer for RingCentral Desktop App
    Invoke-WebRequest -Uri $RingCentralDesktopApp -OutFile "$InstallerPath\RingCentral-x64.msi" -UseBasicParsing

    # Grab MSI installer for RingCentral App VDI Service
    Invoke-WebRequest -Uri $RingCentralAppVDIService -OutFile "$InstallerPath\RingCentral-App-VdiUniversalService.msi" -UseBasicParsing
}
Catch {
    NMMLogOutput -Level 'Warning' -Message "Downloading the installers failed. $($_.exception.message)" -throw $true

}

Try {
    # Install RingCentral Desktop App
    NMMLogOutput -Level 'Information' -Message 'Installing RingCentral Desktop App' -return $true

    Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/i  C:\Windows\Temp\RingCentral\install\RingCentral-x64.msi  /log C:\Windows\temp\NerdioManagerLogs\RingCentralApp_install_log.txt /quiet /norestart" -Wait 2>&1

    NMMLogOutput -Level 'Information' -Message 'Finished running Ring Central App installer. Check C:\Windows\Temp\NerdioManagerLogs for logs on the MSI installations.' -return $true
    
}
catch {
    NMMLogOutput -Level 'Warning' -Message "Ring Central App installation failed with exception $($_.exception.message)" -throw $true
}

Try {
    # Install RingCentral App VDI Service
    NMMLogOutput -Level 'Information' -Message 'Installing RingCentral App VDI Service' -return $true

    Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/i  C:\Windows\Temp\RingCentral\install\RingCentral-App-VdiUniversalService.msi /log C:\Windows\temp\NerdioManagerLogs\RingCentralService_install_log.txt /quiet /norestart" -Wait 2>&1

    NMMLogOutput -Level 'Information' -Message 'Finished running Ring Central App installer. Check C:\Windows\Temp\NerdioManagerLogs for logs on the MSI installations.' -return $true
    
}
catch {
    NMMLogOutput -Level 'Warning' -Message "RingCentral Service install failed. $($_.exception.message)" -throw $true
}