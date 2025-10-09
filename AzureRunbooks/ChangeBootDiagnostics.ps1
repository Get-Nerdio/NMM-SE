#description: Update Boot Diagnostics storage account URI for a VM using Nerdio context
#tags: Nerdio, Diagnostics, VM

<#
This Scripted Action updates the Boot Diagnostics storage account for the current VM.
It uses Nerdio's built‑in $AzureVMName variable.

You must supply the new Storage Account **name** at runtime (optional, because there's a default).
If you do not, the script will fall back to the default.
Ensure the automation identity has rights to the VM and to the target storage account.

This script only handles Boot Diagnostics (legacy). It does not configure full Azure Monitor diagnostics.

Note: If you encounter Az module compatibility issues, consider updating your Az modules:
Update-PSResource Az.* -- Update your Az modules.

#>

<# Variables:
{
  "NewStorageAccountName": {
    "Description": "Name of the storage account to use for Boot Diagnostics (just the name, not the URI).",
    "IsRequired": false,
    "DefaultValue": "diagstoracct2501"
  }
}
#>

$ErrorActionPreference = "Stop"

# Manually enforce default fallback if Nerdio did not inject a value or if it's blank
if ([string]::IsNullOrWhiteSpace($NewStorageAccountName)) {
    $NewStorageAccountName = "diagstoracct2501"
    Write-Output "No storage account name provided — falling back to default: $NewStorageAccountName"
}
else {
    Write-Output "Using provided storage account name: $NewStorageAccountName"
}

# Connect to Azure (using the context Nerdio provides)
Write-Output "Verifying Azure connection..."
try {
    $context = Get-AzContext
    if (-not $context) {
        Throw "No Azure context found. Please ensure you're connected to Azure."
    }
    Write-Output "Connected to Azure subscription: $($context.Subscription.Name)"
}
catch {
    Throw "Failed to verify Azure connection: $($_.Exception.Message)"
}

Write-Output "Getting VM information from Nerdio context..."
try {
    $vm = Get-AzVM -Name $AzureVMName
}
catch {
    Throw "Failed to retrieve VM '$AzureVMName': $($_.Exception.Message)"
}

if (-not $vm) {
    Throw "Could not find VM with name '$AzureVMName'."
}

$resourceGroup = $vm.ResourceGroupName
$location = $vm.Location

Write-Output "VM Resource Group: $resourceGroup, Location: $location"

# Find the storage account
Write-Output "Looking for storage account '$NewStorageAccountName' in region '$location'..."
try {
    $storageAccount = Get-AzStorageAccount | Where-Object {
        $_.StorageAccountName -eq $NewStorageAccountName -and $_.Location -eq $location
    }
}
catch {
    Throw "Failed to retrieve storage accounts: $($_.Exception.Message)"
}

if (-not $storageAccount) {
    Write-Output "Storage account '$NewStorageAccountName' not found in region '$location'. Searching all regions..."
    try {
        $storageAccount = Get-AzStorageAccount | Where-Object {
            $_.StorageAccountName -eq $NewStorageAccountName
        }
        if ($storageAccount) {
            Write-Output "Found storage account '$NewStorageAccountName' in region '$($storageAccount.Location)'"
        }
    }
    catch {
        Throw "Failed to search for storage account: $($_.Exception.Message)"
    }
}

if (-not $storageAccount) {
    Write-Output "Storage account '$NewStorageAccountName' was not found in any region."
    
    # If using the default name, try to find any existing storage account in the VM's region
    if ($NewStorageAccountName -eq "diagstoracct2501") {
        Write-Output "Attempting to find any existing storage account in region '$location'..."
        try {
            $existingStorageAccounts = Get-AzStorageAccount | Where-Object { $_.Location -eq $location }
            if ($existingStorageAccounts) {
                $storageAccount = $existingStorageAccounts | Select-Object -First 1
                Write-Output "Found existing storage account '$($storageAccount.StorageAccountName)' in region '$location'"
                Write-Output "Using this storage account for Boot Diagnostics instead of creating a new one."
            }
        }
        catch {
            Write-Warning "Could not search for existing storage accounts: $($_.Exception.Message)"
        }
    }
    
    # If still no storage account found, create one
    if (-not $storageAccount) {
        Write-Output "No suitable storage account found. Creating new storage account '$NewStorageAccountName'..."
        try {
            # Generate a unique name if the default name is taken
            $baseName = $NewStorageAccountName
            $counter = 1
            do {
                $testName = if ($counter -eq 1) { $baseName } else { "$baseName$counter" }
                $existing = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $testName }
                if (-not $existing) {
                    $NewStorageAccountName = $testName
                    break
                }
                $counter++
            } while ($counter -lt 100)
            
            Write-Output "Creating storage account '$NewStorageAccountName' in resource group '$resourceGroup'..."
            $storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $NewStorageAccountName -Location $location -SkuName "Standard_LRS" -Kind "StorageV2"
            Write-Output "✅ Successfully created storage account '$NewStorageAccountName'"
        }
        catch {
            Throw "Failed to create storage account '$NewStorageAccountName': $($_.Exception.Message)"
        }
    }
}

# Construct the storage URI
$storageUri = "https://$($storageAccount.StorageAccountName).blob.core.windows.net/"

Write-Output "Storage Account Details:"
Write-Output "  Name: $($storageAccount.StorageAccountName)"
Write-Output "  Resource Group: $($storageAccount.ResourceGroupName)"
Write-Output "  Location: $($storageAccount.Location)"
Write-Output "  Storage URI: $storageUri"

# Verify storage account is accessible
Write-Output "Verifying storage account accessibility..."
try {
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -UseConnectedAccount
    $null = Get-AzStorageContainer -Context $storageContext -ErrorAction SilentlyContinue
    Write-Output "Storage account is accessible"
}
catch {
    Write-Warning "Could not verify storage account accessibility: $($_.Exception.Message)"
    Write-Warning "The VM update will proceed, but Boot Diagnostics may not work if the storage account is not accessible."
    Write-Warning "This may be due to Az module version compatibility issues."
}

Write-Output "Updating VM '$AzureVMName' to use new Boot Diagnostics URI: $storageUri"

# Enable/Set Boot Diagnostics
Write-Output "Configuring Boot Diagnostics settings..."
try {
    # Ensure DiagnosticsProfile exists
    if (-not $vm.DiagnosticsProfile) {
        $vm.DiagnosticsProfile = New-Object Microsoft.Azure.Management.Compute.Models.DiagnosticsProfile
    }
    
    # Ensure BootDiagnostics exists
    if (-not $vm.DiagnosticsProfile.BootDiagnostics) {
        $vm.DiagnosticsProfile.BootDiagnostics = New-Object Microsoft.Azure.Management.Compute.Models.BootDiagnostics
    }
    
    $vm.DiagnosticsProfile.BootDiagnostics.Enabled = $true
    $vm.DiagnosticsProfile.BootDiagnostics.StorageUri = $storageUri
    
    Write-Output "Applying VM configuration changes..."
    $result = Update-AzVM -ResourceGroupName $resourceGroup -VM $vm
    
    if ($result) {
        Write-Output "Boot Diagnostics storage account updated successfully for VM '$AzureVMName'."
        Write-Output "Storage URI: $storageUri"
    }
    else {
        Throw "VM update operation returned no result"
    }
}
catch {
    Throw "Failed to update VM Boot Diagnostics: $($_.Exception.Message)"
}
