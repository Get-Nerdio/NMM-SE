<#
Graph Permissions Needed:

- Reports.Read.All
- Directory.Read.All

Todo:
- Mail send setup
#>



#$TenantId = $EnvironmentalVars.TenantId #Tenant ID of the Azure AD
$TenantId = '9f563539-3e60-4e96-aff7-915a7b66fb7a'

# Define the parameters for splatting
$params = @{
    Scopes   = @(
        "Reports.Read.All",
        "ReportSettings.Read.All",
        "User.Read.All",
        "Group.Read.All",
        "Mail.Read",
        "Calendars.Read",
        "Sites.Read.All",
        "Directory.Read.All"
        "RoleManagement.Read.Directory"
        "AuditLog.Read.All"
        "Organization.Read.All"
    )
    TenantId = $TenantId
}


try {
    #Connect to MS Graph
    Connect-MgGraph @params
}
catch {
    $_.Exception.Message
}


############################################################################################################

function GetLicenseDetails {
    param (
        [string[]]$LicenseId
    )
    $licenseList = [System.Collections.Generic.List[Object]]::new()
    $AllLicenses = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/subscribedSkus/" -OutputType PSObject).Value

    foreach ($license in $LicenseId) {
        
        $MatchskuID = $AllLicenses | Where-Object { $_.skuId -eq $license }
        $licenseList.Add($MatchskuID)
    }

    return $licenseList
}

function Get-AssignedRoleMembers {
    
    try {
        #Report on all users and their roles
        $roles = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/directoryRoles"

        # Create an empty list to store the role assignments
        $roleAssignments = [System.Collections.Generic.List[Object]]::new()
 
        # Iterate over each role and get its members
        foreach ($role in $roles.value) {
            $roleId = $role.id
            $roleName = $role.displayName
 
            # Retrieve the members of the role
            $members = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members"
 
            # Iterate through the members and create a custom object for each
            foreach ($member in $members.value) {
         
                # Create a PSCustomObject to store the role assignment information
                $roleAssignment = [PSCustomObject]@{
                    RoleName          = $roleName
                    UserPrincipalName = $member.userPrincipalName
                    DisplayName       = $member.displayName
                    Id                = $member.id
                }
 
                # Add the custom object to the array
                $roleAssignments.Add($roleAssignment)
            }
        }
 
        #Output the results
        return $roleAssignments
    }
    catch {
        $_.Exception.Message
    } 
   
}

function Get-InactiveUsers {
    param(
        [int]$DaysInactive = 30
    )

    try {
        # Get the date 30 days ago in UTC format and format it as required
        $cutoffDate = (Get-Date).AddDays(-$DaysInactive).ToUniversalTime()
        $cutoffDateFormatted = $cutoffDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Get users whose last sign-in is before the cutoff date
        $signIns = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/users?`$filter=signInActivity/lastSuccessfulSignInDateTime ge $cutoffDateFormatted" -OutputType PSObject).value

        if ($null -eq $signIns) {
            return "No inactive users found"
        }
        else {
            # Process the results to identify inactive users
            $inactiveUsers = [System.Collections.Generic.List[Object]]::new()

            foreach ($user in $signIns) {
                $inactiveUser = [PSCustomObject]@{
                    DisplayName       = $user.displayName
                    UserPrincipalName = $user.userPrincipalName
                    Id                = $user.id
                    #LastSignIn        = $user.signInActivity.lastSuccessfulSignInDateTime
                    AssignedLicenses = ((GetLicenseDetails -LicenseId $user.assignedLicenses.skuId).skuPartNumber).Split(",")
                    UsageLocation     = $user.usageLocation
                    AccountEnabled    = $user.accountEnabled
                }

                # Add to the inactive users list
                $inactiveUsers.Add($inactiveUser)
            }

            # Return the list of inactive users
            return $inactiveUsers
        }
        
    }
    catch {
        $_.Exception.Message
    }
}

