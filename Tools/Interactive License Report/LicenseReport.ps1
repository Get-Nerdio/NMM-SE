<#
.SYNOPSIS
Generates Microsoft 365 license reports using raw Graph API calls and interactive authentication.

.DESCRIPTION
This script connects to Microsoft Graph using interactive device code flow, retrieves license and user data,
combines it with Microsoft's official product name mappings, and generates reports in various formats (CSV, HTML, Terminal).
It is designed to run in environments like Azure Cloud Shell where modules might not be pre-installed and app registration is not desired.

.PARAMETER OutputCsv
Specifies whether to generate a CSV report with the default timestamped name in the Reports folder.

.PARAMETER OutputHtml
Specifies whether to generate an HTML report with the default timestamped name in the Reports folder.

.PARAMETER CsvPath
Specifies a custom file path for the CSV report.

.PARAMETER HtmlPath
Specifies a custom file path for the HTML report.

.PARAMETER ShowInTerminal
Displays a formatted summary report directly in the terminal.

.PARAMETER IncludeServicePlans
Includes detailed service plan information for each assigned license in the reports.

.PARAMETER IncludeUnlicensed
Includes users without any assigned licenses in the reports.

.PARAMETER LicenseSummaryOnly
Displays only a summary list of tenant licenses and their usage counts.

.PARAMETER TenantName
Custom tenant name to use in the report instead of the actual tenant name.

.PARAMETER TenantIdentifier
Identifier to add to the output filenames for better organization.

.EXAMPLE
.\LicenseReport.ps1 -ShowInTerminal

Generates and displays the report in the terminal.

.EXAMPLE
.\LicenseReport.ps1 -OutputCsv -OutputHtml -IncludeServicePlans

Generates CSV and HTML reports including service plan details.

.EXAMPLE
.\LicenseReport.ps1 -IncludeUnlicensed -ShowInTerminal

Generates a report including unlicensed users and displays it in the terminal.

.EXAMPLE
.\LicenseReport.ps1 -LicenseSummaryOnly

Displays only the summary of licenses in the tenant.

.NOTES
Author: AI Assistant
Requires: PowerShell 5.1 or later, Internet connectivity.
Ensure System.Web assembly is available or adjust the code accordingly if running in restricted environments.
#>

#Requires -Version 5.1

[CmdletBinding()] # Moved CmdletBinding before the configuration
param (
    # Define script parameters here
    [Parameter(Mandatory = $false,
               HelpMessage = "Generate a CSV report with the default timestamped name in the Reports folder.")]
    [switch]$OutputCsv,

    [Parameter(Mandatory = $false,
               HelpMessage = "Generate an HTML report with the default timestamped name in the Reports folder.")]
    [switch]$OutputHtml,

    [Parameter(Mandatory = $false,
               HelpMessage = "Specifies a custom file path for the CSV report.")]
    [string]$CsvPath,

    [Parameter(Mandatory = $false,
               HelpMessage = "Specifies a custom file path for the HTML report.")]
    [string]$HtmlPath,

    [Parameter(Mandatory = $false,
               HelpMessage = "Displays a formatted summary report directly in the terminal.")]
    [switch]$ShowInTerminal,

    [Parameter(Mandatory = $false,
               HelpMessage = "Includes detailed service plan information for each assigned license in the reports.")]
    [switch]$IncludeServicePlans,

    [Parameter(Mandatory = $false,
               HelpMessage = "Includes users without any assigned licenses in the reports.")]
    [switch]$IncludeUnlicensed,

    [Parameter(Mandatory = $false,
               HelpMessage = "Displays only a summary list of tenant licenses and their usage counts.")]
    [switch]$LicenseSummaryOnly,

    [Parameter(Mandatory = $false,
               HelpMessage = "Custom tenant name to use in the report instead of the actual tenant name.")]
    [string]$TenantName,

    [Parameter(Mandatory = $false,
               HelpMessage = "Identifier to add to the output filenames for better organization.")]
    [string]$TenantIdentifier
)

# --- Configuration: SKU Ignore List ---
# Add SkuPartNumber strings to this list to exclude them from all reports and calculations.
$global:ignoredSkuPartNumbers = @(
    'FLOW_FREE' # Example: Ignore the free Power Automate license
    # Add other SkuPartNumbers here, e.g., 'POWER_BI_STANDARD'
)
# --------------------------------------

# Load required assemblies
try {
    Add-Type -AssemblyName System.Web
} catch {
    Write-Warning "Failed to load System.Web assembly. URI decoding may not work correctly: $($_.Exception.Message)"
}

#------------------------------------------------------------------------------
#region Core Functions: Authentication, Mapping, API Interaction
#------------------------------------------------------------------------------

#region Authentication
function Get-MsGraphToken {
    <#
    .SYNOPSIS
    Handles interactive device code authentication for Microsoft Graph.
    .DESCRIPTION
    Initiates a device code flow, prompts the user to authenticate in a browser,
    and exchanges the code for an access token. Uses a well-known client ID for PowerShell.
    .OUTPUTS
    PSCustomObject containing AccessToken, RefreshToken, ExpiresOn, and TenantId.
    #>
    [CmdletBinding()]
    param()

    Write-Verbose "Starting MS Graph Token Acquisition"

    # Use well-known client ID for PowerShell / Azure CLI
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2" # Default PowerShell App ID
    $resourceUri = "https://graph.microsoft.com"
    $tenantId = "common" # Start with common endpoint
    $deviceCodeEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/devicecode"
    $tokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

    # Request device code
    $deviceCodeBody = @{
        client_id = $clientId
        scope = "$resourceUri/.default openid profile offline_access" # Request necessary scopes
    }

    try {
        Write-Verbose "Requesting Device Code from $deviceCodeEndpoint"
        $deviceCodeResponse = Invoke-RestMethod -Method Post -Uri $deviceCodeEndpoint -Body $deviceCodeBody -ContentType "application/x-www-form-urlencoded"
    }
    catch {
        Write-Error "Failed to request device code: $($_.Exception.Message)"
        throw
    }

    # Display user instructions
    Write-Host $deviceCodeResponse.message -ForegroundColor Cyan

    # Poll for token
    $tokenBody = @{
        grant_type = "urn:ietf:params:oauth:grant-type:device_code"
        client_id = $clientId
        device_code = $deviceCodeResponse.device_code
    }
    $expires_at = (Get-Date).AddSeconds($deviceCodeResponse.expires_in)
    $tokenResponse = $null

    Write-Verbose "Polling for token..."
    do {
        try {
            Start-Sleep -Seconds $deviceCodeResponse.interval
            $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue # Capture error manually
            # Check for specific error indicating authorization pending
            if ($tokenResponse.error -eq 'authorization_pending') {
                Write-Verbose "Authorization still pending..."
                $tokenResponse = $null # Reset response to continue loop
            } elseif ($tokenResponse.error) {
                 Write-Error "Error polling for token: $($tokenResponse.error_description)"
                 throw $tokenResponse.error_description
            }
        }
        catch {
            # Handle potential errors during polling (e.g., network issues), but ignore authorization_pending which is handled above
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -ne 400) { # 400 might be authorization_pending or other client errors
                 Write-Error "Error polling for token: $($_.Exception.Message)"
                 throw
            } elseif (-not $_.Exception.Response) { # Handle non-HTTP errors
                 Write-Error "Non-HTTP Error polling for token: $($_.Exception.Message)"
                 throw
            }
             # If it's a 400 error related to pending auth, it's handled in the try block. Any other 400 will be thrown by the logic inside the try block.
        }
         if ((Get-Date) -gt $expires_at) {
             Write-Error "Device code expired. Please run the script again."
             throw "Device code expired."
         }
    } while (-not $tokenResponse)

    Write-Verbose "Token acquired successfully."

    # Extract Tenant ID from the token claims (more reliable)
    try {
        $accessTokenPayload = $tokenResponse.access_token.Split('.')[1]
        $decodedPayload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($accessTokenPayload.PadRight($accessTokenPayload.Length + (4 - $accessTokenPayload.Length % 4) % 4, '=')))
        $tokenClaims = ConvertFrom-Json -InputObject $decodedPayload
        $tenantId = $tokenClaims.tid
        Write-Verbose "Tenant ID from Token: $tenantId"
    } catch {
        Write-Warning "Could not decode Tenant ID from token, using 'common'. Error: $($_.Exception.Message)"
        $tenantId = "common"
    }

    # Extract the tenant name from token claims if available
    $tenantName = $null
    if ($tokenClaims.PSObject.Properties['tid'] -ne $null) {
        # If we have the tenant ID but not the display name, use the ID as the name
        $tenantName = $tokenClaims.tid
    }
    # Check for tenant name in the claims
    if ($tokenClaims.PSObject.Properties['tenant_display_name'] -ne $null) {
        $tenantName = $tokenClaims.tenant_display_name
    } elseif ($tokenClaims.PSObject.Properties['tenant_name'] -ne $null) {
        $tenantName = $tokenClaims.tenant_name
    } elseif ($tokenClaims.PSObject.Properties['upn'] -ne $null -and $tokenClaims.upn -match '@(.+)$') {
        # Try to extract from UPN domain
        $tenantName = $Matches[1]
    }

    # Return the token info with tenant name
    return [PSCustomObject]@{
        AccessToken = $tokenResponse.access_token
        RefreshToken = $tokenResponse.refresh_token
        ExpiresOn = (Get-Date).AddSeconds($tokenResponse.expires_in)
        TenantId = $tenantId
        TenantName = $tenantName
    }
}
#endregion Authentication

