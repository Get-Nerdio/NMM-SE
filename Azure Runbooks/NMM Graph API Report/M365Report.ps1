<#
Version: 0.1
Author: Jan Scholte | Nerdio
Module Needed:

Microsoft.Graph.Authentication

Todo:
- Add more reports
- Create function for authentication support managed identity and interactive login
- Try to automatically configure the managed identity on th automation account and set the needed graph permissions on the managed identity
#>

#$TenantId = $EnvironmentalVars.TenantId #Tenant ID of the Azure AD
$TenantId = '000-000-000-000-000'

# Define the parameters for splatting
$params = @{
    Scopes   = @(
        "Reports.Read.All",
        "ReportSettings.Read.All",
        "User.Read.All",
        "Group.Read.All",
        "Mail.Read",
        "Mail.Send",
        "Calendars.Read",
        "Sites.Read.All",
        "Directory.Read.All",
        "RoleManagement.Read.Directory",
        "AuditLog.Read.All",
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

#Start of Report Functions
############################################################################################################
function DownloadLicenseDefinitions {
    [CmdletBinding()]
    param (
        [string]$CsvUrl = "https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"
    )

    try {
        Write-Output "Downloading CSV from URL: $CsvUrl"
        
        # Download the CSV content using Invoke-RestMethod
        $csvContent = Invoke-RestMethod -Uri $CsvUrl -Method Get -UseBasicParsing

        # Debug: Check content length
        Write-Output "CSV Content Length: $($csvContent.Length)"

        if ([string]::IsNullOrWhiteSpace($csvContent)) {
            Write-Warning "The CSV content is empty or could not be retrieved."
            return $null
        }

        # Convert CSV content to objects
        $csvData = $csvContent | ConvertFrom-Csv

        # Debug: Check if CSV was parsed correctly
        if ($null -eq $csvData -or $csvData.Count -eq 0) {
            Write-Warning "No data found in the CSV after conversion."
            return $null
        }
        else {
            Write-Output "CSV successfully converted. Total records: $($csvData.Count)"
        }

        # Initialize the list to store license definitions
        $licenseDefinitions = [System.Collections.Generic.List[PSObject]]::new()

        # Iterate through each row in the CSV and add to the list
        foreach ($row in $csvData) {
            $licenseDefinitions.Add($row)
        }

        #Write-Output "License definitions list created. Total items in list: $($licenseDefinitions.Count)"
        return $licenseDefinitions
    }
    catch {
        Write-Error "Error downloading or parsing the CSV: $_"
    }
}
function Get-LicenseDetails {
    [CmdletBinding(DefaultParameterSetName = 'LicenseID')]
    param (
        [Parameter(ParameterSetName = 'LicenseID', Mandatory = $true)]
        [string[]]$LicenseId,

        [Parameter(ParameterSetName = 'All', Mandatory = $true)]
        [switch]$All
    )

    # Fetch all licenses once
    $AllLicenses = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/subscribedSkus/" -OutputType PSObject).Value

    if ($PSCmdlet.ParameterSetName -eq 'LicenseID') {
        # List to store selected license names
        $licenseList = [System.Collections.Generic.List[Object]]::new()

        foreach ($license in $LicenseId) {
            # Find the matching license by skuId
            $MatchskuID = $AllLicenses | Where-Object { $_.skuId -eq $license }
            if ($MatchskuID) {
                # Get friendly license name using the LicenseConversionTable function
                $FriendlyLicName = LicenseConversionTable -LicenseId $MatchskuID.skuId
                if ($FriendlyLicName) {
                    $licenseList.Add($FriendlyLicName)
                }
                else {
                    $licenseList.Add($MatchskuID.skuPartNumber)
                }
            }
            else {
                Write-Warning "License ID $license not found in AllLicenses"
            }
        }

        return $licenseList
    }

    if ($PSCmdlet.ParameterSetName -eq 'All') {
        # Return all licenses
        return $AllLicenses
    }
}
function LicenseConversionTable {
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string]$licenseId
    )
    
    begin {
        try {
            # Attempt to retrieve license definitions using DownloadLicenseDefinitions
            if ($null -eq $licenseDefinitions) {
                $script:licenseDefinitions = DownloadLicenseDefinitions
            }
            else {
                Write-Verbose "License definitions already loaded from cache, $($licenseDefinitions.Count) records"
            }
            
            if ($null -eq $licenseDefinitions) {
                Write-Output "DownloadLicenseDefinitions returned null. Falling back to GitHub CSV retrieval."
                
                # Define repository details
                $repoOwner = "Get-Nerdio"
                $repoName = "NMM-SE"
                $filePath = "Azure Runbooks/NMM Graph API Report/LicenseConversionTable.csv"
                $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/contents/$filePath"
            
                # Send request to GitHub API and store the content in the begin block
                $response = Invoke-RestMethod -Uri $apiUrl -Headers @{Accept = "application/vnd.github.v3+json" }
            
                # Decode the base64-encoded content
                $encodedContent = $response.content
                $decodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedContent))
            
                # Convert the CSV content into a PowerShell object
                $script:licenseDefinitions = $decodedContent | ConvertFrom-Csv
                
                # Check if CSV was parsed correctly
                if ($null -eq $licenseDefinitions -or $licenseDefinitions.Count -eq 0) {
                    Write-Warning "No data found in the CSV after conversion from GitHub."
                    return $null
                }
                else {
                    Write-Output "CSV from GitHub successfully converted. Total records: $($licenseDefinitions.Count)" | Out-Null
                }
            }
            else {
                Write-Output "License definitions retrieved using DownloadLicenseDefinitions. Total records: $($licenseDefinitions.Count)" | Out-Null
            }
        }
        catch {
            Write-Error "Error fetching license definitions: $_"
            return $null
        }
    }

    process {
        try {
            if ($null -eq $licenseDefinitions) {
                Write-Warning "No license definitions available to process."
                return $null
            }

            # Find the matching GUID in the table for the current licenseId
            $matchedLicense = $licenseDefinitions | Where-Object { $_.GUID -eq $licenseId } | Select-Object -First 1

            if ($matchedLicense) {
                # Output the matching license name
                return $matchedLicense.Product_Display_Name
            }
            else {
                Write-Warning "License ID $licenseId not found in the license definitions."
                return $null
            }
        }
        catch {
            Write-Error "Error processing LicenseId $licenseId : $_"
        }
    }
}
function Get-AssignedRoleMembers {
    [CmdletBinding()]
    param()

    try {
        # Report on all users and their roles
        $roles = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/directoryRoles" -OutputType PSObject

        # Create a hashtable to store the user-role assignments
        $userRoles = @{}

        # Iterate over each role and get its members
        foreach ($role in $roles.value) {
            $roleId = $role.id
            $roleName = $role.displayName

            # Retrieve the members of the role
            $members = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members" -OutputType PSObject

            # Iterate through the members
            foreach ($member in $members.value) {
                # Ensure member properties are not null
                $userPrincipalName = if ($member.userPrincipalName) { $member.userPrincipalName } else { "N/A" }
                $displayName = if ($member.displayName) { $member.displayName } else { "N/A" }
                $id = if ($member.id) { $member.id } else { "N/A" }

                if ($userRoles.ContainsKey($userPrincipalName)) {
                    # Append the role to the existing user's Roles list
                    $userRoles[$userPrincipalName].Roles.Add($roleName)
                }
                else {
                    # Create a new user object with their roles (using List for Roles)
                    $userRoles[$userPrincipalName] = [PSCustomObject]@{
                        UserPrincipalName = $userPrincipalName
                        DisplayName       = $displayName
                        Id                = $id
                        Roles             = [System.Collections.Generic.List[string]]::new()
                    }
                    $userRoles[$userPrincipalName].Roles.Add($roleName)
                }
            }
        }

        # Convert hashtable values to a list and format roles as a comma-separated string
        $roleAssignments = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($user in $userRoles.Values) {
            $roleAssignments.Add([PSCustomObject]@{
                    UserPrincipalName = $user.UserPrincipalName
                    DisplayName       = $user.DisplayName
                    Id                = $user.Id
                    Roles             = ($user.Roles -join ", ")  # Convert list to a comma-separated string
                })
        }

        # Output the results
        if ($roleAssignments.Count -eq 0) {
            return [PSCustomObject]@{
                Info = "No role assignments found"
            }
        }
        else {
            return $roleAssignments
        }
    }
    catch {
        Write-Error "Error in Get-AssignedRoleMembers: $_"
    }
}
function Get-RecentAssignedRoleMembers {
    [CmdletBinding()]
    param()

    try {
        # Calculate the cutoff date for the last 30 days
        $cutoffDate = (Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        Write-Output "Fetching role assignments from the last 30 days..." | Out-Null

        # Define the filter for audit logs: activity is 'Add member to role' and within the last 30 days
        $filter = "activityDisplayName eq 'Add member to role' and activityDateTime ge $cutoffDate and result eq 'success'"
        $orderby = "activityDateTime desc"

        # Retrieve audit logs related to role assignments
        $auditLogs = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=$filter&`$orderby=$orderby&`$top=1000" -OutputType PSObject

        if ($null -eq $auditLogs -or $auditLogs.value.Count -eq 0) {
            Write-Output "No recent role assignments found in the last 30 days." | Out-Null
            return [PSCustomObject]@{
                Info = "No recent role assignments found."
            }
        }

        # Initialize the list to store recent role assignments
        $recentRoleAssignments = [System.Collections.Generic.List[PSObject]]::new()

        foreach ($log in $auditLogs.value) {
            try {
                # Extract the role name from the targetResources
                $roleName = ($log.targetresources.modifiedProperties | Where-Object { $_.DisplayName -eq 'Role.DisplayName' }).newvalue
                # Extract the role TemplateId
                $roleTemplateId = ($log.targetresources.modifiedProperties | Where-Object { $_.DisplayName -eq 'Role.TemplateId' }).newvalue
                # Extract the user who was assigned the role
                $assignedUser = ($log.targetResources | Where-Object { $_.type -eq "User" }).userPrincipalName
                # Extract the date of assignment
                $assignmentDate = $log.activityDateTime

                if ($null -ne $roleName -and $null -ne $assignedUser) {
                    # Create a PSCustomObject for each assignment
                    $roleAssignment = [PSCustomObject]@{
                        UserPrincipalName = $assignedUser
                        RoleName          = $roleName
                        AssignedDate      = $assignmentDate
                        RoleTemplateId    = $roleTemplateId
                    }

                    # Add to the list
                    $recentRoleAssignments.Add($roleAssignment)
                }
                else {
                    Write-Output "Incomplete information in audit log entry ID: $($log.id)" | Out-Null
                }
            }
            catch {
                Write-Error "Error processing audit log entry ID: $($log.id) - $_"
            }
        }

        # Remove duplicate assignments if any
        $uniqueRoleAssignments = $recentRoleAssignments | Sort-Object UserPrincipalName, RoleName, AssignedDate, RoleTemplateId -Unique

        # Output the results
        if ($uniqueRoleAssignments.Count -eq 0) {
            return [PSCustomObject]@{
                Info = "No recent role assignments found after processing audit logs."
            }
        }
        else {
            return $uniqueRoleAssignments
        }
    }
    catch {
        Write-Error "Error in Get-RecentAssignedRoleMembers: $_"
    }
}
function Get-InactiveUsers {
    [CmdletBinding()]
    param(
        [int]$DaysInactive = 30
    )

    try {
        # Calculate the cutoff date in UTC format
        $cutoffDate = (Get-Date).AddDays(-$DaysInactive).ToUniversalTime()
        $cutoffDateFormatted = $cutoffDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Retrieve users with last sign-in before the cutoff date
        $signIns = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/users?`$filter=signInActivity/lastSuccessfulSignInDateTime le $cutoffDateFormatted" -OutputType PSObject).value

        if ($null -eq $signIns -or $signIns.Count -eq 0) {
            return [PSCustomObject]@{
                Info = "No inactive users found"
            }
        }
        else {
            # Initialize the list to store inactive user details
            $inactiveUsers = [System.Collections.Generic.List[PSObject]]::new()

            foreach ($user in $signIns) {
                try {
                    # Initialize assigned licenses string and license end dates
                    $assignedLicensesString = "No Licenses Assigned"
                    $licenseEndDates = "No End Dates"
            
                    if ($user.assignedLicenses -and $user.assignedLicenses.skuid) {
                        # Initialize temporary lists to store license names and end dates
                        $licenseNames = [System.Collections.Generic.List[string]]::new()
                        $licenseEndDateList = [System.Collections.Generic.List[string]]::new()
            
                        foreach ($skuId in $user.assignedLicenses.skuid) {
                            # Retrieve license details
                            $licenseDetails = Get-LicenseDetails -LicenseId $skuId
                            if ($licenseDetails) {
                                # Split multiple display names if necessary and add to the list
                                $displayNames = $licenseDetails.Split(",")
                                foreach ($name in $displayNames) {
                                    $licenseNames.Add($name.Trim())
                                }
            
                                # Retrieve the end date for the license
                                $endDateObj = Get-LicenseEndDate -LicenseId $skuId
                                if ($endDateObj -and $endDateObj.EndDate) {
                                    $endDate = $endDateObj.EndDate
                                    $licenseEndDateList.Add("$licenseDetails : $endDate")
                                }
                                else {
                                    $licenseEndDateList.Add("$licenseDetails : N/A")
                                }
                            }
                            else {
                                Write-Warning "License ID $skuId could not be resolved."
                                $licenseNames.Add("Unknown License")
                                $licenseEndDateList.Add("Unknown License: N/A")
                            }
                        }
            
                        # Generate the comma-separated strings
                        if ($licenseNames.Count -gt 0) {
                            $assignedLicensesString = ($licenseNames | Sort-Object -Unique) -join ", "
                        }
            
                        if ($licenseEndDateList.Count -gt 0) {
                            $licenseEndDates = $licenseEndDateList -join ", "
                        }
                    }
            
                    # Create the inactive user object with safe property assignments
                    $inactiveUser = [PSCustomObject]@{
                        DisplayName       = if ($user.displayName) { $user.displayName } else { "N/A" }
                        UserPrincipalName = if ($user.userPrincipalName) { $user.userPrincipalName } else { "N/A" }
                        Id                = if ($user.id) { $user.id } else { "N/A" }
                        AssignedLicenses  = $assignedLicensesString
                        LicenseEndDate    = $licenseEndDates
                        UsageLocation     = if ($user.usageLocation) { $user.usageLocation } else { "N/A" }
                        AccountEnabled    = if ($user.accountEnabled -ne $null) { $user.accountEnabled } else { $false }
                    }
            
                    # Add the inactive user to the list
                    $inactiveUsers.Add($inactiveUser)
                }
                catch {
                    Write-Error "Error processing user $($user.userPrincipalName): $_"
                }
            }

            # Return the inactive users list or an info message if empty
            if ($inactiveUsers.Count -eq 0) {
                return [PSCustomObject]@{
                    Info = "No inactive users found after processing."
                }
            }
            else {
                return $inactiveUsers
            }
        }

    }
    catch {
        Write-Error "Error in Get-InactiveUsers: $_"
    }
}
function Get-LatestCreatedUsers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [int]$days = 30  # Number of days to look back for created users
    )

    try {
        # Calculate the cutoff date for the specified number of days
        $cutoffDate = (Get-Date).AddDays(-$days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        Write-Output "Fetching users created in the last $days days (since $cutoffDate)..." | Out-Null

        # Define the filter for users created in the last $days days without quotes
        $filter = "createdDateTime ge $cutoffDate"

        # Initialize the list to store the latest created users
        $latestCreatedUsers = [System.Collections.Generic.List[PSObject]]::new()

        # Define the properties to select
        $selectProperties = "displayName,givenName,surname,userPrincipalName,createdDateTime,department,jobTitle,usageLocation,id"

        # Initialize the URI with the filter and select parameters without $orderby
        $uri = "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=$selectProperties&`$top=999"

        # Retrieve users in batches (handling pagination)
        do {
            $response = Invoke-MgGraphRequest -Uri $uri -OutputType PSObject

            if ($null -eq $response -or $null -eq $response.value) {
                Write-Warning "No users found matching the criteria."
                break
            }

            foreach ($user in $response.value) {
                # Create a PSCustomObject with the desired user properties
                $userDetails = [PSCustomObject][Ordered]@{
                    displayName       = if ($user.displayName) { $user.displayName } else { "N/A" }
                    givenName         = if ($user.givenName) { $user.givenName } else { "N/A" }
                    surname           = if ($user.surname) { $user.surname } else { "N/A" }
                    userPrincipalName = if ($user.userPrincipalName) { $user.userPrincipalName } else { "N/A" }
                    mail              = if ($user.mail) { $user.mail } else { "N/A" }
                    department        = if ($user.department) { $user.department } else { "N/A" }
                    jobTitle          = if ($user.jobTitle) { $user.jobTitle } else { "N/A" }
                    usageLocation     = if ($user.usageLocation) { $user.usageLocation } else { "N/A" }
                    officeLocation    = if ($user.officeLocation) { $user.officeLocation } else { "N/A" }
                    preferredLanguage = if ($user.preferredLanguage) { $user.preferredLanguage } else { "N/A" }
                    createdDateTime   = if ($user.createdDateTime) { $user.createdDateTime } else { "N/A" }
                    id                = if ($user.id) { $user.id } else { "N/A" }
                }

                # Add the user details to the list
                $latestCreatedUsers.Add($userDetails)
            }

            # Check for nextLink for pagination
            if ($response.'@odata.nextLink') {
                $uri = $response.'@odata.nextLink'
            }
            else {
                $uri = $null
            }

        } while ($uri -ne $null)

        # Sort the users by CreatedDateTime in descending order locally
        $sortedUsers = $latestCreatedUsers | Sort-Object -Property createdDateTime -Descending

        # Output the results
        if ($sortedUsers.Count -eq 0) {
            return [PSCustomObject]@{
                Info = "No users created in the last $days days."
            }
        }
        else {
            return $sortedUsers
        }
    }
    catch {
        Write-Error "Error in Get-LatestCreatedUsers: $_"
    }
}
function Get-UnusedLicenses {
    # Retrieve all licenses
    $AllLicenses = Get-LicenseDetails -All

    # List to store the results
    $UnusedLicensesList = [System.Collections.Generic.List[Object]]::new()

    # Loop through each license
    foreach ($license in $AllLicenses) {
        # Calculate unused licenses
        $prepaidEnabled = $license.prepaidUnits.enabled
        $consumedUnits = $license.consumedUnits
        $unusedUnits = $prepaidEnabled - $consumedUnits

        # Only process if there are unused units
        if ($unusedUnits -gt 0) {
            # Get the friendly license name using LicenseConversionTable
            $friendlyName = LicenseConversionTable -LicenseId $license.skuId

            
            # Create a PSCustomObject for each license with unused units
            $licenseObject = [PSCustomObject]@{
                AccountName    = $license.accountName
                AccountId      = $license.accountId
                SkuPartNumber  = $license.skuPartNumber
                SkuId          = $license.skuId
                LicenseEndDate = (Get-LicenseEndDate -LicenseId $license.skuId).EndDate
                FriendlyName   = $friendlyName
                PrepaidUnits   = $prepaidEnabled
                ConsumedUnits  = $consumedUnits
                UnusedUnits    = $unusedUnits
                AppliesTo      = $license.appliesTo
            }

            # Add to the result list
            $UnusedLicensesList.add($licenseObject)
        }
    }

    # Return the list of unused licenses
    if ($UnusedLicensesList.Count -eq 0) {
        return [PSCustomObject]@{
            Info = "No unused licenses found"
        }
    }
    else {
        return $UnusedLicensesList
    }
}
function Get-RecentEnterpriseAppsAndRegistrations {
    try {
        # Calculate the date for 30 days ago
        $dateThreshold = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Get enterprise applications (service principals)
        $enterpriseApps = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" -OutputType PSObject
        $recentEnterpriseApps = $enterpriseApps.value | Where-Object { $_.createdDateTime -ge $dateThreshold }

        # Get app registrations (applications)
        $appRegistrations = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/applications" -OutputType PSObject
        $recentAppRegistrations = $appRegistrations.value | Where-Object { $_.createdDateTime -ge $dateThreshold }

        # Combine results into a single list
        $recentApps = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($app in $recentEnterpriseApps) {
            $recentApps.Add([PSCustomObject]@{
                    AppType         = "Enterprise Application"
                    AppId           = $app.appId
                    DisplayName     = $app.displayName
                    CreatedDateTime = $app.createdDateTime
                })
        }

        foreach ($app in $recentAppRegistrations) {
            $recentApps.Add([PSCustomObject]@{
                    AppType         = "App Registration"
                    AppId           = $app.appId
                    DisplayName     = $app.displayName
                    CreatedDateTime = $app.createdDateTime
                })
        }

        # Return the list of recent apps
        if ($recentApps.Count -eq 0) {
            return [PSCustomObject]@{
                Info = "No recent apps found"
            }
        }
        else {
            return $recentApps
        }
    }
    catch {
        $_.Exception.Message
    }
}
function Get-RecentGroupsAndAddedMembers {
    try {
        # Calculate the date for 30 days ago
        $dateThreshold = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Get groups created in the last 30 days
        $groups = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups" -OutputType PSObject
        $recentGroups = $groups.value | Where-Object { $_.createdDateTime -ge $dateThreshold }

        # Get all "Add member to group" actions from audit logs in the last 30 days
        $auditLogs = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Add member to group' and activityDateTime ge $dateThreshold and result eq 'success'&`$orderby=activityDateTime desc" -OutputType PSObject

        # Create a list to store the group details and recent members
        $groupDetails = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($group in $recentGroups) {
            $groupId = $group.id
            $groupName = $group.displayName

            # Create a list to store recent members
            $recentMembers = [System.Collections.Generic.List[string]]::new()

            foreach ($log in $auditLogs.value) {
                
                $groupObjectId = ($log.targetResources.modifiedProperties | Where-Object { $_.displayName -eq "Group.ObjectID" } | Select-Object -ExpandProperty newValue) -replace '"', ''

                if ($groupObjectId -eq $groupId) {
                    # Extract the userPrincipalName for the user added to the group
                    $user = $log.targetResources | Where-Object { $_.type -eq "User" }
                    if ($user) {
                        $recentMembers.Add($user.userPrincipalName)
                    }
                }
            }

            # Prepare a comma-separated string of recent members' names
            $recentMemberNames = $recentMembers -join ", "

            # Add group details with recent members to the list
            $groupDetails.Add([PSCustomObject]@{
                    GroupName       = $groupName
                    GroupId         = $groupId
                    CreatedDateTime = $group.createdDateTime
                    RecentMembers   = if ($recentMemberNames) { $recentMemberNames } else { "No recent members" }
                })
        }

        # Output the results
        if ($groupDetails.Count -eq 0) {
            return [PSCustomObject]@{
                Info = "No recent groups found"
            }
        }
        else {
            return $groupDetails
        }
    }
    catch {
        $_.Exception.Message
    }
}
function Get-RecentDevices {
    try {
        # Calculate the date for 30 days ago
        $dateThreshold = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Get devices added in the last 30 days
        $devices = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/devices" -OutputType PSObject
        $recentDevices = $devices.value | Where-Object { $_.createdDateTime -ge $dateThreshold }

        # Create a list to store the recent devices
        $deviceDetails = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($device in $recentDevices) {
            # Add device details to the list
            $deviceDetails.Add([PSCustomObject]@{
                    DisplayName      = $device.displayName    
                    DeviceId         = $device.id
                    OperatingSystem  = "$($device.operatingSystem) - $($device.operatingSystemVersion)"
                    CreatedDateTime  = $device.createdDateTime
                    TrustType        = $device.deviceTrustType
                    RegistrationDate = $device.registeredDateTime
                })
        }

        if ($deviceDetails.Count -eq 0) {
            return [PSCustomObject]@{
                Info = "No recent devices found"
            }
        }
        else {
            return $deviceDetails
        } 
    }
    catch {
        Write-Error "Error retrieving devices: $_"
    }
}
function Get-LicensedUsers {
    [CmdletBinding()]
    param ()

    try {
        # Initialize the list to store user details
        $licensedUsers = [System.Collections.Generic.List[PSObject]]::new()

        $selectedProperties = @(
            "displayName",
            "givenName",
            "surname",
            "department",
            "jobTitle",
            "mail",
            "officeLocation",
            "preferredLanguage",
            "userPrincipalName",
            "id",
            "assignedLicenses"
        ) -join ','

        $headers = @{
            'ConsistencyLevel' = 'eventual'
        }

        # Get all users with assigned licenses
        $users = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/users?`$filter=assignedLicenses/`$count ne 0&`$count=true&`$select=$selectedProperties" -Headers $headers -OutputType PSObject

        # Use ForEach-Object for handling large collections efficiently
        $users.value | ForEach-Object {
            try {
                # Ensure assignedLicenses and skuid are not null
                if ($_.assignedLicenses -and $_.assignedLicenses.skuid) {
                    # Handle multiple skuid values
                    $assignedLicenses = $_.assignedLicenses.skuid | ForEach-Object {
                        $licenseDetails = Get-LicenseDetails -LicenseId $_
                        if ($licenseDetails) {
                            $licenseDetails.Split(",")
                        }
                        else {
                            Write-Warning "License ID $_ could not be resolved."
                            @("Unknown License")
                        }
                    } | Select-Object -Unique

                    $assignedLicensesString = $assignedLicenses -join ", "
                }
                else {
                    $assignedLicensesString = "No Licenses Assigned"
                }

                # Pre-calculate the license end dates and join them with a comma
                $licenseEndDates = ($_.assignedLicenses.skuid | ForEach-Object {
                        $licenseDetails = Get-LicenseDetails -LicenseId $_
                        $endDate = (Get-LicenseEndDate -LicenseId $_).EndDate
                        "$licenseDetails : $endDate"
                    }) -join ", "

                $userDetails = [PSCustomObject][Ordered]@{
                    displayName       = $_.displayName
                    givenName         = $_.givenName
                    surname           = $_.surname
                    userPrincipalName = $_.userPrincipalName
                    mail              = $_.mail
                    assignedLicenses  = $assignedLicensesString
                    licenseEndDate    = $licenseEndDates
                    department        = $_.department
                    location          = $_.usageLocation
                    jobTitle          = $_.jobTitle
                    officeLocation    = $_.officeLocation
                    preferredLanguage = $_.preferredLanguage
                }

                $licensedUsers.Add($userDetails)
            }
            catch {
                Write-Error "Error processing user $($_.userPrincipalName): $_"
            }
        }

        if ($licensedUsers.Count -eq 0) {
            return [PSCustomObject]@{
                Info = "No licensed users found"
            }
        }
        else {
            return $licensedUsers
        }
    }
    catch {
        Write-Error "Error retrieving licensed user details: $_"
    }
}
function Get-LicenseEndDate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$LicenseIds
    )

    try {
        # Initialize the list to store license end dates
        $licenseEndDates = [System.Collections.Generic.List[PSObject]]::new()

        # Define the API endpoint
        $uri = "https://graph.microsoft.com/V1.0/directory/subscriptions"

        # Invoke the Graph API request to retrieve all subscriptions
        $subscriptionsResponse = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject

        if ($subscriptionsResponse -and $subscriptionsResponse.value -and $subscriptionsResponse.value.Count -gt 0) {
            # Iterate through each LicenseId provided
            foreach ($licenseId in $LicenseIds) {
                # Find subscription(s) matching the LicenseId
                $matchedSubscriptions = $subscriptionsResponse.value | Where-Object { $_.skuId -eq $licenseId }

                if ($matchedSubscriptions -and $matchedSubscriptions.Count -gt 0) {
                    foreach ($sub in $matchedSubscriptions) {
                        # Extract nextLifecycleDateTime and format it
                        $endDate = if ($sub.nextLifecycleDateTime) {
                            [datetime]::Parse($sub.nextLifecycleDateTime).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                        }
                        else {
                            "N/A"
                        }

                        # Create PSObject with LicenseId and EndDate
                        $licenseEndDate = [PSCustomObject]@{
                            LicenseId = $licenseId
                            EndDate   = $endDate
                        }

                        # Add to the list
                        $licenseEndDates.Add($licenseEndDate)
                    }
                }
                else {
                    Write-Output "License ID $licenseId not found in Subscriptions"

                    # Create PSObject with LicenseId and default EndDate
                    $licenseEndDate = [PSCustomObject]@{
                        LicenseId = $licenseId
                        EndDate   = "N/A"
                    }

                    # Add to the list
                    $licenseEndDates.Add($licenseEndDate)
                }
            }

            return $licenseEndDates
        }
        else {
            Write-Warning "No subscriptions data retrieved from the API."
            return [PSCustomObject]@{
                Info = "No subscriptions data available."
            }
        }
    }
    catch {
        Write-Error "Error in Get-LicenseEndDate: $_"
    }
}
function Get-ConditionalAccessPolicyModifications {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [int]$Days = 30  # Number of days to look back for policy modifications
    )

    try {
        # Calculate the cutoff date for the specified number of days
        $cutoffDate = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        Write-Verbose "Fetching Conditional Access Policy modifications in the last $Days days (since $cutoffDate)..."

        # Define the filter for Conditional Access Policy modification activities
        # Ensure activityDisplayName matches exactly with the audit log entries (case and spacing)
        $filter = " (activityDisplayName eq 'Add conditional access policy' or activityDisplayName eq 'Update conditional access policy' or activityDisplayName eq 'Delete conditional access policy') and activityDateTime ge $cutoffDate "

        # Initialize the list to store policy modification events
        $policyModifications = [System.Collections.Generic.List[PSObject]]::new()

        # Define the URI with the corrected filter, ordering, and pagination
        $uri = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=$($filter)&`$orderby=activityDateTime desc&`$top=999"

        # Retrieve audit logs in batches (handling pagination)
        do {
            $response = Invoke-MgGraphRequest -Uri $uri -OutputType PSObject

            if ($null -eq $response -or $null -eq $response.value) {
                Write-Warning "No Conditional Access Policy modifications found in the last $Days days."
                break
            }

            foreach ($log in $response.value) {
                try {
                    
                    # Extract the user who performed the modification using a switch statement
                    $initiatedByUser = switch ($true) {
                        { $log.initiatedBy.user.userPrincipalName } { 
                            $log.initiatedBy.user.userPrincipalName; break
                        }
                        { $log.initiatedBy.app.displayName } {
                            $log.initiatedBy.app.displayName; break
                        }
                        default {
                            "Unknown"
                        }
                    }


                    # Get the IP Address of the user using a switch statement
                    $ipAddress = switch ($true) {
                        { $log.initiatedBy.user.ipAddress } { 
                            $log.initiatedBy.user.ipAddress; break
                        }
                        { $log.initiatedBy.app.ipAddress } {
                            $log.initiatedBy.app.ipAddress; break
                        }
                        default {
                            "Unknown"
                        }
                    }
                    

                    # Extract the target resource details
                    #$caPolicyResource = $log.targetResources | Where-Object { $_.type -eq "ConditionalAccessPolicy" }

                    $newValue = $log.targetResources.modifiedProperties.newValue | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $oldValue = $log.targetResources.modifiedProperties.oldValue | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $diff = if ($null -ne $oldValue -and $null -ne $newValue) { 
                        Compare-Object -ReferenceObject $oldValue -DifferenceObject $newValue -Property displayName, id, state, conditions, grantControls, sessionControls 
                    }
                    else { 
                        "No changes" 
                    }

                    # Create a PSCustomObject with the desired properties
                    $modificationDetails = [PSCustomObject][Ordered]@{
                        InitiatedBy         = $initiatedByUser
                        IpAddress           = $ipAddress
                        ActivityDisplayName = $log.activityDisplayName
                        ActivityDateTime    = $log.activityDateTime
                        PolicyName          = if ($newValue.displayName) { $newValue.displayName } else { "N/A" }
                        PolicyId            = if ($newValue.id) { $newValue.id } else { "N/A" }
                        State               = if ($newValue.state) { $newValue.state } else { "N/A" }
                        Differences         = $diff
                        Result              = $log.result
                        OperationType       = $log.operationType
                    }

                    # Add the modification details to the list
                    $policyModifications.Add($modificationDetails)
                }
                catch {
                    Write-Error "Error processing audit log entry ID: $($log.id) - $_"
                }
            }

            # Check for nextLink for pagination
            if ($response.'@odata.nextLink') {
                $uri = $response.'@odata.nextLink'
            }
            else {
                $uri = $null
            }

        } while ($uri -ne $null)

        # Sort the modifications by ActivityDateTime in descending order locally
        $sortedModifications = $policyModifications | Sort-Object -Property ActivityDateTime -Descending

        # Output the results
        if ($sortedModifications.Count -eq 0) {
            return @()  # Return an empty array if no modifications found
        }
        else {
            return $sortedModifications
        }
    }
    catch {
        $_ | Out-File -FilePath ".\ErrorLog.txt" -Append
        Write-Error "Error in Get-ConditionalAccessPolicyModifications: $_"
        return @()  # Return an empty array on error
    }
}
function ConvertTo-ObjectToHtmlTable {
    param (
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[Object]]$Objects
    )

    $sb = [System.Text.StringBuilder]::new()

    # Start the HTML table with the 'rounded-table' class
    [void]$sb.Append('<table class="rounded-table">')
    [void]$sb.Append('<thead><tr>')

    # Add column headers based on the properties of the first object
    $Objects[0].PSObject.Properties.Name | ForEach-Object {
        [void]$sb.Append("<th>$_</th>")
    }

    [void]$sb.Append('</tr></thead><tbody>')

    # Add table rows with alternating row colors handled by CSS
    foreach ($obj in $Objects) {
        [void]$sb.Append("<tr>")
        foreach ($prop in $obj.PSObject.Properties.Name) {
            # Include 'data-label' for responsive design
            [void]$sb.Append("<td data-label='$prop'>$($obj.$prop)</td>")
        }
        [void]$sb.Append('</tr>')
    }

    [void]$sb.Append('</tbody></table>')
    return $sb.ToString()
}
function GenerateReport {
    param (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$dataSets, # Accepts multiple datasets, each with a title

        [Parameter(Mandatory = $false)]
        [switch]$json,

        [Parameter(Mandatory = $false)]
        [switch]$psObject,

        [Parameter(Mandatory = $false)]
        [switch]$RawHTML,

        [Parameter(Mandatory = $false)]
        [switch]$Html,

        [Parameter(Mandatory = $false)]
        [string]$htmlOutputPath = "Report.html",

        [Parameter(Mandatory = $false)]
        [string]$logoUrl = "https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf",

        [Parameter(Mandatory = $false)]
        [string]$summaryText = "This report shows information about your Microsoft 365 environment.",

        [Parameter(Mandatory = $false)]
        [string]$fontFamily = "Roboto"  # Allow user to specify a custom font family
    )

    begin {
        # Initialize a string builder for HTML content
        $htmlContent = [System.Text.StringBuilder]::new()
    }

    process {
        # Create a header section with the logo, summary, and font for HTML output
        if ($Html -or $RawHTML) {
            [void]$htmlContent.Append("<!DOCTYPE html>")
            [void]$htmlContent.Append("<html>")
            [void]$htmlContent.Append("<head>")
            [void]$htmlContent.Append("<meta charset='UTF-8'>")
            [void]$htmlContent.Append("<meta name='viewport' content='width=device-width, initial-scale=1.0'>")
            [void]$htmlContent.Append("<title>Microsoft 365 Tenant Report</title>")
            [void]$htmlContent.Append("<style>")
            # Existing Styles
            [void]$htmlContent.Append("body { font-family: '$fontFamily', sans-serif; background-color: #f4f7f6; margin: 0; padding: 0; }")
            [void]$htmlContent.Append("h2 { color: #FFFFFF; margin: 10px; }")
            [void]$htmlContent.Append("h3 { color: #151515; margin-top: 30px; margin-bottom: 10px; }")
            [void]$htmlContent.Append(".report-header { background-color: #13ba7c; color: white; padding: 20px 0; text-align: center; }")
            [void]$htmlContent.Append(".report-header img { width: 150px; height: auto; }")
            [void]$htmlContent.Append(".content { font-family: '$fontFamily', sans-serif; padding: 20px; }")
            
            # Accordion Styles
            [void]$htmlContent.Append("
                /* Accordion Styles */
                details {
                    margin-bottom: 10px;
                }

                summary {
                    cursor: pointer;
                    font-weight: bold;
                    padding: 10px;
                    background-color: #f2f2f2;
                    border: 1px solid #ddd;
                    border-radius: 5px;
                }

                summary::-webkit-details-marker {
                    display: none;
                }

                /* Enhanced CSS for Rounded Tables */
                table.rounded-table {
                    width: 100%;
                    border-collapse: separate; /* Allows border-radius to work */
                    border-spacing: 0;
                    border: 1px solid #ddd;
                    border-radius: 8px; /* Rounded corners */
                    overflow: hidden; /* Ensures child elements don't overflow the rounded corners */
                    margin-bottom: 20px;
                    font-family: 'Inter', sans-serif;
                }
                table.rounded-table thead tr {
                    background-color: #13ba7c;
                    color: white;
                }
                table.rounded-table th,
                table.rounded-table td {
                    border: 1px solid #ddd;
                    padding: 12px;
                    text-align: left;
                }
                table.rounded-table tbody tr:nth-child(even) {
                    background-color: #f9f9f9;
                }
                table.rounded-table tbody tr:nth-child(odd) {
                    background-color: #ffffff;
                }
                /* Optional: Add hover effect */
                table.rounded-table tbody tr:hover {
                    background-color: #f1f1f1;
                }

                /* Responsive Design */
                @media (max-width: 768px) {
                    table.rounded-table thead {
                        display: none;
                    }
                    table.rounded-table, 
                    table.rounded-table tbody, 
                    table.rounded-table tr, 
                    table.rounded-table td {
                        display: block;
                        width: 100%;
                    }
                    table.rounded-table tr {
                        margin-bottom: 15px;
                    }
                    table.rounded-table td {
                        text-align: right;
                        padding-left: 50%;
                        position: relative;
                    }
                    table.rounded-table td::before {
                        content: attr(data-label);
                        position: absolute;
                        left: 0;
                        width: 50%;
                        padding-left: 15px;
                        font-weight: bold;
                        text-align: left;
                    }
                }
            ")
            [void]$htmlContent.Append("</style>")
            [void]$htmlContent.Append("</head>")
            [void]$htmlContent.Append("<body>")

            # Add a header section with a logo and summary text
            [void]$htmlContent.Append("<div class='report-header'>")
            [void]$htmlContent.Append("<img src='$logoUrl' alt='Logo' /><br/>")
            [void]$htmlContent.Append("<h2>Microsoft 365 Tenant Report</h2>")
            [void]$htmlContent.Append("<p>$summaryText</p>")
            [void]$htmlContent.Append("</div>")

            [void]$htmlContent.Append("<div class='content'>")
        }

        # Iterate through the datasets in the hashtable
        foreach ($key in $dataSets.Keys) {
            $sectionTitle = $key   # The title for the section is the hashtable key
            $data = $dataSets[$key]  # The data for this section is the hashtable value
            $itemCount = if ($data.PSObject.Properties.Name -eq 'Info') { 0 } else { $data.Count }


             

            if ($Html -or $RawHTML) {
                # Wrap each table section within <details> and <summary> for collapsible functionality
                [void]$htmlContent.Append("<details>")
                [void]$htmlContent.Append("<summary>$sectionTitle ($itemCount)</summary>")
                [void]$htmlContent.Append((ConvertTo-ObjectToHtmlTable -Objects $data))  # Convert the data to an HTML table
                [void]$htmlContent.Append("</details>")
            }
        }

        # HTML Output: Close the content section and body
        if ($Html) {
            [void]$htmlContent.Append("</div></body></html>")
            $htmlContentString = $htmlContent.ToString()
            Set-Content -Path $htmlOutputPath -Value $htmlContentString
            Write-Output "HTML report generated at: $htmlOutputPath"
        }

        # Raw HTML Output
        if ($RawHTML) {
            [void]$htmlContent.Append("</div></body></html>")
            $htmlContentString = $htmlContent.ToString()
            return $htmlContentString
        }

        # JSON Output
        if ($json) {
            return $dataSets | ConvertTo-Json
        }

        # PSObject Output
        if ($psObject) {
            return $dataSets
        }
    }
}
function Send-EmailWithGraphAPI {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Recipient, # The recipient's email address

        [Parameter(Mandatory = $true)]
        [string]$Subject, # The subject of the email

        [Parameter(Mandatory = $true)]
        [string]$HtmlBody, # The HTML content to send

        [Parameter(Mandatory = $false)]
        [switch]$Attachment, # Switch to attach the HTML content as a file

        [Parameter(Mandatory = $false)]
        [string]$Sender = "me"  # Use "me" for the authenticated user, or specify another sender
    )

    try {
        # Create the email payload with correct emailAddress structure
        $emailPayload = @{
            message         = @{
                subject      = $Subject
                body         = @{
                    contentType = "HTML"
                    content     = $HtmlBody
                }
                toRecipients = @(@{
                        emailAddress = @{
                            address = $Recipient
                        }
                    })
            }
            saveToSentItems = "true"
        }

        # If the -Attachment parameter is set, attach the HTML content as a file
        if ($Attachment) {
            # Convert the HTML body content to base64
            $htmlFileBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($HtmlBody))

            # Add the attachment to the email payload
            $emailPayload.message.attachments = @(@{
                    '@odata.type' = "#microsoft.graph.fileAttachment"
                    name          = "Report.html"
                    contentType   = "text/html"
                    contentBytes  = $htmlFileBase64
                })
        }

        # Convert the payload to JSON with increased depth
        $jsonPayload = $emailPayload | ConvertTo-Json -Depth 10

        # Send the email using Microsoft Graph API
        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/$Sender/sendMail" `
            -Method POST `
            -Body $jsonPayload `
            -ContentType "application/json"
                              
        Write-Host "Email sent successfully to $Recipient"
    }
    catch {
        Write-Error "Error sending email: $_"
    }
}

