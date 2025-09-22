#description: (PREVIEW) Creates a temp VM to run chkdsk on all FSLogix profile disks
#tags: Nerdio, Preview

# NOTE: This script uses SecureVars as the primary configuration method.
# Parameters can override SecureVars values, but SecureVars must be configured first.
# Required SecureVars:
# - FslTempVmVnet: VNet name for temp VM
# - FslTempVmSubnet: Subnet name for temp VM  
# - FslResourceGroup: Resource group for temp VM
# - FslRegion: Azure region
# - FslStorageUser: Storage account user
# - FslStorageKey: Storage account key
# - FslFileShare: UNC path to FSLogix file share

<# Variables:
{
  "VNetName": {
    "Description": "VNet in which to create the temp VM. Must be able to access the fslogix fileshare.",
    "IsRequired": false
  },
  "SubnetName": {
    "Description": "Subnet in which to create the temp VM.",
    "IsRequired": false
  },
  "FileSharePath": {
    "Description": "UNC path e.g. \\\\storageaccount.file.core.windows.net\\premiumfslogix01",
    "IsRequired": false
  },
  "TempVmSize": {
    "Description": "Size of the temporary VM from which the shrink script will be run.",
    "IsRequired": false,
    "DefaultValue": "Standard_D16s_v4"
  },
  "TempVmResourceGroup": {
    "Description": "Resource group in which to create the temp vm. If not supplied, resource group of vnet will be used.",
    "IsRequired": false
  },
  "AdditionalShrinkDiskParameters": {
    "Description": "parameters to send to the FSLogix-ShrinkDisk.ps1 script. E.g: -DeleteOlderThanDays 90 -IgnoreLessThanGB 5",
    "IsRequired": false
  },
  "FslStorageUser": {
    "Description": "Storage account key user (storage account name), or AD user with access to fileshare",
    "IsRequired": false
  },
  "FslStorageKey": {
    "Description": "Storage account key, or AD password",
    "IsRequired": false
  }

}
#>

$ErrorActionPreference = 'Stop'

##### Variables from SecureVars with Parameter Override #####

# Debug: Show what parameters were received
Write-Output "Received parameters:"
Write-Output "VNetName: $VNetName"
Write-Output "SubnetName: $SubnetName"
Write-Output "FileSharePath: $FileSharePath"
Write-Output "TempVmSize: $TempVmSize"
Write-Output "TempVmResourceGroup: $TempVmResourceGroup"
Write-Output "FslStorageUser: $FslStorageUser"
Write-Output "FslStorageKey: $FslStorageKey"
Write-Output "FslRegion: $FslRegion"
Write-Output "FslResourceGroup: $FslResourceGroup"

# Start with SecureVars as base values
$AzureVMName = "fslchkdisk-tempvm"
$azureVmSize = 'Standard_D4s_v3'
$azureVnetName = $SecureVars.FslTempVmVnet
$azureVnetSubnetName = $SecureVars.FslTempVmSubnet
$AzureResourceGroup = $SecureVars.FslResourceGroup
$AzureRegionName = $SecureVars.FslRegion

$StorageAccountUser = $SecureVars.FslStorageUser
$StorageAccountKey = $SecureVars.FslStorageKey
$FSLogixFileShare = $SecureVars.FslFileShare

# Override with parameters if provided (but check for valid values)
if ($VNetName -and $VNetName -ne "Standard_D4s_v3") { $azureVnetName = $VNetName }
if ($SubnetName) { $azureVnetSubnetName = $SubnetName }
if ($FileSharePath) { $FSLogixFileShare = $FileSharePath }
if ($TempVmSize -and $TempVmSize -notlike "*BADLdobezV*") { $azureVmSize = $TempVmSize }
if ($TempVmResourceGroup) { $AzureResourceGroup = $TempVmResourceGroup }
if ($FslStorageUser) { $StorageAccountUser = $FslStorageUser }
if ($FslStorageKey -and $FslStorageKey -notlike "*BADLdobezV*") { $StorageAccountKey = $FslStorageKey }
if ($FslRegion) { $AzureRegionName = $FslRegion }
if ($FslResourceGroup) { $AzureResourceGroup = $FslResourceGroup }

##### Optional/Derived Variables #####

