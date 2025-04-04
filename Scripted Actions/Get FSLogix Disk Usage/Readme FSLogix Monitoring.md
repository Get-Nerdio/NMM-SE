![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)


# FSLogix Profile Monitoring Solution

This solution monitors FSLogix profile sizes in Azure Storage and sends email alerts when profiles exceed specified space thresholds.

## Prerequisites

### Azure Resources
- Azure Storage Account with Table Storage enabled
- Azure Communication Services resource (use the one setup by Nerdio)
- Azure Automation Account (for running as a runbook)

### Required PowerShell Modules (for `Runbook-CheckFSLogixTable.ps1` only)
If using the `Runbook-CheckFSLogixTable.ps1` script, the following PowerShell modules must be imported into your Azure Automation Account:

1. `Az.Storage` - For interacting with Azure Storage Tables
2. `Az.Communication` - For sending emails via Azure Communication Services

**Note:** The `Runbook-CheckFSLogixTable-NoModuleDependency.ps1` script does **not** require these modules as it uses direct REST API calls.

### Configuration Requirements

1. **Azure Storage Account**:
   - Storage Account Name
   - Storage Account Key
   - Table Name (will be created if it doesn't exist)

2. **Azure Communication Services**:
   - Connection String
   - Sender Domain (format: `<id>.azurecomm.net`)
   - Verified sender address

3. **Email Configuration**:
   - IT Support Email address for receiving alerts
   - Threshold percentage for disk space alerts (default: 92%)

## Setup Instructions

1. **Import Required Modules (If using `Runbook-CheckFSLogixTable.ps1`)**:
   - If you plan to use the `Runbook-CheckFSLogixTable.ps1` script, go to your Azure Automation Account > "Shared Resources" > "Modules".
   - Import the following modules:
     ```
     Az.Storage
     Az.Communication
     ```
   - If using `Runbook-CheckFSLogixTable-NoModuleDependency.ps1`, this step is **not required**.

2. **Add Variables**:
   - Create the following variables in Nerdio for MSP, how you can do this read the Nerdio documentation: [Scripted Actions - MSP Level Variables](https://nmmhelp.getnerdio.com/hc/en-us/articles/25498222400269-Scripted-Actions-MSP-Level-Variables)
     - StorageAccountName
     - StorageAccountKey (Create as secure Variable MSP Level)
     - TableName
     - ACSConnectionString (Create as secure Variable MSP Level)
     - ACSFromAddress (sender domain)
     - ITSupportEmail

3. **Import the Runbook**:
   - Choose **one** of the following scripts based on your preference for module dependencies:
     - `Runbook-CheckFSLogixTable.ps1`: Requires `Az.Storage` and `Az.Communication` modules.
     - `Runbook-CheckFSLogixTable-NoModuleDependency.ps1`: Uses direct REST APIs, no module dependencies.
   - Paste the code from your chosen script into a new runbook in Nerdio.
   - Make sure you created the variables in Nerdio as described in step 2.

## Monitoring Runbook Versions

This solution provides two versions of the monitoring runbook:

1.  **`Runbook-CheckFSLogixTable.ps1`**:
    -   Uses standard Azure PowerShell modules (`Az.Storage`, `Az.Communication`).
    -   Requires these modules to be imported into the Azure Automation Account (see Step 1 above).
    -   May be easier to maintain if you are comfortable with standard Az modules.

2.  **`Runbook-CheckFSLogixTable-NoModuleDependency.ps1`**:
    -   Uses direct REST API calls to Azure Storage and Azure Communication Services.
    -   **Does not require any external PowerShell modules** to be imported into the Automation Account.
    -   Suitable for environments where module management is restricted or complex, or if you prefer fewer dependencies.

Choose the version that best suits your environment and management preferences when importing the runbook (Step 3 above). Both scripts achieve the same monitoring and alerting functionality.

## Usage

The script can be run in two ways:

1. **As an Azure Runbook**:
   - Schedule the runbook to run periodically
   - Uses managed identity for Azure authentication
   - Sends email alerts when profiles exceed threshold

2. **Locally/Manually**:
   - Can be run as a PowerShell script
   - Requires the same modules installed locally
   - Useful for testing and development

## Email Alerts

The solution sends HTML-formatted emails containing:
- List of profiles exceeding space threshold
- Profile details (username, total size, used size, free space %)
- Last modified timestamp
- Generated timestamp

## Endpoint script Get-FSLogixProfileSize.ps1

This PowerShell script needs to be added as a Scripted Action in Nerdio for MSP to collect FSLogix profile sizes from the endpoints.

### Setup in Nerdio

1. **Create New Scripted Action**:
   - Go to Nerdio Portal > Settings > Scripted Actions
   - Click "Add Scripted Action"
   - Name: "Get FSLogix Profile Size"
   - Description: "Collects FSLogix profile size information and stores it in Azure Table Storage"
   - Type: PowerShell
   - Paste the contents of `Get-FSLogixProfileSize.ps1`

2. **Usage**:
   - Run on: AVD Session Hosts
   - Execution Frequency: Daily (recommended)

3. **Link to Variables**:
   - Make sure the MSP-level variables are created (as mentioned in setup instructions above)
   - The script will automatically use these variables when running

4. **Schedule Execution**:
   - Enable scheduling for the scripted action
   - Set to run daily (recommended to run a few hours before the monitoring runbook)
   - Configure retry settings if needed

### Script Function

The endpoint script:
- Scans local FSLogix profiles
- Calculates disk usage metrics
- Uploads data to Azure Table Storage
- Uses the same storage account and table as configured in the monitoring runbook

### Testing

To test the script:
1. Run it manually on a single session host first
2. Check the Azure Storage Table for new entries
3. Verify the monitoring runbook can read the uploaded data

## Troubleshooting

Common issues and solutions:

1. **Module Import Errors**:
   - Ensure all required modules are imported in the Automation Account
   - Check module versions are compatible

2. **Authentication Errors**:
   - Verify Storage Account credentials
   - Check Communication Services connection string
   - Ensure sender domain is properly configured

3. **Email Sending Issues**:
   - Verify sender address format
   - Check recipient email address
   - Confirm Communication Services resource is properly set up

## Security Notes

- Store sensitive information (keys, connection strings) in Automation Account variables
- Use managed identity where possible
- Regularly rotate storage account keys
- Monitor access to the storage account and communication services

## Support

For issues or questions, please contact your system administrator or open an issue in the repository.
