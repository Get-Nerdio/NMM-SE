![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# NMM Graph API Report

This script is designed to generate a comprehensive report on the Microsoft 365 environment using the Microsoft Graph API.

## Prerequisites

Before running the script, ensure you have the following prerequisites:

1. **Create NMM Inherited Variables**:

Keep in mind that the script is using the Pax8 API to get some extra details for the report, if you are not a Pax8 customer you can ignore the Pax8 variables.
Further for each customer you assign the runbook to you need to change the variables values to the corresponding customer.

   - Create a new inherited variable in NMM with the following values:
     - Name: M365ReportClientId
     - Value: The Client ID of the App Registration
   - Create a new inherited variable in NMM with the following values:
     - Name: Pax8CompanyID
     - Value: The Company ID of the Pax8 API
   - Create a new inherited variable in NMM with the following values:
     - Name: Pax8ClientID
     - Value: The Client ID of the Pax8 API
   - Create a new inherited variable in NMM with the following values:
     - Name: M365ReportMailRecip
     - Value: The email address of the recipient of the report
   - Create a new inherited variable in NMM with the following values:
     - Name: M365ReportMailSender (See step 5 below)
     - Value: The email address of the sender of the report

2. **Create NMM Secure Variables**:
   - Create a new secure variable in NMM with the following values:
     - Name: Pax8Secret
     - Value: The Client Secret of the Pax8 API
   - Create a new secure variable in NMM with the following values:
     - Name: M365ReportSecret
     - Value: The Client Secret of the Azure AD App Registration

3. **Create Runbook in NMM**:
   - Create a new runbook in NMM with the following values:
     - Name: M365Report
     - Script: The contents of the M365Report script: [M365Report.ps1](https://github.com/Get-Nerdio/NMM-SE/blob/main/Azure%20Runbooks/NMM%20Graph%20API%20Report/M365Report.ps1)
     - Note: You can create the runbook on the Global level in NMM so you can assign it to multiple customer environments, dont forget to update the variables values corrosponding to the managed tenant environment of that customer.

4. **Create App Registration**:
   - Create an App Registration in Azure AD with the necessary permissions to access the Microsoft Graph API.
   - Give the App Registration a Name and selecte the Single Tenant option.
   - Then generate a client secret for the App Registration, and note this down for later use, we need to save this client secret in the NMM Secure Variables.
   - Use the following permissions:
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

5. **Create Shared Mailbox**:
   - Create a new Shared Mailbox in your Microsoft 365 environment this is used to send the report to the recipient email address.

6. **Optional: Create Pax8 API Key**:
    - If you are a Pax8 customer you can create a new API key in your Pax8 account and note this down for later use, we need to save this API key in the NMM Inherited Variables.
    - Link to KB article: [Pax8 API setup](https://devx.pax8.com/docs/integrationrequest)





