using namespace System.Net

param($Request, $TriggerMetadata)

# Function to send message to Slack
function Send-SlackMessage {
    param(
        [object]$Request,
        [string]$WebhookUrl,
        [string]$NerdioUrl
    )

    if ($null -eq $Request.AccountId) {
        $AccountID = 'Global'
    }
    else {
        $AccountID = $Request.AccountId
    }

    if ($Request.Job.JobStatus -eq 'Failed') { 
        $JobStatus = "@here - A critical event has occurred" 
    } else { 
        $JobStatus = $Request.Job.JobStatus
    }
    # Construct the JSON body for Slack with blocks
    $body = @{
        "blocks"     = @(
            @{
                "type" = "header"
                "text" = @{
                    "type"  = "plain_text"
                    "text"  = "New Job Notification"
                    "emoji" = $true
                }
            }
            @{
                "type"   = "section"
                "fields" = @(
                    @{
                        "type" = "mrkdwn"
                        "text" = "*Job Type:* $($Request.Job.JobType)"
                    }
                    @{
                        "type" = "mrkdwn"
                        "text" = "*Initiated by Account ID:* $($AccountID)"
                    }
                )
            }
            @{
                "type"   = "section"
                "fields" = @(
                    @{
                        "type" = "mrkdwn"
                        "text" = "*Job Status:* $($JobStatus)"
                    }
                    @{
                        "type" = "mrkdwn"
                        "text" = "*Job Run Mode:* $($Request.Job.JobRunMode)"
                    }
                )
            }
            @{
                "type"   = "section"
                "fields" = @(
                    @{
                        "type" = "mrkdwn"
                        "text" = "*Timestamp UTC:* $($Request.Job.CreationDateUtc)"
                    }
                    @{
                        "type" = "mrkdwn"
                        "text" = "*User:* $($Request.Job.User)"
                    }
                )
            }
            @{
                "type" = "section"
                "text" = @{
                    "type" = "mrkdwn"
                    "text" = "<https://$NerdioUrl/Logs|View Job Details>"
                }
            }
        )
        "username"   = "Nerdio Bot"  # Customize the bot name here
        "icon_emoji" = ":nerd_face:"    # Customize the bot icon here (using emoji)
        "channel"    = "#general"        # Set this to your Slack channel or leave it for default
    } | ConvertTo-Json -Depth 10

    # Send the message to Slack
    $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType 'application/json'
    return $response
}

try {
    # Webhook URL for your Slack channel
    $webhookUrl = "SLACK_WEBHOOK_URL"  # Replace with your actual webhook URL
    $NerdioUrl = "NERDIO_PORTAL_URL" # Replace with your actual Nerdio URL (e.g. mycompany.nerdio.net)
    # Send the message to Slack
    Send-SlackMessage -Request $Request.body -WebhookUrl $webhookUrl NerdioUrl $NerdioUrl
}
catch {
    $_.Exception.Message
}

# Return response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = "Message sent to Slack successfully!"
    })

