![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# Manual Join AzFiles to ADDS

This script is designed to manually join an Azure Files share to an Active Directory Domain Services (ADDS) domain. This is an alternative method to the automated process in Nerdio of joining an Azure Files share to an ADDS domain. The script is intended for use in scenarios where the automated process is not feasible or has failed.

## Prerequisites

You need to run this script from a machine that is joined to the domain. Best is to save the **ManualJoinAzFilesToADDS.ps1** script file to a local folder on the machine and open it from Powershell ISE or Visual Studio Code.

Creating a Service Princial you can follow the steps in the following Microsoft documentation: [Create a Service Principal](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)

In this script we use the Secret and ID of the Service Principal to authenticate to Azure and Microsoft Graph. You can generate a new Secret in the Entra Portal under the Service Principal. Ather generating the Secret you can copy the ID and Secret to the script.

![CleanShot 2024-06-18 at 21 40 15@2x](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/19548017-0cf4-4a40-8ae8-19beb8ba010c)


To use a Service Principal to authenticate to Azure and Microsoft Graph, you need to have the following permissions setup for the Service Principal:

**Azure Portal:**
- Azure Subscription: **Contributor** and **Role Based Access Control Administrator**
    - You can also set these permissions on the Resource Group level.
    - When adding the Service Principal to the role search for the Service Principal name instead of the ID.

**Entra Portal:**
- Microsoft Graph: **Group.ReadWrite.All**
    - Look for the Service Principal in the **App Registrations** section, under API permissions you can add the permission. Dont forget to grant admin consent.
 
      ![CleanShot 2024-06-18 at 21 28 54@2x](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/e8e492f3-89fd-465b-ae68-5df6aed1b8f6)


## How to Use

The script requires the following parameters to be set:

```powershell
$JoinAzFilesParams = @{
    ServicePrincipal      = $false
    SubscriptionId        = 'Azure Subscription ID'
    ResourceGroupName     = 'Resource Group Name'
    StorageAccountName    = 'Name of Strorage Account'
    FileShareName         = 'Name of File Share in Storage Account'
    StorageAccountKey     = 'Storage Account Key'
    OrganizationUnit      = 'OU=AzFiles,OU=Nerdio Sales,DC=nerdiosales,DC=local' #Example value
    DomainAccountType     = 'ComputerAccount' #ComputerAccount or ServiceLogonAccount default is ComputerAccount
    EncryptionType        = 'AES256'
    TenantID              = 'Tenant ID'
    Debug                 = $false
    ClientSecret          = 'Client Secret'
    ClientId              = 'Client ID'
    SetRBACAzFiles        = $false
    EntraGroupName        = 'AzFiles-TestGroup'
    EntraGroupDescription = 'Test Group for AzFiles'
    AzureRoleName         = 'Storage File Data SMB Share Contributor' #Role needed for assigned Group to have access to the Storage Account
}

JoinAzFilesToADDS @JoinAzFilesParams
```

## Parameters Details

- **ServicePrincipal**: Set to **false** to use the current logged in user with devicecode to authenticate to Azure, or **true** to use a Service Principal.
- **SetRBACAzFiles**: Set to **false** to skip the RBAC role assignment, or **true** to assign the role to the group specified in the EntraGroup param.
- **SubscriptionId**: The Azure Subscription ID where the Storage Account is located.
- **ResourceGroupName**: The Resource Group Name where the Storage Account is located.
- **StorageAccountName**: The name of the Storage Account.
- **FileShareName**: The name of the File Share in the Storage Account.
- **StorageAccountKey**: The Storage Account Key of the Storage Account.
- **OrganizationUnit**: The Organization Unit where the Computer Account will be created in ADDS.
- **DomainAccountType**: The type of account to be created in ADDS. Can be **ComputerAccount** or **ServiceLogonAccount**. Default is **ComputerAccount**.
- **EncryptionType**: The type of encryption to be used. Can be **AES256**
- **TenantID**: The Tenant ID of the Azure AD.
- **Debug**: Set to **$true** to run the Debug feature of the AzFilesHybrid module
- **ClientSecret**: The Client Secret of the Service Principal.
- **ClientId**: The Client ID of the Service Principal.
- **EntraGroupName**: The name of the group to be created in Entra.
- **EntraGroupDescription**: The description of the group to be created in Entra.
- **AzureRoleName**: The name of the role to be assigned to the group in Azure, this is set default to **Storage File Data SMB Share Contributor**.

***

After all the parameters are set, you can select all the code and run it in the Powershell ISE or Visual Studio Code. By pressing **F8** or Right Click and choose **Run Selection**.

It will first check if the needed modules are installed, if not it will install them. Keep in mind that sometimes you need to restart you Powershell ISE or Visual Studio Code to make sure the modules are loaded correctly.

## Note

If somehow any issue arrise with this script you can always use the steps described in the official Microsoft documentation to join the Azure Files to the ADDS domain. [Join Azure Files to a Windows Server AD domain](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-ad-ds-enable)
This approach involves a few additional manual steps but serves as a reliable alternative if the script fails due to potential changes from Microsoft. It’s also advisable to consult the official documentation for the most up-to-date information.
