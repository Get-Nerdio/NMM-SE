![Nerdio Logo](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# Azure Auto Lab Setup Script

This PowerShell script automates the creation and removal of Azure lab environments. It supports both simple and advanced configurations for creating multiple VMs with different specifications.

## Prerequisites

- Azure PowerShell module installed
- Azure subscription
- Appropriate permissions to create resources in Azure

## Features

- Automated creation of complete lab environments
- Support for multiple VMs with different configurations
- Automatic network security group setup with RDP access
- Configurable auto-shutdown with email notifications
- Parallel VM creation for faster deployment
- Automatic timezone detection and configuration
- Clean removal of lab environments

## Basic Usage

### 1. Simple Configuration

```powershell
# Set basic parameters
$labConfig = [PSCustomObject]@{
    SubscriptionId     = "SubscriptionId"
    ResourceGroupName  = "ResourceGroupName"
    Location          = "Location"
    VMCount           = 1
    VMPrefix          = "DevVM"
    VMSize            = "Standard_B2ms"
    AdminUsername     = "labadmin"            # Optional: Default is "labadmin"
    AdminPassword     = "Lab2024@Nerdio!"     # Optional: Default is "LabP@ssw0rd123!"
    VNetName          = "Lab-VNet"
    SubnetName        = "default"
    NSGName           = "Lab-NSG"
    RDPSourceIP       = (Invoke-RestMethod -Uri "https://icanhazip.com").Trim()
    EnableBastion     = $false
    VNetAddressPrefix = "10.0.0.0/16"
    SubnetAddressPrefix = "10.0.1.0/24"
    OsDiskSku         = "StandardSSD_LRS"    # Optional: Default is "StandardSSD_LRS"
    ShutdownNotificationEmail = "jscholte@getnerdio.com"  # Optional: Email for shutdown notifications
}

# Create the lab environment
$labConfig | New-AzureLabEnvironment
```

### 2. Advanced Configuration with Multiple VMs

```powershell
$labConfig = [PSCustomObject]@{
    SubscriptionId     = "SubscriptionId"
    ResourceGroupName  = "ResourceGroupName"
    Location          = "Location"
    AdminUsername     = "labadmin"           # Optional: Default is "labadmin"
    AdminPassword     = "Lab2024@Nerdio!"    # Optional: Default is "LabP@ssw0rd123!"
    VNetName          = "Lab-VNet"
    SubnetName        = "default"
    NSGName           = "Lab-NSG"
    RDPSourceIP       = (Invoke-RestMethod -Uri "https://icanhazip.com").Trim()
    EnableBastion     = $false
    VNetAddressPrefix = "10.0.0.0/16"
    SubnetAddressPrefix = "10.0.1.0/24"
    OsDiskSku         = "Premium_LRS"        # Optional: Default is "StandardSSD_LRS"
    ShutdownNotificationEmail = "jscholte@getnerdio.com"  # Optional: Email for shutdown notifications
    VMs = @(
        @{
            Name = "DevVM1-Windows11"
            Size = "Standard_E2as_v4"
            OsDiskSku = "StandardSSD_LRS"    # Override default disk SKU for this VM
            Image = @{
                Publisher = "MicrosoftWindowsDesktop"
                Offer     = "Windows-11"
                Sku       = "win11-24h2-ent"  # Using Generation 2 image
                Version   = "latest"
            }
        },
        @{
            Name = "DevVM2-Server"
            Size = "Standard_D2as_v4"
            OsDiskSku = "StandardSSD_LRS"        # Override default disk SKU for this VM
            Image = @{
                Publisher = "MicrosoftWindowsServer"
                Offer     = "WindowsServer"
                Sku       = "2022-datacenter-g2"  # Using Generation 2 image
                Version   = "latest"
            }
        }
    )
}

# Create with explicit credentials
$credential = Get-Credential -Message "Enter credentials for lab VMs"
$labConfig | New-AzureLabEnvironment -Credential $credential
```

## Configuration Options

### Basic Parameters
- `SubscriptionId`: Your Azure subscription ID
- `ResourceGroupName`: Name for the resource group
- `Location`: Azure region (e.g., "northeurope")
- `VMCount`: Number of VMs (for simple configuration)
- `VMPrefix`: Base name for VMs
- `VMSize`: Azure VM size
- `AdminUsername`: VM administrator username (default: "labadmin")
- `AdminPassword`: VM administrator password
- `ShutdownNotificationEmail`: Email for auto-shutdown notifications

### Network Parameters
- `VNetName`: Virtual network name (default: "Lab-VNet")
- `SubnetName`: Subnet name (default: "default")
- `NSGName`: Network security group name (default: "Lab-NSG")
- `RDPSourceIP`: IP address for RDP access
- `VNetAddressPrefix`: VNet address space (default: "10.0.0.0/16")
- `SubnetAddressPrefix`: Subnet address space (default: "10.0.1.0/24")

### Storage Parameters
- `OsDiskSku`: OS disk type (StandardSSD_LRS, Premium_LRS, Standard_LRS)

## Available VM Images

### Windows Server
```powershell
Publisher: MicrosoftWindowsServer
Offer: WindowsServer
SKUs:
- 2022-datacenter-g2
- 2022-datacenter-azure-edition-g2
- 2022-datacenter-core-g2
```

### Windows 11
```powershell
Publisher: MicrosoftWindowsDesktop
Offer: Windows-11
SKUs:
- win11-24h2-pro
- win11-24h2-ent
- win11-23h2-pro
- win11-23h2-ent
```

### Windows 10
```powershell
Publisher: MicrosoftWindowsDesktop
Offer: Windows-10
SKUs:
- win10-22h2-pro-g2
- win10-22h2-ent-g2
```

## Common VM Sizes
- Standard_B2s (2 vCPU, 4 GB RAM)
- Standard_B2ms (2 vCPU, 8 GB RAM)
- Standard_D2as_v4 (2 vCPU, 8 GB RAM)
- Standard_E2as_v4 (2 vCPU, 16 GB RAM)

## Cleaning Up

To remove the lab environment:

```powershell
# Preview what will be deleted
Remove-AzureLabEnvironment -SubscriptionId "your-subscription-id" -ResourceGroupName "YourLabRG" -WhatIf

# Remove with confirmation
Remove-AzureLabEnvironment -SubscriptionId "your-subscription-id" -ResourceGroupName "YourLabRG"

# Remove without confirmation
Remove-AzureLabEnvironment -SubscriptionId "your-subscription-id" -ResourceGroupName "YourLabRG" -Confirm:$false
```

## Notes
- All VMs are configured with auto-shutdown at 7:00 PM local time
- RDP access is automatically configured
- Network security group is created with basic RDP rules
- The script automatically handles unique naming for multiple VMs
