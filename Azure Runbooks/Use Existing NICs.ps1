#description: Swaps a VM's NIC to one from an existing group of NICs
#tags: Nerdio, Preview

<#
Notes:

For applications that require consistent MAC addresses, this script can be assigned to the "VM Creation" event in 
Nerdio. After a new VM is created, its NIC will be swapped with an existing NIC. The existing NICs must have a
specific tag applied in Azure. The default tag name and value are defined below. To use a different tag name
or value, copy this script and modify as needed. The NICs must be in a resource group that Nerdio is linked to.

#>

$ErrorActionPreference = 'Stop'

# Define tag to identify existing NICs
$TagName = 'ReUseNicGroup'
$TagValue = 1

# Get existing NICs
$Nics = Get-AzResource -tagname $TagName -TagValue $TagValue | 
    Where-Object ResourceType -eq 'Microsoft.Network/networkInterfaces'

if ($null -eq $nics){
    Throw "No unassigned network interfaces found"
}

$VM = Get-AzVM -ResourceGroupName $AzureResourceGroupName -Name $azureVMName 

$ExistingNic = Get-AzResource -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].id 

# script is not compatible with VMs that have multiple NICs
if ($vm.NetworkProfile.NetworkInterfaces.count -ne 1) {
    Throw "More than one network interface is attached to VM"
}

if ($ExistingNic.id -in $Nics.ResourceId){
    Write-Error "VM $AzureVMName already has NIC $($ExistingNic.ResourceName) assigned"
}
else {
    Stop-AzVM -Name $azureVMName -ResourceGroupName $AzureResourceGroupName -force 
    $Success = $false
    # attempt to swap NICs
    While ($Success -eq $false -or $AttemptedNics.count -ge $nics.Count){
        $Nics = Get-AzResource -tagname $TagName -TagValue $TagValue | 
            Where-Object ResourceType -eq 'Microsoft.Network/networkInterfaces' |
            Where-Object ManagedBy -eq $null
            Where-Object {$_ -notin $AttemptedNics}
        # Selecting a random NIC from the list, so that multiple VMs being provisioned simultaneously won't always select the first NIC in the list
        $NewNic = $nics | get-random
        $AttemptedNics += $NewNic
        try {
            Write-Output "Attempting to add NIC $($newnic.name) to vm $azureVMName."
            Add-AzVMNetworkInterface -VM $vm -Id $NewNic.id  
            Remove-AzVMNetworkInterface -VM $vm -id $ExistingNic.id | Update-AzVM
            $Success = $true
            Write-Output "Added NIC $($newnic.name) to vm $azureVMName."
        }
        catch {
            # If multiple VMs are being provisioned at once, the attachment may fail, so we'll retry
            Write-output "Unable to add NIC $($newnic.name) to vm $azureVMName. Retrying with another NIC from the tag group"
        }
    }
    Start-AzVM -Name $azureVMName -ResourceGroupName $AzureResourceGroupName 
    # Delete the original NIC
    if ($Success) {
        Remove-AzNetworkInterface -ResourceGroupName $AzureResourceGroupName -Name $ExistingNic.Name -Force
    }
    if ($AttemptedNics.count -ge $nics.Count) {
        Throw "Attempted all NICs in the tag group. Could not assign any to $azureVMName"
    }

}