#region License Mapping
function Get-LicenseMappings {
    <#
    .SYNOPSIS
    Downloads and parses the Microsoft product names and service plan identifiers CSV.
    .DESCRIPTION
    Fetches the latest mapping file from Microsoft's download center and creates
    hashtables to map SKU IDs and String IDs (Part Numbers) to friendly product names.
    Includes basic error handling and fallback if the download or parsing fails.
    .OUTPUTS
    PSCustomObject containing SkuIdToName and SkuPartNumberToName hashtables.
    #>
    [CmdletBinding()]
    param()

    Write-Verbose "Fetching License Mappings"
    # URL from Microsoft documentation - check occasionally if it changes
    $licenseCsvURL = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
    $skuIdToName = @{}
    $skuPartNumberToName = @{}

    try {
        Write-Verbose "Downloading license mapping CSV from $licenseCsvURL"
        # Use Invoke-WebRequest for better control and error handling if needed, but Invoke-RestMethod is simpler for direct content
        $responseBytes = Invoke-WebRequest -Uri $licenseCsvURL -UseBasicParsing | Select-Object -ExpandProperty Content
        # Detect encoding (often UTF8 with BOM for MS files) or assume default; PowerShell 5.1 might need explicit handling
        $csvContent = [System.Text.Encoding]::UTF8.GetString($responseBytes)

        # Simple CSV Parsing (Robust parsing might require Import-Csv if available, or more complex logic)
        $csvRows = $csvContent -split '(\r?\n)' | Where-Object { $_ -match '\S' } # Split by newline, keep non-empty
        if ($csvRows.Count -lt 2) {
            throw "CSV file appears empty or has invalid format."
        }

        # Trim potential BOM and quotes from header, handle commas within quotes simply by splitting (may fail on complex CSVs)
        $headers = ($csvRows[0].TrimStart([char]0xFEFF).Trim('"') -replace '"', '') -split ","

        # Find column indices dynamically
        $guidIndex = [array]::IndexOf($headers, "GUID")
        $stringIdIndex = [array]::IndexOf($headers, "String_Id") # Often the SkuPartNumber
        $productNameIndex = [array]::IndexOf($headers, "Product_Display_Name")
        $servicePlanNameIndex = [array]::IndexOf($headers, "Service_Plan_Display_Name") # For mapping service plans too
        $servicePlanIdIndex = [array]::IndexOf($headers, "Service_Plan_Id_(GUID)") # GUID for service plans

        if ($guidIndex -eq -1 -or $stringIdIndex -eq -1 -or $productNameIndex -eq -1 -or $servicePlanNameIndex -eq -1 -or $servicePlanIdIndex -eq -1) {
            Write-Warning "Could not find all expected columns (GUID, String_Id, Product_Display_Name, Service_Plan_Display_Name, Service_Plan_Id_(GUID)) in the CSV. Mappings might be incomplete. Using fallback mapping."
            # Attempt partial mapping if possible
        }

        Write-Verbose "Parsing CSV data..."
        # Start from index 1 to skip headers
        for ($i = 1; $i -lt $csvRows.Count; $i++) {
            # Basic split, assumes commas don't appear within quoted fields
            $row = ($csvRows[$i] -replace '"', '') -split ","
            if ($row.Count -lt ($headers.Count)) {
                Write-Verbose "Skipping potentially malformed row $i : $($csvRows[$i])"
                continue
            }

            $guid = $null
            $stringId = $null
            $productName = $null
            $servicePlanName = $null
            $servicePlanId = $null

            if($guidIndex -ne -1) { $guid = $row[$guidIndex].Trim() }
            if($stringIdIndex -ne -1) { $stringId = $row[$stringIdIndex].Trim() }
            if($productNameIndex -ne -1) { $productName = $row[$productNameIndex].Trim() }
            if($servicePlanNameIndex -ne -1) { $servicePlanName = $row[$servicePlanNameIndex].Trim() }
            if($servicePlanIdIndex -ne -1) { $servicePlanId = $row[$servicePlanIdIndex].Trim() }


            # Map Product SKUs (where Product_Display_Name is present)
            if (-not [string]::IsNullOrWhiteSpace($guid) -and -not [string]::IsNullOrWhiteSpace($productName)) {
                if (-not $skuIdToName.ContainsKey($guid)) {
                    $skuIdToName[$guid] = $productName
                    Write-Verbose "Mapped SKU GUID $guid to Product '$productName'"
                }
                 # Also map String ID (Part Number) if available
                if (-not [string]::IsNullOrWhiteSpace($stringId) -and (-not $skuPartNumberToName.ContainsKey($stringId))) {
                     $skuPartNumberToName[$stringId] = $productName
                     Write-Verbose "Mapped SKU StringID '$stringId' to Product '$productName'"
                }
            }

             # Map Service Plans (where Service_Plan_Display_Name is present)
             if (-not [string]::IsNullOrWhiteSpace($servicePlanId) -and -not [string]::IsNullOrWhiteSpace($servicePlanName)) {
                 if (-not $skuIdToName.ContainsKey($servicePlanId)) {
                     $skuIdToName[$servicePlanId] = $servicePlanName # Use SkuIdToName for service plan GUIDs too
                     Write-Verbose "Mapped Service Plan GUID $servicePlanId to '$servicePlanName'"
                 }
                 # Sometimes StringID column is used for service plan "names" like 'TEAMS_EXPLORATORY'
                 if (-not [string]::IsNullOrWhiteSpace($stringId) -and -not $skuPartNumberToName.ContainsKey($stringId)) {
                     $skuPartNumberToName[$stringId] = $servicePlanName
                     Write-Verbose "Mapped Service Plan StringID '$stringId' to '$servicePlanName'"
                 }
             }
        }
        Write-Verbose "Finished parsing license mappings. Found $($skuIdToName.Count) GUID mappings and $($skuPartNumberToName.Count) String ID mappings."

    }
    catch {
        Write-Warning "Failed to download or parse license mappings: $($_.Exception.Message). License names may show as GUIDs or Part Numbers."
        # Return empty mappings as fallback
        $skuIdToName = @{}
        $skuPartNumberToName = @{}
    }

    return [PSCustomObject]@{
        SkuIdToName = $skuIdToName
        SkuPartNumberToName = $skuPartNumberToName
    }
}
#endregion License Mapping

#region Graph API Wrappers
function Invoke-MsGraphRequest {
    <#
    .SYNOPSIS
    Invokes a Microsoft Graph API request with specified token, URI, and method.
    .DESCRIPTION
    A wrapper around Invoke-RestMethod to handle Graph API calls, including authorization header,
    content type, and basic handling for rate limiting (429).
    .PARAMETER AccessToken
    The OAuth2 Access Token for authentication.
    .PARAMETER Uri
    The full URI for the Graph API endpoint.
    .PARAMETER Method
    The HTTP method (GET, POST, PUT, PATCH, DELETE). Defaults to GET.
    .OUTPUTS
    The parsed JSON response from the Graph API.
    .NOTES
    Includes retry logic for HTTP 429 (Too Many Requests).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method = "GET",

        [Parameter(Mandatory = $false)]
        [object]$Body = $null
    )

    Write-Verbose "Invoking Graph Request: $Method $Uri"

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type" = "application/json"
        "ConsistencyLevel" = "eventual" # Recommended for some queries like directory objects with $count
    }

    $invokeParams = @{
        Uri = $Uri
        Headers = $headers
        Method = $Method
        ErrorAction = 'Stop' # Ensure errors are caught
    }
    if ($Body) {
        $invokeParams.Body = ($Body | ConvertTo-Json -Depth 5)
         # Ensure ContentType is set for methods that typically have a body
         if ($Method -in @('POST', 'PUT', 'PATCH')) {
             $invokeParams.ContentType = 'application/json'
         }
    }


    try {
        $response = Invoke-RestMethod @invokeParams
        Write-Verbose "Graph request successful."
        return $response
    }
    catch {
        # Handle Rate Limiting (429)
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 429) {
            $retryAfterHeader = $_.Exception.Response.Headers["Retry-After"]
            $retryAfterSeconds = 30 # Default retry
            if ($retryAfterHeader -and $retryAfterHeader -match '^\d+$') {
                $retryAfterSeconds = [int]$retryAfterHeader
            }
            Write-Warning "Rate limited (429). Retrying after $retryAfterSeconds seconds..."
            Start-Sleep -Seconds $retryAfterSeconds
            # Recursive call to retry
            return Invoke-MsGraphRequest @PSBoundParameters
        }
        # Handle other potential errors
        else {
            $errorMessage = "Error calling Graph API '$($Uri)': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorMessage += " Status Code: $($_.Exception.Response.StatusCode)."
                try {
                    $errorBody = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorBody)
                    $errorDetails = $reader.ReadToEnd()
                    $reader.Close()
                    $errorBody.Close()
                    $errorMessage += " Response: $errorDetails"
                } catch {
                    $errorMessage += " (Could not read error response body)."
                }
            }
            Write-Error $errorMessage
            throw # Re-throw the original exception after logging details
        }
    }
}

function Get-MsGraphPaginatedResults {
    <#
    .SYNOPSIS
    Retrieves all results from a paginated Microsoft Graph API endpoint.
    .DESCRIPTION
    Handles the '@odata.nextLink' property in Graph API responses to automatically
    fetch all pages of data for a given request.
    .PARAMETER AccessToken
    The OAuth2 Access Token for authentication.
    .PARAMETER Uri
    The initial URI for the paginated Graph API endpoint (e.g., /users, /groups).
    .OUTPUTS
    An array containing all collected items from all pages.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    Write-Verbose "Getting paginated results starting from: $Uri"
    $allResults = [System.Collections.Generic.List[object]]::new()
    $currentUri = $Uri

    while ($currentUri) {
        Write-Verbose "Fetching page: $currentUri"
        $response = Invoke-MsGraphRequest -AccessToken $AccessToken -Uri $currentUri -Method GET

        if ($response -ne $null) {
             # Check if the response itself is the collection (e.g., from $count) or has a 'value' property
            if ($response -is [array]) {
                 $allResults.AddRange($response)
                 Write-Verbose "Added $($response.Count) items from direct array response."
            } elseif ($response.PSObject.Properties['value'] -ne $null -and $response.value -is [array]) {
                $allResults.AddRange($response.value)
                 Write-Verbose "Added $($response.value.Count) items from 'value' property."
            } elseif ($response.PSObject.Properties['value'] -ne $null) {
                 # Handle cases where 'value' is a single object
                 $allResults.Add($response.value)
                 Write-Verbose "Added 1 item from single 'value' property."
            }
            else {
                # Handle cases where the response is a single object without 'value'
                $allResults.Add($response)
                Write-Verbose "Added 1 item from direct object response."
            }

             # Check for the nextLink property
             $currentUri = $null # Assume no next link unless found
             if ($response.PSObject.Properties['@odata.nextLink'] -ne $null) {
                 $currentUri = $response."@odata.nextLink" # Quote property name
                 Write-Verbose "Found nextLink: $currentUri"
             }
        } else {
            # If response is null, stop pagination
            Write-Warning "Received null response while paginating URI '$currentUri'. Stopping pagination."
            $currentUri = $null
        }


    }

    Write-Verbose "Finished pagination. Total items retrieved: $($allResults.Count)"
    return $allResults.ToArray() # Return as a standard array
}

function Get-SubscribedSkus {
    <#
    .SYNOPSIS
    Retrieves all subscribed SKUs (licenses) for the tenant.
    .DESCRIPTION
    Calls the /subscribedSkus Graph API endpoint and handles pagination.
    .PARAMETER AccessToken
    The OAuth2 AccessToken.
    .OUTPUTS
    An array of subscribed SKU objects.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    $uri = "https://graph.microsoft.com/v1.0/subscribedSkus"
    Write-Verbose "Getting subscribed SKUs..."
    return Get-MsGraphPaginatedResults -AccessToken $AccessToken -Uri $uri
}

function Get-TenantUsers {
    <#
    .SYNOPSIS
    Retrieves users from the tenant with specified properties.
    .DESCRIPTION
    Calls the /users Graph API endpoint, handles pagination, and selects specific properties.
    Uses $count=true and ConsistencyLevel=eventual to get total user count for progress reporting.
    .PARAMETER AccessToken
    The OAuth2 AccessToken.
    .PARAMETER Properties
    An array of user properties to select. Defaults to common license-related properties.
    .PARAMETER Top
    The number of users to retrieve per page. Defaults to 999 (max allowed).
    .OUTPUTS
    A PSCustomObject containing the total user count ('Count') and an array of user objects ('Users').
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [string[]]$Properties = @("id", "displayName", "userPrincipalName", "assignedLicenses", "userType", "accountEnabled"),

        [Parameter(Mandatory = $false)]
        [int]$Top = 999 # Max users per page
    )

    # Ensure required properties for licensing are included
    $requiredProps = @("id", "assignedLicenses")
    $selectProps = ($Properties + $requiredProps | Select-Object -Unique) -join ","

    # Use $count=true to get total number of users for progress bar
    # Requires ConsistencyLevel=eventual header (added in Invoke-MsGraphRequest)
    $uri = "https://graph.microsoft.com/v1.0/users?`$select=$selectProps&`$top=$Top&`$count=true"
    Write-Verbose "Getting users with properties: $selectProps"

    # Initial request to get the first page and the total count
    Write-Verbose "Fetching first page and total count from: $uri"
    $initialResponse = Invoke-MsGraphRequest -AccessToken $AccessToken -Uri $uri -Method GET

    $totalUserCount = 0
    if ($initialResponse -and $initialResponse.PSObject.Properties['@odata.count'] -ne $null) {
         $totalUserCount = [int]$initialResponse."@odata.count" # Quote property name
         Write-Verbose "Total user count from @odata.count: $totalUserCount"
    } else {
         Write-Warning "Could not retrieve total user count (@odata.count). Progress bar may not be accurate."
    }


    # Now use the paginated function starting from the initial URI to get all users
    # The count is already obtained, so we just need the user objects
    $allUsers = Get-MsGraphPaginatedResults -AccessToken $AccessToken -Uri $uri

     return [PSCustomObject]@{
         Count = $totalUserCount
         Users = $allUsers
     }
}

