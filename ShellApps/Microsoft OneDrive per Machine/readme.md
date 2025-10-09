# Microsoft OneDrive per Machine Shell App

This Shell App automatically installs the latest version of Microsoft OneDrive in per-machine mode for all users on the system.

## Overview

OneDrive per Machine installation provides:
- Centralized OneDrive installation for all users
- Automatic updates through Windows Update
- Better management in enterprise environments
- Consistent user experience across all profiles

## Scripts

### Detect.ps1
- Always triggers installation/reinstallation to ensure latest version
- Returns exit code 1 to force installation every time
- This ensures OneDrive is always updated to the latest available version

### Install.ps1
- Downloads the latest OneDrive installer from Microsoft
- Removes any existing per-user OneDrive installations
- Removes any existing per-machine OneDrive installations
- Installs OneDrive in per-machine mode using `/allusers` flag
- Cleans up installer files after installation

### Uninstall.ps1
- Stops all OneDrive processes
- Downloads OneDrive installer for uninstall process
- Uninstalls OneDrive per-machine installation
- Removes personal OneDrive installations if found
- Cleans up OneDrive directories and files

## Requirements

- Windows 10/11 or Windows Server 2016+
- Internet connectivity for downloading installer
- Administrative privileges
- PowerShell 5.1 or later

## Usage

1. Upload this Shell App to your Nerdio Manager for MSP environment
2. Configure the Shell App in your host pool or session hosts
3. The Shell App will automatically reinstall OneDrive every time it runs to ensure the latest version

**Note**: This Shell App is configured to always reinstall OneDrive to ensure you always have the latest version. If you prefer to only install when OneDrive is missing, you can modify the Detect.ps1 script to check for existing installations instead of always returning exit code 1.

## Notes

- The installer is downloaded from Microsoft's official OneDrive download link
- Installation is performed silently with `/allusers` flag
- Existing OneDrive installations are removed before installing the latest version
- The Shell App handles both 32-bit and 64-bit installations
- All installer files are automatically cleaned up after use

## Troubleshooting

- Check the Nerdio Manager logs for detailed installation/uninstallation progress
- Ensure internet connectivity is available for downloading the installer
- Verify administrative privileges are available for installation
- Check Windows Event Logs for any OneDrive-related errors
