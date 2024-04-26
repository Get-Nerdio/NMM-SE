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

5. **Setup NMM Custom Notification API:**