function Get-UserLicenseDetails {
    <#
    .SYNOPSIS
    Retrieves detailed license information for a specific user.
    .DESCRIPTION
    Calls the /users/{id}/licenseDetails Graph API endpoint and handles pagination.
    .PARAMETER AccessToken
    The OAuth2 AccessToken.
    .PARAMETER UserId
    The ID (GUID) of the user.
    .OUTPUTS
    An array of license detail objects for the user.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    if ([string]::IsNullOrWhiteSpace($UserId)) {
        Write-Error "UserId cannot be empty."
        throw "UserId cannot be empty."
    }

    $uri = "https://graph.microsoft.com/v1.0/users/$UserId/licenseDetails"
    Write-Verbose "Getting license details for user ID: $UserId"
    return Get-MsGraphPaginatedResults -AccessToken $AccessToken -Uri $uri
}
#endregion Graph API Wrappers

#------------------------------------------------------------------------------
#region Report Processing and Generation Functions
#------------------------------------------------------------------------------

function Process-LicenseData {
    <#
    .SYNOPSIS
    Processes raw user and license data into a structured report format.
    .DESCRIPTION
    Takes user data, subscribed SKU information, license mappings, and fetches detailed license information
    for each user. It then consolidates this data into an array of PSCustomObjects, ready for output.
    Handles mapping IDs to friendly names, calculating consumption, and optionally including service plan details.
    .PARAMETER UsersData
    The object returned by Get-TenantUsers, containing the user count and user array.
    .PARAMETER SubscribedSkus
    An array of subscribed SKU objects from Get-SubscribedSkus.
    .PARAMETER SkuIdToNameMap
    Hashtable mapping SKU GUIDs to friendly names (from Get-LicenseMappings).
    .PARAMETER SkuPartNumberToNameMap
    Hashtable mapping SKU Part Numbers (String IDs) to friendly names (from Get-LicenseMappings).
    .PARAMETER AccessToken
    The OAuth2 Access Token, required for fetching user license details.
    .PARAMETER IncludeServicePlans
    Switch to include detailed service plan information.
    .PARAMETER IncludeUnlicensed
    Switch to include users with no licenses in the report.
    .OUTPUTS
    An array of PSCustomObjects, each representing a user's license assignment (or lack thereof).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$UsersData, # Expecting object with Count and Users properties

        [Parameter(Mandatory = $true)]
        [array]$SubscribedSkus,

        [Parameter(Mandatory = $true)]
        [hashtable]$SkuIdToNameMap,

        [Parameter(Mandatory = $true)]
        [hashtable]$SkuPartNumberToNameMap,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeServicePlans,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeUnlicensed
    )

    Write-Verbose "Starting license data processing."
    $licenseReportData = [System.Collections.Generic.List[object]]::new()

    # Create lookup for SKU consumption data
    $skuLookup = @{}
    foreach ($sku in $SubscribedSkus) {
        if ($sku -and $sku.skuId) {
             if (-not $skuLookup.ContainsKey($sku.skuId)) {
                 $skuLookup[$sku.skuId] = $sku
             } else {
                 Write-Verbose "Duplicate SKU ID found in SubscribedSkus: $($sku.skuId). Using first encountered."
             }
        } else {
            Write-Verbose "Skipping an invalid SKU object in SubscribedSkus."
        }
    }
    Write-Verbose "Created SKU lookup table with $($skuLookup.Count) entries."

    $counter = 0
    # Use the count provided by Get-TenantUsers if available
    $totalUsers = if ($UsersData.Count -gt 0) { $UsersData.Count } else { $UsersData.Users.Count }
    Write-Host "Processing license information for $totalUsers users..." -ForegroundColor Cyan

    foreach ($user in $UsersData.Users) {
        $counter++
        Write-Progress -Activity "Processing user license data" -Status "Processing user $counter of $totalUsers ($($user.userPrincipalName))" -PercentComplete (($counter / $totalUsers) * 100)

        $userHasLicenses = $user.assignedLicenses -and $user.assignedLicenses.Count -gt 0

        # Skip users with no licenses if not including unlicensed users
        if (-not $userHasLicenses -and -not $IncludeUnlicensed) {
            Write-Verbose "Skipping unlicensed user $($user.userPrincipalName) as -IncludeUnlicensed is not specified."
            continue
        }

        # Handle unlicensed users if requested
        if (-not $userHasLicenses) {
            Write-Verbose "Adding unlicensed user $($user.userPrincipalName) to report."
            $licenseReportData.Add([PSCustomObject]@{ # Use .Add for List
                UserDisplayName = $user.displayName
                UserPrincipalName = $user.userPrincipalName
                UserType = $user.userType
                AccountEnabled = $user.accountEnabled
                HasLicenses = $false
                LicenseSkuId = "N/A"
                LicenseSkuPartNumber = "N/A"
                LicenseFriendlyName = "Unlicensed"
                TotalAvailable = "N/A"
                Consumed = "N/A"
                Available = "N/A"
                ServicePlansEnabled = "N/A"
                ServicePlansDisabled = "N/A"
            })
            continue # Move to the next user
        }

        # Process licensed users
        Write-Verbose "Processing licenses for user $($user.userPrincipalName) ($($user.id))"
        try {
            # Get detailed license information for this specific user
            $userLicenseDetails = Get-UserLicenseDetails -AccessToken $AccessToken -UserId $user.id
            Write-Verbose "Retrieved $($userLicenseDetails.Count) license detail entries for user $($user.userPrincipalName)"

            if ($userLicenseDetails.Count -eq 0) {
                 Write-Verbose "User $($user.userPrincipalName) has assignedLicenses property but Get-UserLicenseDetails returned empty. Treating as effectively unlicensed for this report."
                 if ($IncludeUnlicensed) {
                     $licenseReportData.Add([PSCustomObject]@{ # Use .Add for List
                         UserDisplayName = $user.displayName
                         UserPrincipalName = $user.userPrincipalName
                         UserType = $user.userType
                         AccountEnabled = $user.accountEnabled
                         HasLicenses = $false # Mark as false based on details
                         LicenseSkuId = "N/A (No Details)"
                         LicenseSkuPartNumber = "N/A (No Details)"
                         LicenseFriendlyName = "Unlicensed (No Details)"
                         TotalAvailable = "N/A"
                         Consumed = "N/A"
                         Available = "N/A"
                         ServicePlansEnabled = "N/A"
                         ServicePlansDisabled = "N/A"
                     })
                 }
                 continue # Move to next user
            }


            foreach ($licenseDetail in $userLicenseDetails) {
                $skuId = $licenseDetail.skuId
                $skuPartNumber = $licenseDetail.skuPartNumber
                
                # Check if this SKU should be ignored
                if ($global:ignoredSkuPartNumbers -contains $skuPartNumber) {
                    Write-Verbose "Ignoring license with SkuPartNumber '$skuPartNumber' for user $($user.userPrincipalName) as it is in the ignore list."
                    continue # Skip to the next licenseDetail for this user
                }

                # Get friendly name from mapping
                $friendlyName = "Unknown License"
                if ($SkuIdToNameMap.ContainsKey($skuId)) {
                    $friendlyName = $SkuIdToNameMap[$skuId]
                    Write-Verbose "Mapped SKU ID $skuId to '$friendlyName'"
                }
                elseif ($SkuPartNumberToNameMap.ContainsKey($skuPartNumber)) {
                    $friendlyName = $SkuPartNumberToNameMap[$skuPartNumber]
                    Write-Verbose "Mapped SKU Part Number $skuPartNumber to '$friendlyName'"
                }
                else {
                    $friendlyName = $skuPartNumber # Fallback to part number if no mapping found
                    Write-Verbose "No mapping found for SKU ID $skuId or Part Number $skuPartNumber. Using Part Number as name."
                }

                # Get consumption data from the overall SKU info
                $skuInfo = $skuLookup[$skuId]
                $totalAvailable = "Unknown"
                $consumed = "Unknown"
                $available = "Unknown"

                if ($skuInfo) {
                    # Check for prepaidUnits property existence
                    if ($skuInfo.PSObject.Properties['prepaidUnits'] -ne $null) {
                        $totalAvailable = $skuInfo.prepaidUnits.enabled
                        $consumed = $skuInfo.consumedUnits
                        # Calculate available, handle potential nulls
                        if ($totalAvailable -ne $null -and $consumed -ne $null -and $totalAvailable -ge 0) {
                            $available = $totalAvailable - $consumed
                        } else {
                             $available = "Calculation Error" # Indicate issue if values are unexpected
                        }
                    } else {
                         Write-Verbose "SKU Info for $skuId exists but missing 'prepaidUnits' property."
                         $totalAvailable = "N/A (Missing Data)"
                         $consumed = if($skuInfo.consumedUnits -ne $null) { $skuInfo.consumedUnits } else { "N/A (Missing Data)"}
                         $available = "N/A (Missing Data)"
                    }
                } else {
                    Write-Verbose "No SKU information found in subscribedSkus for SKU ID: $skuId. Consumption data unavailable."
                }

                # Process service plans if requested
                $servicePlansEnabledInfo = "Not Included"
                $servicePlansDisabledInfo = "Not Included"

                if ($IncludeServicePlans) {
                    $enabledPlans = [System.Collections.Generic.List[string]]::new()
                    $disabledPlans = [System.Collections.Generic.List[string]]::new()

                    if ($licenseDetail.servicePlans) {
                        foreach ($servicePlan in $licenseDetail.servicePlans) {
                            $planId = $servicePlan.servicePlanId
                            $planName = $servicePlan.servicePlanName
                            $provisioningStatus = $servicePlan.provisioningStatus

                            # Try to get friendly name for the service plan
                            $friendlyPlanName = $planName # Default to technical name
                            if ($SkuIdToNameMap.ContainsKey($planId)) {
                                $friendlyPlanName = $SkuIdToNameMap[$planId]
                            }
                            elseif ($planName -ne $null -and $SkuPartNumberToNameMap.ContainsKey($planName)) {
                                # Sometimes servicePlanName matches a String_Id in the CSV
                                $friendlyPlanName = $SkuPartNumberToNameMap[$planName]
                            }

                            $planEntry = "$friendlyPlanName ($planId)"

                            if ($provisioningStatus -eq "Success") {
                                $enabledPlans.Add($planEntry)
                            } else {
                                $disabledPlans.Add("$planEntry [Status: $provisioningStatus]")
                            }
                        }
                         $servicePlansEnabledInfo = $enabledPlans -join "; "
                         $servicePlansDisabledInfo = $disabledPlans -join "; "
                         if ($enabledPlans.Count -eq 0) { $servicePlansEnabledInfo = "None Enabled" }
                         if ($disabledPlans.Count -eq 0) { $servicePlansDisabledInfo = "None Disabled" }
                    } else {
                         $servicePlansEnabledInfo = "No Service Plan Data"
                         $servicePlansDisabledInfo = "No Service Plan Data"
                    }
                }

                # Add record to the report data
                $licenseReportData.Add([PSCustomObject]@{ # Use .Add for List
                    UserDisplayName = $user.displayName
                    UserPrincipalName = $user.userPrincipalName
                    UserType = $user.userType
                    AccountEnabled = $user.accountEnabled
                    HasLicenses = $true
                    LicenseSkuId = $skuId
                    LicenseSkuPartNumber = $skuPartNumber
                    LicenseFriendlyName = $friendlyName
                    TotalAvailable = $totalAvailable
                    Consumed = $consumed
                    Available = $available
                    ServicePlansEnabled = $servicePlansEnabledInfo
                    ServicePlansDisabled = $servicePlansDisabledInfo
                })
                 Write-Verbose "Added license '$friendlyName' for user $($user.userPrincipalName) to report."
            }
        }
        catch {
            Write-Error "Failed to process licenses for user $($user.userPrincipalName) (ID: $($user.id)): $($_.Exception.Message)"
            # Optionally add an error record to the report
            $licenseReportData.Add([PSCustomObject]@{ # Use .Add for List
                UserDisplayName = $user.displayName
                UserPrincipalName = $user.userPrincipalName
                UserType = $user.userType
                AccountEnabled = $user.accountEnabled
                HasLicenses = $userHasLicenses # Reflect initial check
                LicenseSkuId = "ERROR"
                LicenseSkuPartNumber = "ERROR"
                LicenseFriendlyName = "ERROR Processing Licenses"
                TotalAvailable = "ERROR"
                Consumed = "ERROR"
                Available = "ERROR"
                ServicePlansEnabled = "ERROR: $($_.Exception.Message)"
                ServicePlansDisabled = "ERROR"
            })
        }
    }

    Write-Progress -Activity "Processing user license data" -Completed
    Write-Verbose "Finished processing license data. Total records generated: $($licenseReportData.Count)"
    return $licenseReportData.ToArray() # Return as a standard array
}

