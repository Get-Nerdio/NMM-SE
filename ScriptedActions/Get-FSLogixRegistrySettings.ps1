<#
.SYNOPSIS
    Retrieves and displays all FSLogix registry settings from the local machine.

.DESCRIPTION
    'Get-FSLogixRegistrySettings.ps1' reads all registry values from:
    - HKEY_LOCAL_MACHINE\SOFTWARE\FSLogix\Apps
    - HKEY_LOCAL_MACHINE\SOFTWARE\FSLogix\Profiles
    
    All settings are displayed in the console and logged to a transcript file for audit and troubleshooting purposes.

.NOTES
    File Name  : Get-FSLogixRegistrySettings.ps1
    Author     : NMM-SE
    Version    : 1.0
    Date       : 2026-01-26

.EXAMPLE
    PS> .\Get-FSLogixRegistrySettings.ps1
    This command runs the script and displays all FSLogix registry settings.
#>

# Setup logging preferences and environment
$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = 'continue'
$folderPath = "$env:TEMP\NerdioManagerLogs"
$LognameTXT = "Get-FSLogixRegistrySettings.txt"

if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory $folderPath -Force | Out-Null
    Write-Output "$folderPath has been created."
}
else {
    Write-Output "$folderPath already exists, continue script"
}

Start-Transcript -Path (Join-Path $folderPath -ChildPath $LognameTXT) -Append -IncludeInvocationHeader
Write-Output "################# New Script Run #################"
Write-Output "Current time (UTC-0): $((Get-Date).ToUniversalTime())"
Write-Output ""

try {
    # Define registry paths
    $fsLogixAppsPath = "HKLM:\SOFTWARE\FSLogix\Apps"
    $fsLogixProfilesPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
    
    Write-Output "=========================================="
    Write-Output "FSLogix Registry Settings Report"
    Write-Output "=========================================="
    Write-Output ""
    
    # Check and display FSLogix Apps settings
    Write-Output "------------------------------------------"
    Write-Output "FSLogix Apps Settings"
    Write-Output "Registry Path: $fsLogixAppsPath"
    Write-Output "------------------------------------------"
    
    if (Test-Path $fsLogixAppsPath) {
        Write-Output "Registry key exists."
        Write-Output ""
        
        try {
            $appsProperties = Get-ItemProperty -Path $fsLogixAppsPath -ErrorAction Stop
            
            if ($appsProperties) {
                Write-Output "Registry Values:"
                Write-Output ""
                
                # Get all property names except the default PowerShell properties
                $propertyNames = $appsProperties.PSObject.Properties.Name | Where-Object {
                    $_ -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
                }
                
                if ($propertyNames.Count -gt 0) {
                    foreach ($propertyName in $propertyNames) {
                        $propertyValue = $appsProperties.$propertyName
                        Write-Output "  $propertyName = $propertyValue"
                    }
                }
                else {
                    Write-Output "  (No custom values found - only default registry properties)"
                }
            }
            else {
                Write-Output "No properties found in registry key."
            }
        }
        catch {
            Write-Output "Error reading registry properties: $($_.Exception.Message)"
        }
    }
    else {
        Write-Output "Registry key does not exist. FSLogix Apps may not be configured or installed."
    }
    
    Write-Output ""
    Write-Output ""
    
    # Check and display FSLogix Profiles settings
    Write-Output "------------------------------------------"
    Write-Output "FSLogix Profiles Settings"
    Write-Output "Registry Path: $fsLogixProfilesPath"
    Write-Output "------------------------------------------"
    
    if (Test-Path $fsLogixProfilesPath) {
        Write-Output "Registry key exists."
        Write-Output ""
        
        try {
            $profilesProperties = Get-ItemProperty -Path $fsLogixProfilesPath -ErrorAction Stop
            
            if ($profilesProperties) {
                Write-Output "Registry Values:"
                Write-Output ""
                
                # Get all property names except the default PowerShell properties
                $propertyNames = $profilesProperties.PSObject.Properties.Name | Where-Object {
                    $_ -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
                }
                
                if ($propertyNames.Count -gt 0) {
                    foreach ($propertyName in $propertyNames) {
                        $propertyValue = $profilesProperties.$propertyName
                        Write-Output "  $propertyName = $propertyValue"
                    }
                }
                else {
                    Write-Output "  (No custom values found - only default registry properties)"
                }
            }
            else {
                Write-Output "No properties found in registry key."
            }
        }
        catch {
            Write-Output "Error reading registry properties: $($_.Exception.Message)"
        }
    }
    else {
        Write-Output "Registry key does not exist. FSLogix Profiles may not be configured or installed."
    }
    
    Write-Output ""
    Write-Output "=========================================="
    Write-Output "Report completed successfully."
    Write-Output "=========================================="
}
catch {
    Write-Output "An error occurred: $($_.Exception.Message)"
    Write-Output "Error details: $($_.Exception)"
}
finally {
    Stop-Transcript
    $VerbosePreference = $SaveVerbosePreference
    Write-Output "Script execution completed."
}

# Restore original verbose preference settings
$VerbosePreference = $SaveVerbosePreference
