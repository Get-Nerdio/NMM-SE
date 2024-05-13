# Import the required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications
 
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.Read.All","Application-RemoteDesktopConfig.ReadWrite.All"
 
# Get the object ID for each service principal
$MSRDspId = (Get-MgServicePrincipal -Filter "AppId eq 'a4a365df-50f1-4397-bc59-1a1564b8bb9c'").Id
$WCLspId = (Get-MgServicePrincipal -Filter "AppId eq '270efc09-cd0d-444b-a71f-39af4910ec45'").Id
 
# Set the property isRemoteDesktopProtocolEnabled to true
If ((Get-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $MSRDspId) -ne $true) {
    Update-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $MSRDspId -IsRemoteDesktopProtocolEnabled
}
 
If ((Get-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $WCLspId) -ne $true) {
    Update-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $WCLspId -IsRemoteDesktopProtocolEnabled
}
 
# Confirm the property isRemoteDesktopProtocolEnabled is set to true
Get-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $MSRDspId
Get-MgServicePrincipalRemoteDesktopSecurityConfiguration -ServicePrincipalId $WCLspId
 
# Replace the placeholders with your own values
$tdg = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphTargetDeviceGroup
$tdg.Id = "<Group object ID>"
$tdg.DisplayName = "<Group display name>"
 
# Add the group to the targetDeviceGroup object
New-MgServicePrincipalRemoteDesktopSecurityConfigurationTargetDeviceGroup -ServicePrincipalId $MSRDspId -BodyParameter $tdg
New-MgServicePrincipalRemoteDesktopSecurityConfigurationTargetDeviceGroup -ServicePrincipalId $WCLspId -BodyParameter $tdg
 
 
#Please replace `<Group object ID>` and `<Group display name>` with your own values. This script enables Microsoft Entra authentication for RDP, sets the `isRemoteDesktopProtocolEnabled` property to true for the Microsoft Remote Desktop and Windows Cloud Login applications, and configures the target device groups.
 
#Remember to run this script in the Azure Cloud Shell or a local PowerShell session where you're signed in with Azure PowerShell and your Azure context is set to the subscription you want to use. Also, make sure you've installed the Microsoft Graph PowerShell SDK.