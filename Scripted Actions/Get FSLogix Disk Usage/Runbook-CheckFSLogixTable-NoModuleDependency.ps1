# ****************************************************
# FSLogix Profile Size Monitor - Azure Runbook (No Module Dependencies)
# Monitors FSLogix profile sizes and sends alerts via Azure Communication Services
# Uses direct REST API calls instead of PowerShell modules
# J.Scholte, Nerdio - 2025-01-28
# ****************************************************

# Function to send email using Azure Communication Services REST API
function Send-ACSEmailREST {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ToAddress,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$HtmlContent,

        [Parameter(Mandatory = $true)]
        [string]$ACSConnectionString,

        [Parameter(Mandatory = $true)]
        [string]$SenderAddress,

        [Parameter(Mandatory = $true)]
        [string]$ACSFromAddress
    )

    try {
        # Parse connection string
        $connectionStringParts = $ACSConnectionString -split ';'
        $endpointPart = $connectionStringParts | Where-Object { $_ -like 'endpoint=*' }
        $accessKeyPart = $connectionStringParts | Where-Object { $_ -like 'accesskey=*' }
        
        if (-not $endpointPart -or -not $accessKeyPart) {
            throw "Invalid ACS Connection String format. Could not find 'endpoint=' or 'accesskey=' parts."
        }

        $endpoint = ($endpointPart -split '=', 2)[1].TrimEnd('/')
        # Correctly extract the key including padding by finding the first '=' and taking the substring after it
        $accessKey = $accessKeyPart.Substring($accessKeyPart.IndexOf('=') + 1).Trim() 

        # Construct the email API endpoint URL
        # Make sure we don't double the https:// prefix
        if ($endpoint -match '^https://') {
            $emailApiUrl = "$endpoint/emails:send?api-version=2023-03-31"
        } else {
            $emailApiUrl = "https://$endpoint/emails:send?api-version=2023-03-31"
        }

        # Create email recipient object
        $emailRecipientTo = @(
            @{
                address     = $ToAddress
                displayName = $ToAddress.Split('@')[0]  # Use part before @ as display name
            }
        )

        # Create message object with proper sender address format
        $messageBody = @{
            senderAddress                  = "$SenderAddress@$ACSFromAddress"
            content                        = @{
                subject = $Subject
                html    = $HtmlContent
            }
            recipients                     = @{
                to = $emailRecipientTo
            }
            userEngagementTrackingDisabled = $true
        } | ConvertTo-Json -Depth 10

        # Calculate content hash
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($messageBody)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $contentHashBytes = $sha256.ComputeHash($bodyBytes)
        $contentHashBase64 = [System.Convert]::ToBase64String($contentHashBytes)

        # Get current date and host
        $dateHeaderValue = [DateTime]::UtcNow.ToString('R')
        $uri = [System.Uri]$endpoint # Use the parsed endpoint directly
        $hostHeaderValue = $uri.Host

        # Construct StringToSign
        $verb = "POST"
        $pathAndQuery = "/emails:send?api-version=2023-03-31" # Corrected path and query
        $stringToSign = "$verb`n$pathAndQuery`n$dateHeaderValue;$hostHeaderValue;$contentHashBase64"
        Write-Verbose "HMAC StringToSign: $($stringToSign -replace "`n", '[newline]')"

        # Clean the access key to remove any non-Base64 characters (Optional, but safe to keep)
        $cleanedAccessKey = $accessKey -replace '[^A-Za-z0-9+/=]', ''
        # Note: If the parsing logic is correct, $cleanedAccessKey should be identical to $accessKey

        # Decode access key and compute signature
        try {
            # Use the cleaned key for decoding, just in case parsing still has subtle issues
            $decodedAccessKey = [System.Convert]::FromBase64String($cleanedAccessKey) 
        } catch {
            Write-Error "Failed to decode Access Key. Ensure it's a valid Base64 string. Error: $_"
            return $false
        }
        $hmacsha256 = New-Object System.Security.Cryptography.HMACSHA256
        $hmacsha256.Key = $decodedAccessKey
        $signatureBytes = $hmacsha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign))
        $signatureBase64 = [System.Convert]::ToBase64String($signatureBytes)

        # Format Authorization header
        # Note: Credential=<key_id> is omitted as it's not easily available from connection string and often optional when signing with the key itself.
        $authorizationHeaderValue = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$signatureBase64"

        # Create headers for the request
        $headers = @{
            'Content-Type'          = 'application/json'
            'x-ms-date'             = $dateHeaderValue
            'host'                  = $hostHeaderValue
            'x-ms-content-sha256'   = $contentHashBase64
            'Authorization'         = $authorizationHeaderValue
        }

        Write-Verbose "Sending email to $ToAddress via $emailApiUrl"
        Write-Verbose "Headers: $($headers | ConvertTo-Json -Compress)"
        Write-Verbose "Message body: $messageBody"

        # Send email using REST API
        # Use -ContentType to ensure correct header is sent by Invoke-RestMethod
        $response = Invoke-RestMethod -Uri $emailApiUrl -Method Post -Headers $headers -Body $messageBody -ContentType 'application/json' -ErrorAction Stop

        Write-Verbose "Email sent successfully to $ToAddress"
        return $true
    }
    catch {
        Write-Error "Failed to send email: $_"
        return $false
    }
}

function CheckFSLogixTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountKey,

        [Parameter(Mandatory = $true)]
        [string]$TableName = "FSLogixProfileUsage",

        [Parameter(Mandatory = $true)]
        [string]$ACSConnectionString,

        [Parameter()]
        [string]$ACSFromAddress = "fslogix-monitor@domain.com",

        [Parameter()]
        [string]$ITSupportEmail = "itsupport@domain.com",

        [Parameter()]
        [double]$ThresholdPercent = 15.0,

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 2
    )

    try {
        # Get current date in RFC1123 format (required for Azure Storage API)
        $date = [DateTime]::UtcNow.ToString('R')

        # Base URL for Azure Table Storage
        $baseUrl = "https://$StorageAccountName.table.core.windows.net"

        # Create authorization headers for Azure Storage Table API
        $headers = @{
            'x-ms-date'    = $date
            'x-ms-version' = '2019-07-07'
            'Accept'       = 'application/json;odata=nometadata'
        }

        # Function to create authorization signature for Azure Storage Table API
        function Create-AzureStorageAuthSignature {
            param (
                [string]$verb,
                [string]$contentLength = "",
                [string]$contentType = "",
                [hashtable]$customHeaders = @{},
                [string]$resource = ""
            )

            # For Table service, the signature format is different from Blob/Queue/File
            # Table service uses a simpler format

            # Get the Content-MD5 header if it exists
            $contentMD5 = ""

            # Construct canonical resource string
            $canonicalizedResource = "/$StorageAccountName/$resource"

            # For Table service, the string to sign is:
            # VERB + "\n" + Content-MD5 + "\n" + Content-Type + "\n" + Date + "\n" + CanonicalizedResource
            $stringToSign = $verb + "`n" +
                           $contentMD5 + "`n" +
                           $contentType + "`n" +
                           $headers['x-ms-date'] + "`n" +
                           $canonicalizedResource

            # For debugging
            Write-Verbose "Table API String to sign: $($stringToSign -replace "`n", "[newline]")"

            # Create signature
            $hmacsha256 = New-Object System.Security.Cryptography.HMACSHA256
            $hmacsha256.Key = [Convert]::FromBase64String($StorageAccountKey)
            $signature = [Convert]::ToBase64String($hmacsha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))

            # Return the authorization header value
            return "SharedKey $($StorageAccountName):$signature"
        }

        # Check if table exists, create if not
        $tableUrl = "$baseUrl/Tables('$TableName')"
        $tableHeaders = $headers.Clone()
        $tableHeaders['Authorization'] = Create-AzureStorageAuthSignature -verb "GET" -resource "Tables('$TableName')"

        try {
            $tableResponse = Invoke-RestMethod -Uri $tableUrl -Method Get -Headers $tableHeaders -ErrorAction SilentlyContinue
        }
        catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 404) {
                # Table doesn't exist, create it
                $createTableUrl = "$baseUrl/Tables"
                $createTableBody = @{ TableName = $TableName } | ConvertTo-Json
                $createTableHeaders = $headers.Clone()
                $createTableHeaders['Authorization'] = Create-AzureStorageAuthSignature -verb "POST" -contentLength $createTableBody.Length -contentType "application/json" -resource "Tables"
                $createTableHeaders['Content-Type'] = "application/json"

                $tableResponse = Invoke-RestMethod -Uri $createTableUrl -Method Post -Headers $createTableHeaders -Body $createTableBody
                Write-Output "Created table $TableName"
            }
            else {
                throw "Error checking table: $_"
            }
        }

        # Query table for low space profiles
        $queryUrl = "$baseUrl/$TableName()?`$filter=FreeSpacePercent le $ThresholdPercent"
        $queryHeaders = $headers.Clone()
        $queryHeaders['Authorization'] = Create-AzureStorageAuthSignature -verb "GET" -resource "$TableName()"

        $response = Invoke-RestMethod -Uri $queryUrl -Method Get -Headers $queryHeaders
        $lowSpaceProfiles = @($response.value)

        # Handle pagination if needed
        while ($response.'odata.nextLink') {
            $nextLink = $response.'odata.nextLink'
            $nextUrl = "$baseUrl/$nextLink"
            $response = Invoke-RestMethod -Uri $nextUrl -Method Get -Headers $queryHeaders
            $lowSpaceProfiles += $response.value
        }

        if ($lowSpaceProfiles.Count -gt 0) {
            # Prepare email content
            $htmlContent = @"
        <h2>FSLogix Profile Space Alert</h2>
        <p>The following FSLogix profiles have less than ${ThresholdPercent}% free space:</p>
        <table border='1' style='border-collapse: collapse; width: 100%;'>
            <tr style='background-color: #f2f2f2;'>
                <th>Username</th>
                <th>Total Size (GB)</th>
                <th>Used Size (GB)</th>
                <th>Free Space %</th>
                <th>Last Modified</th>
                <th>Customer Name</th>
                <th>Host Pool Name</th>
            </tr>
"@

            foreach ($profile in $lowSpaceProfiles) {
                $htmlContent += @"
            <tr>
                <td>$($profile.Username)</td>
                <td>$([math]::Round($profile.TotalSizeGB, 2))</td>
                <td>$([math]::Round($profile.UsedSizeGB, 2))</td>
                <td>$([math]::Round($profile.FreeSpacePercent, 1))</td>
                <td>$($profile.LastModified)</td>
                <td>$($profile.CustomerName)</td>
                <td>$($profile.HostPoolName)</td>
            </tr>
"@
            }

            $htmlContent += @"
        </table>
        <p>Please take appropriate action to prevent profile storage issues.</p>
        <p><small>Generated by FSLogix Profile Monitor at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</small></p>
"@

            # Send email alert
            $emailParams = @{
                ToAddress           = $ITSupportEmail
                Subject             = "FSLogix Profile Space Alert - $($lowSpaceProfiles.Count) Profile(s) Low on Space"
                HtmlContent         = $htmlContent
                ACSConnectionString = $ACSConnectionString
                SenderAddress       = "DoNotReply"
                ACSFromAddress      = $ACSFromAddress
            }

            $retryCount = 0
            $emailSent = $false

            while (-not $emailSent -and $retryCount -lt $MaxRetries) {
                try {
                    $emailResult = Send-ACSEmailREST @emailParams
                    if ($emailResult) {
                        Write-Output "Alert email sent successfully for $($lowSpaceProfiles.Count) profile(s)"
                        $emailSent = $true
                    }
                    else {
                        throw "Email send operation returned false"
                    }
                }
                catch {
                    $retryCount++
                    if ($retryCount -ge $MaxRetries) {
                        Write-Error "Failed to send email alert after $MaxRetries attempts. Last error: $_"
                        throw "Maximum retry attempts ($MaxRetries) reached. Email sending failed."
                    }
                    Write-Warning "Retry attempt $retryCount of $MaxRetries - Failed to send email. Retrying in $RetryDelaySeconds seconds..."
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            }

            if (-not $emailSent) {
                throw "Failed to send email after $MaxRetries attempts"
            }
        }
        else {
            Write-Output "No FSLogix profiles found with free space below $ThresholdPercent%"
        }
    }
    catch {
        Write-Error "Error in FSLogix profile monitor: $_"
        throw
    }
}

# Example usage with environment variables
$params = @{
    StorageAccountName  = $InheritedVars.StorageAccountName
    StorageAccountKey   = $SecureVars.StorageAccountKey
    TableName           = $InheritedVars.TableName
    ACSConnectionString = $SecureVars.ACSConnectionString
    ACSFromAddress      = $InheritedVars.ACSFromAddress
    ITSupportEmail      = $InheritedVars.ITSupportEmail
    Verbose             = $true
    ThresholdPercent    = 15.0
    MaxRetries          = 3
    RetryDelaySeconds   = 2
}

CheckFSLogixTable @params
