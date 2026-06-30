<#
.SYNOPSIS
Installs the Claude desktop app and configures it for use on the machine.

.DESCRIPTION
This script enables the Virtual Machine Platform feature, downloads the latest Claude desktop installer, installs it for all users, removes the temporary installer file, and disables Claude update notifications.

Execution mode: IndividualWithRestart
#>

# Configure logging
$LogFileRoot = "$env:Windir\Temp\NerdioManagerLogs\ScriptedActions\claude_sa"
$LogFileName = "Install-Claude.log"
If (-not (Test-Path $LogFileRoot)) {
    New-Item -Path $LogFileRoot -ItemType Directory -Force | Out-Null
}

$LogFilePath = Join-Path -Path $LogFileRoot -ChildPath $LogFileName

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFilePath -Value "[$timestamp] [$Level] $Message"
}

Write-Log "Starting Claude installation script."

# Install Virtual Machine Platform

# Check if the Virtual Machine Platform feature is already enabled
$vmPlatformFeature = Get-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform"
If ($vmPlatformFeature.State -eq "Enabled") {
    Write-Log "Virtual Machine Platform feature is already enabled."
} Else {
    Write-Log "Virtual Machine Platform feature is not enabled. Proceeding to enable it."
    Try {
        Write-Log "Enabling the Virtual Machine Platform feature."
        Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -NoRestart
        Write-Log "Virtual Machine Platform feature enabled successfully."
    } Catch {
        Write-Log "Failed to enable Virtual Machine Platform feature. Error: $($_.Exception.Message)" -Level "ERROR"
        Exit 1
    }
}


# Download latest Claude release
$ClaudeReleaseUrl = "https://claude.ai/api/desktop/win32/x64/msix/latest/redirect"
$ClaudeInstallerPath = "$env:TEMP\ClaudeInstaller.msix"
Try {
    Write-Log "Downloading Claude installer from $ClaudeReleaseUrl."
    if (Test-Path $ClaudeInstallerPath) {
        Remove-Item -Path $ClaudeInstallerPath -Force
        Write-Log "Removed existing installer at $ClaudeInstallerPath."
    }
    Invoke-WebRequest -Uri $ClaudeReleaseUrl -OutFile $ClaudeInstallerPath -UseBasicParsing
    Write-Log "Claude installer downloaded successfully to $ClaudeInstallerPath."
} Catch {
    Write-Log "Failed to download Claude installer from $ClaudeReleaseUrl. Error: $($_.Exception.Message)" -Level "ERROR"
    Exit 1
}

# Install Claude for all users
Try {
    Write-Log "Installing Claude for all users."
    Add-AppxProvisionedPackage -Online -PackagePath $ClaudeInstallerPath -SkipLicense -Regions All
    Write-Log "Claude installation completed successfully."
} Catch {
    Write-Log "Failed to install Claude from $ClaudeInstallerPath. Error: $($_.Exception.Message)" -Level "ERROR"
    Exit 1
}

# Clean up installer
If (Test-Path $ClaudeInstallerPath) {
    Try {
        Remove-Item -Path $ClaudeInstallerPath -Force
        Write-Log "Temporary installer removed from $ClaudeInstallerPath."
    } Catch {
        Write-Log "Failed to remove installer at $ClaudeInstallerPath. Error: $($_.Exception.Message)" -Level "WARN"
    }
} Else {
    Write-Log "Temporary installer file was not found at $ClaudeInstallerPath."
}

# Set registry options for Claude
$ClaudeRegistryPath = "HKLM:\SOFTWARE\Policies\Claude"
    
if (-not (Test-Path $ClaudeRegistryPath)) {
    New-Item -Path $ClaudeRegistryPath -Force | Out-Null
    Write-Log "Created registry path $ClaudeRegistryPath."
}

# Disable update notifications for Claude
Try {
    Write-Log "Configuring registry setting to disable Claude update notifications."
    Set-ItemProperty -Path $ClaudeRegistryPath -Name "disableAutoUpdates" -Value 1 -Type DWord
    Write-Log "Registry setting applied successfully."
} Catch {
    Write-Log "Failed to set registry key to disable update notifications. Error: $($_.Exception.Message)" -Level "WARN"
}

# Keep Cowork enabled
try {
    Write-Log "Configuring registry setting to keep Cowork enabled."
    Set-ItemProperty -Path $ClaudeRegistryPath -Name "secureVmFeaturesEnabled" -Value 1 -Type DWord
    Write-Log "Registry setting applied successfully."
} Catch {
    Write-Log "Failed to set registry key to keep Cowork enabled. Error: $($_.Exception.Message)" -Level "WARN"
}

# Keep extensions enabled
try {
    Write-Log "Configuring registry setting to keep extensions enabled."
    Set-ItemProperty -Path $ClaudeRegistryPath -Name "isDesktopExtensionEnabled" -Value 1 -Type DWord
    Set-ItemProperty -Path $ClaudeRegistryPath -Name "isDesktopExtensionDirectoryEnabled" -Value 1 -Type DWord
    Write-Log "Registry setting applied successfully."
} Catch {
    Write-Log "Failed to set registry key to keep extensions enabled. Error: $($_.Exception.Message)" -Level "WARN"
}

Write-Log "Claude installation script completed."