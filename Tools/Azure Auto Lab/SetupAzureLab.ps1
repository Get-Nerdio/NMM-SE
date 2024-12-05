function New-AzureLabEnvironment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$LabConfig,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        # Check Azure connection and set correct tenant/subscription
        $currentContext = Get-AzContext
        if (-not $currentContext -or 
            $currentContext.Tenant.Id -ne $LabConfig.TenantId -or 
            $currentContext.Subscription.Id -ne $LabConfig.SubscriptionId) {
            Write-Output "Connecting to Azure with specified tenant and subscription..."
            Connect-AzAccount -TenantId $LabConfig.TenantId -Subscription $LabConfig.SubscriptionId -ErrorAction Stop
        }

        # Initialize collections using .NET Generic List for better performance
        $resourceList = [System.Collections.Generic.List[string]]::new()
        
        # Default tags
        $defaultTags = @{
            'Environment' = 'Lab'
            'CreatedBy'  = 'SetupAzureLabScript'
            'CreatedOn'  = (Get-Date).ToString('yyyy-MM-dd')
        }

        # Create credential object if username and password are provided in LabConfig
        if (-not $Credential -and $LabConfig.AdminUsername -and $LabConfig.AdminPassword) {
            $securePassword = ConvertTo-SecureString -String $LabConfig.AdminPassword -AsPlainText -Force
            $Credential = New-Object System.Management.Automation.PSCredential($LabConfig.AdminUsername, $securePassword)
        }
        elseif (-not $Credential) {
            # Use default credentials if none provided
            $defaultPassword = ConvertTo-SecureString -String "LabP@ssw0rd123!" -AsPlainText -Force
            $Credential = New-Object System.Management.Automation.PSCredential("labadmin", $defaultPassword)
        }
    }

    process {
        try {
            # Input validation
            if (-not $LabConfig.SubscriptionId) {
                throw "SubscriptionId is required"
            }

            # Set Azure context
            Write-Output "Setting Azure context to subscription: $($LabConfig.SubscriptionId)"
            Set-AzContext -SubscriptionId $LabConfig.SubscriptionId -ErrorAction Stop

            # Resource Group handling
            if (-not (Get-AzResourceGroup -Name $LabConfig.ResourceGroupName -Location $LabConfig.Location -ErrorAction SilentlyContinue)) {
                Write-Output "Creating Resource Group: $($LabConfig.ResourceGroupName)"
                New-AzResourceGroup -Name $LabConfig.ResourceGroupName -Location $LabConfig.Location -Tag $defaultTags -ErrorAction Stop
            }

            # Virtual Network handling
            $vnetName = $LabConfig.VNetName ?? "Lab-VNet"
            $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $LabConfig.ResourceGroupName -ErrorAction SilentlyContinue

            if (-not $vnet) {
                Write-Output "Creating Virtual Network: $vnetName"
                $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name ($LabConfig.SubnetName ?? "default") `
                    -AddressPrefix ($LabConfig.SubnetAddressPrefix ?? "10.0.1.0/24") -ErrorAction Stop

                $vnet = New-AzVirtualNetwork -Name $vnetName `
                    -ResourceGroupName $LabConfig.ResourceGroupName `
                    -Location $LabConfig.Location `
                    -AddressPrefix ($LabConfig.VNetAddressPrefix ?? "10.0.0.0/16") `
                    -Subnet $subnetConfig `
                    -Tag $defaultTags -ErrorAction Stop
            }

            # NSG Creation
            $nsgName = $LabConfig.NSGName ?? "Lab-NSG"
            $nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $LabConfig.ResourceGroupName -ErrorAction SilentlyContinue

            if (-not $nsg) {
                Write-Output "Creating Network Security Group: $nsgName"
                $nsgRule = New-AzNetworkSecurityRuleConfig -Name "AllowRDP" `
                    -Description "Allow RDP" `
                    -Access Allow `
                    -Protocol Tcp `
                    -Direction Inbound `
                    -Priority 100 `
                    -SourceAddressPrefix ($LabConfig.RDPSourceIP ?? '*') `
                    -SourcePortRange * `
                    -DestinationAddressPrefix * `
                    -DestinationPortRange 3389 -ErrorAction Stop

                $nsg = New-AzNetworkSecurityGroup -Name $nsgName `
                    -ResourceGroupName $LabConfig.ResourceGroupName `
                    -Location $LabConfig.Location `
                    -SecurityRules $nsgRule `
                    -Tag $defaultTags -ErrorAction Stop
            }

            # VM Configurations preparation
            $vmConfigs = @()
            
            # If VMs property exists, use it for multiple VM configurations
            if ($LabConfig.VMs) {
                # For advanced configuration, ensure unique names
                $baseNames = @{}
                foreach ($vm in $LabConfig.VMs) {
                    $baseName = $vm.Name -replace '\d+$', ''
                    if (-not $baseNames.ContainsKey($baseName)) {
                        $baseNames[$baseName] = $true
                        $vmConfigs += $vm
                    } else {
                        Write-Warning "Duplicate base name found: $baseName. Adjusting configuration for uniqueness."
                        $vm = $vm.Clone()
                        $vm.Name = $baseName
                        $vmConfigs += $vm
                    }
                }
            }
            # Otherwise, create VMs based on count (backward compatibility)
            else {
                $vmCount = [int]($LabConfig.VMCount ?? 1)
                1..$vmCount | ForEach-Object {
                    $vmConfigs += @{
                        Name = "$($LabConfig.VMPrefix ?? 'LabVM')"  # Base name without number
                        Size = $LabConfig.VMSize ?? "Standard_B2s"
                        Image = @{
                            Publisher = "MicrosoftWindowsServer"
                            Offer     = "WindowsServer"
                            Sku       = "2022-datacenter-g2"
                            Version   = "latest"
                        }
                        OsDiskSku = $LabConfig.OsDiskSku ?? "StandardSSD_LRS"
                    }
                }
            }

            # Create VMs in parallel
            $vmConfigs | ForEach-Object -ThrottleLimit 5 -Parallel {
                try {
                    $baseVMName = $_.Name -replace '\d+$', ''  # Remove any trailing numbers
                    
                    # Find the next available VM number
                    $existingVMs = Get-AzVM -ResourceGroupName $using:LabConfig.ResourceGroupName | 
                                  Where-Object { $_.Name -match "^$baseVMName\d+$" } |
                                  ForEach-Object { 
                                      if ($_.Name -match "\d+$") { [int]$Matches[0] } 
                                  } |
                                  Sort-Object
                    
                    $nextNumber = 1
                    if ($existingVMs) {
                        # Find the first gap in the sequence, or use the next number after the highest
                        for ($i = 1; $i -le ($existingVMs[-1] + 1); $i++) {
                            if ($i -notin $existingVMs) {
                                $nextNumber = $i
                                break
                            }
                        }
                    }
                    
                    $vmName = "$baseVMName$nextNumber"
                    Write-Output "Creating VM with name: $vmName"
                    
                    $vmSize = $_.Size
                    $image = $_.Image
                    $osDiskSku = $_.OsDiskSku ?? $using:LabConfig.OsDiskSku ?? "StandardSSD_LRS"

                    # Create NIC
                    $nicName = "$vmName-NIC"
                    Write-Output "Creating NIC: $nicName"
                    
                    # Check for existing NIC
                    $existingNic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $using:LabConfig.ResourceGroupName -ErrorAction SilentlyContinue
                    if ($existingNic) {
                        # Check if NIC is attached to a VM
                        if ($null -eq $existingNic.VirtualMachine) {
                            Write-Output "Found orphaned NIC '$nicName'. Removing it..."
                            Remove-AzNetworkInterface -Name $nicName -ResourceGroupName $using:LabConfig.ResourceGroupName -Force -ErrorAction Stop
                        } else {
                            Write-Error "NIC '$nicName' is attached to an existing VM. Cannot proceed."
                            throw "NIC in use"
                        }
                    }

                    # Create new NIC
                    $nic = New-AzNetworkInterface -Name $nicName `
                        -ResourceGroupName $using:LabConfig.ResourceGroupName `
                        -Location $using:LabConfig.Location `
                        -SubnetId ($using:vnet.Subnets[0].Id) `
                        -NetworkSecurityGroupId $using:nsg.Id -Force -ErrorAction Stop

                    # VM Configuration
                    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize -ErrorAction Stop

                    # OS Configuration
                    $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig `
                        -Windows `
                        -ComputerName $vmName `
                        -Credential $using:Credential -ErrorAction Stop

                    # Image Configuration
                    $vmConfig = Set-AzVMSourceImage -VM $vmConfig `
                        -PublisherName ($image.Publisher ?? "MicrosoftWindowsServer") `
                        -Offer ($image.Offer ?? "WindowsServer") `
                        -Skus ($image.Sku ?? "2022-datacenter-g2") `
                        -Version ($image.Version ?? "latest") -ErrorAction Stop

                    # Configure OS disk
                    $vmConfig = Set-AzVMOSDisk -VM $vmConfig `
                        -CreateOption FromImage `
                        -Windows `
                        -StorageAccountType $osDiskSku -ErrorAction Stop

                    # Attach NIC
                    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id -ErrorAction Stop

                    # Disable boot diagnostics
                    $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable -ErrorAction Stop

                    # Create VM
                    Write-Output "Creating VM: $vmName"
                    $vm = New-AzVM -ResourceGroupName $using:LabConfig.ResourceGroupName `
                        -Location $using:LabConfig.Location `
                        -VM $vmConfig `
                        -Tag $using:defaultTags -ErrorAction Stop

                    # Get local timezone information
                    $localTimeZone = Get-TimeZone
                    $timeZoneId = switch ($localTimeZone.BaseUtcOffset.TotalHours) {
                        -12 { "Dateline Standard Time" }
                        -11 { "UTC-11" }
                        -10 { "Hawaiian Standard Time" }
                        -9.5 { "Marquesas Standard Time" }
                        -9 { "Alaskan Standard Time" }
                        -8 { "Pacific Standard Time" }
                        -7 { "Mountain Standard Time" }
                        -6 { "Central Standard Time" }
                        -5 { "Eastern Standard Time" }
                        -4 { "Atlantic Standard Time" }
                        -3.5 { "Newfoundland Standard Time" }
                        -3 { "E. South America Standard Time" }
                        -2 { "UTC-02" }
                        -1 { "Azores Standard Time" }
                        0 { "UTC" }
                        1 { "W. Europe Standard Time" }
                        2 { "E. Europe Standard Time" }
                        3 { "Russian Standard Time" }
                        3.5 { "Iran Standard Time" }
                        4 { "Arabian Standard Time" }
                        4.5 { "Afghanistan Standard Time" }
                        5 { "West Asia Standard Time" }
                        5.5 { "India Standard Time" }
                        5.75 { "Nepal Standard Time" }
                        6 { "Central Asia Standard Time" }
                        6.5 { "Myanmar Standard Time" }
                        7 { "SE Asia Standard Time" }
                        8 { "China Standard Time" }
                        8.75 { "Aus Central W. Standard Time" }
                        9 { "Tokyo Standard Time" }
                        9.5 { "Cen. Australia Standard Time" }
                        10 { "AUS Eastern Standard Time" }
                        10.5 { "Lord Howe Standard Time" }
                        11 { "Central Pacific Standard Time" }
                        12 { "UTC+12" }
                        12.75 { "Chatham Islands Standard Time" }
                        13 { "UTC+13" }
                        14 { "Line Islands Standard Time" }
                        default { "UTC" }
                    }

                    # Configure auto-shutdown
                    $vmResourceId = "/subscriptions/$($using:LabConfig.SubscriptionId)/resourceGroups/$($using:LabConfig.ResourceGroupName)/providers/Microsoft.Compute/virtualMachines/$vmName"
                    $scheduleResourceId = "/subscriptions/$($using:LabConfig.SubscriptionId)/resourceGroups/$($using:LabConfig.ResourceGroupName)/providers/microsoft.devtestlab/schedules/shutdown-computevm-$vmName"
                    
                    # Set shutdown time to 7:00 PM in local time
                    $shutdownTime = "1900"  # Default to 7:00 PM
                    
                    $shutdownProperties = @{
                        status = "Enabled"
                        taskType = "ComputeVmShutdownTask"
                        dailyRecurrence = @{time = $shutdownTime}
                        timeZoneId = $timeZoneId
                        targetResourceId = $vmResourceId
                    }

                    # Add notification settings if email is configured
                    if ($using:LabConfig.ShutdownNotificationEmail) {
                        $shutdownProperties['notificationSettings'] = @{
                            status = "Enabled"
                            timeInMinutes = 30
                            emailRecipient = $using:LabConfig.ShutdownNotificationEmail
                        }
                    }

                    # Create the auto-shutdown schedule
                    Write-Output "Creating auto-shutdown schedule for VM: $vmName"
                    New-AzResource -ResourceId $scheduleResourceId `
                        -Location $using:LabConfig.Location `
                        -Properties $shutdownProperties `
                        -Force -ErrorAction Stop

                } catch {
                    Write-Error "Error creating VM $vmName or its resources: $_"
                    throw
                }
            }
        }
        catch {
            Write-Error "Error in lab environment setup: $_"
            throw
        }
    }

    end {
        Write-Output "Lab environment setup completed successfully"
    }
}

function Remove-AzureLabEnvironment {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    begin {
        try {
            # Check Azure connection and set correct tenant/subscription
            $currentContext = Get-AzContext
            if (-not $currentContext -or 
                ($TenantId -and $currentContext.Tenant.Id -ne $TenantId) -or 
                $currentContext.Subscription.Id -ne $SubscriptionId) {
                Write-Output "Connecting to Azure with specified subscription..."
                $params = @{
                    Subscription = $SubscriptionId
                    ErrorAction = 'Stop'
                }
                if ($TenantId) {
                    $params['TenantId'] = $TenantId
                }
                Connect-AzAccount @params
            }
        }
        catch {
            Write-Error "Error setting Azure context: $_"
            throw
        }
    }

    process {
        try {
            # Check if resource group exists
            $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
            if (-not $resourceGroup) {
                Write-Warning "Resource group '$ResourceGroupName' does not exist."
                return
            }

            # Get all resources in the resource group
            Write-Output "Getting all resources in resource group '$ResourceGroupName'..."
            $resources = Get-AzResource -ResourceGroupName $ResourceGroupName

            # Display resources that will be deleted
            if ($resources) {
                Write-Output "`nThe following resources will be deleted:"
                $resources | ForEach-Object {
                    Write-Output "- $($_.Name) ($($_.ResourceType))"
                }
            }
            else {
                Write-Output "No resources found in resource group '$ResourceGroupName'."
            }

            # Confirm deletion
            if ($PSCmdlet.ShouldProcess($ResourceGroupName, "Delete resource group and all its resources")) {
                # Remove resource group with force and no confirmation
                Write-Output "`nStarting deletion of resource group '$ResourceGroupName'..."
                $job = Remove-AzResourceGroup -Name $ResourceGroupName -Force -AsJob

                # Show progress while deleting
                $lastState = ''
                while (-not $job.IsCompleted) {
                    # Check if resource group still exists
                    $rgExists = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
                    if (-not $rgExists) {
                        Write-Output "Resource group '$ResourceGroupName' has been successfully deleted."
                        break
                    }

                    if ($job.State -ne $lastState) {
                        Write-Output "Deletion in progress... Current state: $($job.State)"
                        $lastState = $job.State
                    }
                    Start-Sleep -Seconds 5
                }

                # If we broke out of the loop due to RG being gone, stop the job
                if (-not $rgExists -and -not $job.IsCompleted) {
                    $job | Stop-Job
                    $job | Remove-Job
                }
                # Otherwise check final state
                elseif ($job.State -eq 'Failed') {
                    Write-Error "Failed to delete resource group: $($job.Error)"
                    throw $job.Error
                }
            }
        }
        catch {
            Write-Error "Error removing lab environment: $_"
            throw
        }
    }
}

