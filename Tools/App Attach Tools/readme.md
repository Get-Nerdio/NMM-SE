# App Attach Script Toolkit for Azure Virtual Desktop (AVD)

This toolkit includes PowerShell scripts designed to automate the preparation, conversion, and deployment of Microsoft Store applications for use with App Attach in Azure Virtual Desktop (AVD) environments.

The scripts support a full lifecycle:  
1. Download apps from the Microsoft Store using WinGet
2. Convert them into App Attach-compatible formats using msixmgr
3. Upload app attach packages to an Azure Storage Account
4. Install necessary runtime dependencies on the AVD image  
5. Remove built-in apps on the AVD image to avoid duplication or conflicts

---

## Script Overview

| Script                       | Purpose                                                                                     |
|------------------------------|---------------------------------------------------------------------------------------------|
| `01-DownloadApps.ps1`         | Downloads MSIX bundles and dependencies from the Microsoft Store                            |
| `02-ConvertApps.ps1`          | Converts MSIX bundles into `.cim` and `.vhdx` files for App Attach                          |
| `03-UploadToStorageAccount.ps1` | Uploads converted packages to an Azure File Share                                          |
| `04-InstallDependencies.ps1`  | Installs dependency packages on the AVD Desktop Image                                      |
| `05-UninstallLocalApps.ps1`   | Removes built-in apps from the AVD image that are replaced via App Attach                   |

---

## Prerequisites

Before running these scripts:

- A computer or VM that's joined to Entra ID
- An Entra ID user with one of the following Roles: 
  User Administator, License Administor, or Global Adminstrator
- Ensure you're using PowerShell 5.1 or later  
- Install WinGet 1.4 or later (`winget download` must be supported)  
- Download and extract `msixmgr.exe` from the MSIX Toolkit:  
  https://aka.ms/msixmgr 
- You must have administrator rights on the image VM  
- Ensure appropriate Azure permissions to retrieve and use storage account keys  
- Make sure you're signed into the Microsoft Store if downloading apps using WinGet  

### Azure PowerShell Modules Requirement

- The scripts require the `Az.Accounts` and `Az.Storage` modules (part of the Az PowerShell module) for Azure interaction.  
- The **Upload script (`03-UploadToStorageAccount.ps1`) now automatically checks for and installs these modules** if they are missing, to simplify first-time use.  
- This automatic installation requires:  
  - Internet access to download modules from the PowerShell Gallery  
  - PowerShell 5.1 or newer  
  - Permission to install modules in the current user scope  

#### Manual Module Installation (optional)

If you prefer to install the Azure modules manually before running the scripts, use:

```powershell
Install-Module -Name Az.Accounts, Az.Storage -Scope CurrentUser -AllowClobber


---

## Script Execution Order

The scripts should be run in the following sequence:

### 1. `01-DownloadApps.ps1`
Downloads selected Microsoft Store apps (e.g., Notepad, Paint, Photos) as `.msixbundle` files and organizes their dependency packages.

Customization:
- Modify `$packageIds` to select apps
- Change destination paths as needed

---

### 2. `02-ConvertApps.ps1`
Converts the downloaded MSIX bundles into `.cim` and `.vhdx` files using `msixmgr.exe`, storing them in the correct folder structure for App Attach.

Customization:
- Set the correct `$msixSourceFolder`, `$appAttachRoot`, and `$msixMgrPath`
- Modify keyword mapping for apps if needed

---

### 3. `03-UploadToStorageAccount.ps1`
Uploads the converted `.cim` and `.vhdx` App Attach files to a specified Azure File Share for use by AVD session hosts.

The script prompts for:
- Resource Group Name
- Storage Account Name
- File Share Name
- Local folder path to upload from

Ensure the Storage Account permissions match Microsoft’s requirements:
https://learn.microsoft.com/en-us/azure/virtual-desktop/app-attach-overview

---

### 4. `04-InstallDependencies.ps1`
Installs all `.appx` and `.msix` dependency packages (previously downloaded in Step 1) onto the AVD Desktop Image so that App Attach apps can run properly.

This script must be run on the AVD image VM with administrator privileges.

---

### 5. `05-UninstallLocalApps.ps1`
Removes built-in app versions (e.g., Notepad, Photos, Snipping Tool) to avoid duplication with App Attach versions.

Edit the `$appIdentifiers` array to include or exclude specific built-in apps.

---

## Example Workflow

```powershell
# On your packaging or utility VM:
.\01-DownloadApps.ps1
.\02-ConvertApps.ps1
.\03-UploadToStorageAccount.ps1

# On your AVD Desktop Image VM:
.\04-InstallDependencies.ps1
.\05-UninstallLocalApps.ps1
