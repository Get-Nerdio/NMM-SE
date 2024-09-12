![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# NMM Custom API Notification to Slack Webhook

## Features

- Sends structured messages to a Discord server using webhooks.
- Dynamically populates message content based on the incoming HTTP request from the NMM Custom API Notification
- Handles requests with no account ID by defaulting to 'Global'.
- Based on JobStatus is show a message collor and when failed will use the @everyone tag in the Discord channel.

## Requirements

- Function App in Azure to run this code
- Slack Webhook in your Slack Workspace
- Enabled the NMM API -> https://nmmhelp.getnerdio.com/hc/en-us/articles/11548091104141-Nerdio-Manager-Partner-API-Getting-Started

## Configuration

1. **Set Up Webhook URL:**
   - Replace `SLACK_WEBHOOK_URL` with your Slack webhook URL in the script.
   - Replace `NERDIO_PORTAL_URL` with your Nerdio Manager for MSP URL in the script.


