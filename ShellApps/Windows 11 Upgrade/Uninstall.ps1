# Windows 11 Upgrade Uninstallation Script
# This script provides rollback capability by stopping the Windows 11 upgrade process
# Note: This script can only stop the upgrade process if it's still running
# Once Windows 11 installation is complete, this script cannot rollback to Windows 10

try {
    $Context.Log("INFO: Starting Windows 11 upgrade uninstallation/rollback")
    
    # Check if running as administrator
    if (!(Test-IsElevated)) {
        $Context.Log("ERROR: This script must be run with Administrator privileges")
        throw "Access Denied. Please run with Administrator privileges."
    }
    
    # Check current OS
    try {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $Context.Log("INFO: Current OS: $($OS.Caption) Version: $($OS.Version)")
    }
    catch {
        $Context.Log("ERROR: Unable to retrieve operating system information: $($_.Exception.Message)")
        throw $_
    }
    
    # If already running Windows 11, we cannot rollback
    if ($OS.Caption -match "Windows 11") {
        $Context.Log("WARNING: Windows 11 is already installed")
        $Context.Log("WARNING: This script cannot rollback Windows 11 to Windows 10")
        $Context.Log("WARNING: To rollback Windows 11, use Windows Settings > Update & Security > Recovery > Go back to Windows 10")
        $Context.Log("INFO: This rollback option is only available for 10 days after Windows 11 installation")
        exit 0  # Exit code 0 means no action needed (already Windows 11)
    }
    
    # Check if Windows 10 upgrade process is running
    $Context.Log("INFO: Checking for running Windows 11 upgrade process")
    $Windows10UpgradeApp = Get-Process -Name "Windows10UpgraderApp" -ErrorAction SilentlyContinue
    
    if (!$Windows10UpgradeApp) {
        $Context.Log("INFO: No Windows 11 upgrade process is currently running")
        $Context.Log("INFO: Nothing to uninstall/rollback")
        exit 0  # Exit code 0 means no action needed
    }
    
    $Context.Log("INFO: Found running Windows 11 upgrade process")
    $Context.Log("INFO: Process Details:")
    $Context.Log("INFO: - PID: $($Windows10UpgradeApp.Id)")
    $Context.Log("INFO: - Name: $($Windows10UpgradeApp.ProcessName)")
    $Context.Log("INFO: - Path: $($Windows10UpgradeApp.Path)")
    
    # Attempt to stop the upgrade process
    try {
        $Context.Log("INFO: Attempting to stop Windows 11 upgrade process")
        
        # Try graceful termination first
        $Windows10UpgradeApp.CloseMainWindow()
        Start-Sleep -Seconds 10
        
        # Check if process is still running
        $Windows10UpgradeApp = Get-Process -Name "Windows10UpgraderApp" -ErrorAction SilentlyContinue
        if ($Windows10UpgradeApp) {
            $Context.Log("WARNING: Graceful termination failed, attempting force termination")
            Stop-Process -Name "Windows10UpgraderApp" -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            
            # Verify process is stopped
            $Windows10UpgradeApp = Get-Process -Name "Windows10UpgraderApp" -ErrorAction SilentlyContinue
            if ($Windows10UpgradeApp) {
                throw "Failed to stop Windows 11 upgrade process"
            }
        }
        
        $Context.Log("INFO: Windows 11 upgrade process stopped successfully")
    }
    catch {
        $Context.Log("ERROR: Failed to stop Windows 11 upgrade process: $($_.Exception.Message)")
        throw "Unable to stop the Windows 11 upgrade process"
    }
    
    # Clean up Windows 11 Installation Assistant files
    try {
        $Context.Log("INFO: Cleaning up Windows 11 Installation Assistant files")
        
        $InstallAssistantPath = "$env:TEMP\Windows11InstallAssistant\Windows11InstallationAssistant.exe"
        if (Test-Path $InstallAssistantPath) {
            Remove-Item $InstallAssistantPath -Force -ErrorAction SilentlyContinue
            $Context.Log("INFO: Removed Windows 11 Installation Assistant executable")
        }
        
        $InstallAssistantDir = "$env:TEMP\Windows11InstallAssistant"
        if (Test-Path $InstallAssistantDir) {
            Remove-Item $InstallAssistantDir -Recurse -Force -ErrorAction SilentlyContinue
            $Context.Log("INFO: Removed Windows 11 Installation Assistant directory")
        }
    }
    catch {
        $Context.Log("WARNING: Failed to clean up Installation Assistant files: $($_.Exception.Message)")
    }
    
    # Clean up Windows 11 Installation Assistant installation directory
    try {
        $InstallAssistantInstallDir = "${env:ProgramFiles(x86)}\WindowsInstallationAssistant"
        if (Test-Path $InstallAssistantInstallDir) {
            $Context.Log("INFO: Found Windows Installation Assistant installation directory")
            
            # Check if there are any running processes from this directory
            $InstallAssistantProcesses = Get-Process | Where-Object { $_.Path -like "*WindowsInstallationAssistant*" }
            if ($InstallAssistantProcesses) {
                $Context.Log("WARNING: Found running processes from Windows Installation Assistant")
                foreach ($proc in $InstallAssistantProcesses) {
                    $Context.Log("INFO: Stopping process: $($proc.ProcessName) (PID: $($proc.Id))")
                    try {
                        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    }
                    catch {
                        $Context.Log("WARNING: Failed to stop process $($proc.ProcessName): $($_.Exception.Message)")
                    }
                }
            }
            
            # Wait a moment for processes to stop
            Start-Sleep -Seconds 5
            
            # Attempt to remove the directory
            try {
                Remove-Item $InstallAssistantInstallDir -Recurse -Force -ErrorAction Stop
                $Context.Log("INFO: Removed Windows Installation Assistant installation directory")
            }
            catch {
                $Context.Log("WARNING: Could not remove installation directory (may be in use): $($_.Exception.Message)")
            }
        }
    }
    catch {
        $Context.Log("WARNING: Failed to clean up Windows Installation Assistant installation: $($_.Exception.Message)")
    }
    
    # Clean up log files
    try {
        $LogLocation = "$env:SYSTEMROOT\Logs\Windows11InstallAssistant"
        if (Test-Path $LogLocation) {
            $Context.Log("INFO: Cleaning up Windows 11 upgrade log files")
            $logFiles = Get-ChildItem $LogLocation -File -ErrorAction SilentlyContinue
            if ($logFiles) {
                foreach ($logFile in $logFiles) {
                    try {
                        Remove-Item $logFile.FullName -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        $Context.Log("WARNING: Could not remove log file $($logFile.Name): $($_.Exception.Message)")
                    }
                }
                $Context.Log("INFO: Cleaned up Windows 11 upgrade log files")
            }
        }
    }
    catch {
        $Context.Log("WARNING: Failed to clean up log files: $($_.Exception.Message)")
    }
    
    # Check for Windows 11 upgrade registry entries and clean them up
    try {
        $Context.Log("INFO: Checking for Windows 11 upgrade registry entries")
        
        # Common Windows 11 upgrade registry locations
        $RegistryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Download",
            "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\Client.OS.rs2.amd64",
            "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\Client.OS.rs3.amd64",
            "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\Client.OS.rs4.amd64",
            "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\Client.OS.rs5.amd64",
            "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\Client.OS.rs6.amd64"
        )
        
        foreach ($regPath in $RegistryPaths) {
            if (Test-Path $regPath) {
                try {
                    $regKey = Get-Item $regPath -ErrorAction SilentlyContinue
                    if ($regKey) {
                        $Context.Log("INFO: Found registry key: $regPath")
                        # Note: We don't remove these keys as they may be needed for Windows Update functionality
                        # Just log their presence for troubleshooting
                    }
                }
                catch {
                    $Context.Log("WARNING: Could not access registry key ${regPath}: $($_.Exception.Message)")
                }
            }
        }
    }
    catch {
        $Context.Log("WARNING: Registry cleanup check failed: $($_.Exception.Message)")
    }
    
    # Final verification
    $Context.Log("INFO: Performing final verification")
    
    # Check if upgrade process is still running
    $Windows10UpgradeApp = Get-Process -Name "Windows10UpgraderApp" -ErrorAction SilentlyContinue
    if ($Windows10UpgradeApp) {
        $Context.Log("WARNING: Windows 11 upgrade process is still running after cleanup attempt")
        $Context.Log("WARNING: Manual intervention may be required")
    }
    else {
        $Context.Log("INFO: Windows 11 upgrade process successfully stopped")
    }
    
    # Check if Windows 11 Installation Assistant is still installed
    $InstallAssistantInstallDir = "${env:ProgramFiles(x86)}\WindowsInstallationAssistant"
    if (Test-Path $InstallAssistantInstallDir) {
        $Context.Log("WARNING: Windows Installation Assistant installation directory still exists")
        $Context.Log("WARNING: This may indicate the upgrade process was not fully stopped")
    }
    else {
        $Context.Log("INFO: Windows Installation Assistant installation directory removed")
    }
    
    $Context.Log("INFO: Windows 11 upgrade uninstallation/rollback completed")
    $Context.Log("INFO: The system should now be back to its pre-upgrade state")
    $Context.Log("INFO: If Windows 11 installation had progressed significantly, a system restart may be required")
}
catch {
    $Context.Log("ERROR: Windows 11 upgrade uninstallation/rollback failed: $($_.Exception.Message)")
    throw $_
}

# Helper Functions
function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