function Export-LicenseReportToCsv {
    <#
    .SYNOPSIS
    Exports the processed license report data to a CSV file.
    .DESCRIPTION
    Takes the array of processed license report objects and exports it to the specified CSV file path
    using the standard Export-Csv cmdlet.
    .PARAMETER ReportData
    The array of PSCustomObjects generated by Process-LicenseData.
    .PARAMETER OutputPath
    The full file path where the CSV report should be saved.
    .NOTES
    Uses -NoTypeInformation to keep the CSV clean.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ReportData,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    if ($ReportData.Count -eq 0) {
        Write-Warning "No data to export to CSV."
        return
    }

    Write-Verbose "Exporting report data to CSV: $OutputPath"
    try {
        # Ensure the directory exists
        $DirectoryPath = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $DirectoryPath)) {
            Write-Verbose "Creating directory: $DirectoryPath"
            New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
        }

        # Select the desired columns in order - this ensures consistency
        # Exclude service plans if they weren't included in processing to avoid empty columns
        $propertiesToExport = @(
            'UserDisplayName',
            'UserPrincipalName',
            'UserType',
            'AccountEnabled',
            'HasLicenses',
            'LicenseFriendlyName',
            'LicenseSkuId',
            'LicenseSkuPartNumber',
            'TotalAvailable',
            'Consumed',
            'Available'
        )
        # Check if the first record has service plan data (assumes consistency)
        if ($ReportData[0].PSObject.Properties['ServicePlansEnabled'] -ne $null -and $ReportData[0].ServicePlansEnabled -ne 'Not Included') {
             $propertiesToExport += 'ServicePlansEnabled', 'ServicePlansDisabled'
             Write-Verbose "Including Service Plan columns in CSV export."
        }


        $ReportData | Select-Object -Property $propertiesToExport | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "CSV report successfully saved to: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export report to CSV at '$OutputPath': $($_.Exception.Message)"
        throw
    }
}

function Export-LicenseReportToHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ReportData,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$ReportTitle = "Microsoft 365 License Report",
        
        [Parameter(Mandatory = $false)]
        [string]$TenantName = "Not Available",
        
        [Parameter(Mandatory = $false)]
        [string]$TenantId = "Not Available",
        
        # Add parameters to receive global counts
        [Parameter(Mandatory = $false)]
        [int]$GlobalTotalLicenses = -1,
        [Parameter(Mandatory = $false)]
        [int]$GlobalConsumedLicenses = -1,
        [Parameter(Mandatory = $false)]
        [int]$GlobalAvailableLicenses = -1
    )

    if ($ReportData.Count -eq 0) {
        Write-Warning "No data to export to HTML."
        return
    }

    Write-Verbose "Exporting report data to HTML: $OutputPath"

    try {
        # Calculate license totals for the summary section - USE THE PASSED GLOBAL TOTALS INSTEAD
        # $userLicenses = $ReportData | Where-Object { $_.HasLicenses -eq $true }
        # $uniqueUsers = $ReportData | Select-Object -Property UserPrincipalName -Unique
        # $licenseCounts = $userLicenses | Group-Object LicenseFriendlyName | Select-Object Name, Count
        # $totalUsers = $uniqueUsers.Count
        # $totalLicensed = ($uniqueUsers | Where-Object { 
        #     $upn = $_.UserPrincipalName
        #     $ReportData | Where-Object { $_.UserPrincipalName -eq $upn -and $_.HasLicenses -eq $true } 
        # }).Count
        # $totalUnlicensed = $totalUsers - $totalLicensed
        
        # Create license summary data table (This is for the TABLE, not the top cards)
        $licenseSummaryData = @()
        $licenseGroups = $ReportData | Where-Object { $_.HasLicenses -eq $true } | Group-Object -Property LicenseSkuId, LicenseFriendlyName, LicenseSkuPartNumber
        
        foreach ($group in $licenseGroups) {
            if ($group.Count -gt 0) {
                $firstRecord = $group.Group[0]
                
                # Extract metadata from the first record for the table
                $licenseSummaryData += [PSCustomObject]@{
                    LicenseName = $firstRecord.LicenseFriendlyName
                    SkuPartNumber = $firstRecord.LicenseSkuPartNumber
                    SkuId = $firstRecord.LicenseSkuId
                    Total = $firstRecord.TotalAvailable
                    Consumed = $firstRecord.Consumed
                    Available = $firstRecord.Available
                }
            }
        }
        
        # Generate summary table rows (This is for the TABLE named 'License Details')
        $licenseSummaryRows = ""
        foreach ($license in $licenseSummaryData) {
            $availableClass = ""
            if ($license.Available -is [int] -and $license.Available -lt 0) { # Check if Available is integer before comparison
                $availableClass = ' class="negative-available"'
            } elseif ($license.Available -is [int] -and $license.Available -le 10) { # Check if Available is integer
                $availableClass = ' class="low-available"'
            }
            
            $licenseSummaryRows += @"
            <tr>
                <td>$([System.Web.HttpUtility]::HtmlEncode($license.LicenseName))</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($license.SkuPartNumber))</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($license.SkuId))</td>
                <td>$($license.Total)</td>
                <td>$($license.Consumed)</td>
                <td$availableClass>$($license.Available)</td>
            </tr>
"@
        }
        
        # Generate detail rows for the user licenses
        $detailRows = ""
        foreach ($entry in $ReportData) {
            $licenseStatus = if ($entry.HasLicenses) { "Licensed" } else { "Unlicensed" }
            $accountStatus = if ($entry.AccountEnabled) { "Enabled" } else { "Disabled" }
            
            $detailRows += @"
            <tr>
                <td>$([System.Web.HttpUtility]::HtmlEncode($entry.UserDisplayName))</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($entry.UserPrincipalName))</td>
                <td>$accountStatus</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($entry.LicenseFriendlyName))</td>
                <td>$licenseStatus</td>
            </tr>
"@
        }
        
        # Get template paths
        $scriptPath = $PSScriptRoot
        $templatePath = Join-Path -Path $scriptPath -ChildPath "ReportTemplates\template.html"
        $cssPath = Join-Path -Path $scriptPath -ChildPath "ReportTemplates\css\report.css"
        $jsPath = Join-Path -Path $scriptPath -ChildPath "ReportTemplates\js\report.js"
        
        # Read CSS and JS directly into variables for embedding
        $cssContent = ""
        $jsContent = ""
        
        if (Test-Path -Path $cssPath) {
            $cssContent = Get-Content -Path $cssPath -Raw
        } else {
            Write-Warning "CSS file not found at '$cssPath'. Using basic styling only."
        }
        
        if (Test-Path -Path $jsPath) {
            $jsContent = Get-Content -Path $jsPath -Raw
        } else {
            Write-Warning "JavaScript file not found at '$jsPath'. Some interactive features will be unavailable."
        }
        
        # Create license data for JavaScript Charts (based on per-license summary)
        $licenseDataForCharts = @()
        foreach ($license in $licenseSummaryData) {
            # Convert string values to integers where needed, handle non-numeric values
            $chartTotalLicenses = 0
            $chartConsumedLicenses = 0
            $chartAvailableLicenses = 0
            
            # Safely convert values to integers for charts
            if ($license.Total -match '^\d+$') {
                $chartTotalLicenses = [int]$license.Total
            }
            
            if ($license.Consumed -match '^\d+$') {
                $chartConsumedLicenses = [int]$license.Consumed
            }
            
            if ($license.Available -match '^-?\d+$') {
                $chartAvailableLicenses = [int]$license.Available
            }
            
            # Use PSCustomObject instead of hashtable for more reliable serialization
            $licenseDataForCharts += [PSCustomObject]@{
                LicenseName = $license.LicenseName
                Count = $chartConsumedLicenses  # For pie chart, based on consumed for this specific license
                TotalLicenses = $chartTotalLicenses
                ConsumedLicenses = $chartConsumedLicenses
                AvailableLicenses = $chartAvailableLicenses
            }
        }
        
        # Ensure we have at least an empty array if no data is available
        if ($licenseDataForCharts.Count -eq 0) {
            Write-Verbose "No license data available for charts. Creating a placeholder."
            $licenseDataForCharts = @([PSCustomObject]@{
                LicenseName = "No Licenses"
                Count = 0
                TotalLicenses = 0
                ConsumedLicenses = 0
                AvailableLicenses = 0
            })
        }
        
        # Convert to JSON with depth 10 to ensure all properties are included
        $licenseDataJson = $licenseDataForCharts | ConvertTo-Json -Depth 10
        
        # Fix for JavaScript syntax - wrap the JSON with var declaration to make it valid
        $licenseDataJson = "var licenseSummaryData = $licenseDataJson;"
        
        # Add debugging support for charts
        $licenseDataJson += @"

