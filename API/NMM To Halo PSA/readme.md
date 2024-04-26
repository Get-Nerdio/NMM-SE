![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)


# NMM Custom API Notification to Halo PSA Ticket

## Synopsis

This is an Azure Function app that is able to receive the Custom API Notifications JSON structure from the NMM portal.
It will be able to sort out that data and use the HaloPSA powershell module to connect to the HaloPSA API and create a ticket for that specific notification.

## Prerequisites

#### Setup Azure Function App and Keyvault:

1. **Azure Function App Setup:**
Create an Azure Function App: You need an existing Azure Function App where you can deploy this script. This Function App should be configured to handle PowerShell-based functions. And the type of function you create for this is HTTP Trigger.
![CleanShot 2024-04-26 at 09 29 42@2x](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/e2b77d92-3f97-4b0b-8fc9-a15a84f01f01)

Afther that you paste in the code content from: NMM_To_HaloPSA.ps1 into the function and save.


3. **HaloAPI Module Installation:**
Edit the requirements.psd1 file in your Azure Function App to include the following line: **'HaloAPI' = '1.*'** this will add the HaloAPI PS Module to your Function App
So you **requirements.psd1** would look something like this:

```powershell
# This file enables modules to be automatically managed by the Functions service.
# See https://aka.ms/functionsmanageddependency for additional information.
#
@{
    # For latest supported version, go to 'https://www.powershellgallery.com/packages/Az'. 
    # To use the Az module in your function app, please uncomment the line below.
    #'Az' = '11.*'
    'HaloAPI' = '1.*'
}
```
Deploy these changes to the Function App, and give it a restart. Note that it might take about 10-15 minutes after a restart for the module to be fully installed.

3. **Managed Identity and Azure Key Vault:**

- **Enable Managed Identity:**
    - Go to the Azure portal, navigate to your Function App settings.
    - Under the "Identity" section, enable the "System-assigned managed identity". This action will create an identity in Azure Active Directory that is directly tied to your Function App. Take note of the Object ID shown here you will need this later in you keyvault Access Policy.  

- **Set up Azure Key Vault:**
    - Create or use an existing Azure Key Vault.
    - Add your *"HaloClientID"* (API key) and *"HaloSecretID"* as secrets in the Key Vault.
- **Configure Access Policies Azure Keyvault:**
In the Azure Key Vault settings, adjust the *"Access Policies"* to allow the managed identity of your Function App to use *"Get"* and *"List"* permissions for secrets.

4. **Environmental Variables:**


- **Configure Environmental Variables:**
In the Function App settings, configure the environment variables HaloClientID and HaloSecretID to fetch values from Azure Key Vault using the managed identity. Use the Azure Key Vault references for application settings. The configuration should look something like this:
![CleanShot 2024-04-26 at 08 57 50@2x](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/83e3b32b-593b-4ce8-88bb-f6c8f9cd90ef)

The format for incorporating Key Vault entries is as follows:
```
@Microsoft.KeyVault(SecretUri=https://vaultname.vault.azure.net/secrets/HaloSecretID/secretid)
```
Essentially, this provides a secure method to access the API key and secret through environment variables within the script, like this:
```
$env:HaloSecretID
``` 
This approach retrieves the HaloAPI Secret from the Key Vault, eliminating the need to embed it directly in the script.

## Setup NMM Notifications

5. **Setup Custom Notification API:**

