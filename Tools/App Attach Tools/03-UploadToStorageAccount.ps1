<#
.SYNOPSIS
    Uploads MSIX App Attach packages to a specified Azure File Share for use with AVD session hosts.

.DESCRIPTION
    This script connects to Azure, authenticates the user, retrieves a storage account key, 
    and maps an Azure File Share as a network drive on the local system. 
    It then copies App Attach package files (e.g., .cim and .vhdx) from a specified local folder to the Azure File Share.

    The Azure File Share is typically preconfigured as part of your AVD App Attach deployment setup.

    After the upload, the script unmaps the drive to leave the system clean.

.PARAMETER None
    The script prompts interactively for:
        - Resource group name
        - Storage account name
        - File share name
        - Local source folder path

.NOTES
    - Requires the `Az.Accounts` and `Az.Storage` modules (included in the Az PowerShell module).
    - The Azure Storage Account and File Share must already exist and be configured with the required permissions.
    - The executing identity must have permissions to retrieve storage account keys.
    - Refer to Microsoft’s official [MSIX App Attach documentation](https://learn.microsoft.com/en-us/azure/virtual-desktop/app-attach-overview) 
      for required permissions and storage setup guidelines.

.CUSTOMIZATION
    - Change `$driveLetter` if Z: is already used or reserved in your environment.
    - Automate input by replacing `Read-Host` with hardcoded variables or script parameters for unattended use.
    - Add logging or validation as needed for production scenarios.

.EXAMPLE
    PS> .\Upload-AppAttachPackages.ps1

    # This will prompt for required inputs and upload files to the specified Azure File Share.

#>

# Ensure required modules are installed and imported
$requiredModules = @("Az.Accounts", "Az.Storage")

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' is not installed. Installing from PSGallery..."
        try {
            Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Host "Module '$module' installed successfully."
        } catch {
            Write-Error "Failed to install module '$module'. Error: $_"
            exit 1
        }
    }
    # Import the module after installation check
    Import-Module $module -ErrorAction Stop
}


# Prompt for necessary variables
$resourceGroupName = Read-Host -Prompt "Enter the Resource Group Name"
$storageAccountName = Read-Host -Prompt "Enter the Azure Storage Account Name"
$fileShareName = Read-Host -Prompt "Enter the Azure File Share Name"
$sourceFolder = Read-Host -Prompt "Enter the local folder path to upload (e.g., C:\Temp\AVD App Attach\AppAttach)"
$driveLetter = "Z:"  # The drive letter you want to map temporarily

# Authenticate to Azure (if not already authenticated)
Connect-AzAccount

# Retrieve the storage account key securely
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
if ($null -eq $storageAccount) {
    Write-Error "Storage account not found. Please check the account name and try again."
    exit
}

$storageKey = ($storageAccount | Get-AzStorageAccountKey)[0].Value

# Construct the UNC path for the Azure File Share
$fileShareUNC = "\\$storageAccountName.file.core.windows.net\$fileShareName"

# Check if the drive letter is already in use
if (Test-Path $driveLetter) {
    Write-Host "Drive letter $driveLetter is already in use. Attempting to disconnect it..."
    # Disconnect the drive if it's already in use
    net use $driveLetter /delete
}

# Mapping the network drive to the Azure File Share using NET USE
Write-Host "Mapping the Azure File Share to $driveLetter..."

try {
    # Construct the correct command for net use
    $netUseCommand = "net use $driveLetter $fileShareUNC /user:Azure\$storageAccountName $storageKey /persistent:no"

    # Run the command
    Invoke-Expression $netUseCommand

    # Wait for a few seconds to ensure the drive is properly mapped
    Start-Sleep -Seconds 5

    # Check if the drive has been successfully mapped
    if (Test-Path $driveLetter) {
        Write-Host "Successfully mapped Azure File Share to $driveLetter."
    } else {
        Write-Error "Failed to map Azure File Share. Please check your credentials and connection."
        exit
    }
} catch {
    Write-Error "Failed to map the Azure File Share. Error: $_"
    exit
}

# Copy files from local folder to the mapped Azure File Share
Write-Host "Starting to copy files from $sourceFolder to $driveLetter..."
try {
    Copy-Item -Path "$sourceFolder\*" -Destination "$driveLetter\" -Recurse -Force
} catch {
    Write-Error "Failed to copy files to Azure File Share. Error: $_"
    exit
}

# Check if the copy was successful
if ($?) {
    Write-Host "Files successfully copied to Azure File Share."
} else {
    Write-Error "Failed to copy files. Please check the logs for errors."
}

# Optionally, remove the mapped network drive after use
Write-Host "Removing the mapped network drive..."
net use $driveLetter /delete

Write-Host "Completed the operation."