// Debug license data structure
console.log('License data loaded:', licenseSummaryData);
if (licenseSummaryData && licenseSummaryData.length > 0) {
    console.log('First license entry:', licenseSummaryData[0]);
} else {
    console.error('No license summary data available for charts');
}
"@
        
        # Create license summary data for JavaScript Table (this is the full table data)
        $licenseDetailDataJson = $licenseSummaryData | ConvertTo-Json -Depth 10
        # Add to the JavaScript
        $licenseDataJson += "\nvar licenseDetailData = $licenseDetailDataJson;"
        
        # Create timestamp for file
        $dateStamp = Get-Date -Format "yyyyMMdd"
        
        # Check if template exists
        if (-not (Test-Path -Path $templatePath)) {
            Write-Warning "HTML template not found at '$templatePath'. Using basic HTML output instead."
            # Fall back to basic HTML
            $css = @"
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; font-size: 0.9em; }
    table { border-collapse: collapse; width: 95%; margin: 15px auto; border: 1px solid #ddd; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background-color: #4CAF50; color: white; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    tr:hover { background-color: #ddd; }
    caption { caption-side: top; font-size: 1.2em; font-weight: bold; margin: 10px; color: #333; }
    .account-disabled { color: red; font-weight: bold; }
    .unlicensed { color: orange; font-style: italic; }
    .error { color: red; background-color: yellow; font-weight: bold; }
</style>
"@

            # Select properties for the HTML table
            $propertiesToExport = @(
                'UserDisplayName',
                'UserPrincipalName',
                'UserType',
                'AccountEnabled',
                'HasLicenses',
                'LicenseFriendlyName',
                'LicenseSkuId',
                'LicenseSkuPartNumber',
                'TotalAvailable',
                'Consumed',
                'Available'
            )
            # Add service plan columns if they exist in the data
            if ($ReportData[0].PSObject.Properties['ServicePlansEnabled'] -ne $null -and $ReportData[0].ServicePlansEnabled -ne 'Not Included') {
                 $propertiesToExport += 'ServicePlansEnabled', 'ServicePlansDisabled'
                 Write-Verbose "Including Service Plan columns in HTML export."
            }

            # Generate HTML fragment for the table
            $htmlTable = $ReportData | Select-Object -Property $propertiesToExport | ConvertTo-Html -Fragment

            # Add tenant info to the HTML
            $tenantInfo = "<div style='text-align:center; margin-bottom:20px;'><strong>Tenant:</strong> $TenantName ($TenantId)</div>"

            # Assemble the full HTML document
            $htmlContent = ConvertTo-Html -Head $css -Body "$tenantInfo<table><caption>$ReportTitle (Generated: $(Get-Date))</caption>$htmlTable</table>" -Title $ReportTitle

            # Ensure the directory exists
            $DirectoryPath = Split-Path -Path $OutputPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($DirectoryPath) -and -not (Test-Path -Path $DirectoryPath)) {
                Write-Verbose "Creating directory: $DirectoryPath"
                New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
            }

            # Save the HTML content to the file
            $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8

            Write-Host "HTML report (basic format) successfully saved to: $OutputPath" -ForegroundColor Green
            return
        }
        
        # Use the modern template with the user license details section
        # Read template
        $templateContent = Get-Content -Path $templatePath -Raw
        
        # Prepare the user details section (Keep this)
        $userLicenseDetailsHtml = @"
        <div class="card mb-4">
            <div class="card-header d-flex justify-content-between align-items-center">
                <h5 class="mb-0">User License Details</h5>
                <button class="btn btn-sm btn-outline-secondary" id="exportUserBtn">
                    <i class="bi bi-download me-1"></i> Export
                </button>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table id="userLicenseTable" class="table table-striped table-hover">
                        <thead>
                            <tr>
                                <th>User</th>
                                <th>UPN</th>
                                <th>Account Status</th>
                                <th>License</th>
                                <th>License Status</th>
                            </tr>
                        </thead>
                        <tbody>
                            $detailRows
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
"@
        
        # Create a pattern to match the entire user license details section including placeholders
        $userDetailsPattern = '(?s){{USER_LICENSE_DETAILS_START}}.*?{{USER_LICENSE_DETAILS_END}}'
        
        # Replace placeholders
        $replacements = @{
            '{{REPORT_TITLE}}' = $ReportTitle
            '{{GENERATION_DATE}}' = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            '{{TENANT_NAME}}' = [System.Web.HttpUtility]::HtmlEncode($TenantName)
            '{{TENANT_ID}}' = [System.Web.HttpUtility]::HtmlEncode($TenantId)
            '{{LICENSE_SUMMARY_ROWS}}' = $licenseSummaryRows
            '{{LICENSE_SUMMARY_DATA}}' = $licenseDataJson
            '{{TOTAL_LICENSES}}' = if ($GlobalTotalLicenses -ge 0) { $GlobalTotalLicenses } else { "N/A" }
            '{{ASSIGNED_LICENSES}}' = if ($GlobalConsumedLicenses -ge 0) { $GlobalConsumedLicenses } else { "N/A" }
            '{{AVAILABLE_LICENSES}}' = if ($GlobalAvailableLicenses -ge -($GlobalTotalLicenses + 100000)) { $GlobalAvailableLicenses } else { "N/A" }
            '{{CSS_PATH}}' = ""
            '{{JS_PATH}}' = ""
            '{{USER_LICENSE_DETAIL_ROWS}}' = ""
            '{{DATE_STAMP}}' = $dateStamp
        }

        $htmlContent = $templateContent
        foreach ($key in $replacements.Keys) {
            $htmlContent = $htmlContent -replace [regex]::Escape($key), $replacements[$key]
        }
        
        # Replace the entire user details section with our generated content
        $htmlContent = $htmlContent -replace $userDetailsPattern, $userLicenseDetailsHtml
        
        # Embed CSS and JavaScript directly
        $htmlContent = $htmlContent -replace '<link rel="stylesheet" href="{{CSS_PATH}}">', "<style>$cssContent</style>"
        $htmlContent = $htmlContent -replace '<script src="{{JS_PATH}}"></script>', "<script>$jsContent</script>"
        
        # Add an additional script tag for Chart.js directly to ensure it's loaded
        $chartJsTag = '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.2.1/dist/chart.umd.min.js"></script>'
        $htmlContent = $htmlContent -replace '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.2.1/dist/chart.umd.min.js"></script>', "$chartJsTag$chartJsTag"
        
        # Add additional JavaScript to ensure DataTables are properly initialized
        # Use a single-quoted heredoc to prevent PowerShell expansion of '$' inside JavaScript
        $additionalJs = @'
<script>
// Additional JavaScript for DataTables initialization
$(document).ready(function() {
    // Check Chart.js availability
    console.log('Chart.js library status:', typeof Chart === 'undefined' ? 'NOT LOADED' : 'Loaded and ready');
    
    // Initialize the main license details table (was licenseSummaryTable)
    if ($('#licenseSummaryTable').length) {
        $('#licenseSummaryTable').DataTable({
            paging: false, // Keep paging off for summary table
            searching: true,
            info: false,
            order: [[3, 'desc']], // Sort by Total column descending
            responsive: true
        });
    }

    // Initialize user license table if it exists
    if ($('#userLicenseTable').length) {
        $('#userLicenseTable').DataTable({
            pageLength: 25,
            searching: true,
            responsive: true,
            // Add any specific configurations for user table here
        });
    }

    // Connect export buttons to the correct tables
    $('#exportSummaryBtn').click(function() { // Button for the license summary table
        exportTableToExcel('licenseSummaryTable', 'License_Details_{{TENANT_NAME}}_{{DATE_STAMP}}');
    });
    $('#exportUserBtn').click(function() { // Button for the user license details table
        exportTableToExcel('userLicenseTable', 'User_Licenses_{{TENANT_NAME}}_{{DATE_STAMP}}');
    });

    // Re-apply styling to available license numbers in the summary table
    document.querySelectorAll('#licenseSummaryTable tbody td:nth-child(6)').forEach(cell => { // Target 6th cell (Available)
        const valueText = cell.textContent.trim();
        if (valueText.match(/^-?\d+$/)) { // Check if it's an integer
            const value = parseInt(valueText);
            if (value < 0) {
                cell.classList.add('negative-available');
            } else if (value <= 10) {
                cell.classList.add('low-available');
            }
        }
    });

    // Apply styling to the top summary cards if needed
    const availableLicensesCard = document.getElementById('availableLicenses');
    if (availableLicensesCard) {
        const valueText = availableLicensesCard.textContent.trim();
        if (valueText.match(/^-?\d+$/)) {
            const value = parseInt(valueText);
            if (value < 0) {
                availableLicensesCard.classList.add('negative-available');
            } else if (value <= 10) {
                availableLicensesCard.classList.add('low-available');
            }
        }
    }
});
</script>
'@
        
        # Insert the additional JS right before the closing body tag
        $htmlContent = $htmlContent -replace '</body>', "$additionalJs</body>"

        # Ensure the directory exists
        $DirectoryPath = Split-Path -Path $OutputPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($DirectoryPath) -and -not (Test-Path -Path $DirectoryPath)) {
            Write-Verbose "Creating directory: $DirectoryPath"
            New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
        }

        # Save the HTML content to the file
        $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8

        Write-Host "HTML report successfully saved to: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export report to HTML at '$OutputPath': $($_.Exception.Message)"
        throw
    }
}

function Show-LicenseReportInTerminal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ReportData,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeServicePlans # Add parameter to control verbosity
    )

    if ($ReportData.Count -eq 0) {
        Write-Warning "No data to display in terminal."
        return
    }

    Write-Verbose "Preparing terminal output..."

    # --- Retro Header ---*
    Write-Host "
╔" + ("═" * 60) + "╗" -ForegroundColor Green
    Write-Host "║" + (" " * 16) + " M365 LICENSE REPORT CONSOLE " + (" " * 15) + "║" -ForegroundColor Green
    Write-Host "╚" + ("═" * 60) + "╝" -ForegroundColor Green
    Write-Host "Generated: $(Get-Date)" -ForegroundColor Cyan
    Write-Host ("─" * 62) -ForegroundColor Green

    # --- Summary Section ---*
    Write-Host "
--- REPORT SUMMARY ---" -ForegroundColor Yellow
    $totalEntries = $ReportData.Count
    $licensedUsers = $ReportData | Where-Object { $_.HasLicenses -eq $true }
    $distinctLicensedUsers = $licensedUsers | Select-Object -ExpandProperty UserPrincipalName -Unique
    $unlicensedUsers = $ReportData | Where-Object { $_.HasLicenses -eq $false }

    Write-Host "Total Users Processed   : $($distinctLicensedUsers.Count + $unlicensedUsers.Count)" -ForegroundColor White
    Write-Host "  - Licensed Users      : $($distinctLicensedUsers.Count)" -ForegroundColor Green
    Write-Host "  - Unlicensed Users    : $($unlicensedUsers.Count)" -ForegroundColor Magenta
    Write-Host "Total License Entries   : $($licensedUsers.Count)" -ForegroundColor White

    Write-Host "
License Distribution:" -ForegroundColor Yellow
    $licenseSummary = $licensedUsers | Group-Object -Property LicenseFriendlyName | Sort-Object Count -Descending
    if ($licenseSummary) {
        $licenseSummary | ForEach-Object {
            Write-Host ("  - {0,-40} : {1}" -f $_.Name, $_.Count) -ForegroundColor White
        }
    } else {
         Write-Host "  No licensed users found." -ForegroundColor Magenta
    }
    
    # --- License Summary Table ---*
    Write-Host "
--- LICENSE SUMMARY TABLE ---" -ForegroundColor Yellow
    Write-Host ("─" * 72) -ForegroundColor Green
    
    # Create a detailed summary table with usage stats
    $licenseSummaryData = @()
    
    # Group and summarize license data
    $licenseGroups = $licensedUsers | Group-Object -Property LicenseSkuId, LicenseFriendlyName, LicenseSkuPartNumber
    
    foreach ($group in $licenseGroups) {
        if ($group.Count -gt 0) {
            $firstRecord = $group.Group[0]
            
            # Extract metadata from the first record
            $licenseSummaryData += [PSCustomObject]@{
                LicenseName = $firstRecord.LicenseFriendlyName
                SkuPartNumber = $firstRecord.LicenseSkuPartNumber
                SkuId = $firstRecord.LicenseSkuId
                Total = $firstRecord.TotalAvailable
                Consumed = $firstRecord.Consumed
                Available = $firstRecord.Available
            }
        }
    }
    
    # Sort by total licenses
    $licenseSummaryData = $licenseSummaryData | Sort-Object -Property Total -Descending
    
    # Display the summary table
    $licenseSummaryData | Format-Table -Property @(
        @{Name='License Name'; Expression={$_.LicenseName}; Width=45 },
        @{Name='SKU ID'; Expression={$_.SkuId}; Width=36 },
        @{Name='Total'; Expression={$_.Total}; Width=10; Alignment='Right'},
        @{Name='Consumed'; Expression={$_.Consumed}; Width=10; Alignment='Right'},
        @{Name='Available'; Expression={$_.Available}; Width=10; Alignment='Right'}
    ) -AutoSize

    # --- Detailed Report Section ---*
    Write-Host "
