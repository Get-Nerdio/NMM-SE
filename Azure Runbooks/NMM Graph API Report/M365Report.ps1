<#
.SYNOPSIS
    Generates a comprehensive Microsoft 365 environment report using Microsoft Graph API and Pax8 API.
    #Pax8 API Code i used from Luke Whitlock his module: https://github.com/lwhitelock/Pax8API Thanks Luke!

.DESCRIPTION
    The M365Report.ps1 script connects to Microsoft Graph API and Pax8 API to gather detailed information about the Microsoft 365 environment. 
    It compiles various datasets, including unused licenses, assigned roles, recent role assignments, enterprise app registrations, recent groups and members, recent devices, licensed users, latest created users, inactive users, conditional access policy modifications, and Pax8 license details. The script generates an HTML report and optionally sends it via email.

.PARAMETER tenantId
    The Tenant ID of the Azure Active Directory. This parameter is mandatory for both App Registration and Interactive authentication methods.

.PARAMETER clientId
    The Client ID of the Azure AD App Registration. Required when using App Registration authentication.

.PARAMETER clientSecret
    The Client Secret of the Azure AD App Registration. Required when using App Registration authentication.

.PARAMETER interactive
    A switch parameter that, when specified, enables interactive browser-based authentication instead of App Registration.

.PARAMETER Pax8CompanyID
    The Company ID for Pax8 API. Used to retrieve subscription details specific to the company.

.PARAMETER Pax8ClientID
    The Client ID for Pax8 API authentication.

.PARAMETER Pax8ClientSecret
    The Client Secret for Pax8 API authentication.

.EXAMPLE
    Read trought the howto here to setup this up in Nerdio for MSP in a Azure Runbook: https://github.com/Get-Nerdio/NMM-SE/blob/main/Azure%20Runbooks/NMM%20Graph%20API%20Report/readme.md

.NOTES
    Author: Jan Scholte | Nerdio
    Version: 0.5
    Modules Needed:
        - Microsoft.Graph.Authentication
    Permissions Needed:
        - "Reports.Read.All"
        - "ReportSettings.Read.All"
        - "User.Read.All"
        - "Group.Read.All"
        - "Mail.Read"
        - "Mail.Send"
        - "Calendars.Read"
        - "Sites.Read.All"
        - "Directory.Read.All"
        - "RoleManagement.Read.Directory"
        - "AuditLog.Read.All"
        - "Organization.Read.All"
        - "PartnerBilling.Read.All"
#>



#Get the variables from Nerdio
$TenantId = $EnvironmentVars.TenantId #Tenant ID of the Azure AD
$clientId = $InheritedVars.M365ReportClientId #Client ID of the Azure AD App Registration
$clientSecret = $SecureVars.M365ReportSecret #Client Secret of the Azure AD App Registration
$Pax8CompanyID = $InheritedVars.Pax8CompanyID #Company ID of the Pax8 API
$Pax8ClientID = $InheritedVars.Pax8ClientID #Client ID of the Pax8 API
$Pax8ClientSecret = $SecureVars.Pax8ClientSecret #Client Secret of the Pax8 API
$MailReportRecipient = $InheritedVars.M365ReportMailRecip #Mail recipient of the report
$MailReportSender = $InheritedVars.M365ReportMailSender #Mail sender of the report

#Create secure string for the client secret
$secureString = ConvertTo-SecureString $clientSecret -AsPlainText -Force
#Create credential object for the Azure AD App Registration
$credential = New-Object System.Management.Automation.PSCredential($clientId, $secureString)


