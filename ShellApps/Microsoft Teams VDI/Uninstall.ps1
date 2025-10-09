# Microsoft Teams Uninstallation Script
# This script completely removes Microsoft Teams and all related components

try {
    $Context.Log("INFO: Starting Microsoft Teams uninstallation")
    
    # Uninstall Teams (Per-user)
    try {
        $TeamsPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'Teams')
        $TeamsUpdateExePath = [System.IO.Path]::Combine($TeamsPath, 'Update.exe')
        
        if ([System.IO.File]::Exists($TeamsUpdateExePath)) {
            $Context.Log("INFO: Uninstalling per-user Teams installation")
            $proc = Start-Process $TeamsUpdateExePath -ArgumentList '-uninstall -s' -PassThru
            $proc.WaitForExit()
            $Context.Log("INFO: Per-user Teams uninstalled")
        } else {
            $Context.Log("INFO: No per-user Teams install found")
        }
        
        $Context.Log("INFO: Removing Teams directories (per-user)")
        Remove-Item -Path $TeamsPath -Recurse -ErrorAction SilentlyContinue
    }
    catch {
        $Context.Log("WARNING: Per-user Teams uninstall failed: $($_.Exception.Message)")
    }
    
    # Uninstall Teams (Per-Machine)
    try {
        $GetTeams = Get-CimInstance -ClassName Win32_Product | Where-Object { 
            $_.Name -like "Teams Machine-Wide*" -and $_.Vendor -eq "Microsoft Corporation" 
        }
        
        if ($null -ne $GetTeams.IdentifyingNumber) {
            $Context.Log("INFO: Uninstalling per-machine Teams installation")
            $uninstallProcess = Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetTeams.IdentifyingNumber) /qn /norestart" -Wait -PassThru
            if ($uninstallProcess.ExitCode -eq 0) {
                $Context.Log("INFO: Per-machine Teams uninstalled successfully")
            } else {
                $Context.Log("WARNING: Per-machine Teams uninstall completed with exit code: $($uninstallProcess.ExitCode)")
            }
        } else {
            $Context.Log("INFO: No per-machine Teams installation found")
        }
    }
    catch {
        $Context.Log("WARNING: Per-machine Teams uninstall failed: $($_.Exception.Message)")
    }
    
    # Uninstall Teams Meeting Add-in (Per-Machine)
    try {
        $GetTeamsAddin = Get-CimInstance -ClassName Win32_Product | Where-Object { 
            $_.Name -like "*Teams Meeting Add-in*" -and $_.Vendor -eq "Microsoft" 
        }
        
        if ($null -ne $GetTeamsAddin.IdentifyingNumber) {
            $Context.Log("INFO: Uninstalling Teams Meeting Add-in")
            $uninstallProcess = Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetTeamsAddin.IdentifyingNumber) /qn /norestart" -Wait -PassThru
            if ($uninstallProcess.ExitCode -eq 0) {
                $Context.Log("INFO: Teams Meeting Add-in uninstalled successfully")
            } else {
                $Context.Log("WARNING: Teams Meeting Add-in uninstall completed with exit code: $($uninstallProcess.ExitCode)")
            }
        } else {
            $Context.Log("INFO: No Teams Meeting Add-in found")
        }
    }
    catch {
        $Context.Log("WARNING: Teams Meeting Add-in uninstall failed: $($_.Exception.Message)")
    }
    
    # Remove AppX Teams packages
    try {
        $Apps = Get-AppxPackage -AllUsers | Where-Object { 
            $_.Name -like "*Teams*" -and $_.Publisher -like "*Microsoft Corporation*" 
        }
        
        if ($Apps) {
            foreach ($App in $Apps) {
                $Context.Log("INFO: Removing AppX Teams package: $($App.Name)")
                Remove-AppxPackage -Package $App.PackageFullName -AllUsers
            }
            $Context.Log("INFO: AppX Teams packages removed")
        } else {
            $Context.Log("INFO: No AppX Teams packages found")
        }
    }
    catch {
        $Context.Log("WARNING: AppX Teams removal failed: $($_.Exception.Message)")
    }
    
    # Uninstall WebRTC component
    try {
        $GetWebRTC = Get-CimInstance -ClassName Win32_Product | Where-Object { 
            $_.Name -like "Remote Desktop WebRTC*" -and $_.Vendor -eq "Microsoft Corporation" 
        }
        
        if ($null -ne $GetWebRTC.IdentifyingNumber) {
            $Context.Log("INFO: Uninstalling WebRTC component")
            $uninstallProcess = Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetWebRTC.IdentifyingNumber) /qn /norestart" -Wait -PassThru
            if ($uninstallProcess.ExitCode -eq 0) {
                $Context.Log("INFO: WebRTC component uninstalled successfully")
            } else {
                $Context.Log("WARNING: WebRTC uninstall completed with exit code: $($uninstallProcess.ExitCode)")
            }
        } else {
            $Context.Log("INFO: No WebRTC component found")
        }
    }
    catch {
        $Context.Log("WARNING: WebRTC uninstall failed: $($_.Exception.Message)")
    }
    
    # Remove Teams registry settings
    try {
        $Context.Log("INFO: Removing Teams registry settings")
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Teams") {
            Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Recurse -Force -ErrorAction SilentlyContinue
            $Context.Log("INFO: Teams registry settings removed")
        } else {
            $Context.Log("INFO: No Teams registry settings found")
        }
    }
    catch {
        $Context.Log("WARNING: Teams registry cleanup failed: $($_.Exception.Message)")
    }
    
    # Clean up any remaining Teams directories
    try {
        $TeamsDirectories = @(
            "$env:LOCALAPPDATA\Microsoft\Teams",
            "$env:APPDATA\Microsoft\Teams",
            "C:\Program Files (x86)\Microsoft\Teams",
            "C:\Program Files\Microsoft\Teams"
        )
        
        foreach ($dir in $TeamsDirectories) {
            if (Test-Path $dir) {
                $Context.Log("INFO: Removing Teams directory: $dir")
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        $Context.Log("INFO: Teams directories cleanup completed")
    }
    catch {
        $Context.Log("WARNING: Teams directories cleanup failed: $($_.Exception.Message)")
    }
    
    # Clean up installation files
    try {
        $InstallDir = 'C:\Windows\Temp\msteams_sa'
        if (Test-Path $InstallDir) {
            $Context.Log("INFO: Cleaning up installation files")
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
            $Context.Log("INFO: Installation files cleaned up")
        }
    }
    catch {
        $Context.Log("WARNING: Installation files cleanup failed: $($_.Exception.Message)")
    }
    
    $Context.Log("INFO: Microsoft Teams uninstallation completed")
}
catch {
    $Context.Log("ERROR: Microsoft Teams uninstallation failed: $($_.Exception.Message)")
    throw $_
}
