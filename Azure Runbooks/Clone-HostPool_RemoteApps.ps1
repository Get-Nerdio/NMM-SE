Install-Module -Name Az.DesktopVirtualization -AllowClobber -Force


# Parameters
$subscriptionId = "subscriptionId"
$resourceGroupName = "NMM-SalesDemos-WinHart"
$existingHostPoolName = "AVD Demo"
$newHostPoolName = "AVD Demo Clone"
$location = "centralus"

$begin = Get-Date

try {
    

    # Login to Azure
    Connect-AzAccount
    Select-AzSubscription -SubscriptionId $subscriptionId

    # Get the existing host pool
    $existingHostPool = Get-AzWvdHostPool -ResourceGroupName $resourceGroupName -Name $existingHostPoolName

    # Clone the existing host pool to a new host pool
    $newHostPool = New-AzWvdHostPool -ResourceGroupName $resourceGroupName -Name $newHostPoolName -Location $location -HostPoolType $existingHostPool.HostPoolType -PreferredAppGroupType $existingHostPool.PreferredAppGroupType -LoadBalancerType $existingHostPool.LoadBalancerType -FriendlyName "$($existingHostPool.FriendlyName) - Clone" -Description "$($existingHostPool.Description) - Clone"

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
            New-AzWvdApplication -ResourceGroupName $resourceGroupName -ApplicationGroupName $newAppGroupName -Name $app.Name -Description $app.Description -ApplicationPath $app.ApplicationPath -CommandLineArgument $app.CommandLineArgument -CommandLineSetting $app.CommandLineSetting -FriendlyName $app.FriendlyName -IconIndex $app.IconIndex -IconPath $app.IconPath -IconResourceId $app.IconResourceId -ShowInPortal $app.ShowInPortal
        }
    }

    Write-Output "Host pool and application groups cloned successfully."



}
catch {
    Write-Error "Error: $($_.Exception.Message)"
}
finally {
    $runtime = New-TimeSpan -Start $begin -End (Get-Date)
    Write-Verbose "Execution completed in $runtime"
}