--- DETAILED USER REPORT ---" -ForegroundColor Yellow
    Write-Host ("─" * 62) -ForegroundColor Green

    $counter = 0
    foreach ($entry in $ReportData) {
        $counter++
        # User Header
        Write-Host ("
[{0}] User: {1} ({2})" -f $counter, $entry.UserDisplayName, $entry.UserPrincipalName) -ForegroundColor Cyan
        Write-Host ("    Type: {0} | Enabled: " -f $entry.UserType) -NoNewline -ForegroundColor White
        if ($entry.AccountEnabled) {
            Write-Host $entry.AccountEnabled -ForegroundColor Green
        } else {
            Write-Host $entry.AccountEnabled -ForegroundColor Red
        }

        # License Details
        if ($entry.HasLicenses -eq $true) {
            Write-Host "    License :" -ForegroundColor Yellow -NoNewline
            Write-Host (" {0} (SKU: {1} | Part: {2})" -f $entry.LicenseFriendlyName, $entry.LicenseSkuId, $entry.LicenseSkuPartNumber) -ForegroundColor White
            Write-Host "    Usage   :" -ForegroundColor Yellow -NoNewline
            Write-Host (" Total={0} | Consumed={1} | Available={2}" -f $entry.TotalAvailable, $entry.Consumed, $entry.Available) -ForegroundColor White

            if ($IncludeServicePlans -and $entry.PSObject.Properties['ServicePlansEnabled'] -ne $null -and $entry.ServicePlansEnabled -ne 'Not Included') {
                Write-Host "    SvcPlans:
       Enabled : $($entry.ServicePlansEnabled)" -ForegroundColor Green
                 Write-Host "       Disabled: $($entry.ServicePlansDisabled)" -ForegroundColor Magenta
            }
        } elseif ($entry.LicenseFriendlyName -match "ERROR") {
            Write-Host "    License :" -ForegroundColor Red -NoNewline
            Write-Host " ERROR Processing Licenses - $($entry.ServicePlansEnabled)" -ForegroundColor Red
        }
         else {
            Write-Host "    License : Unlicensed" -ForegroundColor Magenta
        }

        # Add a small separator
         if ($counter % 5 -eq 0) { # Add separator every 5 users for readability
             Write-Host ("·" * 62) -ForegroundColor DarkGray
         }
    }

    # --- Footer ---*
    Write-Host ("
" + "═" * 62) -ForegroundColor Green
    Write-Host "End of Report." -ForegroundColor Cyan
    Write-Host ("═" * 62) -ForegroundColor Green

    Write-Verbose "Finished displaying terminal output."
}

function Show-LicenseSummaryInTerminal {
    <#
    .SYNOPSIS
    Displays a summary table of tenant licenses and their usage counts.
    .DESCRIPTION
    Takes the subscribed SKU data and license mappings and formats a summary table
    showing friendly names, SKU IDs, total, consumed, and available counts for each license.
    .PARAMETER SubscribedSkus
    An array of subscribed SKU objects from Get-SubscribedSkus.
    .PARAMETER SkuIdToNameMap
    Hashtable mapping SKU GUIDs to friendly names (from Get-LicenseMappings).
    .PARAMETER SkuPartNumberToNameMap
    Hashtable mapping SKU Part Numbers (String IDs) to friendly names (from Get-LicenseMappings).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SubscribedSkus,
        [Parameter(Mandatory = $true)]
        [hashtable]$SkuIdToNameMap,
        [Parameter(Mandatory = $true)]
        [hashtable]$SkuPartNumberToNameMap
    )

    if ($SubscribedSkus.Count -eq 0) {
        Write-Warning "No subscribed SKU data found to display summary."
        return
    }

    Write-Verbose "Preparing license summary terminal output..."

    # Filter out ignored SKUs
    $filteredSkus = $SubscribedSkus | Where-Object { $null -ne $_ -and $_.skuPartNumber -notin $global:ignoredSkuPartNumbers }
    if ($filteredSkus.Count -ne $SubscribedSkus.Count) {
        Write-Verbose "Filtered out $($SubscribedSkus.Count - $filteredSkus.Count) ignored SKUs."
    }

    $summaryData = foreach ($sku in $filteredSkus) {
        $skuId = $sku.skuId
        $skuPartNumber = $sku.skuPartNumber

        # Get friendly name
        $friendlyName = "Unknown License"
        if ($SkuIdToNameMap.ContainsKey($skuId)) {
            $friendlyName = $SkuIdToNameMap[$skuId]
        }
        elseif ($SkuPartNumberToNameMap.ContainsKey($skuPartNumber)) {
            $friendlyName = $SkuPartNumberToNameMap[$skuPartNumber]
        }
        else {
            $friendlyName = $skuPartNumber # Fallback
        }

        # Get counts
        $total = 0
        $consumed = $sku.consumedUnits
        $available = 0
        if ($sku.prepaidUnits) {
            $total = $sku.prepaidUnits.enabled
            if ($total -ne $null -and $consumed -ne $null) {
                $available = $total - $consumed
            }
        }

        [PSCustomObject]@{            
            LicenseName = $friendlyName
            SkuId = $skuId
            Total = $total
            Consumed = $consumed
            Available = $available
        }
    }

    # --- Retro Header ---*
    Write-Host "
╔" + ("═" * 70) + "╗" -ForegroundColor Green
    Write-Host "║" + (" " * 21) + " M365 LICENSE SUMMARY CONSOLE " + (" " * 20) + "║" -ForegroundColor Green
    Write-Host "╚" + ("═" * 70) + "╝" -ForegroundColor Green
    Write-Host "Generated: $(Get-Date)" -ForegroundColor Cyan
    Write-Host ("─" * 72) -ForegroundColor Green

    # Display the formatted table
    $summaryData | Format-Table -Property @(
        @{Name='License Name'; Expression={$_.LicenseName}; Width=45 },
        @{Name='SKU ID'; Expression={$_.SkuId}; Width=36 },
        @{Name='Total'; Expression={$_.Total}; Width=10; Alignment='Right'},
        @{Name='Consumed'; Expression={$_.Consumed}; Width=10; Alignment='Right'},
        @{Name='Available'; Expression={$_.Available}; Width=10; Alignment='Right'}
    ) -AutoSize

    # --- Footer ---*
    Write-Host ("═" * 72) -ForegroundColor Green
    Write-Host "End of License Summary." -ForegroundColor Cyan
    Write-Host ("═" * 72) -ForegroundColor Green
}

function Export-LicenseSummaryToCsv {
    <#
    .SYNOPSIS
    Exports a summary of tenant licenses to a CSV file.
    .DESCRIPTION
    Takes the subscribed SKU data and license mappings and exports a summary table
    showing friendly names, SKU IDs, total, consumed, and available counts to a CSV file.
    .PARAMETER SubscribedSkus
    An array of subscribed SKU objects from Get-SubscribedSkus.
    .PARAMETER SkuIdToNameMap
    Hashtable mapping SKU GUIDs to friendly names (from Get-LicenseMappings).
    .PARAMETER SkuPartNumberToNameMap
    Hashtable mapping SKU Part Numbers (String IDs) to friendly names (from Get-LicenseMappings).
    .PARAMETER OutputPath
    The full file path where the CSV report should be saved.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SubscribedSkus,
        [Parameter(Mandatory = $true)]
        [hashtable]$SkuIdToNameMap,
        [Parameter(Mandatory = $true)]
        [hashtable]$SkuPartNumberToNameMap,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    if ($SubscribedSkus.Count -eq 0) {
        Write-Warning "No subscribed SKU data found to export to CSV."
        return
    }

    Write-Verbose "Preparing license summary for CSV export: $OutputPath"

    # Filter out ignored SKUs
    $filteredSkus = $SubscribedSkus | Where-Object { $null -ne $_ -and $_.skuPartNumber -notin $global:ignoredSkuPartNumbers }
    if ($filteredSkus.Count -ne $SubscribedSkus.Count) {
        Write-Verbose "Filtered out $($SubscribedSkus.Count - $filteredSkus.Count) ignored SKUs."
    }

    # Prepare the summary data
    $summaryData = foreach ($sku in $filteredSkus) {
        $skuId = $sku.skuId
        $skuPartNumber = $sku.skuPartNumber

        # Get friendly name
        $friendlyName = "Unknown License"
        if ($SkuIdToNameMap.ContainsKey($skuId)) {
            $friendlyName = $SkuIdToNameMap[$skuId]
        }
        elseif ($SkuPartNumberToNameMap.ContainsKey($skuPartNumber)) {
            $friendlyName = $SkuPartNumberToNameMap[$skuPartNumber]
        }
        else {
            $friendlyName = $skuPartNumber # Fallback
        }

        # Get counts
        $total = 0
        $consumed = $sku.consumedUnits
        $available = 0
        if ($sku.prepaidUnits) {
            $total = $sku.prepaidUnits.enabled
            if ($total -ne $null -and $consumed -ne $null) {
                $available = $total - $consumed
            }
        }

        [PSCustomObject]@{            
            LicenseName = $friendlyName
            SkuPartNumber = $skuPartNumber
            SkuId = $skuId
            TotalLicenses = $total
            ConsumedLicenses = $consumed
            AvailableLicenses = $available
        }
    }

    try {
        # Ensure the directory exists
        $DirectoryPath = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $DirectoryPath)) {
            Write-Verbose "Creating directory: $DirectoryPath"
            New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
        }

        # Export to CSV
        $summaryData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "License summary CSV successfully saved to: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export license summary to CSV at '$OutputPath': $($_.Exception.Message)"
        throw
    }
}

function Export-LicenseSummaryToHtml {
    <#
    .SYNOPSIS
    Exports a summary of tenant licenses to an HTML file.
    .DESCRIPTION
    Takes the subscribed SKU data and license mappings and exports a summary table
    showing friendly names, SKU IDs, total, consumed, and available counts to an HTML file with basic styling.
    .PARAMETER SubscribedSkus
    An array of subscribed SKU objects from Get-SubscribedSkus.
    .PARAMETER SkuIdToNameMap
    Hashtable mapping SKU GUIDs to friendly names (from Get-LicenseMappings).
    .PARAMETER SkuPartNumberToNameMap
    Hashtable mapping SKU Part Numbers (String IDs) to friendly names (from Get-LicenseMappings).
    .PARAMETER OutputPath
    The full file path where the HTML report should be saved.
    .PARAMETER ReportTitle
    Optional title for the HTML report page.
    .PARAMETER TenantName
    Custom tenant name to use in the report instead of the actual tenant name.
    .PARAMETER TenantId
    Identifier to add to the output filenames for better organization.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SubscribedSkus,
        [Parameter(Mandatory = $true)]
        [hashtable]$SkuIdToNameMap,
        [Parameter(Mandatory = $true)]
        [hashtable]$SkuPartNumberToNameMap,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $false)]
        [string]$ReportTitle = "Microsoft 365 License Summary Report",
        [Parameter(Mandatory = $false)]
        [string]$TenantName = "Not Available",
        [Parameter(Mandatory = $false)]
        [string]$TenantId = "Not Available",

        # Add parameters to receive global counts for summary report as well
        [Parameter(Mandatory = $false)]
        [int]$GlobalTotalLicenses = -1,
        [Parameter(Mandatory = $false)]
        [int]$GlobalConsumedLicenses = -1,
        [Parameter(Mandatory = $false)]
        [int]$GlobalAvailableLicenses = -1
    )

    if ($SubscribedSkus.Count -eq 0) {
        Write-Warning "No subscribed SKU data found to export to HTML."
        return
    }

    Write-Verbose "Preparing license summary for HTML export: $OutputPath"

    # Filter out ignored SKUs
    $filteredSkus = $SubscribedSkus | Where-Object { $null -ne $_ -and $_.skuPartNumber -notin $global:ignoredSkuPartNumbers }
    if ($filteredSkus.Count -ne $SubscribedSkus.Count) {
        Write-Verbose "Filtered out $($SubscribedSkus.Count - $filteredSkus.Count) ignored SKUs."
    }

    # Prepare the summary data for the table
    $summaryData = foreach ($sku in $filteredSkus) {
        $skuId = $sku.skuId
        $skuPartNumber = $sku.skuPartNumber

        # Get friendly name
        $friendlyName = "Unknown License"
        if ($SkuIdToNameMap.ContainsKey($skuId)) {
            $friendlyName = $SkuIdToNameMap[$skuId]
        }
        elseif ($SkuPartNumberToNameMap.ContainsKey($skuPartNumber)) {
            $friendlyName = $SkuPartNumberToNameMap[$skuPartNumber]
        }
        else {
            $friendlyName = $skuPartNumber # Fallback
        }

        # Get counts
        $total = 0
        $consumed = $sku.consumedUnits
        $available = 0
        if ($sku.prepaidUnits -and $sku.prepaidUnits.enabled -ne $null) { # Check prepaidUnits exists
            $total = $sku.prepaidUnits.enabled
            if ($consumed -eq $null) { $consumed = 0 } # Ensure consumed is numeric
            $available = $total - $consumed
        } else {
            # Handle case where prepaidUnits might be missing (e.g., trial licenses)
            $total = 0
            if ($consumed -eq $null) { $consumed = 0 }
            $available = 0 - $consumed # Available will be negative consumed
        }

        [PSCustomObject]@{            
            LicenseName = $friendlyName
            SkuPartNumber = $skuPartNumber
            SkuId = $skuId
            TotalLicenses = $total
            ConsumedLicenses = $consumed
            AvailableLicenses = $available
        }
    }

    try {
        # Use the globally calculated totals if provided, otherwise calculate from the summaryData
        $totalLicenses = if ($GlobalTotalLicenses -ge 0) { $GlobalTotalLicenses } else { ($summaryData | Measure-Object -Property TotalLicenses -Sum).Sum }
        $totalConsumed = if ($GlobalConsumedLicenses -ge 0) { $GlobalConsumedLicenses } else { ($summaryData | Measure-Object -Property ConsumedLicenses -Sum).Sum }
        $totalAvailable = if ($GlobalAvailableLicenses -ge -($GlobalTotalLicenses + 100000)) { $GlobalAvailableLicenses } else { ($summaryData | Measure-Object -Property AvailableLicenses -Sum).Sum } # Use large negative sentinel check

        # Generate table rows for the template
        $tableRows = ""
        foreach ($item in $summaryData) {
            $availableClass = ""
            if ($item.AvailableLicenses -lt 0) {
                $availableClass = ' class="negative-available"'
            } elseif ($item.AvailableLicenses -le 10) {
                $availableClass = ' class="low-available"'
            }
            
            $tableRows += @"
            <tr>
                <td>$([System.Web.HttpUtility]::HtmlEncode($item.LicenseName))</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($item.SkuPartNumber))</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($item.SkuId))</td>
                <td>$($item.TotalLicenses)</td>
                <td>$($item.ConsumedLicenses)</td>
                <td$availableClass>$($item.AvailableLicenses)</td>
            </tr>
