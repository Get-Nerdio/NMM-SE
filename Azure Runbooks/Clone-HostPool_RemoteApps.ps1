Install-Module -Name Az.DesktopVirtualization -AllowClobber -Force


# Parameters
$subscriptionId = "subscriptionId"
$resourceGroupName = "NMM-SalesDemos-WinHart"
$existingHostPoolName = "AVD Demo"
$newHostPoolName = "AVD Demo Clone"
$location = "centralus"


try {
    

    # Login to Azure
    Connect-AzAccount
    Select-AzSubscription -SubscriptionId $subscriptionId

    if ((Get-AzContext).Subscription.id -eq $subscriptionId) {
        Write-Output "Successfully logged in to Azure."
    } else {
        throw "Failed to log in to Azure."
        
    }

    # Get the existing host pool
    $existingHostPool = Get-AzWvdHostPool -ResourceGroupName $resourceGroupName -Name $existingHostPoolName

    # Clone the existing host pool to a new host pool
    $hostPoolParams = @{
        ResourceGroupName     = $resourceGroupName
        Name                  = $newHostPoolName
        Location              = $location
        HostPoolType          = $existingHostPool.HostPoolType
        PreferredAppGroupType = $existingHostPool.PreferredAppGroupType
        LoadBalancerType      = $existingHostPool.LoadBalancerType
        FriendlyName          = "$($existingHostPool.FriendlyName) - Clone"
        Description           = "$($existingHostPool.Description) - Clone"
    }
    
    $newHostPool = New-AzWvdHostPool @hostPoolParams
    

    # Get existing application groups in the existing host pool
    $appGroups = Get-AzWvdApplicationGroup -ResourceGroupName $resourceGroupName | Where-Object { $_.HostPoolArmPath -eq $existingHostPool.Id -and $_.Kind -eq 'RemoteApp' }

    foreach ($appGroup in $appGroups) {

        # Clone each application group
        $newAppGroupName = "$($appGroup.Name) - Clone"
        $newAppGroup = New-AzWvdApplicationGroup -ResourceGroupName $resourceGroupName -Name $newAppGroupName -HostPoolArmPath $newHostPool.Id -Location $location -ApplicationGroupType $appGroup.ApplicationGroupType -Description "$($appGroup.Description) - Clone"

        # Get existing applications in the application group
        $apps = Get-AzWvdApplication -ResourceGroupName $resourceGroupName -ApplicationGroupName $appGroup.Name

        foreach ($app in $apps) {
            # Clone each application
            $appParams = @{
                ResourceGroupName   = $resourceGroupName
                GroupName           = $newAppGroup.Name 
                Name                = $app.name.Split('/')[-1]
                Description         = $app.Description
                FilePath            = $app.FilePath
                CommandLineArgument = $app.CommandLineArgument
                CommandLineSetting  = $app.CommandLineSetting
                FriendlyName        = $app.FriendlyName
                IconIndex           = $app.IconIndex
                IconPath            = $app.IconPath
                ShowInPortal        = $app.ShowInPortal
            }
            
            New-AzWvdApplication @appParams
            
        }
    }

    Write-Output "Host pool and application groups cloned successfully."

}
catch {
    Write-Error "Error: $($_.Exception.Message)"
}



# Parameters
$subscriptionId = "da1a2fbb-3c08-48dc-bef8-2edabdc08f3f"
$resourceGroupName = "NMM-SalesDemos-WinHart"
$existingHostPoolName = "Dev-ISV Template Hostpool"
$newHostPoolName = "Dev-ISV Clone"
$location = "centralus"
