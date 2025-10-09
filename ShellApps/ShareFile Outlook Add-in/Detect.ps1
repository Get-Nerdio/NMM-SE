# ShareFile Outlook Add-in Detection Script
# This script detects if the ShareFile Outlook add-in is installed and checks if it's the latest version

try {
    $Context.Log("INFO: Starting ShareFile Outlook add-in detection")
    
    # Check for ShareFile Outlook add-in using Win32_Product
    $installedApps = Get-CimInstance Win32_Product | Where-Object {
        $_.Name -like "*ShareFile Outlook*" -or 
        $_.Name -like "*Citrix Files for Outlook*" -or
        $_.Name -like "*ShareFile*" -and $_.Name -like "*Outlook*"
    }

    if (-not $installedApps) {
        # Application is not installed
        $Context.Log("INFO: ShareFile Outlook add-in not detected")
        exit 1  # Exit code 1 means application is not detected/not installed
    }

    # Application is installed - now check version
    $Context.Log("INFO: ShareFile Outlook add-in detected - $($installedApps.Name)")
    
    # Get installed version information
    $installedVersion = "Unknown"
    $isVersionCurrent = $false
    
    try {
        # Try to get version from the installed application
        if ($installedApps.Version) {
            $installedVersion = $installedApps.Version
            $Context.Log("INFO: Installed ShareFile version: $installedVersion")
        }
        
        # Try to get version from registry as backup
        if ($installedVersion -eq "Unknown") {
            try {
                # Check common registry locations for ShareFile version
                $registryPaths = @(
                    "HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\ShareFile.OutlookAddin",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\ShareFile.OutlookAddin",
                    "HKLM:\SOFTWARE\Citrix\ShareFile\OutlookAddin"
                )
                
                foreach ($regPath in $registryPaths) {
                    if (Test-Path $regPath) {
                        $versionValue = Get-ItemProperty -Path $regPath -Name "Version" -ErrorAction SilentlyContinue
                        if ($versionValue) {
                            $installedVersion = $versionValue.Version
                            $Context.Log("INFO: Found ShareFile version in registry: $installedVersion")
                            break
                        }
                    }
                }
            } catch {
                $Context.Log("WARNING: Could not check registry for ShareFile version: $($_.Exception.Message)")
            }
        }
        
        # Try to get latest version from ShareFile
        $latestVersion = "Unknown"
        try {
            # Check if we can get version info from the installer URL
            $Context.Log("INFO: Attempting to fetch latest ShareFile version information")
            
            # Try to get version from ShareFile's version endpoint or installer metadata
            try {
                # Make a HEAD request to the installer URL to check for version info
                $response = Invoke-WebRequest -Uri "https://dl.sharefile.com/sfo-msi" -Method Head -UseBasicParsing -TimeoutSec 30
                
                # Check if there's version info in headers
                if ($response.Headers.ContainsKey("X-Version")) {
                    $latestVersion = $response.Headers["X-Version"]
                } elseif ($response.Headers.ContainsKey("Content-Disposition")) {
                    # Try to extract version from filename if available
                    $contentDisposition = $response.Headers["Content-Disposition"]
                    if ($contentDisposition -match "version[=:]\s*([0-9.]+)") {
                        $latestVersion = $matches[1]
                    }
                }
                
                $Context.Log("INFO: Latest ShareFile version from server: $latestVersion")
            } catch {
                $Context.Log("WARNING: Could not fetch latest version from ShareFile server: $($_.Exception.Message)")
            }
            
            # If we couldn't get version from server, use a fallback approach
            if ($latestVersion -eq "Unknown") {
                # For ShareFile, we'll assume the installer always provides the latest version
                # Since the install script downloads from the official URL, we'll consider any installed version as current
                # unless we can definitively determine it's outdated
                $Context.Log("INFO: Could not determine latest version - assuming current installation is acceptable")
                $isVersionCurrent = $true
            } else {
                # Compare versions if we have both
                if ($installedVersion -ne "Unknown" -and $latestVersion -ne "Unknown") {
                    try {
                        # Convert to System.Version objects for proper comparison
                        $installedVer = [System.Version]$installedVersion
                        $latestVer = [System.Version]$latestVersion
                        
                        if ($installedVer -ge $latestVer) {
                            $isVersionCurrent = $true
                            $Context.Log("INFO: ShareFile version is current ($installedVersion >= $latestVersion)")
                        } else {
                            $Context.Log("INFO: ShareFile version is outdated - installed: $installedVersion, latest: $latestVersion")
                        }
                    } catch {
                        $Context.Log("WARNING: Could not compare versions - assuming current: $($_.Exception.Message)")
                        $isVersionCurrent = $true
                    }
                } else {
                    # If we can't determine versions, assume current
                    $isVersionCurrent = $true
                }
            }
        } catch {
            $Context.Log("WARNING: Version checking failed - assuming current installation is acceptable: $($_.Exception.Message)")
            $isVersionCurrent = $true
        }
        
    } catch {
        $Context.Log("WARNING: Version detection failed - assuming current installation is acceptable: $($_.Exception.Message)")
        $isVersionCurrent = $true
    }
    
    # Log detection results
    $Context.Log("INFO: Detection Results:")
    $Context.Log("INFO: - ShareFile Outlook Add-in: Installed ($($installedApps.Name))")
    $Context.Log("INFO: - Installed Version: $installedVersion")
    $Context.Log("INFO: - Latest Version: $latestVersion")
    $Context.Log("INFO: - Version Current: $(if($isVersionCurrent) { 'Yes' } else { 'No' })")
    
    # Determine if ShareFile is properly installed and up-to-date
    if ($isVersionCurrent) {
        $Context.Log("INFO: ShareFile Outlook add-in is installed and up-to-date")
        exit 0  # Exit code 0 means application is detected/installed and current
    } else {
        $Context.Log("INFO: ShareFile Outlook add-in is installed but needs update")
        exit 1  # Exit code 1 means application needs update
    }
}
catch {
    $Context.Log("ERROR: Detection failed - $($_.Exception.Message)")
    exit 1  # Exit code 1 on error (assume not installed)
}
