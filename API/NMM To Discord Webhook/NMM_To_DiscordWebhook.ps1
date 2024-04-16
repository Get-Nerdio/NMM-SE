using namespace System.Net
param($Request, $TriggerMetadata)

# Function to send message to Microsoft Teams
function Send-DiscordMessage {
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
    
    # Construct Discord message
    $Fields = @(
        @{ name = "Job Type"; value = $Request.Job.JobType; inline = $true }
        @{ name = "Job Status"; value = $Request.Job.JobStatus; inline = $true }
        @{ name = "Job Run Mode"; value = $Request.Job.JobRunMode; inline = $false }
        @{ name = "AccountID"; value = $AccountID; inline = $true }
    )

    # Create the embed object for Discord
    $DiscordEmbed = [PSCustomObject]@{
        title       = "NMM Notification"
        description = "Details of Job ID: $($Request.Job.Id)"
        color       = if ($Request.Job.JobStatus -eq 'Failed') { 0xFF0000 }else { 0x13BA7C }
        fields      = $Fields
        timestamp   = $Request.Job.CreationDateUtc
    }

    # Wrap the embed in an array
    [System.Collections.ArrayList]$EmbedArray = @()
    $EmbedArray.Add($DiscordEmbed)

    # Create the payload
    $Payload = [PSCustomObject]@{
        content  = if ($Request.Job.JobStatus -eq 'Failed') { "@everyone - A critical event has occurred" } else { "" }
        username = "Nerdio Manager"
        embeds   = $EmbedArray

    }

    # Convert the object to JSON with increased depth
    $DiscordWebhookData = $Payload | ConvertTo-Json -Depth 4

    # Send data to Discord webhook
    $Response = Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $DiscordWebhookData -ContentType "application/json"

    return $Response

}

try {
    # Webhook URL for your Teams channel
    $webhookUrl = "DISCORD_WEBHOOK_URL"
    # Send the message to Teams
    Send-DiscordMessage -Request $Request.body -WebhookUrl $webhookUrl
}
catch {
    $_.Exception.Message
}


# Return response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = "Message sent to Teams successfully!"
    })
