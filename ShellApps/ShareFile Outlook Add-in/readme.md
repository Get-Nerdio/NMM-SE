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
- **Version Checking**: Compares installed version against latest available version
- **Safe Installation**: Closes Outlook before installation to prevent conflicts
- **Version Management**: Uninstalls existing versions before installing the latest
- **Silent Installation**: Performs installations without user interaction
- **Comprehensive Logging**: Uses Nerdio's Context.Log for detailed operation logging
- **Error Handling**: Robust error handling with appropriate exit codes
- **Fallback Logic**: Gracefully handles version checking failures by assuming current installation is acceptable

## Installation Process

1. Closes any running Outlook processes
2. Uninstalls existing ShareFile Outlook add-in versions
3. Downloads the latest installer from Citrix (https://dl.sharefile.com/sfo-msi)
4. Performs silent installation
5. Cleans up temporary files

## Detection Logic

The detection script performs comprehensive checks to ensure the ShareFile Outlook add-in is installed and up-to-date:

### Installation Detection
Checks for applications with names containing:
- "ShareFile Outlook"
- "Citrix Files for Outlook" 
- "ShareFile" AND "Outlook"

### Version Checking
The script includes advanced version checking capabilities:

1. **Installed Version Detection**:
   - Retrieves version from Win32_Product information
   - Falls back to registry lookup in common ShareFile locations:
     - `HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\ShareFile.OutlookAddin`
     - `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\ShareFile.OutlookAddin`
     - `HKLM:\SOFTWARE\Citrix\ShareFile\OutlookAddin`

2. **Latest Version Detection**:
   - Attempts to fetch latest version from ShareFile's official installer URL
   - Checks HTTP headers for version information
   - Extracts version from Content-Disposition headers if available

3. **Version Comparison**:
   - Compares installed version against latest available version
   - Uses proper System.Version comparison for accurate results
   - Falls back to assuming current installation is acceptable if version checking fails

### Detection Results
The script provides detailed logging of:
- Installation status
- Installed version number
- Latest available version
- Whether update is required

## Exit Codes

- **Detection Script**: 
  - 0 = Application detected/installed and up-to-date
  - 1 = Application not detected/not installed OR needs update
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
