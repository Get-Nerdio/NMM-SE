# ShareFile Outlook Add-in Shell App

This Shell App automates the installation, detection, and uninstallation of the ShareFile Outlook add-in (Citrix Files for Outlook) in Nerdio Manager for MSP.

## Overview

The ShareFile Outlook add-in allows users to securely share files directly from Microsoft Outlook using Citrix ShareFile. This Shell App provides automated management of the add-in across your managed environments.

## Files

- **Detect.ps1** - Detection script that checks if the ShareFile Outlook add-in is installed
- **Install.ps1** - Installation script that downloads and installs the latest version
- **Uninstall.ps1** - Uninstallation script that removes the add-in

## Features

- **Automatic Detection**: Checks for existing installations using multiple product name variations
- **Safe Installation**: Closes Outlook before installation to prevent conflicts
- **Version Management**: Uninstalls existing versions before installing the latest
- **Silent Installation**: Performs installations without user interaction
- **Comprehensive Logging**: Uses Nerdio's Context.Log for detailed operation logging
- **Error Handling**: Robust error handling with appropriate exit codes

## Installation Process

1. Closes any running Outlook processes
2. Uninstalls existing ShareFile Outlook add-in versions
3. Downloads the latest installer from Citrix (https://dl.sharefile.com/sfo-msi)
4. Performs silent installation
5. Cleans up temporary files

## Detection Logic

The detection script checks for applications with names containing:
- "ShareFile Outlook"
- "Citrix Files for Outlook" 
- "ShareFile" AND "Outlook"

## Exit Codes

- **Detection Script**: 
  - 0 = Application detected/installed
  - 1 = Application not detected/not installed
- **Install/Uninstall Scripts**: 
  - 0 = Success
  - Non-zero = Error occurred

## Requirements

- PowerShell execution policy allowing script execution
- Administrative privileges for software installation/uninstallation
- Internet connectivity for downloading the installer
- Microsoft Outlook (for the add-in to function)

## Usage in Nerdio Manager

1. Navigate to **Applications** > **Shell Apps**
2. Click **Add** > **Add new**
3. Configure the Shell App:
   - **Name**: ShareFile Outlook Add-in
   - **Publisher**: Citrix
   - **Detection**: Upload `Detect.ps1`
   - **Install**: Upload `Install.ps1`
   - **Uninstall**: Upload `Uninstall.ps1`
4. Assign to appropriate Host Pools or Users

## Notes

- The installer URL points to Citrix's official download location
- Installation is performed silently with no user interaction required
- The script handles multiple product name variations for maximum compatibility
- Temporary files are automatically cleaned up after installation