#Start of Helper Functions
############################################################################################################
function Connect-MgGraphHelper {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param (
        # Associate tenantId with both parameter sets
        [Parameter(Mandatory = $true, ParameterSetName = 'AppRegistration')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Interactive')]
        [string]$tenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'AppRegistration')]
        [string]$clientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'AppRegistration')]
        [string]$clientSecret,

        [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
        [switch]$interactive
    )

    begin {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'AppRegistration') {
                # Validate required parameters for App Registration
                if (-not ($clientId -and $clientSecret)) {
                    throw "For App Registration authentication, -clientId and -clientSecret must be provided."
                }

                # Convert client secret to secure string
                $secureSecret = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential ($clientId, $secureSecret)

                # Connect to Microsoft Graph using App Registration
                Connect-MgGraph -NoWelcome -ClientSecretCredential $credential -TenantId $tenantId
                Write-Output "Connected to Microsoft Graph using App Registration."
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'Interactive') {
                # Connect to Microsoft Graph using interactive browser session
                $params = @{
                    Scopes    = @(
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
                        "Organization.Read.All",
                        "PartnerBilling.Read.All"
                    )
                    TenantId  = $tenantId
                }
                Connect-MgGraph @params

                Write-Output "Connected to Microsoft Graph using interactive browser session."
            }
            else {
                throw "Please specify an authentication method: either provide -clientId, -clientSecret, and -tenantId for App Registration or use the -interactive switch for interactive login."
            }
        }
        catch {
            Write-Error "Failed to connect to Microsoft Graph: $_"
        }
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
        [array]$DataSets, # Accepts an ordered array of objects with Title and Data
    
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
                      /* New CSS for Nested Tables */
  table.rounded-table table {
      color: #000000; /* Set font color to black for nested tables */
      background-color: #ffffff; /* Optional: Set background color if needed */
  }
  table.rounded-table table thead tr {
      background-color: #f2f2f2; /* Optional: Different header color for nested tables */
                    color: #000000; /* Ensure header text is readable */
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

        # Iterate through the ordered array of dataSets
        foreach ($section in $DataSets) {
            $sectionTitle = $section.Title
            $data = $section.Data
            $itemCount = if ($data -and $data.PSObject.Properties.Name -ne 'Info') { $data.Count } else { 0 }

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
            return $DataSets | ConvertTo-Json
        }

        # PSObject Output
        if ($psObject) {
            return $DataSets
        }
    }
}
function Compare-JsonDifference {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$firstJson,

        [Parameter(Mandatory = $true)]
        [string]$secondJson
    )

    # Convert JSON strings to PowerShell objects
    try {
        $firstObject = $firstJson | ConvertFrom-Json -Depth 10
    }
    catch {
        Write-Error "Failed to parse first JSON: $_"
        return
    }

    try {
        $secondObject = $secondJson | ConvertFrom-Json -Depth 10
    }
    catch {
        Write-Error "Failed to parse second JSON: $_"
        return
    }

    # Flatten the objects for comparison
    function FlattenObject {
        param (
            [Parameter(Mandatory = $true)]
            [object]$obj,

            [string]$prefix = ""
        )
        $result = [System.Collections.Generic.Dictionary[string, object]]::new()

        foreach ($prop in $obj.PSObject.Properties) {
            $propName = if ($prefix) { "$prefix.$($prop.Name)" } else { $prop.Name }
            if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
                $flattened = FlattenObject -obj $prop.Value -prefix $propName
                foreach ($key in $flattened.Keys) {
                    if (-not $result.ContainsKey($key)) {
                        $result.Add($key, $flattened[$key])
                    }
                }
            }
            elseif ($prop.Value -is [System.Collections.IEnumerable] -and -not ($prop.Value -is [string])) {
                $index = 0
                foreach ($item in $prop.Value) {
                    if ($item -is [System.Management.Automation.PSCustomObject]) {
                        $flattened = FlattenObject -obj $item -prefix "$propName[$index]"
                        foreach ($key in $flattened.Keys) {
                            if (-not $result.ContainsKey($key)) {
                                $result.Add($key, $flattened[$key])
                            }
                        }
                    }
                    else {
                        $key = "$propName[$index]"
                        if (-not $result.ContainsKey($key)) {
                            $result.Add($key, $item)
                        }
                    }
                    $index++
                }
            }
            else {
                if (-not $result.ContainsKey($propName)) {
                    $result.Add($propName, $prop.Value)
                }
            }
        }

        return $result
    }

    $flatFirst = FlattenObject -obj $firstObject
    $flatSecond = FlattenObject -obj $secondObject

    # Convert dictionaries to arrays of PSCustomObjects
    $flatFirstArray = $flatFirst.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            Path  = $_.Key
            Value = $_.Value
        }
    }

    $flatSecondArray = $flatSecond.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            Path  = $_.Key
            Value = $_.Value
        }
    }

    # Compare the flattened objects using Compare-Object
    $comparison = Compare-Object -ReferenceObject $flatFirstArray -DifferenceObject $flatSecondArray -Property Path, Value -PassThru

    if ($comparison) {
        $differences = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($diff in $comparison) {
            $path = $diff.Path
            $sideIndicator = $diff.SideIndicator

            switch ($sideIndicator) {
                "<=" {
                    $changeType = "Removed"
                    $oldValue = $diff.Value
                    $newValue = $null
                }
                "=>" {
                    $changeType = "Added"
                    $oldValue = $null
                    $newValue = $diff.Value
                }
                default {
                    $changeType = "Modified"
                    # Retrieve old and new values
                    $oldValue = $flatFirst[$path]
                    $newValue = $flatSecond[$path]
                }
            }

            # Only capture meaningful changes
            if ($changeType -ne "==") {
                $differences.Add([PSCustomObject]@{
                        Path       = $path
                        ChangeType = $changeType
                        OldValue   = $oldValue
                        NewValue   = $newValue
                    })
            }
        }

        return $differences | Sort-Object Path
    }
    else {
        Write-Output "No differences found between the provided JSON strings."
    }
}
function Invoke-GraphRequestWithPaging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers
    )

    # Initialize an array to store all results
    $allResults = [System.Collections.Generic.List[PSObject]]::new()

    do {
        Write-Verbose "Fetching data from URI: $Uri"

        try {
            # Invoke the Graph API request with or without headers based on the presence of $Headers
            if ($PSBoundParameters.ContainsKey('Headers')) {
                $response = Invoke-MgGraphRequest -Uri $Uri -OutputType PSObject -Headers $Headers
            }
            else {
                $response = Invoke-MgGraphRequest -Uri $Uri -OutputType PSObject
            }
        }
        catch {
            Write-Error "Failed to fetch data from $Uri. Error: $_"
            break
        }

        if ($response.value) {
            # Append the current page's items to the results
            $allResults.add($response.value)
            Write-Verbose "Retrieved $($response.value.Count) items."
        }
        else {
            Write-Verbose "No items found in the current response."
        }

        # Update the URI to the next page if available
        if ($response.'@odata.nextLink') {
            $Uri = $response.'@odata.nextLink'
        }
        else {
            $Uri = $null
        }

    } while ($Uri)

    return $allResults
}
function Connect-Pax8 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientID,
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret

    )

    $auth = @{
        client_id     = $ClientID
        client_secret = $ClientSecret
        audience      = "api://p8p.client"
        grant_type    = "client_credentials"
    }
    
    $json = $auth | ConvertTo-json -Depth 2

    try {
        $Response = Invoke-WebRequest -Method POST -Uri 'https://login.pax8.com/oauth/token' -ContentType 'application/json' -Body $json
        $script:Pax8Token = ($Response | ConvertFrom-Json).access_token
        $script:Pax8BaseURL = 'https://api.pax8.com/v1/'
        $script:Pax8BaseURLv2 = 'https://app.pax8.com/p8p/api-v2/1/'
    }
    catch {
        Write-Host $_ -ForegroundColor Red
    }

    

}
function Get-Pax8Subscriptions {
    [CmdletBinding()]
    Param(
        [ValidateSet("quantity", "startDate", "endDate", "createdDate", "billingStart", "price")]    
        [string]$sort,
        [ValidateSet("Active", "Cancelled", "PendingManual", "PendingAutomated", "PendingCancel", "WaitingForDetails", "Trial", "Converted", "PendingActivation", "Activated")]  
        [string]$status,
        [ValidateSet("Monthly", "Annual", "2-Year", "3-Year", "One-Time", "Trial", "Activation")]    
        [string]$billingTerm,
        [string]$companyId,
        [string]$productId,
        [string]$subscriptionId
    )
  
    if ($subscriptionId) {
        $Subscriptions = Invoke-Pax8Request -method get -resource "subscriptions/$subscriptionId"
    }
    else {
  
        $resourcefilter = ''
  
        if ($sort) {
            $resourcefilter = "$($resourcefilter)&sort=$($sort)"
        }
  
        if ($status) {
            $resourcefilter = "$($resourcefilter)&status=$($status)"
        }
  
        if ($billingTerm) {
            $resourcefilter = "$($resourcefilter)&billingTerm=$($billingTerm)"
        }
  
        if ($companyId) {
            $resourcefilter = "$($resourcefilter)&companyId=$($companyId)"
        }
  
        if ($productId) {
            $resourcefilter = "$($resourcefilter)&productId=$($productId)"
        }
  
        $Subscriptions = Invoke-Pax8Request -method get -resource "subscriptions" -ResourceFilter $resourcefilter
    
    }
    return $Subscriptions
  
}
function Get-Pax8LicenseDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ClientID,
        
        [Parameter(Mandatory = $false)]
        [string]$ClientSecret,
        
        [Parameter(Mandatory = $true)]
        [string]$CompanyId
    )
    
    try {
        # Connect to Pax8 if credentials are provided
        if ($ClientID -and $ClientSecret) {
            Connect-Pax8 -ClientID $ClientID -ClientSecret $ClientSecret
        }
        elseif (-not $script:Pax8Token) {
            [PSCustomObject]@{
                Info = "Pax8 Integration not configured, please provide Pax8ClientSecret and Pax8ClientID"
            }
        }
        
        # Retrieve subscriptions for the specified company
        $subscriptions = Get-Pax8Subscriptions -companyId $CompanyId
        
        if (-not $subscriptions) {
            Write-Warning "No subscriptions found for Company ID: $CompanyId"
            return
        }
        
        # Extract unique Product IDs from subscriptions
        $productIds = $subscriptions | Select-Object -ExpandProperty productId | Sort-Object -Unique
        
        if (-not $productIds) {
            Write-Warning "No Product IDs found in the subscriptions for Company ID: $CompanyId"
            return
        }
        
        # Retrieve only the products associated with the subscriptions
        $products = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($productId in $productIds) {
            $productDetails = Get-Pax8Products -id $productId
            if ($productDetails) {
                $products.Add($productDetails)
            }
            else {
                Write-Warning "Product with ID $productId not found."
            }
        }
        
        if ($products.Count -eq 0) {
            Write-Warning "No valid products retrieved for the specified Product IDs."
            return
        }
        
        # Create a lookup table for product details based on Product ID
        $productLookup = @{}
        foreach ($product in $products) {
            $productLookup[$product.id] = $product
        }
        
        # Initialize a list to store license details
        $licenseDetailsList = [System.Collections.Generic.List[PSCustomObject]]::new()
        
        # Process each subscription and compile license details
        foreach ($subscription in $subscriptions) {
            try {
                # Retrieve associated product details from the lookup
                $product = $productLookup[$subscription.productId]
                
                if (-not $product) {
                    Write-Warning "Product ID $($subscription.productId) not found in the retrieved products."
                    continue
                }
                
                
                # Create a PSCustomObject with license details
                $licenseDetail = [PSCustomObject]@{
                    LicenseName = $product.name
                    Quantity    = $subscription.quantity
                    Status      = $subscription.status
                    BillingTerm = $subscription.billingTerm
                    StartDate   = $subscription.startDate
                    CreatedDate = $subscription.createdDate
                    Currency    = $subscription.currencyCode
                    VendorName  = $product.vendorName
                    Description = $product.shortDescription
                }
                
                # Add the license detail to the list
                $licenseDetailsList.Add($licenseDetail)
            }
            catch {
                Write-Warning "Failed to process subscription ID $($subscription.id): $_"
            }
        }
        
        # Output the compiled license details
        return $licenseDetailsList
    }
    catch {
        Write-Error "Error in Get-Pax8LicenseDetails: $_"
    }
}
function Invoke-Pax8Request {
    [CmdletBinding()]
    Param(
        [string]$Method,
        [string]$Resource,
        [string]$ResourceFilter,
        [string]$Body,
        [bool]$v2API
    )
	
    if (!$script:Pax8Token) {
        Write-Host "Please run 'Connect-Pax8' first" -ForegroundColor Red
    }
    else {
	
        $headers = @{
            Authorization = "Bearer $($script:Pax8Token)"
        }

        If (!$v2API) {

            try {
                if (($Method -eq "put") -or ($Method -eq "post") -or ($Method -eq "delete")) {
                    $Response = Invoke-WebRequest -Method $method -Uri ($Script:Pax8BaseURL + $Resource) -ContentType 'application/json' -Body $Body -Headers $headers -ea stop
                    $Result = $Response | ConvertFrom-Json
                }
                else {
                    $Complete = $false
                    $PageNo = 0
                    $Result = do {
                        $Response = Invoke-WebRequest -Method $method -Uri ($Script:Pax8BaseURL + $Resource + "?page=$PageNo&size=200" + $ResourceFilter) -ContentType 'application/json' -Headers $headers -ea stop
                        $JSON = $Response | ConvertFrom-Json
                        if ($JSON.Page) {
                            if (($JSON.Page.totalPages - 1) -eq $PageNo -or $JSON.Page.totalPages -eq 0) {
                                $Complete = $true
                            }
                            $PageNo = $PageNo + 1
                            $JSON.content
                        }
                        else {
                            $Complete = $true
                            $JSON
                        }
                    } while ($Complete -eq $false)
                }
            }
            catch {
                if ($_.Response.StatusCode -eq 429) {
                    Write-Warning "Rate limit exceeded. Waiting to try again."
                    Start-Sleep 8
                    $Result = Invoke-Pax8Request -Method $Method -Resource $Resource -ResourceFilter $ResourceFilter -Body $Body
                }
                else {
                    Write-Error "An Error Occured $($_) "
                }
            }
		
            return $Result
        }
        else {
            try {
                if (($Method -eq "put") -or ($Method -eq "post") -or ($Method -eq "delete")) {
                    $Response = Invoke-WebRequest -Method $method -Uri ($script:Pax8BaseURLv2 + $Resource) -ContentType 'application/json' -Body $Body -Headers $headers -ea stop
                    $Result = $Response | ConvertFrom-Json
                }
                else {
                    $Complete = $false
                    $PageNo = 0
                    $Result = do {
                        $Response = Invoke-WebRequest -Method $method -Uri ($script:Pax8BaseURLv2 + $Resource + "?page=$PageNo&size=200" + $ResourceFilter) -ContentType 'application/json' -Headers $headers -ea stop
                        $JSON = $Response | ConvertFrom-Json
                        $Complete = $true
                        $JSON
                    } while ($Complete -eq $false)
                }
            }
            catch {
                if ($_.Response.StatusCode -eq 429) {
                    Write-Warning "Rate limit exceeded. Waiting to try again."
                    Start-Sleep 8
                    $Result = Invoke-Pax8Request -Method $Method -Resource $Resource -ResourceFilter $ResourceFilter -Body $Body
                }
                else {
                    Write-Error "An Error Occured $($_) "
                }
            }
		
            return $Result
        }
    }	
}
function Get-Pax8Products {
    [CmdletBinding()]
    Param(
        [ValidateSet("name", "vendor")]    
        [string]$sort,
        [string]$vendorName,
        [string]$id
    )
  
    if ($id) {
        $Products = Invoke-Pax8Request -method get -resource "products/$id"
    }
    else {
  
        $resourcefilter = ''
        if ($sort) {
            $resourcefilter = "$($resourcefilter)&sort=$($sort)"
        }
        if ($vendorName) {
            $resourcefilter = "$($resourcefilter)&vendorName=$($vendorName)"
        }
     
        $Products = Invoke-Pax8Request -method get -resource "products" -ResourceFilter $resourcefilter
    }
  
    return $Products
  
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
        [string]$Sender  # Use "me" for the authenticated user, or specify another sender
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
        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/users/$Sender/sendMail" `
            -Method POST `
            -Body $jsonPayload `
            -ContentType "application/json"
                              
        Write-Host "Email sent successfully to $Recipient"
    }
    catch {
        Write-Error "Error sending email: $_"
    }
}
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

