using namespace System.Net
param($Request, $TriggerMetadata)

# Function to send message to Microsoft Teams
function Send-TeamsMessage {
    param(
        [object]$Request,
        [string]$WebhookUrl
    )
    if ($null -eq $Request.AccountId) {
        $AccountID = 'Global'
    }
    else {
        $AccountID = $Request.AccountId
    }
    $body = [Ordered]@{
        "type"        = "message"
        "attachments" = @(
            @{
                "contentType" = 'application/vnd.microsoft.card.adaptive'
                "content"     = [Ordered]@{
                    '$schema' = "<http://adaptivecards.io/schemas/adaptive-card.json>"
                    "type"    = "AdaptiveCard"
                    "version" = "1.5"
                    "body"    = @(
                        [Ordered]@{
                            "type"  = "Container"
                            "items" = @(
                                @{
                                    "type"   = "TextBlock"
                                    "text"   = "NMM Notification"
                                    "wrap"   = $true
                                    "weight" = "Bolder"
                                    "size"   = "Large"
                                }
                                @{
                                    "type"   = "TextBlock"
                                    "text"   = "Details of Job ID: $($Request.Job.Id) initiated by Account ID: $($AccountID)"
                                    "wrap"   = $true
                                    "weight" = "Bolder"
                                }
                            )
                        }
                        [Ordered]@{
                            "type"    = "ColumnSet"
                            "columns" = @(
                                @{
                                    "type"  = "Column"
                                    "width" = "stretch"
                                    "items" = @(
                                        @{
                                            "type"  = "FactSet"
                                            "facts" = @(
                                                @{
                                                    "title" = "Job Type"
                                                    "value" = $Request.Job.JobType
                                                }
                                                @{
                                                    "title" = "Job Status"
                                                    "value" = $Request.Job.JobStatus
                                                }
                                                @{
                                                    "title" = "Job Run Mode"
                                                    "value" = $Request.Job.JobRunMode
                                                }
                                                @{
                                                    "title" = "Timestamp UTC"
                                                    "value" = $Request.Job.CreationDateUtc
                                                }
                                            )
                                        }
                                    )
                                }
                            )
                        }
                    )
                }
            }
        )
    }   | ConvertTo-Json -Depth 20




    
    $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType 'application/json'
    return $response
}

try {
    # Webhook URL for your Teams channel
    $webhookUrl = "TEAMS_WEBHOOK_URL"
    # Send the message to Teams
    Send-TeamsMessage -Request $Request.body -WebhookUrl $webhookUrl
}
catch {
    $_.Exception.Message
}

# Return response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = "Message sent to Teams successfully!"
    })
