# ****************************************************
# FSLogix Profile Size Monitor - Azure Runbook
# Monitors FSLogix profile sizes and sends alerts via Azure Communication Services
# J.Scholte, Nerdio - 2025-01-28
# ****************************************************



# Function to send email using Azure Communication Services
function Send-ACSEmail {
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
        [string]$SenderAddress
    )

    if (-not (Get-Module -ListAvailable Az.Communication)) {
        Install-Module -Name Az.Communication -Force
        Import-Module Az.Communication -Force
    }

    try {
        # Parse connection string
        $connectionStringParts = $ACSConnectionString -split ';'
        $endpoint = ([System.Uri]($connectionStringParts[0] -split '=')[1]).AbsoluteUri
        $accessKey = ($connectionStringParts[1] -split '=')[1]

        # Set the access key as an environment variable (required by the Az module)
        $env:AZURE_COMMUNICATION_SERVICE_KEY = $accessKey

        # Create email recipient object
        $emailRecipientTo = @(
            @{
                Address     = $ToAddress
                DisplayName = $ToAddress.Split('@')[0]  # Use part before @ as display name
            }
        )

        # Create message object with proper sender address format
        $message = @{
            ContentSubject = $Subject
            RecipientTo    = @($emailRecipientTo)
            SenderAddress  = "$SenderAddress@$($ACSFromAddress)"  # Combine ID with domain
            ContentHtml    = $HtmlContent
        }

        # Send email using Az.Communication module
        $result = Send-AzEmailServicedataEmail -Message $message -Endpoint $endpoint
        
        if ($result.Status -eq "Succeeded") {
            Write-Verbose "Email sent successfully to $ToAddress"
            return $true
        }
        else {
            throw "Email send operation failed with status: $($result.Status)"
        }
    }
    catch {
        Write-Error "Failed to send email: $_"
        return $false
    }
    finally {
        # Clean up the environment variable
        Remove-Item Env:\AZURE_COMMUNICATION_SERVICE_KEY -ErrorAction SilentlyContinue
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

        #Connect to Azure
        #Connect-AzAccount -Identity

        # Ensure required modules are installed
        if (-not (Get-Module -ListAvailable Az.Storage)) {
            Install-Module -Name Az.Storage -Force
        }

        # Create storage context using account key
        $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
        
        # Get or create the table
        $table = Get-AzStorageTable -Name $TableName -Context $ctx -ErrorAction SilentlyContinue
        if (-not $table) {
            $table = New-AzStorageTable -Name $TableName -Context $ctx
        }
    
        # Get current timestamp minus 24 hours (for filtering recent entries)
        $yesterday = [DateTime]::UtcNow.AddHours(-24).ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Query table for low space profiles
        $query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
        $filter = [Microsoft.Azure.Cosmos.Table.TableQuery]::GenerateFilterConditionForDouble(
            "FreeSpacePercent",
            "le",
            $ThresholdPercent
        )
        $query = $query.Where($filter)

        $lowSpaceProfiles = @($table.CloudTable.ExecuteQuery($query))

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
            </tr>
"@

            foreach ($profile in $lowSpaceProfiles) {
                $htmlContent += @"
            <tr>
                <td>$($profile.Properties["Username"].StringValue)</td>
                <td>$([math]::Round($profile.Properties["TotalSizeGB"].DoubleValue, 2))</td>
                <td>$([math]::Round($profile.Properties["UsedSizeGB"].DoubleValue, 2))</td>
                <td>$([math]::Round($profile.Properties["FreeSpacePercent"].DoubleValue, 1))</td>
                <td>$($profile.Properties["LastModified"].DateTime.ToString("yyyy-MM-dd HH:mm:ss"))</td>
                <td>$($profile.Properties["CustomerName"].StringValue)</td>
                <td>$($profile.Properties["HostPoolName"].StringValue)</td>
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
            }

            $retryCount = 0
            $emailSent = $false

            while (-not $emailSent -and $retryCount -lt $MaxRetries) {
                try {
                    $emailResult = Send-ACSEmail @emailParams
                    if ($emailResult) {
                        Write-Output "Alert email sent successfully for $($lowSpaceProfiles.Count) profile(s)"
                        $emailSent = $true
                    } else {
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
    ThresholdPercent    = 15.0
    MaxRetries          = 3
    RetryDelaySeconds   = 2
}

CheckFSLogixTable @params