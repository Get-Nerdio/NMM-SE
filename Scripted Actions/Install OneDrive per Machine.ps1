#description: Downloads and installs OneDrive for all users
#tags: Nerdio

<#
Notes:
This script will download the OneDriveSetup.exe file from the Microsoft link, remove per-user OneDrive, and install OneDrive per-machine for all users.
#>

# Define the URL of the OneDriveSetup.exe file
$OneDriveSetupUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2182910"

# Define the path where the OneDriveSetup.exe file will be downloaded
$DownloadPath = "C:\Temp\OneDriveSetup.exe"


#Stop and Remove per-user OneDrive

$Processes = Get-Process
If ($Processes.ProcessName -Like "OneDrive") {

    Write-Host OneDrive is Running and will be shutdown

    taskkill /f /im OneDrive.exe

    If (Test-Path C:\Windows\SysWOW64\OneDriveSetup.exe){
        
        Write-Host "OneDrive installation found, OneDrive Personal will be removed"

        C:\Windows\SysWOW64\OneDriveSetup.exe /uninstall

       
    }
    Else{
        Write-Host "OneDrive Personal Installation not found"
    }

}
Else{
    Write-Host OneDrive is not running
}

# Create the directory if it doesn't exist
if (!(Test-Path -Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp"
}

# Download the OneDriveSetup.exe file
Invoke-WebRequest -Uri $OneDriveSetupUrl -OutFile $DownloadPath
Write-Host "Downloading the latest OneDrive Installer"

# Execute the OneDriveSetup.exe file with the /allusers flag
Write-Host "Starting OneDrive per-machine Install"
Start-Process -FilePath $DownloadPath -ArgumentList "/allusers" | Out-Null


#Remove previous installers
Write-Host "OneDrive installed successfully"
Write-Host "Cleaning-up the installers"
start-sleep 30
Remove-Item $DownloadPath -Force

Write-Host "Install and clean-up successful"

### End Script ###