# Example usage:

#Set Params
$SubscriptionId = "00000000-0000-0000-0000-000000000000"
$TenantId = "00000000-0000-0000-0000-000000000000"
$ResourceGroupName = "ResourceGroupName"
$Location = "northeurope"
$AdminUsername = "labadmin"
$AdminPassword = "Lab2024@Nerdio!"

# Example 1: Simple configuration with plaintext credentials and email notification
$labConfig = [PSCustomObject]@{
    SubscriptionId     = $SubscriptionId
    TenantId           = $TenantId
    ResourceGroupName  = $ResourceGroupName
    Location          = $Location
    VMCount           = 1
    VMPrefix          = "DevVM"
    VMSize            = "Standard_B2ms"
    AdminUsername     = $AdminUsername           # Optional: Default is "labadmin"
    AdminPassword     = $AdminPassword    # Optional: Default is "LabP@ssw0rd123!"
    VNetName          = "Lab-VNet"
    SubnetName        = "default"
    NSGName           = "Lab-NSG"
    RDPSourceIP       = (Invoke-RestMethod -Uri "https://icanhazip.com").Trim()
    EnableBastion     = $false
    VNetAddressPrefix = "10.0.0.0/16"
    SubnetAddressPrefix = "10.0.1.0/24"
    OsDiskSku         = "StandardSSD_LRS"    # Optional: Default is "StandardSSD_LRS"
    ShutdownNotificationEmail = "username@company.com"  # Optional: Email for shutdown notifications
}