"@
        }

        # Get template paths
        $scriptPath = $PSScriptRoot
        $templatePath = Join-Path -Path $scriptPath -ChildPath "ReportTemplates\template.html"
        $cssPath = Join-Path -Path $scriptPath -ChildPath "ReportTemplates\css\report.css"
        $jsPath = Join-Path -Path $scriptPath -ChildPath "ReportTemplates\js\report.js"
        
        # Read CSS and JS directly into variables for embedding
        $cssContent = ""
        $jsContent = ""
        
        if (Test-Path -Path $cssPath) {
            $cssContent = Get-Content -Path $cssPath -Raw
        } else {
            Write-Warning "CSS file not found at '$cssPath'. Using basic styling only."
        }
        
        if (Test-Path -Path $jsPath) {
            $jsContent = Get-Content -Path $jsPath -Raw
        } else {
            Write-Warning "JavaScript file not found at '$jsPath'. Some interactive features will be unavailable."
        }
        
        # Check if template exists
        if (-not (Test-Path -Path $templatePath)) {
            Write-Warning "HTML template not found at '$templatePath'. Using basic HTML output instead."
            # Fall back to basic HTML (original implementation)
            $basicHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>$ReportTitle</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; font-size: 0.9em; }
        h1 { color: #2E7D32; text-align: center; }
        p.timestamp { text-align: center; color: #666; margin-bottom: 20px; }
        table { border-collapse: collapse; width: 90%; margin: 20px auto; border: 1px solid #ddd; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        tr:hover { background-color: #ddd; }
        .negative-available { color: red; font-weight: bold; }
        .low-available { color: orange; font-weight: bold; }
    </style>
</head>
<body>
    <h1>$ReportTitle</h1>
    <p class="timestamp">Generated: $(Get-Date)</p>
    <p>Tenant: $TenantName ($TenantId)</p>
    <table>
        <tr>
            <th>License Name</th>
            <th>Part Number</th>
            <th>SKU ID</th>
            <th>Total</th>
            <th>Consumed</th>
            <th>Available</th>
        </tr>
        $tableRows
    </table>
</body>
</html>
"@
            # Ensure the directory exists
            $DirectoryPath = Split-Path -Path $OutputPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($DirectoryPath) -and -not (Test-Path -Path $DirectoryPath)) {
                Write-Verbose "Creating directory: $DirectoryPath"
                New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
            }

            # Output basic HTML
            $basicHtml | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Host "License summary HTML (basic format) successfully saved to: $OutputPath" -ForegroundColor Green
            return
        }

        # Read template
        $templateContent = Get-Content -Path $templatePath -Raw

        # Create license data for JavaScript Charts (based on per-license summary)
        $licenseDataForCharts = @()
        foreach ($license in $summaryData) {
            # Convert values to integers where needed, handle non-numeric values
            $chartTotalLicenses = 0
            $chartConsumedLicenses = 0
            $chartAvailableLicenses = 0
            
            if ($license.TotalLicenses -is [int]) { $chartTotalLicenses = $license.TotalLicenses }
            if ($license.ConsumedLicenses -is [int]) { $chartConsumedLicenses = $license.ConsumedLicenses }
            if ($license.AvailableLicenses -is [int]) { $chartAvailableLicenses = $license.AvailableLicenses }
            
            # Use PSCustomObject instead of hashtable for more reliable serialization
            $licenseDataForCharts += [PSCustomObject]@{
                LicenseName = $license.LicenseName
                Count = $chartConsumedLicenses  # For pie chart, based on consumed for this specific license
                TotalLicenses = $chartTotalLicenses
                ConsumedLicenses = $chartConsumedLicenses
                AvailableLicenses = $chartAvailableLicenses
            }
        }
        
        # Ensure we have at least an empty array if no data is available
        if ($licenseDataForCharts.Count -eq 0) {
            Write-Verbose "No license data available for charts. Creating a placeholder."
            $licenseDataForCharts = @([PSCustomObject]@{
                LicenseName = "No Licenses"
                Count = 0
                TotalLicenses = 0
                ConsumedLicenses = 0
                AvailableLicenses = 0
            })
        }
        
        # Convert to JSON with depth 10 to ensure all properties are included
        $licenseDataJson = $licenseDataForCharts | ConvertTo-Json -Depth 10
        
        # Fix for JavaScript syntax - wrap the JSON with var declaration to make it valid
        $licenseDataJson = "var licenseSummaryData = $licenseDataJson;"
        
        # Add debugging support for charts
        $licenseDataJson += @"

// Debug license data structure
console.log('License data loaded:', licenseSummaryData);
if (licenseSummaryData && licenseSummaryData.length > 0) {
    console.log('First license entry:', licenseSummaryData[0]);
} else {
    console.error('No license summary data available for charts');
}
"@
        
        # Create license summary data for JavaScript Table (this is the full table data)
        $licenseDetailDataJson = $summaryData | ConvertTo-Json -Depth 10
        # Add to the JavaScript
        $licenseDataJson += "\nvar licenseDetailData = $licenseDetailDataJson;"
        
        # Create timestamp for file
        $dateStamp = Get-Date -Format "yyyyMMdd"

        # Replace placeholders
        $replacements = @{
            '{{REPORT_TITLE}}' = $ReportTitle
            '{{GENERATION_DATE}}' = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            '{{TENANT_NAME}}' = [System.Web.HttpUtility]::HtmlEncode($TenantName)
            '{{TENANT_ID}}' = [System.Web.HttpUtility]::HtmlEncode($TenantId)
            '{{LICENSE_SUMMARY_ROWS}}' = $tableRows
            '{{LICENSE_SUMMARY_DATA}}' = $licenseDataJson
            '{{TOTAL_LICENSES}}' = $totalLicenses
            '{{ASSIGNED_LICENSES}}' = $totalConsumed
            '{{AVAILABLE_LICENSES}}' = $totalAvailable
            '{{CSS_PATH}}' = ""
            '{{JS_PATH}}' = ""
            '{{USER_LICENSE_DETAIL_ROWS}}' = ""
            '{{DATE_STAMP}}' = $dateStamp
        }

        $htmlContent = $templateContent
        foreach ($key in $replacements.Keys) {
            $htmlContent = $htmlContent -replace [regex]::Escape($key), $replacements[$key]
        }
        
        # Replace the entire user details section with empty content for the summary report
        $userDetailsPattern = '(?s){{USER_LICENSE_DETAILS_START}}.*?{{USER_LICENSE_DETAILS_END}}'
        $htmlContent = $htmlContent -replace $userDetailsPattern, "<!-- No user details in summary report -->"
        
        # Embed CSS and JavaScript directly
        $htmlContent = $htmlContent -replace '<link rel="stylesheet" href="{{CSS_PATH}}">', "<style>$cssContent</style>"
        $htmlContent = $htmlContent -replace '<script src="{{JS_PATH}}"></script>', "<script>$jsContent</script>"
        
        # Add an additional script tag for Chart.js directly to ensure it's loaded
        $chartJsTag = '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.2.1/dist/chart.umd.min.js"></script>'
        $htmlContent = $htmlContent -replace '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.2.1/dist/chart.umd.min.js"></script>', "$chartJsTag$chartJsTag"
        
        # Add additional JavaScript to ensure DataTables are properly initialized
        # Use a single-quoted heredoc to prevent PowerShell expansion of '$' inside JavaScript
        $additionalJs = @'
<script>
// Additional JavaScript for DataTables initialization
$(document).ready(function() {
    // Initialize license summary table if it exists
    if ($('#licenseSummaryTable').length) {
        $('#licenseSummaryTable').DataTable({
            paging: false,
            searching: true,
            info: false,
            order: [[3, 'desc']], // Sort by Total column descending
            responsive: true
        });
    }
    
    // Connect export button to the correct table
    $('#exportSummaryBtn').click(function() {
        exportTableToExcel('licenseSummaryTable', 'License_Details_{{TENANT_NAME}}_{{DATE_STAMP}}'); // Corrected filename
    });

    // Add styling logic for available licenses in summary table
    document.querySelectorAll('#licenseSummaryTable tbody td:nth-child(6)').forEach(cell => {
        const valueText = cell.textContent.trim();
        if (valueText.match(/^-?\d+$/)) { // Check if it's an integer
            const value = parseInt(valueText);
            if (value < 0) { cell.classList.add('negative-available'); }
            else if (value <= 10) { cell.classList.add('low-available'); }
        }
    });

    // Apply styling to the top summary cards
    function styleSummaryCard(elementId) {
        const cardElement = document.getElementById(elementId);
        if (cardElement) {
            const valueText = cardElement.textContent.trim();
            if (valueText.match(/^-?\d+$/)) { // Check if it's an integer
                const value = parseInt(valueText);
                if (elementId === 'availableLicenses') {
                    cardElement.classList.remove('negative-available', 'low-available'); 
                    if (value < 0) { cardElement.classList.add('negative-available'); }
                    else if (value <= 10) { cardElement.classList.add('low-available'); }
                }
            }
        }
    }
    styleSummaryCard('totalLicenses');
    styleSummaryCard('assignedLicenses');
    styleSummaryCard('availableLicenses');
});
</script>
'@
        
        # Insert the additional JS right before the closing body tag
        $htmlContent = $htmlContent -replace '</body>', "$additionalJs</body>"

        # Ensure the directory exists
        $DirectoryPath = Split-Path -Path $OutputPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($DirectoryPath) -and -not (Test-Path -Path $DirectoryPath)) {
            Write-Verbose "Creating directory: $DirectoryPath"
            New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
        }

        # Save HTML file
        $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8

        Write-Host "License summary HTML successfully saved to: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export license summary to HTML at '$OutputPath': $($_.Exception.Message)"
        throw
    }
}