Within the NMM Portal you need to setup the Alert Nofications section to allow your Function app to receive those json structure Custom API Notifications.
Documentation how to setup the basics you can find here [NMM Alerts and Notifications Setup](https://nmmhelp.getnerdio.com/hc/en-us/articles/25498222093709-Alerts-and-Notifications)

One you set this up correctly you need to paste in your FunctionApp url that is attached to the HTTP trigger function you created earlier. You can find the url endpoint here:

![CleanShot 2024-04-26 at 09 45 54@2x](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/e2c18198-fff8-4c97-ae8f-13f94bc4da52)

That copied url needs to be pasted into the custom notification url field shown here:

![CleanShot 2024-04-26 at 09 47 59@2x](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/1c28342a-367f-4eee-bc17-6ad44c376ca6)

## Halo PSA Settings and Prerequisites

6. **HaloPSA Setup:**

The most important step here is to configure the Halo CustomFields so that the Function app can post additional data extracted from the JSON data structure. The fields we currently use are:

```text
Nerdio Action ID
Nerdio Condition ID
Nerdio Creation Date
Nerdio Customer ID
Nerdio Incident ID
Nerdio Job Run Mode
Nerdio Job Status
Nerdio Job Type
```

When these fields are created in Halo PSA, each will be assigned an ID. You need to map these IDs in the main script. Currently, they are filled with ID numbers that correspond to our test environment. Below is an example of which ID numbers within the Custom Fields object need to be changed:

```powershell
customfields  = @(
        [PSCustomObject]@{
            id    = 178 #Change this ID accordingly to your Halo environment
            value = if ($null -ne $NMMObj.AccountId){"$($NMMObj.AccountId)"}else{"Global MSP"}
        },
        [PSCustomObject]@{
            id    = 179 #Change this ID accordingly to your Halo environment 
            value = $NMMObj.Job.Id
        },
        [PSCustomObject]@{
            id    = 180 #Change this ID accordingly to your Halo environment 
            value = $NMMObj.Job.CreationDateUtc  
        }
    )
```
For instructions on how to create these custom fields, refer to the [HaloPSA Custom Fields Documentation](https://halopsa.com/guides/article/?kbid=1938).

I also recommend setting up a specific ticket type for NMM alerts. While this isn’t a strict requirement, it allows you to segment your NMM tickets more effectively. You can find guidance on creating these ticket types in the [HaloPSA Create Ticket Types Documentation](https://halopsa.com/guides/article/?kbid=876).

When you create the new ticket type, take note of the ID assigned to it. You will need to specify this ID in the PSCustomObject within the script, as shown in the example below:


```powershell
$HaloObj = [PSCustomObject]@{
    oppjobtitle   = 'New NMM Alert'
    tickettype_id = '27' #This is the ticket type ID you created earlier
    priority_id   = if ($NMMObj.Job.JobStatus -eq 'Completed'){'4'}else{'2'}
    supplier_name = 'Nerdo Manager MSP'
    summary       = "NMM: $(($NMMObj.Job.JobType -creplace '([A-Z])',' $1').Trim())"
    details       = 'Details of the NMM Alert in Additional Fields'
```
As you can see, *tickettype_id* has an ID number attached, which is the ID of the ticket type you created earlier. If you prefer not to specify this, you can leave it empty like this: ''.

## Testing the Function App

7. **Manual Testing**

Open the HTTP Trigger in the Function App you created earlier and click the Test/Run button at the top.

![CleanShot 2024-04-26 at 09 35 52@2x](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/6a941a1e-7245-491b-8c2b-035ef2c62ba4)


Copy and paste the following JSON into the test body field:

```json
{
    "AccountId": null,
    "ActionId": 6,
    "ConditionId": 18,
    "Job": {
        "Id": 288471,
        "AccountId": null,
        "CreationDateUtc": "2024-04-15T09:36:50.9472011+00:00",
        "JobType": "CloneMspWindowsScriptedAction",
        "JobStatus": "Completed",
        "JobRunMode": "Default"
    }
}
```
![CleanShot 2024-04-26 at 09 37 22@2x](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5a435839-e3c5-4532-9e58-c4a054b5573a)

Now, hit Run. If everything is set up correctly, you will see a new ticket created in HaloPSA. For troubleshooting, you can use the Function App's logging feature to pinpoint any issues.

## Disclaimer

"Please note that our main policy, as outlined in the [Disclaimer](https://github.com/Get-Nerdio/NMM-SE/blob/main/readme.md#disclaimer), also applies to this document."

## Contributing

We highly encourage contributions from the community! If you have made improvements or modifications to this script that have been effective in your environment and you believe it could benefit others, please consider contributing. Here’s how you can do it:

- Fork the Repository: Start by forking the repository where this script is hosted and make your modifications or additions.
- Submit a Pull Request: After you've made your changes, submit a pull request to the main branch. Please provide a detailed description of what the script does and any other information that might be helpful.
- Code Review: One of our Sales Engineers will review the submission. If everything checks out, it will be merged into the main repository.