# Example 2: Advanced configuration with different VM specifications
$labConfig = [PSCustomObject]@{
    SubscriptionId     = $SubscriptionId
    TenantId           = $TenantId 
    ResourceGroupName  = $ResourceGroupName
    Location          = $Location
    AdminUsername     = $AdminUsername           # Optional: Default is "labadmin"
    AdminPassword     = $AdminPassword    # Optional: Default is "LabP@ssw0rd123!"
    VNetName          = "Lab-VNet"
    SubnetName        = "default"
    NSGName           = "Lab-NSG"
    RDPSourceIP       = (Invoke-RestMethod -Uri "https://icanhazip.com").Trim()
    EnableBastion     = $false
    VNetAddressPrefix = "10.0.0.0/16"
    SubnetAddressPrefix = "10.0.1.0/24"
    OsDiskSku         = "Premium_LRS"        # Optional: Default is "StandardSSD_LRS"
    ShutdownNotificationEmail = "username@company.com"  # Optional: Email for shutdown notifications
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

# Run without explicit credentials (uses credentials from LabConfig or defaults)
$labConfig | New-AzureLabEnvironment -Verbose

# Or run with explicit credentials if needed
$credential = Get-Credential -Message "Enter credentials for lab VMs"
$labConfig | New-AzureLabEnvironment -Credential $credential

################################################################################

# Remove the lab environment
$SubscriptionId = "00000000-0000-0000-0000-000000000000"
$ResourceGroupName = "ResourceGroupName"

# To see what would be deleted without actually deleting:
Remove-AzureLabEnvironment -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WhatIf

# To delete with confirmation:
Remove-AzureLabEnvironment -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName

# To delete without confirmation:
Remove-AzureLabEnvironment -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Confirm:$false


# Available Azure VM Offers and Image SKUs
# =======================================
#
# Windows Server Images:
# ---------------------
# Publisher: MicrosoftWindowsServer
# Offer: WindowsServer
# Common SKUs:
# - 2022-datacenter-g2                     : Windows Server 2022 Datacenter (Gen 2)
# - 2022-datacenter-azure-edition-g2       : Windows Server 2022 Azure Edition (Gen 2)
# - 2022-datacenter-core-g2                : Windows Server 2022 Datacenter Core (Gen 2)
# - 2022-datacenter-core-azure-edition-g2  : Windows Server 2022 Datacenter Core Azure Edition (Gen 2)
#
# Windows Client Images:
# --------------------
# Publisher: MicrosoftWindowsDesktop
# Offer: Windows-10
# Common SKUs:
# - win10-22h2-pro-g2      : Windows 10 Pro 22H2 (Gen 2)
# - win10-22h2-ent-g2      : Windows 10 Enterprise 22H2 (Gen 2)
# - win10-21h2-pro-g2      : Windows 10 Pro 21H2 (Gen 2)
# - win10-21h2-ent-g2      : Windows 10 Enterprise 21H2 (Gen 2)
#
# Publisher: MicrosoftWindowsDesktop
# Offer: Windows-11
# Common SKUs:
# - win11-24h2-pro      : Windows 11 Pro 24H2 (Gen 2)
# - win11-24h2-ent      : Windows 11 Enterprise 24H2 (Gen 2)
# - win11-23h2-pro      : Windows 11 Pro 23H2 (Gen 2)
# - win11-23h2-ent      : Windows 11 Enterprise 23H2 (Gen 2)
#
# Note: This is not an exhaustive list. Use Get-AzVMImageSku cmdlet to get all available SKUs for a specific publisher and offer:
# Example: Get-AzVMImageSku -Location "eastus2" -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer"
#
# Availble Disk SKUs:
# - StandardSSD_LRS
# - Premium_LRS
# - Standard_LRS
#
# Most Common VM Sizes:
# - Standard_B2s
# - Standard_B2ms
# - Standard_D2as_v4
# - Standard_D2as_v5
# - Standard_D2s_v3
# - Standard_D2s_v4
# - Standard_D2s_v5
# - Standard_E2as_v4
# - Standard_E2as_v5
# - Standard_E2s_v4
# - Standard_E2s_v5