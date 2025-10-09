# Microsoft OneDrive per Machine Uninstallation Script
# This script uninstalls OneDrive per-machine installation

try {
    $Context.Log("INFO: Starting Microsoft OneDrive per-machine uninstallation")
    
    # Stop OneDrive processes
    $Context.Log("INFO: Stopping OneDrive processes")
    try {
        $OneDriveProcesses = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
        if ($OneDriveProcesses) {
            $OneDriveProcesses | Stop-Process -Force
            Start-Sleep -Seconds 5
            $Context.Log("INFO: OneDrive processes stopped")
        } else {
            $Context.Log("INFO: No OneDrive processes found")
        }
    } catch {
        $Context.Log("WARNING: Failed to stop OneDrive processes: $($_.Exception.Message)")
    }
    
    # Check for per-machine OneDrive installation
    $OneDriveInstalled = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" |
        Where-Object { ($_ | Get-ItemProperty).DisplayName -like "Microsoft OneDrive*" }
    
    if (-not $OneDriveInstalled) {
        # Also check 32-bit registry if nothing found in main uninstall key
        $OneDriveInstalled = Get-ChildItem "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" |
            Where-Object { ($_ | Get-ItemProperty).DisplayName -like "Microsoft OneDrive*" }
    }
    
    if ($OneDriveInstalled) {
        $Context.Log("INFO: Per-machine OneDrive installation found - proceeding with uninstall")
        
        # Download OneDriveSetup.exe for uninstall
        $OneDriveSetupUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2182910"
        $DownloadPath = "$env:TEMP\OneDriveSetup.exe"
        
        try {
            $Context.Log("INFO: Downloading OneDrive installer for uninstall")
            Invoke-WebRequest -Uri $OneDriveSetupUrl -OutFile $DownloadPath -UseBasicParsing
            
            $Context.Log("INFO: Uninstalling OneDrive per-machine")
            $uninstallProcess = Start-Process -FilePath $DownloadPath -ArgumentList "/uninstall" -Wait -PassThru
            
            if ($uninstallProcess.ExitCode -eq 0) {
                $Context.Log("INFO: OneDrive per-machine uninstalled successfully")
            } else {
                $Context.Log("WARNING: Uninstall completed with exit code: $($uninstallProcess.ExitCode)")
            }
        } catch {
            $Context.Log("ERROR: Uninstall failed: $($_.Exception.Message)")
            throw $_
        } finally {
            # Clean up installer file
            if (Test-Path $DownloadPath) {
                Remove-Item $DownloadPath -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        $Context.Log("INFO: No per-machine OneDrive installation found")
    }
    
    # Also check for and remove personal OneDrive installation
    if (Test-Path "C:\Windows\SysWOW64\OneDriveSetup.exe") {
        $Context.Log("INFO: Personal OneDrive installation found, removing...")
        try {
            Start-Process "C:\Windows\SysWOW64\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait
            $Context.Log("INFO: Personal OneDrive removed successfully")
        } catch {
            $Context.Log("WARNING: Failed to remove personal OneDrive: $($_.Exception.Message)")
        }
    }
    
    # Clean up OneDrive directories
    $OneDriveDirs = @(
        "${env:ProgramFiles}\Microsoft OneDrive",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive",
        "${env:LOCALAPPDATA}\Microsoft\OneDrive"
    )
    
    foreach ($dir in $OneDriveDirs) {
        if (Test-Path $dir) {
            try {
                $Context.Log("INFO: Removing OneDrive directory: $dir")
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                $Context.Log("WARNING: Failed to remove directory $dir : $($_.Exception.Message)")
            }
        }
    }
    
    $Context.Log("INFO: Microsoft OneDrive per-machine uninstallation completed")
}
catch {
    $Context.Log("ERROR: OneDrive per-machine uninstallation failed: $($_.Exception.Message)")
    throw $_
}
