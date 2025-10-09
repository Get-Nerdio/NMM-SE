# Microsoft Teams VDI Shell App

This Shell App provides automated installation, detection, and uninstallation of Microsoft Teams optimized for Virtual Desktop Infrastructure (VDI) environments.

## Overview

The Microsoft Teams VDI Shell App installs:
- **Microsoft Teams** (machine-wide installation)
- **Teams Meeting Add-in for Outlook**
- **WebRTC component** for enhanced audio/video
- **Microsoft Edge WebView2 Runtime** (if not present)
- **VDI optimization settings** for better performance in virtual environments

## Components

### Detection Script (`Detect.ps1`)
Detects if Microsoft Teams is properly installed with all required components and up-to-date:
- Teams Machine-Wide installation
- Teams Meeting Add-in for Outlook
- WebRTC component
- Microsoft Edge WebView2 Runtime
- VDI optimization registry settings
- **Teams version is current** (compares against latest available version)

**Version Detection:**
- Fetches latest Teams version from Microsoft's official API
- Compares installed version against latest available version
- Triggers reinstallation if outdated version is detected
- Gracefully handles network failures (assumes current version is acceptable)

**Exit Codes:**
- `0` - Teams is properly installed and up-to-date
- `1` - Teams is not installed, missing components, or outdated

### Installation Script (`Install.ps1`)
Performs a complete installation of Microsoft Teams with VDI optimization:

**Parameters:**
- `TeamsInstallerUrl` - URL to Teams bootstrapper installer
- `WebRTCInstallerUrl` - URL to WebRTC component installer  
- `WebView2InstallerUrl` - URL to Microsoft Edge WebView2 Runtime installer

**Process:**
1. Installs WebView2 Runtime (if not present)
2. Uninstalls any existing Teams installations (per-user and per-machine)
3. Removes AppX Teams packages
4. Downloads and installs Teams with Meeting Add-in
5. Configures VDI optimization settings
6. Downloads and installs WebRTC component
7. Cleans up installation files

### Uninstallation Script (`Uninstall.ps1`)
Completely removes Microsoft Teams and all related components:

**Process:**
1. Uninstalls per-user Teams installation
2. Uninstalls per-machine Teams installation
3. Uninstalls Teams Meeting Add-in
4. Removes AppX Teams packages
5. Uninstalls WebRTC component
6. Removes Teams registry settings
7. Cleans up Teams directories and files

## Usage in Nerdio Manager for MSP

### Creating the Shell App

1. **Navigate to Shell Apps** in Nerdio Manager for MSP
2. **Create New Shell App** with the following details:
   - **Name:** Microsoft Teams VDI
   - **Description:** Installs Microsoft Teams optimized for VDI environments with Meeting Add-in and WebRTC support

3. **Upload Scripts:**
   - **Detection Script:** Upload `Detect.ps1`
   - **Installation Script:** Upload `Install.ps1`
   - **Uninstallation Script:** Upload `Uninstall.ps1`

4. **Configure Parameters** for the Installation Script:
   ```
   TeamsInstallerUrl: https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409
   WebRTCInstallerUrl: https://aka.ms/msrdcwebrtcsvc/msi
   WebView2InstallerUrl: https://go.microsoft.com/fwlink/p/?LinkId=2124703
   ```

### Deploying the Shell App

1. **Assign to Host Pools** or individual VMs
2. **Schedule Installation** or deploy immediately
3. **Monitor Installation** through Nerdio Manager logs

## Features

### VDI Optimization
- Enables Teams WVD Environment mode
- Disables automatic updates for better control
- Optimizes performance for virtual desktop scenarios

### Version Detection
- **Automatic version checking** against Microsoft's latest release
- **Smart update detection** - only reinstalls when newer version is available
- **Network resilience** - gracefully handles API failures
- **Prevents unnecessary reinstalls** of current versions

### Complete Cleanup
- Removes all previous Teams installations
- Cleans up per-user and per-machine installations
- Removes AppX packages and registry settings

### Comprehensive Installation
- Installs all required components in correct order
- Handles dependencies (WebView2 Runtime)
- Provides detailed logging throughout the process

## Logging

All scripts provide detailed logging through the `$Context.Log()` function:
- **INFO** - Normal operations and status updates
- **WARNING** - Non-critical issues that don't stop execution
- **ERROR** - Critical errors that cause script failure

Logs are available in Nerdio Manager for MSP for troubleshooting and monitoring.

## Requirements

- **Windows 10/11** or **Windows Server 2019/2022**
- **Administrator privileges** for installation/uninstallation
- **Internet connectivity** for downloading installers
- **PowerShell 5.1** or later

## Troubleshooting

### Common Issues

1. **Installation Fails**
   - Check internet connectivity
   - Verify URLs are accessible
   - Ensure sufficient disk space
   - Check Windows Event Logs

2. **Teams Not Appearing**
   - Wait 5-10 minutes after installation
   - Check if Teams service is running
   - Verify registry settings are applied

3. **WebRTC Issues**
   - Ensure WebRTC component installed successfully
   - Check firewall settings
   - Verify VDI optimization is enabled

### Registry Settings

The installation creates/modifies these registry keys:
```
HKLM:\SOFTWARE\Microsoft\Teams\IsWVDEnvironment = 1
HKLM:\SOFTWARE\Microsoft\Teams\disableAutoUpdate = 1
```

## Version History

- **v1.0** - Initial Shell App creation based on ScriptedAction
- Comprehensive detection, installation, and uninstallation
- VDI optimization and WebRTC support
- Complete cleanup and error handling

## Support

For issues or questions regarding this Shell App:
1. Check Nerdio Manager for MSP logs
2. Review Windows Event Logs
3. Verify all parameters are correctly configured
4. Contact Nerdio support if issues persist
