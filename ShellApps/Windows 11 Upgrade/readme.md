# Windows 11 Upgrade Shell App

This Shell App provides automated detection, installation, and rollback capabilities for Windows 11 upgrades using the Windows 11 Installation Assistant.

## Overview

The Windows 11 Upgrade Shell App:
- **Detects** if Windows 11 is already installed or if Windows 10 is ready for upgrade
- **Installs** Windows 11 using Microsoft's official Installation Assistant
- **Provides rollback** capability to stop in-progress upgrades
- **Validates** hardware compatibility before attempting upgrade
- **Ensures** sufficient disk space and system requirements

## Components

### Detection Script (`Detect.ps1`)
Detects the current state and readiness for Windows 11 upgrade:

**Checks Performed:**
- Current operating system (Windows 10 vs Windows 11)
- Available disk space (minimum 64GB required)
- Hardware compatibility (TPM 2.0, Secure Boot, CPU, Memory)
- Running upgrade processes
- Existing Installation Assistant files

**Exit Codes:**
- `0` - Windows 11 is already installed or upgrade is ready
- `1` - Upgrade is needed or system is not compatible

### Installation Script (`Install.ps1`)
Performs the Windows 11 upgrade process:

**Parameters:**
- `InstallAssistantDownloadURL` - URL to Windows 11 Installation Assistant (default: Microsoft official)
- `DownloadDestination` - Local path for installer (default: TEMP directory)
- `UpdateLogLocation` - Directory for upgrade logs (default: Windows\Logs)

**Process:**
1. Validates administrator privileges
2. Verifies Windows 10 compatibility
3. Checks disk space (64GB minimum)
4. Runs hardware compatibility check
5. Downloads Windows 11 Installation Assistant
6. Verifies digital signature
7. Creates log directory
8. Initiates upgrade process
9. Monitors process startup

### Uninstallation Script (`Uninstall.ps1`)
Provides rollback capability for in-progress upgrades:

**Process:**
1. Checks current OS state
2. Stops running Windows 11 upgrade processes
3. Cleans up Installation Assistant files
4. Removes installation directories
5. Cleans up log files
6. Performs final verification

**Limitations:**
- Cannot rollback completed Windows 11 installations
- Only stops in-progress upgrade processes
- Completed upgrades require Windows Settings rollback (10-day limit)

## Usage in Nerdio Manager for MSP

### Creating the Shell App

1. **Navigate to Shell Apps** in Nerdio Manager for MSP
2. **Create New Shell App** with the following details:
   - **Name:** Windows 11 Upgrade
   - **Description:** Upgrades Windows 10 to Windows 11 using Microsoft's Installation Assistant

3. **Upload Scripts:**
   - **Detection Script:** Upload `Detect.ps1`
   - **Installation Script:** Upload `Install.ps1`
   - **Uninstallation Script:** Upload `Uninstall.ps1`

4. **Configure Parameters** for the Installation Script (optional):
   ```
   InstallAssistantDownloadURL: https://go.microsoft.com/fwlink/?linkid=2171764
   DownloadDestination: C:\Windows\TEMP\Windows11InstallAssistant\Windows11InstallationAssistant.exe
   UpdateLogLocation: C:\Windows\Logs\Windows11InstallAssistant
   ```

### Deploying the Shell App

1. **Assign to Host Pools** or individual VMs running Windows 10
2. **Schedule Installation** during maintenance windows
3. **Monitor Installation** through Nerdio Manager logs
4. **Use Uninstall** to stop in-progress upgrades if needed

## Hardware Requirements

### Minimum Requirements
- **OS:** Windows 10 version 2004 or later
- **CPU:** 1 GHz or faster with 2 or more cores
- **Memory:** 4 GB RAM
- **Storage:** 64 GB available space
- **TPM:** Trusted Platform Module version 2.0
- **Secure Boot:** UEFI firmware with Secure Boot capability
- **Graphics:** DirectX 12 compatible graphics / WDDM 2.x

