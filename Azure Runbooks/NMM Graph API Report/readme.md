![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# NMM Graph API Report

This script is designed to generate a comprehensive report on the Microsoft 365 environment using the Microsoft Graph API.

## Prerequisites

Before running the script, ensure you have the following prerequisites:

1. **Managed Identities Azure Automation**:
   - Enable the managed identity in the Azure Automation account managed by NMM or feel free to create your own but keep in mind you need to run the script from there instead of NMM Runbooks.
   - Assign the necessary permissions to the managed identity. Use the code below to assign the necessary permissions to the managed identity.
    - Make sure you replace the $managedIdentityName with the name of your managed identity. You can find the Name if you navigate within a customer to Settings -> Azure -> Azure runbooks scripted actions and click the Enabled button, a screenshot will be shown with the name of the Automation Account.

```powershell

$TenantId = '000-000-0000-000' #Tenant ID M365 Environment

$managedIdentityName = "nmm-app-runbooks-06e6" #Name of the Managed Identity of the Automation Account.

Connect-MgGraph -Scopes Application.Read.All, AppRoleAssignment.ReadWrite.All -TenantId $TenantId #Authenticate with your Global Admin account or Application Administrator account

$permissions = @(
    "Reports.Read.All"
    "ReportSettings.Read.All"
    "User.Read.All"
    "Group.Read.All"
    "Mail.Read"
    "Mail.Send"
    "Calendars.Read"
    "Sites.Read.All"
    "Directory.Read.All"
    "RoleManagement.Read.Directory"
    "AuditLog.Read.All"
    "Organization.Read.All"
)

$managedIdentity = (Get-MgServicePrincipal -Filter "DisplayName eq '$managedIdentityName'")
$managedIdentityId = $managedIdentity.Id
$getPerms = (Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'").AppRoles | Where { $_.Value -in $permissions }
$graphAppId = (Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'").Id

foreach ($perm in $getPerms) {
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityId `
        -PrincipalId $managedIdentityId -ResourceId $graphAppId -AppRoleId $perm.id
}

```

2. **Graph API Permissions**:
   - Ensure the managed identity has the required permissions to access the Microsoft Graph API.
   - This script will automatically assign the necessary permissions to the managed identity.
   - You can verify the permissions in the Entra portal under Enterprise applications -> Managed identity name -> API permissions.
   - The following permissions are required:
     - Reports.Read.All
     - ReportSettings.Read.All
     - User.Read.All
     - Group.Read.All
     - Mail.Read
     - Mail.Send
     - Calendars.Read
     - Sites.Read.All
     - Directory.Read.All
     - RoleManagement.Read.Directory
     - AuditLog.Read.All
     - Organization.Read.All

3. **NMM Runbook**:
- Paste the contents of the M365Report script into a new runbook in NMM.
- Do a test run
- Set a schedule to run the runbook as needed.