#Start of Report Functions
############################################################################################################

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
        $signIns = Invoke-GraphRequestWithPaging -Uri "https://graph.microsoft.com/beta/users?`$filter=signInActivity/lastSuccessfulSignInDateTime le $cutoffDateFormatted"

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
    [CmdletBinding()]
    param ()

    try {
        # Initialize the date threshold in UTC (30 days ago)
        $dateThreshold = (Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Define the filter for recent creations
        $filter = "createdDateTime ge $dateThreshold"

        # Initialize the list to store recent apps
        $recentApps = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Define the initial URIs with server-side filtering
        $servicePrincipalsUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$filter&`$top=999"
        $applicationsUri = "https://graph.microsoft.com/v1.0/applications?`$filter=$filter&`$top=999"

        # Retrieve recent Enterprise Applications using Invoke-GraphRequestWithPaging
        $servicePrincipals = Invoke-GraphRequestWithPaging -Uri $servicePrincipalsUri

        foreach ($app in $servicePrincipals) {
            # Add Enterprise Application details to the list
            $recentApps.Add([PSCustomObject]@{
                    AppType         = "Enterprise Application"
                    AppId           = $app.appId
                    DisplayName     = $app.displayName
                    CreatedDateTime = $app.createdDateTime
                })
        }

        # Retrieve recent App Registrations using Invoke-GraphRequestWithPaging
        $applications = Invoke-GraphRequestWithPaging -Uri $applicationsUri

        foreach ($app in $applications) {
            # Add App Registration details to the list
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
        Write-Error $_.Exception.Message
    }
}
function Get-RecentGroupsAndAddedMembers {
    try {
        # Calculate the date for 30 days ago
        $dateThreshold = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Get groups created in the last 30 days
        
        $groups = Invoke-GraphRequestWithPaging -Uri "https://graph.microsoft.com/v1.0/groups"
        $recentGroups = $groups | Where-Object { $_.createdDateTime -ge $dateThreshold }

        # Get all "Add member to group" actions from audit logs in the last 30 days
        $auditLogs = Invoke-GraphRequestWithPaging -Uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Add member to group' and activityDateTime ge $dateThreshold and result eq 'success'&`$orderby=activityDateTime desc"

        # Create a list to store the group details and recent members
        $groupDetails = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($group in $recentGroups) {
            $groupId = $group.id
            $groupName = $group.displayName

            # Create a list to store recent members
            $recentMembers = [System.Collections.Generic.List[string]]::new()

            foreach ($log in $auditLogs) {
                
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
        $users = Invoke-GraphRequestWithPaging -Uri "https://graph.microsoft.com/v1.0/users?`$filter=assignedLicenses/`$count ne 0&`$count=true&`$select=$selectedProperties" -Headers $headers

        # Use ForEach-Object for handling large collections efficiently
        $users | ForEach-Object {
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
        $uri = "https://graph.microsoft.com/beta/directory/subscriptions"

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

                    $newValue = $log.targetResources.modifiedProperties.newValue
                    $oldValue = $log.targetResources.modifiedProperties.oldValue

                    $newValueObj = $newValue | ConvertFrom-Json -ErrorAction SilentlyContinue

                    
                    $diff = [System.Collections.Generic.List[PSObject]]::new()

                    if ($null -ne $oldValue -and $null -ne $newValue) { 
                        $DataObj = Compare-JsonDifference -firstJson $oldValue -secondJson $newValue | Where-Object { $_.Path -ne "modifiedDateTime" }
                        $DataObj | ForEach-Object {
                            $diff.Add([PSCustomObject]@{
                                    Setting    = $_.Path
                                    ChangeType = $_.ChangeType
                                    OldValue   = $_.OldValue
                                    NewValue   = $_.NewValue
                                })
                        }
                    }

                    # Create a PSCustomObject with the desired properties
                    $modificationDetails = [PSCustomObject][Ordered]@{
                        InitiatedBy         = $initiatedByUser
                        IpAddress           = $ipAddress
                        ActivityDisplayName = $log.activityDisplayName
                        ActivityDateTime    = $log.activityDateTime
                        PolicyName          = if ($newValueObj.displayName) { $newValueObj.displayName } else { "N/A" }
                        PolicyId            = if ($newValueObj.id) { $newValueObj.id } else { "N/A" }
                        State               = if ($newValueObj.state) { $newValueObj.state } else { "N/A" }
                        Differences         = if ($diff) { ConvertTo-ObjectToHtmlTable -Object $diff } else { "No changes" }
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

#End of Functions
############################################################################################################

#Connect to MS Graph with App Registration
Import-Module Microsoft.Graph.Authentication

Connect-MgGraphHelper -clientId $clientId -clientSecret $clientSecret -tenantId $tenantId

#Cache Data in $Script Variables
$script:CacheGroups = Invoke-GraphRequestWithPaging -Uri "https://graph.microsoft.com/v1.0/groups"
$script:CacheUsers = Invoke-GraphRequestWithPaging -Uri "https://graph.microsoft.com/v1.0/users"
$script:CacheRoles = Invoke-GraphRequestWithPaging -Uri "https://graph.microsoft.com/v1.0/directoryRoles"

# Save Data in Vars for the ordered array
$unusedLicenses = Get-UnusedLicenses
$AssignedRoles = Get-AssignedRoleMembers
$recentRoleAssignments = Get-RecentAssignedRoleMembers
$AppsAndRegistrations = Get-RecentEnterpriseAppsAndRegistrations
$GroupsAndMembers = Get-RecentGroupsAndAddedMembers
$recentDevices = Get-RecentDevices
$licensedUsers = Get-LicensedUsers
$latestCreatedUsers = Get-LatestCreatedUsers
$inactiveUsers = Get-InactiveUsers
$caPolicyModifications = Get-ConditionalAccessPolicyModifications
$Pax8LicenseDetails = Get-Pax8LicenseDetails -ClientID $Pax8ClientID -ClientSecret $Pax8ClientSecret -CompanyId $Pax8CompanyID


# Define an ordered array of objects with Title and Data properties
$dataSets = @(
    @{ Title = "Latest Created Users"; Data = $latestCreatedUsers },
    @{ Title = "Inactive Users"; Data = $inactiveUsers },
    @{ Title = "Licensed Users"; Data = $licensedUsers },
    @{ Title = "Unused Licenses"; Data = $unusedLicenses },
    @{ Title = "Pax8 License Details"; Data = $Pax8LicenseDetails },
    @{ Title = "Recent Groups and Members"; Data = $GroupsAndMembers },
    @{ Title = "Recent Role Assignments"; Data = $recentRoleAssignments },
    @{ Title = "Assigned Roles"; Data = $AssignedRoles },
    @{ Title = "Enterprise App Registrations"; Data = $AppsAndRegistrations },
    @{ Title = "Recent Devices"; Data = $recentDevices },
    @{ Title = "Conditional Access Policy Modifications"; Data = $caPolicyModifications }
)

# Generate the HTML report and send it via email
$htmlContent = GenerateReport -DataSets $dataSets -RawHTML -Html

#Mail sned is still if you auth with a user, so no mail send from Runbook yet.
Send-EmailWithGraphAPI -Recipient $MailReportRecipient -Sender $MailReportSender -Subject "M365 Report - $(Get-Date -Format "yyyy-MM-dd")" -HtmlBody ($htmlContent | Out-String) -Attachment


#Todo: 
# - Use the Cache data in the variables to reduce the number of API calls
# - Add a seperate function that can enumerate the object IDs and resolve the display names for the settings in the CA Policy Modifications
# - Document the shared mailbox setup
# - Create nice summary for the main mail body and then add the details in the attachment

