#description: Install the SentinelOne agent.
#execution mode: Individual
#tags: Nerdio, SentinelOne, Preview

<#
Notes:
06/2025
This script has been modified to utilize an Inherited Variable for the Site Token and AgentVersion so that you don't need to maintain multiole copies of the script and will only need to update the API Token on a per-account basis.
You can also make the S1APItoken an inherited variable, but it will be stored in clear text so if that's a concern, please utilize a secure variable.

Included an updated "Install Sentinel One Agent" section (as contributed by @John Tokash on the NMM forums (https://nmmhelp.getnerdio.com/hc/en-us/community/posts/37239443332877-Sentinel-One-NMM-Provided-Azure-Runbook-Improvement))

Original Notes:
The installation script requires an Agent version, Site token and API token.

    Agent version: In the Management Console, click Sentinels > Packages. Copy the
version number of the Agent to deploy. This is the full version number (aka the "Build
number" e.g. 21.7.5.1080)

    Site token: In Sentinels > Packages, click Copy token.

    API token: Click Settings > Users > My User. Click Generate or Options > Regenerate
API Token.

You must provide variables to this script as seen in the Required Variables section. 
Set these up in Nerdio Manager under Settings->Portal. The variables to create are:
    S1AgentVersion
    S1SiteToken
    S1APItoken
#>

##### Required Variables #####

$SiteToken = $InheritedVars.S1SiteToken
$AgentVersion = $InheritedVars.S1AgentVersion
$APItoken = $SecureVars.S1APItoken

##### Script Logic #####

$sub = get-azsubscription -SubscriptionId $AzureSubscriptionId

set-azcontext -subscription $sub 

$Settings = @{"WindowsAgentVersion" = $AgentVersion; "SiteToken" = $SiteToken}

$ProtectedSettings = @{"SentinelOneConsoleAPIKey" = $APItoken};

# Get status of vm
$vm = Get-AzVM -ResourceGroupName $AzureResourceGroupName -Name $AzureVMName -Status

# if vm is stopped, start it
if ($vm.statuses[1].displaystatus -eq "VM deallocated") {
    Write-Output "Starting VM $AzureVMName"
    Start-AzVM -ResourceGroupName $AzureResourceGroupName -Name $AzureVMName
}

# Install SentinelOne agent
try {
    Write-Output "Installing SentinelOne agent on VM $AzureVMName..."


    $installResult = Set-AzVMExtension `
        -ResourceGroupName $AzureResourceGroupName `
        -Location $AzureRegionName `
        -VMName $AzureVMName `
        -Name "SentinelOne.WindowsExtension" `
        -Publisher "SentinelOne.WindowsExtension" `
        -Type "WindowsExtension" `
        -TypeHandlerVersion "1.0" `
        -Settings $Settings `
        -ProtectedSettings $ProtectedSettings `
        -ErrorAction Stop

    $installResult
    Write-Output "SentinelOne extension installation initiated successfully."
}
catch {
    $errMsg = "Failed to install SentinelOne agent on VM $AzureVMName. Error: $($_.Exception.Message)"
    Write-Error $errMsg
    throw $errMsg
}

# if VM was stopped, stop it again
if ($vm.statuses[1].displaystatus -eq "VM deallocated") {
    Write-Output "Stopping VM $AzureVMName"
    Stop-AzVM -ResourceGroupName $AzureResourceGroupName -Name $AzureVMName -Force
}
