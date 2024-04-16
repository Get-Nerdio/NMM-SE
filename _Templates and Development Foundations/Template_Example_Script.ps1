#This is an example of a script that uses proper logging and error handling techniques, its not a hard requirement to use this template but more best practice to follow it.

<#
.SYNOPSIS
    This script performs clean-up tasks on the public desktop of a Windows machine.

.DESCRIPTION
    'Cleanup-PublicDesktop.ps1' is designed to remove specified items from the public desktop of all users.
    It logs all actions taken for audit and troubleshooting purposes.

.NOTES
    File Name  : Cleanup-PublicDesktop.ps1
    Author     : Your Name
    Version    : 1.0
    Date       : YYYY-MM-DD

.EXAMPLE
    PS> .\Cleanup-PublicDesktop.ps1
    This command runs the script with default parameters and performs clean-up tasks.
#>

# Setup logging preferences and environment
$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = 'continue'
$folderPath = "$env:TEMP\NerdioManagerLogs"
$LognameTXT = "Detection-CleanupPublicDestop.txt"

if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory $folderPath -Force
    Write-Output "$folderPath has been created."
}
else {
    Write-Output "$folderPath already exists, continue script"
}

Start-Transcript -Path (Join-Path $folderPath -ChildPath $LognameTXT) -Append -IncludeInvocationHeader
Write-Output "################# New Script Run #################"
Write-Output "Current time (UTC-0): $((Get-Date).ToUniversalTime())"

try {
    
    # Example task: Remove a specific shortcut from the public desktop
    $publicDesktopPath = [System.Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcutPath = Join-Path -Path $publicDesktopPath -ChildPath "UnwantedShortcut.lnk"
    
    if (Test-Path $shortcutPath) {
        Remove-Item -Path $shortcutPath -Force
        Write-Output "Removed shortcut from public desktop: $shortcutPath"
    }
    else {
        Write-Output "No action needed. Shortcut not found: $shortcutPath"
    }
}
catch {
    $_.Exception.Message
}
finally {
    Stop-Transcript
    $VerbosePreference = $SaveVerbosePreference
    Write-Output "Script execution completed."
}

# Restore original verbose preference settings
$VerbosePreference = $SaveVerbosePreference
