#description: Downloads and installs OneDrive for all users
#tags: Nerdio

<#
Notes:
This script will download the OneDriveSetup.exe file from the Microsoft link, remove per-user and per-machine versions of OneDrive, and install the latest version of OneDrive in all users mode.
#>

# Define the URL of the OneDriveSetup.exe file
$OneDriveSetupUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2182910"

# Define the path where the OneDriveSetup.exe file will be downloaded
$DownloadPath = "C:\Temp\OneDriveSetup.exe"

# Download the OneDriveSetup.exe file
Invoke-WebRequest -Uri $OneDriveSetupUrl -OutFile $DownloadPath
Write-Host "Downloading the latest OneDrive Installer"


#Stop and Remove per-user OneDrive
Write-Host "Checking for OneDrive being installed"

$Processes = Get-Process
If ($Processes.ProcessName -Like "OneDrive") {

    Write-Host OneDrive is Running and will be shutdown

    taskkill /f /im OneDrive.exe

    If (Test-Path C:\Windows\SysWOW64\OneDriveSetup.exe){
        
        Write-Host "Personal OneDrive installation found, OneDrive Personal will be removed"

        C:\Windows\SysWOW64\OneDriveSetup.exe /uninstall

       
    }
    Else{
        Write-Host "OneDrive Personal Installation not found"
    }

}
Else{
    Write-Host OneDrive is not running
}

# Check and remove per-machine OneDrive
Write-Host "Checking if per-machine OneDrive is installed"
# Check if OneDrive is installed (per-machine) by checking registry
$OneDriveInstalled = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" |
    Where-Object { ($_ | Get-ItemProperty).DisplayName -like "Microsoft OneDrive*" }

if (-not $OneDriveInstalled) {
    # Also check 32-bit registry if nothing found in main uninstall key
    $OneDriveInstalled = Get-ChildItem "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" |
        Where-Object { ($_ | Get-ItemProperty).DisplayName -like "Microsoft OneDrive*" }
}

if ($OneDriveInstalled) {
    Write-Host "Per-machine OneDrive detected — uninstalling to avoid version conflict..."
    Start-Process -FilePath $DownloadPath -ArgumentList "/uninstall" -Wait
} else {
    Write-Host "Per-machine OneDrive not found — skipping uninstall."
}

# Create the directory if it doesn't exist
if (!(Test-Path -Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp"
}


# Execute the OneDriveSetup.exe file with the /allusers flag
Write-Host "Starting OneDrive per-machine install"
Start-Process -FilePath $DownloadPath -ArgumentList "/allusers" | Out-Null


#Remove the downloaded installers
Write-Host "OneDrive installed successfully"
Start-Sleep 30
Write-Host "Cleaning-up the installers"
Remove-Item $DownloadPath -Force

Write-Host "Install and clean-up successful"

### End Script ###