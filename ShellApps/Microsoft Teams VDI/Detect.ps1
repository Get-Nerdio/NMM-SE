# Microsoft Teams Detection Script
# This script detects if Microsoft Teams (VDI optimized) is properly installed and up-to-date

try {
    $Context.Log("INFO: Starting Microsoft Teams detection")
    
    # Check for Teams machine-wide installation
    $teamsMachineWide = Get-CimInstance -ClassName Win32_Product | Where-Object { 
        $_.Name -like "Teams Machine-Wide*" -and $_.Vendor -eq "Microsoft Corporation" 
    }
    
    # Check for Teams Meeting Add-in for Outlook
    $teamsAddin = Get-CimInstance -ClassName Win32_Product | Where-Object { 
        $_.Name -like "*Teams Meeting Add-in*" -and $_.Vendor -eq "Microsoft" 
    }
    
    # Check for WebRTC component
    $webRTC = Get-CimInstance -ClassName Win32_Product | Where-Object { 
        $_.Name -like "Remote Desktop WebRTC*" -and $_.Vendor -eq "Microsoft Corporation" 
    }
    
    # Check for WebView2 runtime
    $webView2Installed = (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\') -or 
                         (Test-Path 'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\')
    
    # Check for Teams VDI optimization registry settings
    $teamsVDIEnabled = $false
    try {
        $isWVDEnvironment = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" -ErrorAction SilentlyContinue
        $disableAutoUpdate = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "disableAutoUpdate" -ErrorAction SilentlyContinue
        
        if ($isWVDEnvironment -and $isWVDEnvironment.IsWVDEnvironment -eq 1 -and 
            $disableAutoUpdate -and $disableAutoUpdate.disableAutoUpdate -eq 1) {
            $teamsVDIEnabled = $true
        }
    } catch {
        $Context.Log("WARNING: Could not check Teams VDI registry settings: $($_.Exception.Message)")
    }
    
    # Check Teams version if installed
    $teamsVersionCurrent = $false
    $installedVersion = "Not Installed"
    $latestVersion = "Unknown"
    
    if ($teamsMachineWide) {
        try {
            # Get installed Teams version
            $teamsExePath = "C:\Program Files (x86)\Microsoft\Teams\current\Teams.exe"
            if (Test-Path $teamsExePath) {
                $installedVersion = (Get-Item $teamsExePath).VersionInfo.FileVersion
                $Context.Log("INFO: Installed Teams version: $installedVersion")
                
                # Get latest Teams version from Microsoft
                try {
                    $versionResponse = Invoke-WebRequest -Uri "https://statics.teams.cdn.office.net/production-windows-x64/versions.json" -UseBasicParsing -TimeoutSec 30
                    $versionData = $versionResponse.Content | ConvertFrom-Json
                    $latestVersion = $versionData.latest
                    $Context.Log("INFO: Latest Teams version: $latestVersion")
                    
                    # Compare versions
                    if ([System.Version]$installedVersion -ge [System.Version]$latestVersion) {
                        $teamsVersionCurrent = $true
                        $Context.Log("INFO: Teams version is current")
                    } else {
                        $Context.Log("INFO: Teams version is outdated - update needed")
                    }
                } catch {
                    $Context.Log("WARNING: Could not fetch latest Teams version: $($_.Exception.Message)")
                    # If we can't check latest version, assume current version is acceptable
                    $teamsVersionCurrent = $true
                }
            } else {
                $Context.Log("WARNING: Teams executable not found at expected path")
            }
        } catch {
            $Context.Log("WARNING: Could not check Teams version: $($_.Exception.Message)")
        }
    }
    
    # Log detection results
    $Context.Log("INFO: Detection Results:")
    $Context.Log("INFO: - Teams Machine-Wide: $(if($teamsMachineWide) { 'Installed' } else { 'Not Found' })")
    $Context.Log("INFO: - Teams Meeting Add-in: $(if($teamsAddin) { 'Installed' } else { 'Not Found' })")
    $Context.Log("INFO: - WebRTC Component: $(if($webRTC) { 'Installed' } else { 'Not Found' })")
    $Context.Log("INFO: - WebView2 Runtime: $(if($webView2Installed) { 'Installed' } else { 'Not Found' })")
    $Context.Log("INFO: - Teams VDI Optimization: $(if($teamsVDIEnabled) { 'Enabled' } else { 'Not Enabled' })")
    $Context.Log("INFO: - Teams Version: $installedVersion (Latest: $latestVersion)")
    $Context.Log("INFO: - Version Current: $(if($teamsVersionCurrent) { 'Yes' } else { 'No' })")
    
    # Determine if Teams is properly installed and up-to-date
    # We consider Teams properly installed if:
    # 1. Teams Machine-Wide is installed
    # 2. Teams Meeting Add-in is installed  
    # 3. WebRTC component is installed
    # 4. WebView2 runtime is installed
    # 5. VDI optimization is enabled
    # 6. Teams version is current (or version check failed)
    $isProperlyInstalled = $teamsMachineWide -and $teamsAddin -and $webRTC -and $webView2Installed -and $teamsVDIEnabled -and $teamsVersionCurrent
    
    if ($isProperlyInstalled) {
        $Context.Log("INFO: Microsoft Teams (VDI optimized) is properly installed and up-to-date")
        exit 0  # Exit code 0 means application is detected/installed
    } else {
        $Context.Log("INFO: Microsoft Teams (VDI optimized) needs installation or update")
        exit 1  # Exit code 1 means application is not detected/not installed
    }
}
catch {
    $Context.Log("ERROR: Detection failed - $($_.Exception.Message)")
    exit 1  # Exit code 1 on error (assume not installed)
}