#End of Report Functions
############################################################################################################

# Save Data in Vars
$unusedLicenses = Get-UnusedLicenses
$AssignedRoles = Get-AssignedRoleMembers
$recentRoleAssignments = Get-RecentAssignedRoleMembers
$AppsAndRegistrations = Get-RecentEnterpriseAppsAndRegistrations
$GroupsAndMembers = Get-RecentGroupsAndAddedMembers
$recentDevices = Get-RecentDevices
$licensedUsers = Get-LicensedUsers
$latestCreatedUsers = Get-LatestCreatedUsers
$inactiveUsers = Get-InactiveUsers
$conditionalAccessPolicyModifications = Get-ConditionalAccessPolicyModifications





# Create a hashtable where the keys are the section titles and the values are the datasets
$dataSets = @{
    "Unused Licenses"                         = $unusedLicenses
    "AssignedRoles"                           = $AssignedRoles
    "Recent Role Assignments"                 = $recentRoleAssignments
    "Enterprise App Registrations"            = $AppsAndRegistrations
    "Recent Groups and Members"               = $GroupsAndMembers
    "Recent Devices"                          = $recentDevices
    "Licensed Users"                          = $licensedUsers
    "Latest Created Users"                    = $latestCreatedUsers
    "Inactive Users"                          = $inactiveUsers
    "Conditional Access Policy Modifications" = $conditionalAccessPolicyModifications
    
}

# Generate the HTML report and send it via email
$htmlcontent = GenerateReport -DataSets $dataSets -RawHTML -Html -HtmlOutputPath ".\M365Report-NMM.html"

#Mail sned is still if you auth with a user, so no mail send from Runbook yet.
Send-EmailWithGraphAPI -Recipient "test@msp.com" -Subject "M365 Report - $(Get-Date -Format "yyyy-MM-dd")" -HtmlBody ($htmlContent | Out-String) -Attachment


#Todo: 
# - Setup with azure communication service or appsreg for email send.




