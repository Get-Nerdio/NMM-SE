#description: Swaps a VM's NIC to a newly created NIC
#tags: Nerdio, Preview

<#
Notes:

This script is intended to be used as a counterpart to the "Use Existing NICs" scripted action, which swaps a VM's
NIC to one from a pre-defined group of NICs. This script should be used when removing a host from a host group; it
will replace the VMs current NIC with a newly-created NIC, so that the current NIC is not deleted when the VM is 
destroyed

#>

$ErrorActionPreference = 'Stop'

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
    $Subnet = Get-azvirtualnetworksubnetconfig -resourceid $ExistingNic.Properties.ipConfigurations.properties.subnet.id
    $NewNic = New-AzNetworkInterface -ResourceGroupName $AzureResourceGroupName `
                                     -Name "$azureVMName-nic$(get-random -minimum 1000 -maximum 9999)" `
                                     -location $ExistingNic.location `
                                     -Subnet $Subnet
    # attempt to swap NICs
    try {
            Write-Output "Attempting to add NIC $($newnic.name) to vm $azureVMName."
            Add-AzVMNetworkInterface -VM $vm -Id $NewNic.id  
            Remove-AzVMNetworkInterface -VM $vm -id $ExistingNic.id | Update-AzVM
            Write-Output "Added NIC $($newnic.name) to vm $azureVMName."
    }
    catch {
        # If multiple VMs are being provisioned at once, the attachment may fail, so we'll retry
        Write-output "Unable to add NIC $($newnic.name) to vm $azureVMName."
        Throw $_
    }

}