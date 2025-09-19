#description: Creates an Azure disk, attaches it to the VM, and initializes it as the D: drive, or next available drive letter
#tags: Nerdio

<# Notes:
    This script will create a new disk, attach it to the VM, and initialize it as the D: drive, or next available drive letter.

    To adjust the size and sku of the disk, clone this script and change the variables $DiskSizeGB and $DiskSku.
#>

$ErrorActionPreference = 'Stop'

# Hardcoded disk parameters
$DiskSizeGB = 128
$DiskSku = "Premium_LRS"
$DiskName = "$AzureVMName-data-disk"
try {

    # Get the VM and its current data disks
    $vm = Get-AzVM -Name $AzureVMName -ResourceGroupName $AzureResourceGroupName
    $currentLuns = $vm.storageprofile.datadisks | ForEach-Object { $_.Lun }

    # Determine the next available LUN
    $Lun = 0
    while ($currentLuns -contains $Lun) {
        $Lun++
    }

    # Get the tags of the VM's os disk
    $osDisk = Get-AzDisk -ResourceGroupName $AzureResourceGroupName -DiskName $vm.StorageProfile.OsDisk.Name
    $tags = $osDisk.Tags

    # Create the new disk
    $diskConfig = New-AzDiskConfig -SkuName $DiskSku -OsType Windows -CreateOption Empty -DiskSizeGB $DiskSizeGB -Location $AzureRegionName -Tag $tags
    $disk = New-AzDisk -DiskName $DiskName -ResourceGroupName $AzureResourceGroupName -Disk $diskConfig 


    # Attach the disk to the VM with the determined LUN
    $vm = Add-AzVMDataDisk -VM $vm -Name $DiskName -CreateOption Attach -ManagedDiskId $disk.Id -Lun $Lun
    Update-AzVM -VM $vm -ResourceGroupName $AzureResourceGroupName

    # Get status of vm
    $vm = Get-AzVM -ResourceGroupName $AzureResourceGroupName -Name $AzureVMName -Status

    # if vm is stopped, start it
    if ($vm.statuses[1].displaystatus -eq "VM deallocated") {
        Write-Output "Starting VM $AzureVMName"
        Start-AzVM -ResourceGroupName $AzureResourceGroupName -Name $AzureVMName
    }

    $DiskSize = $DiskSizeGB * 1GB

    # Initialize, partition, and format the new disk on the VM
    $scriptContent = 
@"
    # Find the disk by size
    `$disk = Get-Disk | Where-Object { `$_.Size -eq $DiskSize -and `$_.PartitionStyle -eq 'RAW' }

    # Initialize the disk
    Initialize-Disk -Number `$disk.Number -PartitionStyle GPT

    # Create a partition and format it as NTFS
    New-Partition -DiskNumber `$disk.Number -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'DataDisk'
"@

    $ScriptContent > "$env:temp\data-disk.ps1"
    Invoke-AzVMRunCommand -ResourceGroupName $AzureResourceGroupName -VMName $AzureVMName -CommandId 'RunPowerShellScript' -ScriptPath "$env:temp\data-disk.ps1"

    # if VM was stopped, stop it again
    if ($vm.statuses[1].displaystatus -eq "VM deallocated") {
        Write-Output "Stopping VM $AzureVMName"
        Stop-AzVM -ResourceGroupName $AzureResourceGroupName -Name $AzureVMName -Force
    }
}
catch {
    # if VM was stopped, stop it again
    if ($vm.statuses[1].displaystatus -eq "VM deallocated") {
        Write-Output "Stopping VM $AzureVMName"
        Stop-AzVM -ResourceGroupName $AzureResourceGroupName -Name $AzureVMName -Force
    }
    # remove the new disk if the script fails
    Write-Output "Removing disk $DiskName"
    Remove-AzDisk -ResourceGroupName $AzureResourceGroupName -DiskName $DiskName -Force
    throw $_
}
### End Script ###
