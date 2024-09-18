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
$TenantId = '9f563539-3e60-4e96-aff7-915a7b66fb7a'

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
                $licenseList.Add($FriendlyLicName)
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
        [string]$LicenseId
    )
    
    begin {
        try {
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
            $allConvertedLicense = $decodedContent | ConvertFrom-Csv
        }
        catch {
            Write-Error "Error fetching or decoding the CSV file: $_"
        }
    }

    process {
        try {
            # Find the matching GUID in the table for the current LicenseId
            $matchedLicense = $allConvertedLicense | Where-Object { $_.GUID -eq $LicenseId } | Select-Object -First 1

            # Output the matching license
            return $matchedLicense.Product_Display_Name
        }
        catch {
            Write-Error "Error processing LicenseId $LicenseId : $_"
        }
    }
}
function Get-AssignedRoleMembers {
    
    try {
        # Report on all users and their roles
        $roles = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/directoryRoles"

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
                $userPrincipalName = $member.userPrincipalName
                $displayName = $member.displayName
                $id = $member.id

                # If the user is already in the hashtable, append the role using .Add()
                if ($userRoles.ContainsKey($userPrincipalName)) {
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
        $roleAssignments = $userRoles.Values | ForEach-Object {
            [PSCustomObject]@{
                UserPrincipalName = $_.UserPrincipalName
                DisplayName       = $_.DisplayName
                Id                = $_.Id
                Roles             = ($_.Roles -join ", ")  # Convert list to a comma-separated string
            }
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
        $_.Exception.Message
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
                    # Initialize assigned licenses string
                    $assignedLicensesString = "No Licenses Assigned"

                    if ($user.assignedLicenses -and $user.assignedLicenses.skuid) {
                        # Handle multiple skuIds
                        $assignedLicenses = $user.assignedLicenses.skuid | ForEach-Object {
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

                    # Create the inactive user object with safe property assignments
                    $inactiveUser = [PSCustomObject]@{
                        DisplayName       = if ($user.displayName) { $user.displayName } else { "N/A" }
                        UserPrincipalName = if ($user.userPrincipalName) { $user.userPrincipalName } else { "N/A" }
                        Id                = if ($user.id) { $user.id } else { "N/A" }
                        #LastSignIn        = if ($user.signInActivity.lastSuccessfulSignInDateTime) { $user.signInActivity.lastSuccessfulSignInDateTime } else { "N/A" }
                        AssignedLicenses  = $assignedLicensesString
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
                AccountName   = $license.accountName
                AccountId     = $license.accountId
                SkuPartNumber = $license.skuPartNumber
                SkuId         = $license.skuId
                FriendlyName  = $friendlyName
                PrepaidUnits  = $prepaidEnabled
                ConsumedUnits = $consumedUnits
                UnusedUnits   = $unusedUnits
                AppliesTo     = $license.appliesTo
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
            "employeeId",
            "mail",
            "mobilePhone",
            "officeLocation",
            "preferredLanguage",
            "userPrincipalName",
            "id",
            "businessPhones",
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

                $userDetails = [PSCustomObject]@{
                    displayName       = $_.displayName
                    userPrincipalName = $_.userPrincipalName
                    department        = $_.department
                    location          = $_.usageLocation
                    assignedLicenses  = $assignedLicensesString
                    givenName         = $_.givenName
                    surname           = $_.surname
                    jobTitle          = $_.jobTitle
                    employeeId        = $_.employeeId
                    mail              = $_.mail
                    mobilePhone       = $_.mobilePhone
                    officeLocation    = $_.officeLocation
                    preferredLanguage = $_.preferredLanguage
                    businessPhones    = $_.businessPhones -join ", "
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
$inactiveUsers = Get-InactiveUsers
$AppsAndRegistrations = Get-RecentEnterpriseAppsAndRegistrations
$GroupsAndMembers = Get-RecentGroupsAndAddedMembers
$recentDevices = Get-RecentDevices 
$licensedUsers = Get-LicensedUsers



# Create a hashtable where the keys are the section titles and the values are the datasets
$dataSets = @{
    "Unused Licenses"              = $unusedLicenses
    "AssignedRoles"                = $AssignedRoles
    "Inactive Users"               = $inactiveUsers
    "Enterprise App Registrations" = $AppsAndRegistrations
    "Recent Groups and Members"    = $GroupsAndMembers
    "Recent Devices"               = $recentDevices
    "Licensed Users"               = $licensedUsers
}

# Generate the HTML report and send it via email
$htmlcontent = GenerateReport -DataSets $dataSets -RawHTML -Html -HtmlOutputPath ".\M365Report-NMM.html"

Send-EmailWithGraphAPI -Recipient "test@msp.com" -Subject "M365 Report - $(Get-Date -Format "yyyy-MM-dd")" -HtmlBody ($htmlContent | Out-String) -Attachment



