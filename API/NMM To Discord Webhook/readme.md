# NMM Custom API Notification to Discord Webhook

## Features

- Sends structured messages to a Discord server using webhooks.
- Dynamically populates message content based on the incoming HTTP request from the NMM Custom API Notification
- Handles requests with no account ID by defaulting to 'Global'.
- Based on JobStatus is show a message collor and when failed will use the @everyone tag in the Discord channel.

## Requirements

- Discord Server
- Discord Webhook in your server
- Enabled the NMM API -> https://nmmhelp.getnerdio.com/hc/en-us/articles/11548091104141-Nerdio-Manager-Partner-API-Getting-Started

## Configuration

1. **Set Up Webhook URL:**
   - Replace `DISCORD_WEBHOOK_URL` with your Discord webhook URL in the script.

![CleanShot 2024-04-15 at 16 13 14@2x](https://github.com/freezscholte/Public-Nerdio-Scripts/assets/52416805/97e7df19-f969-4ee4-b866-65410f23b735)