$vmAdminUsername = "LocalAdminUser"
$Guid = (New-Guid).Guid
$vmAdminPassword = ConvertTo-SecureString "$Guid" -AsPlainText -Force
$vmComputerName = "fslchkdisk-tmp"
$azureVmOsDiskName = "$AzureVMName-os"
$azureNicName = "$azureVMName-NIC"
$azurePublicIpName = "$azureVMName-IP"
$azureVmPublisherName = "MicrosoftWindowsServer"
$azureVmOffer = "WindowsServer"
$azureVmSkus = "2019-datacenter-core-g2"

##### Validation #####

Write-Output "Validating required parameters..."

if ([string]::IsNullOrEmpty($azureVnetName)) {
    Write-Output "ERROR: Missing vnet name. Check SecureVars.FslTempVmVnet or VNetName parameter."
    throw "Missing vnet name."
}
if ([string]::IsNullOrEmpty($azureVnetSubnetName)) {
    Write-Output "ERROR: Missing subnet name. Check SecureVars.FslTempVmSubnet or SubnetName parameter."
    throw "Missing subnet name."
}
if ([string]::IsNullOrEmpty($FSLogixFileShare)) {
    Write-Output "ERROR: Missing FSLogix FileShare path. Check SecureVars.FslFileShare or FileSharePath parameter."
    throw "Missing FSLogix FileShare path."
}
if ([string]::IsNullOrEmpty($StorageAccountUser) -or [string]::IsNullOrEmpty($StorageAccountKey)) {
    Write-Output "ERROR: Missing storage credentials. Check SecureVars.FslStorageUser/FslStorageKey or FslStorageUser/FslStorageKey parameters."
    throw "Missing credentials for storage access."
}

Write-Output "All required parameters validated successfully."

##### Main Execution #####

