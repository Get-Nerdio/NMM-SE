![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# NMM Graph API Report

This script is designed to generate a comprehensive report on the Microsoft 365 environment using the Microsoft Graph API.

## Prerequisites

Before running the script, ensure you have the following prerequisites:

1. **Create NMM Inherited Variables**:

Nerdio KB Article: [MSP-Level Variables](https://nmmhelp.getnerdio.com/hc/en-us/articles/25498222400269-Scripted-Actions-MSP-Level-Variables)

Keep in mind that the script is using the Pax8 API to get some extra details for the report, if you are not a Pax8 customer you can ignore the Pax8 variables.
Further for each customer you assign the runbook to you need to change the variables values to the corresponding customer.

   - Create a new inherited variable in NMM with the following values:
     - **Name:** M365ReportClientId
     - **Value:** The Client ID of the App Registration
   - Create a new inherited variable in NMM with the following values:
     - **Name:** Pax8CompanyID
     - **Value:** The Company ID of the Pax8 API
   - Create a new inherited variable in NMM with the following values:
     - **Name:** Pax8ClientID
     - **Value:** The Client ID of the Pax8 API
   - Create a new inherited variable in NMM with the following values:
     - **Name:** M365ReportMailRecip
     - **Value:** The email address of the recipient of the report
   - Create a new inherited variable in NMM with the following values:
     - **Name:** M365ReportMailSender (See step 5 below)
     - **Value:** The email address of the sender of the report

2. **Create NMM Secure Variables**:
Nerdio KB Article: [Secure Account Variables](https://nmmhelp.getnerdio.com/hc/en-us/articles/25498291119629-Scripted-Actions-Account-Level-Variables)
The Secure Variables need to be set per customer, so you need to create one for each customer you want to run the report for.
   - Create a new secure variable in NMM with the following values:
     - **Name:** Pax8Secret
     - **Value:** The Client Secret of the Pax8 API
   - Create a new secure variable in NMM with the following values:
     - **Name:** M365ReportSecret
     - **Value:** The Client Secret of the Azure AD App Registration

3. **Create Runbook in NMM**:
   - Create a new runbook in NMM with the following values:
     - **Name:** M365Report
     - **Script:** The contents of the M365Report script: [M365Report.ps1](https://github.com/Get-Nerdio/NMM-SE/blob/main/Azure%20Runbooks/NMM%20Graph%20API%20Report/M365Report.ps1)
     - **Note:** You can create the runbook on the Global level in NMM so you can assign it to multiple customer environments, dont forget to update the variables values corrosponding to the managed tenant environment of that customer.

4. **Enable Runbook Integration in NMM**:
   - Go to the account where you want to run the report from and click on the "Settings" menu and click on Azure.
   - In this page you will see a section called "Azure runbooks scripted actions" click on the Disabled button and then follow the steps to enable it.
   - Afther you have enabled it this section will show a Enabled button, also when the runbook integration was already setup click on the Enabled button. We need to note down the name of the Runbook
   - Next search for the Runbook name in the Azure Portal and open it.
   - Under the menu "Shared Resources" click on "Modules" and then click on "Add Module"
   - In the "Add Module" page select "Browse from gallery" and search for the "Microsoft.Graph.Authentication" module and select it.
   - Select "Runtime Version 5.1" This means PowerShell 5.1 is used to run the runbook. This is current the default for NMM Runbooks
   - Click on "Import" and wait for the import to finish.

4. **Create App Registration**:
   - Create an App Registration in Azure AD with the necessary permissions to access the Microsoft Graph API.
   - Give the App Registration a Name and selecte the Single Tenant option.
   - Then generate a client secret for the App Registration, and note this down for later use, we need to save this client secret in the NMM Secure Variables.
   - Use the following Graph API "Application" permissions:

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





