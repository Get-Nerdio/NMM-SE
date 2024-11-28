<#
This is based on this script from Microsoft (see https://learn.microsoft.com/en-us/azure/virtual-desktop/configure-single-sign-on), but takes it one step further and automatically creates a dynamic device security group to automate the process without needing to be tied to an AVD naming scheme.
It can be run from Azure Cloud Shell or a local PowerShell session where you're signed in with Azure PowerShell and your Azure context is set to the subscription you want to use. Also, make sure you've installed the Microsoft Graph PowerShell SDK.
#>


# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

# Connect to Microsoft Graph with required permissions
Connect-MgGraph -Scopes "Application.Read.All","Application-RemoteDesktopConfig.ReadWrite.All"

# Define the dynamic group details
$groupName = "Device|AVDHosts"
$groupDescription = "This is a dynamic device group for EntraID joined AVD Hosts"
$dynamicRule = '(device.devicePhysicalIds -any (_ -contains "[AzureResourceId]"))'   

# Create the dynamic group with correct parameter names
$group = New-MgGroup -DisplayName $groupName -Description $groupDescription -SecurityEnabled:$true -MailEnabled:$false -GroupTypes @("DynamicMembership") -MembershipRule $dynamicRule -MembershipRuleProcessingState "On" -mailNickname $groupName
$group
# Wait for the group to be created and resolved (it may take a few minutes for the group to populate)
Start-Sleep -Seconds 30  # Adjust the sleep time if necessary, depending on your environment

# Retrieve the object ID of the newly created group
$groupObjectId = (Get-MgGroup -Filter "DisplayName eq '$groupName'").Id

# Get the object ID for each service principal
$MSRDspId = (Get-MgServicePrincipal -Filter "AppId eq 'a4a365df-50f1-4397-bc59-1a1564b8bb9c'").Id
$WCLspId = (Get-MgServicePrincipal -Filter "AppId eq '270efc09-cd0d-444b-a71f-39af4910ec45'").Id

# Set the property 'isRemoteDesktopProtocolEnabled' to true for each service principal, if not already enabled
If ((Get-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $MSRDspId).IsRemoteDesktopProtocolEnabled -ne $true) {
    Update-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $MSRDspId -IsRemoteDesktopProtocolEnabled $true
}

If ((Get-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $WCLspId).IsRemoteDesktopProtocolEnabled -ne $true) {
    Update-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $WCLspId -IsRemoteDesktopProtocolEnabled $true
}

# Confirm the property 'isRemoteDesktopProtocolEnabled' is set to true for both service principals
$MSRDPConfig = Get-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $MSRDspId
$WCLRDPConfig = Get-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $WCLspId

Write-Host "Microsoft Remote Desktop Service Principal RDP Status: $($MSRDPConfig.IsRemoteDesktopProtocolEnabled)"
Write-Host "Windows Cloud Login Service Principal RDP Status: $($WCLRDPConfig.IsRemoteDesktopProtocolEnabled)"

# Configure the Target Device Group for both service principals
$tdg = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphTargetDeviceGroup
$tdg.Id = $groupObjectId
$tdg.DisplayName = $groupName

# Add the dynamic group to the target device group configuration
New-MgServicePrincipalRemoteDesktopSecurityConfigurationTargetDeviceGroup -ServicePrincipalId $MSRDspId -BodyParameter $tdg
New-MgServicePrincipalRemoteDesktopSecurityConfigurationTargetDeviceGroup -ServicePrincipalId $WCLspId -BodyParameter $tdg

Write-Host "Successfully configured RDP and target device group for service principals."
