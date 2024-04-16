# NMM Custom API Notification to Teams Webhook

## Features

- Sends structured messages to Microsoft Teams using Adaptive Cards.
- Dynamically populates message content based on the incoming HTTP request from the NMM Custom API Notification
- Handles requests with no account ID by defaulting to 'Global'.

## Requirements

- Azure FunctionApp that runs Powershell
- Enabled the NMM API -> https://nmmhelp.getnerdio.com/hc/en-us/articles/11548091104141-Nerdio-Manager-Partner-API-Getting-Started

## Configuration

1. **Set Up Webhook URL:**
   - Replace `TEAMS_WEBHOOK_URL` with your Microsoft Teams channel webhook URL in the script.

2. **Create HTTP Trigger type function in a Azure FunctionApp:**
   - Follow these basisc steps to create a HTTP Trigger FunctionApp -> https://dev.to/henriettatkr/how-to-create-and-test-an-http-triggered-function-with-azure-function-app-4ffd

![CleanShot 2024-04-15 at 14 13 56](https://github.com/freezscholte/Public-Nerdio-Scripts/assets/52416805/6e963455-4dd9-4fe5-9a4e-efd289295b01)