### Compatibility Check
The Shell App automatically validates:
- **Storage:** Minimum 64GB free space
- **Memory:** Minimum 4GB RAM
- **TPM:** Version 2.0 present and enabled
- **Secure Boot:** UEFI Secure Boot enabled
- **CPU:** 64-bit processor with required features
- **Architecture:** 64-bit system

## Features

### Comprehensive Compatibility Validation
- **Hardware readiness check** using Microsoft's official algorithm
- **Disk space verification** before starting upgrade
- **TPM and Secure Boot validation**
- **CPU architecture and feature checks**

### Safe Installation Process
- **Digital signature verification** of Installation Assistant
- **Process monitoring** to ensure successful startup
- **Comprehensive logging** for troubleshooting
- **Error handling** with detailed error messages

### Rollback Capability
- **Stop in-progress upgrades** before completion
- **Clean up installation files** and directories
- **Remove temporary files** and logs
- **Restore system to pre-upgrade state**

### Detailed Logging
- **Progress tracking** throughout the upgrade process
- **Error reporting** with specific failure reasons
- **Process monitoring** with PID and path information
- **Compatibility results** with detailed breakdown

## Logging

All scripts provide detailed logging through the `$Context.Log()` function:
- **INFO** - Normal operations and status updates
- **WARNING** - Non-critical issues that don't stop execution
- **ERROR** - Critical errors that cause script failure

Logs are available in Nerdio Manager for MSP for troubleshooting and monitoring.

## Requirements

- **Windows 10** version 2004 or later
- **Administrator privileges** for installation/uninstallation
- **Internet connectivity** for downloading Installation Assistant
- **PowerShell 5.1** or later
- **Hardware compatibility** with Windows 11 requirements

## Troubleshooting

### Common Issues

1. **Installation Fails - Hardware Incompatible**
   - Check TPM 2.0 is enabled in BIOS/UEFI
   - Verify Secure Boot is enabled
   - Ensure sufficient disk space (64GB+)
   - Check CPU compatibility

2. **Installation Fails - Download Issues**
   - Verify internet connectivity
   - Check firewall/proxy settings
   - Ensure Microsoft URLs are accessible
   - Try different download URL parameter

3. **Upgrade Process Not Starting**
   - Check administrator privileges
   - Verify no other upgrade processes running
   - Review Windows Event Logs
   - Check disk space and permissions

4. **Rollback Not Working**
   - Only works for in-progress upgrades
   - Completed upgrades require Windows Settings rollback
   - Check if upgrade process is actually running
   - Verify administrator privileges

### Log Locations

- **Nerdio Manager Logs:** Available in NMM interface
- **Windows 11 Upgrade Logs:** `C:\Windows\Logs\Windows11InstallAssistant`
- **Installation Assistant Logs:** `C:\Program Files (x86)\WindowsInstallationAssistant\Logs`
- **Windows Event Logs:** Check Application and System logs

### Registry Settings

The upgrade process may create/modify these registry keys:
```
HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\*
```

## Security Considerations

- **Digital Signature Verification:** All downloads are verified against Microsoft certificates
- **Administrator Privileges:** Required for system-level changes
- **Secure Downloads:** Uses HTTPS and TLS 1.2/1.3
- **Process Validation:** Verifies legitimate Microsoft processes

## Version History

- **v1.0** - Initial Shell App creation
- Comprehensive detection, installation, and rollback capabilities
- Hardware compatibility validation
- Safe installation process with signature verification
- Detailed logging and error handling

## Support

For issues or questions regarding this Shell App:

1. **Check Nerdio Manager for MSP logs** for detailed error information
2. **Review Windows Event Logs** for system-level issues
3. **Verify hardware compatibility** using Windows 11 compatibility checker
4. **Check Microsoft documentation** for Windows 11 requirements
5. **Contact Nerdio support** if issues persist

## Important Notes

- **Backup Recommended:** Always backup important data before upgrading
- **Testing Recommended:** Test on non-production systems first
- **Maintenance Window:** Upgrades can take several hours to complete
- **Rollback Window:** Windows 11 rollback is only available for 10 days after installation
- **Compatibility:** Not all Windows 10 systems are compatible with Windows 11
