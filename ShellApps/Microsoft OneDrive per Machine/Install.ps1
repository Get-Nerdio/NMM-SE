# Microsoft OneDrive per Machine Installation Script
# This script installs the latest version of OneDrive in per-machine mode

try {
    # Define the URL of the OneDriveSetup.exe file
    $OneDriveSetupUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2182910"
    
    # Define the path where the OneDriveSetup.exe file will be downloaded
    $DownloadPath = "$env:TEMP\OneDriveSetup.exe"
    
    $Context.Log("INFO: Starting Microsoft OneDrive per-machine installation")
    
    # Create the temp directory if it doesn't exist
    if (!(Test-Path -Path "$env:TEMP")) {
        New-Item -ItemType Directory -Path "$env:TEMP" -Force | Out-Null
    }
    
    # Download the OneDriveSetup.exe file
    $Context.Log("INFO: Downloading the latest OneDrive installer")
    Invoke-WebRequest -Uri $OneDriveSetupUrl -OutFile $DownloadPath -UseBasicParsing
    
    # Stop and Remove per-user OneDrive
    $Context.Log("INFO: Checking for existing OneDrive installations")
    
    $Processes = Get-Process -ErrorAction SilentlyContinue
    If ($Processes.ProcessName -Like "OneDrive") {
        $Context.Log("INFO: OneDrive is running and will be shutdown")
        taskkill /f /im OneDrive.exe
        Start-Sleep -Seconds 5
        
        # Check for personal OneDrive installation
        If (Test-Path "C:\Windows\SysWOW64\OneDriveSetup.exe") {
            $Context.Log("INFO: Personal OneDrive installation found, removing...")
            Start-Process "C:\Windows\SysWOW64\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait
        } else {
            $Context.Log("INFO: Personal OneDrive installation not found")
        }
    } else {
        $Context.Log("INFO: OneDrive is not running")
    }
    
    # Check and remove per-machine OneDrive
    $Context.Log("INFO: Checking if per-machine OneDrive is already installed")
    
    # Check if OneDrive is installed (per-machine) by checking registry
    $OneDriveInstalled = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" |
        Where-Object { ($_ | Get-ItemProperty).DisplayName -like "Microsoft OneDrive*" }
    
    if (-not $OneDriveInstalled) {
        # Also check 32-bit registry if nothing found in main uninstall key
        $OneDriveInstalled = Get-ChildItem "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" |
            Where-Object { ($_ | Get-ItemProperty).DisplayName -like "Microsoft OneDrive*" }
    }
    
    if ($OneDriveInstalled) {
        $Context.Log("INFO: Per-machine OneDrive detected — uninstalling to avoid version conflict...")
        $uninstallProcess = Start-Process -FilePath $DownloadPath -ArgumentList "/uninstall" -Wait -PassThru
        if ($uninstallProcess.ExitCode -ne 0) {
            $Context.Log("WARNING: Uninstall completed with exit code: $($uninstallProcess.ExitCode)")
        }
    } else {
        $Context.Log("INFO: Per-machine OneDrive not found — proceeding with fresh install")
    }
    
    # Execute the OneDriveSetup.exe file with the /allusers flag
    $Context.Log("INFO: Starting OneDrive per-machine install")
    $installProcess = Start-Process -FilePath $DownloadPath -ArgumentList "/allusers" -Wait -PassThru
    
    if ($installProcess.ExitCode -eq 0) {
        $Context.Log("INFO: OneDrive per-machine installed successfully")
    } else {
        $Context.Log("ERROR: OneDrive installation failed with exit code: $($installProcess.ExitCode)")
        throw "Installation failed with exit code: $($installProcess.ExitCode)"
    }
    
    # Wait a moment for installation to complete
    Start-Sleep -Seconds 30
    
    # Remove the downloaded installer
    $Context.Log("INFO: Cleaning up installer files")
    if (Test-Path $DownloadPath) {
        Remove-Item $DownloadPath -Force -ErrorAction SilentlyContinue
    }
    
    $Context.Log("INFO: Microsoft OneDrive per-machine installation completed successfully")
}
catch {
    $Context.Log("ERROR: OneDrive per-machine installation failed: $($_.Exception.Message)")
    
    # Clean up installer file on error
    if (Test-Path $DownloadPath) {
        Remove-Item $DownloadPath -Force -ErrorAction SilentlyContinue
    }
    
    throw $_
}