try {
    Write-Output "Starting FSLogix CheckDisk process..."
    Write-Output "Final resolved parameters:"
    Write-Output "VNet: $azureVnetName"
    Write-Output "Subnet: $azureVnetSubnetName" 
    Write-Output "FileShare: $FSLogixFileShare"
    Write-Output "VM Size: $azureVmSize"
    Write-Output "Resource Group: $AzureResourceGroup"
    Write-Output "Region: $AzureRegionName"

    ##### Create VM #####

    Write-Output "Getting vnet details..."
$Vnet = Get-AzVirtualNetwork -Name $azureVnetName
if (!$Vnet) { throw "Cannot find vNet: $azureVnetName" }

if ([string]::IsNullOrEmpty($AzureResourceGroup)) {
    $AzureResourceGroup = $Vnet.ResourceGroupName
}
$AzureRegionName = $Vnet.Location
$azureVnetSubnet = $Vnet.Subnets | Where-Object { $_.Name -eq $azureVnetSubnetName }

Write-Output "Creating temp VM resources..."

# Check for existing resources and clean them up if they exist
Write-Output "Checking for existing resources..."

if (Get-AzPublicIpAddress -Name $azurePublicIpName -ResourceGroupName $AzureResourceGroup -ErrorAction SilentlyContinue) {
    Write-Output "Public IP already exists, removing..."
    Remove-AzPublicIpAddress -Name $azurePublicIpName -ResourceGroupName $AzureResourceGroup -Force -ErrorAction SilentlyContinue
}

if (Get-AzNetworkInterface -Name $azureNicName -ResourceGroupName $AzureResourceGroup -ErrorAction SilentlyContinue) {
    Write-Output "NIC already exists, removing..."
    Remove-AzNetworkInterface -Name $azureNicName -ResourceGroupName $AzureResourceGroup -Force -ErrorAction SilentlyContinue
}

if (Get-AzVM -Name $AzureVMName -ResourceGroupName $AzureResourceGroup -ErrorAction SilentlyContinue) {
    Write-Output "VM already exists, removing..."
    Remove-AzVM -Name $AzureVMName -ResourceGroupName $AzureResourceGroup -Force -ErrorAction SilentlyContinue
}

Write-Output "Creating new resources..."
$azurePublicIp = New-AzPublicIpAddress -Name $azurePublicIpName -ResourceGroupName $AzureResourceGroup -Location $AzureRegionName -AllocationMethod Static -Sku Standard
$azureNIC = New-AzNetworkInterface -Name $azureNicName -ResourceGroupName $AzureResourceGroup -Location $AzureRegionName -SubnetId $azureVnetSubnet.Id -PublicIpAddressId $azurePublicIp.Id
$vmCredential = New-Object PSCredential ($vmAdminUsername, $vmAdminPassword)

$VirtualMachine = New-AzVMConfig -VMName $AzureVMName -VMSize $azureVmSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $vmComputerName -Credential $vmCredential -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $azureNIC.Id
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName $azureVmPublisherName -Offer $azureVmOffer -Skus $azureVmSkus -Version "latest"
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Disable
$VirtualMachine = Set-AzVMOSDisk -VM $VirtualMachine -StorageAccountType "Premium_LRS" -Caching ReadWrite -Name $azureVmOsDiskName -CreateOption FromImage

Write-Output "Creating VM..."
$VM = New-AzVM -ResourceGroupName $AzureResourceGroup -Location $AzureRegionName -VM $VirtualMachine
$VM

##### Build ScriptBlock for VM #####
$ScriptBlock = @"
try {
    # Map the FSLogix file share
    Write-Output "Mapping FSLogix file share: $FSLogixFileShare"
    net use "$FSLogixFileShare" /user:$StorageAccountUser $StorageAccountKey
    
    # Get all VHD/VHDX files
    Write-Output "Searching for VHD/VHDX files..."
    `$files = Get-ChildItem "$FSLogixFileShare" -Recurse -Include *.vhd, *.vhdx
    Write-Output "Found `$(`$files.Count) VHD/VHDX files to process"

    foreach (`$file in `$files) {
        try {
            Write-Output "Processing: `$(`$file.FullName)"

            # Check if VHD is already mounted using diskpart
            `$checkScriptPath = "C:\Windows\Temp\check_vdisk.txt"
            ("select vdisk file=`"" + `$file.FullName + "`"") | Out-File -FilePath `$checkScriptPath -Encoding ASCII
            "detail vdisk" | Out-File -FilePath `$checkScriptPath -Append -Encoding ASCII
            
            `$alreadyMounted = `$false
            try {
                `$diskpartOutput = diskpart /s `$checkScriptPath 2>&1
                if (`$diskpartOutput -match "Disk.*Online") {
                    `$alreadyMounted = `$true
                }
                Remove-Item `$checkScriptPath -ErrorAction SilentlyContinue
            } catch {
                # Continue with mounting
                Remove-Item `$checkScriptPath -ErrorAction SilentlyContinue
            }
            
            if (`$alreadyMounted) {
                Write-Output "VHD already mounted, skipping: `$(`$file.FullName)"
                continue
            }

            # Mount the VHD using diskpart
            Write-Output "Mounting VHD: `$(`$file.FullName)"
            `$mountScriptPath = "C:\Windows\Temp\mount_vdisk.txt"
            `$filePath = `$file.FullName
            `$mountCommand1 = 'select vdisk file="' + `$filePath + '"'
            `$mountCommand2 = "attach vdisk"
            Write-Output "Creating diskpart script with commands:"
            Write-Output "Command 1: `$mountCommand1"
            Write-Output "Command 2: `$mountCommand2"
            `$mountCommand1 | Out-File -FilePath `$mountScriptPath -Encoding ASCII
            `$mountCommand2 | Out-File -FilePath `$mountScriptPath -Append -Encoding ASCII
            
            # Debug: Show script contents
            Write-Output "Script file contents:"
            Get-Content `$mountScriptPath | ForEach-Object { Write-Output "  `$_" }
            
            try {
                `$mountResult = diskpart /s `$mountScriptPath 2>&1
                Write-Output "Diskpart output: `$mountResult"
                if (`$LASTEXITCODE -ne 0) {
                    throw "Failed to mount VHD: `$mountResult"
                }
                Write-Output "VHD mounted successfully"
                Remove-Item `$mountScriptPath -ErrorAction SilentlyContinue
            } catch {
                Write-Output "Error mounting VHD: `$(`$_.Exception.Message)"
                Remove-Item `$mountScriptPath -ErrorAction SilentlyContinue
                continue
            }

            # Wait longer for the disk to be recognized and drive letter assigned
            Write-Output "Waiting for disk to be recognized and drive letter assigned..."
            Start-Sleep -Seconds 30
            
            # Try multiple times to find the mounted disk
            `$mountedDisk = `$null
            `$maxAttempts = 5
            for (`$attempt = 1; `$attempt -le `$maxAttempts; `$attempt++) {
                Write-Output "Attempt `$attempt to find mounted disk..."
                
                # Try multiple methods to find the mounted disk
                `$mountedDisk = Get-Disk | Where-Object { `$_.Location -eq `$file.FullName }
                
                if (-not `$mountedDisk) {
                    # Try finding by checking if the disk was recently added
                    `$allDisks = Get-Disk
                    Write-Output "Total disks found: `$(`$allDisks.Count)"
                    foreach (`$disk in `$allDisks) {
                        Write-Output "Disk `$(`$disk.Number): Location=`$(`$disk.Location), BusType=`$(`$disk.BusType), Size=`$(`$disk.Size)"
                    }
                    
                    # Look for disks that might be our VHD (check by size or other characteristics)
                    `$mountedDisk = `$allDisks | Where-Object { 
                        `$_.Location -like "*`$(`$file.Name)*" -or 
                        (`$_.BusType -eq "FileBackedVirtual" -and `$_.Size -gt 0)
                    } | Select-Object -First 1
                }
                
                if (`$mountedDisk) {
                    Write-Output "Found mounted disk: `$(`$mountedDisk.Number) - Location: `$(`$mountedDisk.Location)"
                    break
                }
                Start-Sleep -Seconds 10
            }
            
            if (`$mountedDisk) {
                Write-Output "Found mounted disk: `$(`$mountedDisk.Number)"
                
                # Wait a bit more for the disk to be fully initialized
                Start-Sleep -Seconds 5
                
                # Get all partitions on the mounted disk
                `$partitions = Get-Partition -DiskNumber `$mountedDisk.Number -ErrorAction SilentlyContinue
                Write-Output "Found `$(`$partitions.Count) partitions on disk `$(`$mountedDisk.Number)"
                
                `$vol = `$null
                if (`$partitions) {
                    foreach (`$partition in `$partitions) {
                        Write-Output "Checking partition `$(`$partition.PartitionNumber) - Type: `$(`$partition.Type), Size: `$(`$partition.Size)"
                        if (`$partition.Type -eq "Basic" -and `$partition.Size -gt 0) {
                            `$vol = Get-Volume -Partition `$partition -ErrorAction SilentlyContinue
                            if (`$vol) {
                                Write-Output "Volume found on partition `$(`$partition.PartitionNumber): `$(`$vol.DriveLetter)"
                                break
                            }
                        }
                    }
                }
                
                if (-not `$vol) {
                    Write-Output "No volume found for mounted disk `$(`$mountedDisk.Number)"
                    # Try alternative method to get volume
                    `$allVolumes = Get-Volume | Where-Object { `$_.FileSystemLabel -or `$_.DriveLetter }
                    Write-Output "All available volumes:"
                    foreach (`$v in `$allVolumes) {
                        Write-Output "  Drive: `$(`$v.DriveLetter), Label: `$(`$v.FileSystemLabel), Type: `$(`$v.DriveType)"
                    }
                    
                    # Try to assign a drive letter manually
                    Write-Output "Attempting to assign drive letter manually..."
                    try {
                        # Get available drive letters
                        `$usedDrives = Get-Volume | Where-Object { `$_.DriveLetter } | ForEach-Object { `$_.DriveLetter }
                        `$availableDrives = 67..90 | ForEach-Object { [char]`$_ } | Where-Object { `$_ -notin `$usedDrives }
                        
                        if (`$availableDrives) {
                            `$driveLetter = `$availableDrives[0]
                            Write-Output "Assigning drive letter `$driveLetter to disk `$(`$mountedDisk.Number)"
                            
                            # Use diskpart to assign drive letter
                            `$assignScriptPath = "C:\Windows\Temp\assign_drive.txt"
                            "select disk `$(`$mountedDisk.Number)" | Out-File -FilePath `$assignScriptPath -Encoding ASCII
                            "select partition 1" | Out-File -FilePath `$assignScriptPath -Append -Encoding ASCII
                            "assign letter=`$driveLetter" | Out-File -FilePath `$assignScriptPath -Append -Encoding ASCII
                            
                            `$assignResult = diskpart /s `$assignScriptPath 2>&1
                            Write-Output "Drive assignment result: `$assignResult"
                            Remove-Item `$assignScriptPath -ErrorAction SilentlyContinue
                            
                            # Try to get the volume again
                            Start-Sleep -Seconds 5
                            `$vol = Get-Volume -DriveLetter `$driveLetter -ErrorAction SilentlyContinue
                            if (`$vol) {
                                Write-Output "Successfully assigned drive letter `$(`$vol.DriveLetter) to volume"
                            }
                        } else {
                            Write-Output "No available drive letters found"
                        }
                    } catch {
                        Write-Output "Error assigning drive letter: `$(`$_.Exception.Message)"
                    }
                }
            } else {
                Write-Output "Could not find mounted disk for `$(`$file.FullName)"
                # Try to unmount using diskpart
                `$unmountScriptPath = "C:\Windows\Temp\unmount_vdisk.txt"
                'select vdisk file="' + `$file.FullName + '"' | Out-File -FilePath `$unmountScriptPath -Encoding ASCII
                "detach vdisk" | Out-File -FilePath `$unmountScriptPath -Append -Encoding ASCII
                diskpart /s `$unmountScriptPath | Out-Null
                Remove-Item `$unmountScriptPath -ErrorAction SilentlyContinue
                continue
            }
            
            if (`$vol -and `$vol.DriveLetter) {
                Write-Output "Running chkdsk on drive `$(`$vol.DriveLetter):"
                
                # Run chkdsk with /f parameter to fix errors
                `$logPath = "C:\Windows\Temp\CHK_`$(`$file.Name -replace '\\\.', '_').log"
                
                # Use Start-Process to run chkdsk non-interactively
                `$processInfo = New-Object System.Diagnostics.ProcessStartInfo
                `$processInfo.FileName = "chkdsk.exe"
                `$processInfo.Arguments = "`$(`$vol.DriveLetter): /f /r /x"
                `$processInfo.UseShellExecute = `$false
                `$processInfo.RedirectStandardOutput = `$true
                `$processInfo.RedirectStandardError = `$true
                `$processInfo.CreateNoWindow = `$true
                
                `$process = New-Object System.Diagnostics.Process
                `$process.StartInfo = `$processInfo
                `$process.Start() | Out-Null
                
                # Read output
                `$output = `$process.StandardOutput.ReadToEnd()
                `$errorOutput = `$process.StandardError.ReadToEnd()
                `$process.WaitForExit()
                
                # Log results
                "Chkdsk output for `$(`$file.FullName):" | Out-File -FilePath `$logPath -Append
                `$output | Out-File -FilePath `$logPath -Append
                if (`$errorOutput) {
                    "Chkdsk errors:" | Out-File -FilePath `$logPath -Append
                    `$errorOutput | Out-File -FilePath `$logPath -Append
                }
                
                Write-Output "Chkdsk completed for `$(`$file.FullName). Exit code: `$(`$process.ExitCode). Log saved to: `$logPath"
            } elseif (`$mountedDisk) {
                Write-Output "Could not determine drive letter for `$(`$file.FullName), but disk is mounted. Attempting chkdsk on disk `$(`$mountedDisk.Number)"
                
                # Try to run chkdsk on the disk directly using diskpart
                `$logPath = "C:\Windows\Temp\CHK_`$(`$file.Name -replace '\\\.', '_').log"
                
                try {
                    # First try to assign a drive letter to the volume
                    Write-Output "Attempting to assign drive letter to disk `$(`$mountedDisk.Number)"
                    
                    # Get available drive letters
                    `$usedDrives = Get-Volume | Where-Object { `$_.DriveLetter } | ForEach-Object { `$_.DriveLetter }
                    `$availableDrives = 67..90 | ForEach-Object { [char]`$_ } | Where-Object { `$_ -notin `$usedDrives }
                    
                    if (`$availableDrives) {
                        `$driveLetter = `$availableDrives[0]
                        Write-Output "Assigning drive letter `$driveLetter to disk `$(`$mountedDisk.Number)"
                        
                        # Use diskpart to assign drive letter
                        `$assignScriptPath = "C:\Windows\Temp\assign_drive.txt"
                        "select disk `$(`$mountedDisk.Number)" | Out-File -FilePath `$assignScriptPath -Encoding ASCII
                        "select partition 1" | Out-File -FilePath `$assignScriptPath -Append -Encoding ASCII
                        "assign letter=`$driveLetter" | Out-File -FilePath `$assignScriptPath -Append -Encoding ASCII
                        
                        `$assignResult = diskpart /s `$assignScriptPath 2>&1
                        Write-Output "Drive assignment result: `$assignResult"
                        Remove-Item `$assignScriptPath -ErrorAction SilentlyContinue
                        
                        # Wait for drive letter to be assigned
                        Start-Sleep -Seconds 5
                        
                        # Try to get the volume with the assigned drive letter
                        `$vol = Get-Volume -DriveLetter `$driveLetter -ErrorAction SilentlyContinue
                        if (`$vol) {
                            Write-Output "Successfully assigned drive letter `$(`$vol.DriveLetter) to volume"
                            
                            # Run chkdsk on the drive letter
                            `$processInfo = New-Object System.Diagnostics.ProcessStartInfo
                            `$processInfo.FileName = "chkdsk.exe"
                            `$processInfo.Arguments = "`$(`$vol.DriveLetter): /f /r /x"
                            `$processInfo.UseShellExecute = `$false
                            `$processInfo.RedirectStandardOutput = `$true
                            `$processInfo.RedirectStandardError = `$true
                            `$processInfo.CreateNoWindow = `$true
                            
                            `$process = New-Object System.Diagnostics.Process
                            `$process.StartInfo = `$processInfo
                            `$process.Start() | Out-Null
                            
                            # Read output
                            `$output = `$process.StandardOutput.ReadToEnd()
                            `$errorOutput = `$process.StandardError.ReadToEnd()
                            `$process.WaitForExit()
                            
                            # Log results
                            "Chkdsk output for drive `$(`$vol.DriveLetter): (`$(`$file.FullName)):" | Out-File -FilePath `$logPath -Append
                            `$output | Out-File -FilePath `$logPath -Append
                            if (`$errorOutput) {
                                "Chkdsk errors:" | Out-File -FilePath `$logPath -Append
                                `$errorOutput | Out-File -FilePath `$logPath -Append
                            }
                            
                            Write-Output "Chkdsk completed for drive `$(`$vol.DriveLetter): (`$(`$file.FullName)). Exit code: `$(`$process.ExitCode). Log saved to: `$logPath"
                        } else {
                            Write-Output "Failed to get volume after drive letter assignment"
                            throw "Could not access volume after drive letter assignment"
                        }
                    } else {
                        Write-Output "No available drive letters found"
                        throw "No available drive letters for chkdsk"
                    }
                } catch {
                    Write-Output "Error running chkdsk on disk `$(`$mountedDisk.Number): `$(`$_.Exception.Message)"
                    "Error running chkdsk on disk `$(`$mountedDisk.Number): `$(`$_.Exception.Message)" | Out-File -FilePath `$logPath -Append
                }
            } else {
                Write-Output "Could not determine drive letter or find mounted disk for `$(`$file.FullName)"
            }

            # Unmount the VHD using diskpart
            Write-Output "Unmounting VHD: `$(`$file.FullName)"
            try {
                `$unmountScriptPath = "C:\Windows\Temp\unmount_vdisk.txt"
                'select vdisk file="' + `$file.FullName + '"' | Out-File -FilePath `$unmountScriptPath -Encoding ASCII
                "detach vdisk" | Out-File -FilePath `$unmountScriptPath -Append -Encoding ASCII
                `$unmountResult = diskpart /s `$unmountScriptPath 2>&1
                if (`$LASTEXITCODE -eq 0) {
                    Write-Output "Successfully unmounted: `$(`$file.FullName)"
                } else {
                    throw "diskpart exit code: `$LASTEXITCODE, output: `$unmountResult"
                }
                Remove-Item `$unmountScriptPath -ErrorAction SilentlyContinue
            } catch {
                Write-Output "Warning: Could not unmount `$(`$file.FullName): `$(`$_.Exception.Message)"
                Remove-Item `$unmountScriptPath -ErrorAction SilentlyContinue
                # Try alternative unmount method
                try {
                    `$forceUnmountScriptPath = "C:\Windows\Temp\force_unmount_vdisk.txt"
                    'select vdisk file="' + `$file.FullName + '"' | Out-File -FilePath `$forceUnmountScriptPath -Encoding ASCII
                    "detach vdisk" | Out-File -FilePath `$forceUnmountScriptPath -Append -Encoding ASCII
                    diskpart /s `$forceUnmountScriptPath | Out-Null
                    Write-Output "Force unmount attempted: `$(`$file.FullName)"
                    Remove-Item `$forceUnmountScriptPath -ErrorAction SilentlyContinue
                } catch {
                    Write-Output "Error: Could not force unmount `$(`$file.FullName): `$(`$_.Exception.Message)"
                    Remove-Item `$forceUnmountScriptPath -ErrorAction SilentlyContinue
                }
            }
            
        } catch {
            `$errorMsg = "Error processing `$(`$file.FullName): `$(`$_.Exception.Message)"
            Write-Output `$errorMsg
            `$errorMsg | Out-File -Append "C:\Windows\Temp\ChkdskErrors.log"
        }
    }
    
    Write-Output "All VHD/VHDX files processed successfully"
    
    # Cleanup: Ensure all VHDs are unmounted
    Write-Output "Performing final cleanup..."
    `$mountedVHDs = Get-Disk | Where-Object { `$_.Location -like "*$FSLogixFileShare*" }
    foreach (`$vhd in `$mountedVHDs) {
        try {
            Write-Output "Unmounting remaining VHD: `$(`$vhd.Location)"
            `$cleanupScriptPath = "C:\Windows\Temp\cleanup_vdisk.txt"
            'select vdisk file="' + `$vhd.Location + '"' | Out-File -FilePath `$cleanupScriptPath -Encoding ASCII
            "detach vdisk" | Out-File -FilePath `$cleanupScriptPath -Append -Encoding ASCII
            diskpart /s `$cleanupScriptPath | Out-Null
            Remove-Item `$cleanupScriptPath -ErrorAction SilentlyContinue
        } catch {
            Write-Output "Could not unmount `$(`$vhd.Location): `$(`$_.Exception.Message)"
        }
    }
}
catch {
    `$errorMsg = "Fatal error: `$(`$_.Exception.Message)"
    Write-Output `$errorMsg
    `$errorMsg | Out-File -Append "C:\Windows\Temp\ChkdskErrors.log"
    
    # Cleanup: Ensure all VHDs are unmounted even on error
    Write-Output "Performing emergency cleanup..."
    try {
        `$mountedVHDs = Get-Disk | Where-Object { `$_.Location -like "*$FSLogixFileShare*" }
        foreach (`$vhd in `$mountedVHDs) {
            try {
                Write-Output "Emergency unmounting VHD: `$(`$vhd.Location)"
                `$emergencyScriptPath = "C:\Windows\Temp\emergency_vdisk.txt"
                'select vdisk file="' + `$vhd.Location + '"' | Out-File -FilePath `$emergencyScriptPath -Encoding ASCII
                "detach vdisk" | Out-File -FilePath `$emergencyScriptPath -Append -Encoding ASCII
                diskpart /s `$emergencyScriptPath | Out-Null
                Remove-Item `$emergencyScriptPath -ErrorAction SilentlyContinue
            } catch {
                Write-Output "Could not emergency unmount `$(`$vhd.Location): `$(`$_.Exception.Message)"
            }
        }
    } catch {
        Write-Output "Emergency cleanup failed: `$(`$_.Exception.Message)"
    }
    
    throw
}
"@

##### Wait for VM to be Ready #####

Write-Output "Waiting for VM to be ready..."
$maxWaitTime = 10 # minutes
$waitStartTime = Get-Date

do {
    try {
        $vmStatus = Get-AzVM -ResourceGroupName $AzureResourceGroup -Name $AzureVMName -Status
        $vmPowerState = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }
        
        if ($vmPowerState.DisplayStatus -eq "VM running") {
            Write-Output "VM is running, waiting for Azure VM Agent to be ready..."
            Start-Sleep -Seconds 30
            break
        } else {
            Write-Output "VM status: $($vmPowerState.DisplayStatus), waiting..."
            Start-Sleep -Seconds 30
        }
    } catch {
        Write-Output "Error checking VM status: $($_.Exception.Message)"
        Start-Sleep -Seconds 30
    }
} while ((Get-Date) -lt $waitStartTime.AddMinutes($maxWaitTime))

if ((Get-Date) -ge $waitStartTime.AddMinutes($maxWaitTime)) {
    throw "VM did not become ready within $maxWaitTime minutes"
}

##### Execute Script on VM #####

try {
    Write-Output "Running chkdsk script on temp VM..."
    $Time = Get-Date
    
    # Create temporary script file
    $tempScriptPath = ".\fslogix-chkdsk-script.ps1"
    Write-Output "Creating temporary script file: $tempScriptPath"
    $ScriptBlock | Out-File -FilePath $tempScriptPath -Encoding UTF8
    
    if (Test-Path $tempScriptPath) {
        Write-Output "Script file created successfully. Size: $((Get-Item $tempScriptPath).Length) bytes"
    } else {
        throw "Failed to create temporary script file"
    }
    
    Write-Output "Executing script on VM: $AzureVMName"
    $job = Invoke-AzVmRunCommand -ResourceGroupName $AzureResourceGroup -VMName $AzureVMName -ScriptPath $tempScriptPath -CommandId 'RunPowerShellScript' -AsJob

    while ((Get-Job $job.Id).State -eq 'Running') {
        if ((Get-Date) -gt $Time.AddMinutes(86)) {
            Stop-Job $job.Id -Force
            throw "Timed out after 90 minutes"
        } else {
            Write-Output "Script still running... (Elapsed: $(((Get-Date) - $Time).TotalMinutes.ToString('F1')) minutes)"
            Start-Sleep 60
        }
    }

    # Get job results
    $jobOutput = Receive-Job -Id $job.Id
    $jobState = (Get-Job $job.Id).State

    Write-Output "Script execution completed with state: $jobState"
    $jobOutput | Out-String | Write-Output

    # Clean up the job
    Remove-Job -Id $job.Id -Force

    # Clean up the temporary script file
    if (Test-Path ".\fslogix-chkdsk-script.ps1") {
        Remove-Item ".\fslogix-chkdsk-script.ps1" -Force
    }
} catch {
    Write-Output "Error during script execution: $($_.Exception.Message)"
    
    # Clean up the job if it exists
    if ($job) {
        try {
            Stop-Job $job.Id -Force -ErrorAction SilentlyContinue
            Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
        } catch {
            # Ignore cleanup errors
        }
    }
    
    # Clean up the temporary script file
    if (Test-Path ".\fslogix-chkdsk-script.ps1") {
        Remove-Item ".\fslogix-chkdsk-script.ps1" -Force -ErrorAction SilentlyContinue
    }
    
    throw
}

} catch {
    Write-Output "Error occurred during execution: $($_.Exception.Message)"
    Write-Output "Stack trace: $($_.ScriptStackTrace)"
    throw
} finally {
    ##### Cleanup #####
    
    Write-Output "Cleaning up temporary resources..."
    Start-Sleep 30  # Reduced wait time
    
    try {
        Write-Output "Removing VM..."
        Remove-AzVM -Name $AzureVMName -ResourceGroupName $AzureResourceGroup -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Output "Error removing VM: $($_.Exception.Message)"
    }
    
    try {
        Write-Output "Removing OS disk..."
        Remove-AzDisk -ResourceGroupName $AzureResourceGroup -DiskName $azureVmOsDiskName -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Output "Error removing OS disk: $($_.Exception.Message)"
    }
    
    try {
        Write-Output "Removing network interface..."
        Remove-AzNetworkInterface -Name $azureNicName -ResourceGroupName $AzureResourceGroup -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Output "Error removing NIC: $($_.Exception.Message)"
    }
    
    try {
        Write-Output "Removing public IP..."
        Remove-AzPublicIpAddress -Name $azurePublicIpName -ResourceGroupName $AzureResourceGroup -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Output "Error removing public IP: $($_.Exception.Message)"
    }
    
    Write-Output "Cleanup completed."
}