# Helper function to get relative path
function Get-RelativePath {
    param (
        [string]$TargetPath,
        [string]$BasePath
    )
    
    # Convert to full paths
    $TargetPath = [System.IO.Path]::GetFullPath($TargetPath)
    $BasePath = [System.IO.Path]::GetFullPath($BasePath)
    
    # Get the directory of the base path
    $BaseDir = [System.IO.Path]::GetDirectoryName($BasePath)
    
    # Calculate the relative path
    $Uri = New-Object System.Uri($BaseDir)
    $RelPath = $Uri.MakeRelativeUri((New-Object System.Uri($TargetPath))).ToString()
    
    # Convert URL format to local path format
    $RelPath = [System.Web.HttpUtility]::UrlDecode($RelPath).Replace('/', '\')
    
    return $RelPath
}

#------------------------------------------------------------------------------
#endregion Report Processing and Generation Functions
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
#region Main Script Logic / Controller Function
#------------------------------------------------------------------------------

function Start-M365LicenseReport {
    [CmdletBinding(SupportsShouldProcess=$false)]
    param ()

    Write-Verbose "Starting M365 License Report Generation"

    # Default behavior: If no output specified, assume terminal output
    if (-not $PSBoundParameters.ContainsKey('OutputCsv') -and `
        -not $PSBoundParameters.ContainsKey('OutputHtml') -and `
        -not $PSBoundParameters.ContainsKey('CsvPath') -and `
        -not $PSBoundParameters.ContainsKey('HtmlPath') -and `
        -not $PSBoundParameters.ContainsKey('ShowInTerminal') -and `
        -not $PSBoundParameters.ContainsKey('LicenseSummaryOnly')) {
        Write-Verbose "No output format specified, defaulting to ShowInTerminal (full report)."
        $script:ShowInTerminal = $true
    }

    # 1. Authentication
    Write-Host "`nStep 1: Authenticating to Microsoft Graph..." -ForegroundColor Cyan
    $tokenInfo = Get-MsGraphToken
    if (-not $tokenInfo -or -not $tokenInfo.AccessToken) {
        Write-Error "Authentication failed. Cannot proceed."
        return
    }
    Write-Host "Authentication successful." -ForegroundColor Green
    
    # Get tenant information for filenames and reporting
    $tenantActualId = $tokenInfo.TenantId
    $tenantActualName = $tokenInfo.TenantName
    
    # Determine tenant name/ID to USE based on parameters or defaults
    $tenantIdForFilename = if ($TenantIdentifier) { $TenantIdentifier } else { $tenantActualId }
    $tenantNameForReport = if ($TenantName) { $TenantName } elseif ($tenantActualName) { $tenantActualName } else { $tenantActualId } # Use provided name, then actual name, fallback to ID
    $tenantIdForReport = $tenantActualId # Always use the actual ID for the report display alongside the name

    # Create a safe filename string from the NAME used for reporting
    $safeTenantName = $tenantNameForReport -replace '[^\w\-\.]', '_'
    $filenameTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    # Include the ID used for filename (which might be custom) in the prefix
    $filenamePrefix = "M365License_${safeTenantName}_${tenantIdForFilename}_$filenameTimestamp"
    
    # Configure default output paths if needed
    $scriptPath = $PSScriptRoot
    $reportsFolder = Join-Path -Path $scriptPath -ChildPath "Reports"
    
    # Create Reports folder if it doesn't exist
    if (-not (Test-Path -Path $reportsFolder)) {
        Write-Verbose "Creating Reports folder: $reportsFolder"
        New-Item -ItemType Directory -Path $reportsFolder -Force | Out-Null
    }
    
    # Determine CSV path based on parameter combination
    $outputCsvPath = $null
    if ($CsvPath) {
        # If CsvPath is provided, use it (check if it's relative or absolute)
        if ([System.IO.Path]::IsPathRooted($CsvPath)) {
            $outputCsvPath = $CsvPath
        } else {
            $outputCsvPath = Join-Path -Path $reportsFolder -ChildPath $CsvPath
        }
        Write-Verbose "Using custom CSV path: $outputCsvPath"
    } elseif ($OutputCsv) {
        # If OutputCsv switch is used, create default path
        $reportType = if ($LicenseSummaryOnly) { "Summary" } else { "Full" }
        $outputCsvPath = Join-Path -Path $reportsFolder -ChildPath "${filenamePrefix}_${reportType}.csv"
        Write-Verbose "Using default CSV path: $outputCsvPath"
    }
    
    # Determine HTML path based on parameter combination
    $outputHtmlPath = $null
    if ($HtmlPath) {
        # If HtmlPath is provided, use it (check if it's relative or absolute)
        if ([System.IO.Path]::IsPathRooted($HtmlPath)) {
            $outputHtmlPath = $HtmlPath
        } else {
            $outputHtmlPath = Join-Path -Path $reportsFolder -ChildPath $HtmlPath
        }
        Write-Verbose "Using custom HTML path: $outputHtmlPath"
    } elseif ($OutputHtml) {
        # If OutputHtml switch is used, create default path
        $reportType = if ($LicenseSummaryOnly) { "Summary" } else { "Full" }
        $outputHtmlPath = Join-Path -Path $reportsFolder -ChildPath "${filenamePrefix}_${reportType}.html"
        Write-Verbose "Using default HTML path: $outputHtmlPath"
    }

    # 2. Get License Mappings
    Write-Host "`nStep 2: Loading license mappings..." -ForegroundColor Cyan
    $licenseMappings = Get-LicenseMappings
    Write-Host "License mappings loaded successfully." -ForegroundColor Green

    # 3. Get Subscribed SKUs
    Write-Host "`nStep 3: Retrieving license information from tenant..." -ForegroundColor Cyan
    $subscribedSkus = Get-SubscribedSkus -AccessToken $tokenInfo.AccessToken
    
    # Initialize global counts
    $script:globalTenantTotalLicenses = 0
    $script:globalTenantConsumedLicenses = 0
    $script:globalTenantAvailableLicenses = 0
    
    if (-not $subscribedSkus -or $subscribedSkus.Count -eq 0) {
        Write-Warning "No license information found. The tenant may not have any licenses, or the authenticated account may not have permission to view them."
        # Defaults remain 0 if no SKUs found
    } else {
        Write-Host "Retrieved $($subscribedSkus.Count) license SKU(s) from tenant." -ForegroundColor Green
        
        # --- Calculate Global Tenant License Totals ---*
        Write-Verbose "Calculating global tenant license totals from subscribed SKUs..."
        $filteredTenantSkus = $subscribedSkus | Where-Object { $null -ne $_ -and $_.skuPartNumber -notin $global:ignoredSkuPartNumbers }
        foreach ($sku in $filteredTenantSkus) {
            if ($sku.prepaidUnits -and $sku.prepaidUnits.enabled -ne $null) {
                $script:globalTenantTotalLicenses += $sku.prepaidUnits.enabled
            }
            if ($sku.consumedUnits -ne $null) {
                $script:globalTenantConsumedLicenses += $sku.consumedUnits
            }
        }
        # Ensure calculation happens even if total is 0
        $script:globalTenantAvailableLicenses = $script:globalTenantTotalLicenses - $script:globalTenantConsumedLicenses
        Write-Verbose "Global Totals: Total=$($script:globalTenantTotalLicenses), Consumed=$($script:globalTenantConsumedLicenses), Available=$($script:globalTenantAvailableLicenses)" # Corrected available calc
        # --- End Calculation ---
    }

    # --- Mode Check ---*
    if ($LicenseSummaryOnly) {
        Write-Host "`nGenerating License Summary..." -ForegroundColor Yellow
        
        # Process output requests
        $outputGenerated = $false
        
        # Check for CSV output
        if ($outputCsvPath) {
            Export-LicenseSummaryToCsv -SubscribedSkus $subscribedSkus `
                                      -SkuIdToNameMap $licenseMappings.SkuIdToName `
                                      -SkuPartNumberToNameMap $licenseMappings.SkuPartNumberToName `
                                      -OutputPath $outputCsvPath
            $outputGenerated = $true
        }

        # Check for HTML output
        if ($outputHtmlPath) {
            Export-LicenseSummaryToHtml -SubscribedSkus $subscribedSkus `
                                        -SkuIdToNameMap $licenseMappings.SkuIdToName `
                                        -SkuPartNumberToNameMap $licenseMappings.SkuPartNumberToName `
                                        -OutputPath $outputHtmlPath `
                                        -ReportTitle "Microsoft 365 License Summary Report" `
                                        -TenantName $tenantNameForReport `
                                        -TenantId $tenantIdForReport `
                                        -GlobalTotalLicenses $script:globalTenantTotalLicenses `
                                        -GlobalConsumedLicenses $script:globalTenantConsumedLicenses `
                                        -GlobalAvailableLicenses $script:globalTenantAvailableLicenses
            $outputGenerated = $true
        }

        # Show terminal output if specifically requested or if no output was generated
        if ($ShowInTerminal -or (-not $outputGenerated -and -not ($PSBoundParameters.ContainsKey('ShowInTerminal') -and $ShowInTerminal -eq $false))) {
            Show-LicenseSummaryInTerminal -SubscribedSkus $subscribedSkus `
                                        -SkuIdToNameMap $licenseMappings.SkuIdToName `
                                        -SkuPartNumberToNameMap $licenseMappings.SkuPartNumberToName
        }
        
        Write-Host "`nLicense summary generation finished." -ForegroundColor Cyan
        return # Exit after showing summary
    }

    # If we get here, we're doing the full report, not just the summary

    # 4. Get User Data
    Write-Host "`nStep 4: Retrieving user data..." -ForegroundColor Cyan
    $usersData = Get-TenantUsers -AccessToken $tokenInfo.AccessToken
    if (-not $usersData -or -not $usersData.Users -or $usersData.Users.Count -eq 0) {
        Write-Error "No user data found. Cannot proceed with report generation."
        return
    }
    Write-Host "Retrieved $($usersData.Users.Count) users." -ForegroundColor Green

    # 5. Process Data
    Write-Host "`nStep 5: Processing license data..." -ForegroundColor Cyan
    $reportData = Process-LicenseData -UsersData $usersData `
                                     -SubscribedSkus $subscribedSkus `
                                     -SkuIdToNameMap $licenseMappings.SkuIdToName `
                                     -SkuPartNumberToNameMap $licenseMappings.SkuPartNumberToName `
                                     -AccessToken $tokenInfo.AccessToken `
                                     -IncludeServicePlans:$IncludeServicePlans `
                                     -IncludeUnlicensed:$IncludeUnlicensed
    Write-Host "License data processed successfully." -ForegroundColor Green

    # 6. Output
    Write-Host "`nStep 6: Generating requested outputs..." -ForegroundColor Cyan
    
    # Generate outputs based on parameters
    if ($outputCsvPath) {
        Export-LicenseReportToCsv -ReportData $reportData -OutputPath $outputCsvPath
    }
    
    if ($outputHtmlPath) {
        # Pass the globally calculated totals to the HTML export function
        Export-LicenseReportToHtml -ReportData $reportData `
                                  -OutputPath $outputHtmlPath `
                                  -TenantName $tenantNameForReport `
                                  -TenantId $tenantIdForReport `
                                  -GlobalTotalLicenses $script:globalTenantTotalLicenses `
                                  -GlobalConsumedLicenses $script:globalTenantConsumedLicenses `
                                  -GlobalAvailableLicenses $script:globalTenantAvailableLicenses
    }
    
    if ($ShowInTerminal) {
        Show-LicenseReportInTerminal -ReportData $reportData
    }
} # <-- Add missing closing brace for Start-M365LicenseReport function

# --- Script Entry Point ---*
# Call the main function with all the parameters passed to the script
Start-M365LicenseReport