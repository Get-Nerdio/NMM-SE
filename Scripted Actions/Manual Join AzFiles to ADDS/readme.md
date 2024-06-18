![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# Manual Join AzFiles to ADDS

This script is designed to manually join an Azure Files share to an Active Directory Domain Services (ADDS) domain. This is an alternative method to the automated process in Nerdio of joining an Azure Files share to an ADDS domain. The script is intended for use in scenarios where the automated process is not feasible or has failed.

## Prerequisites

You need to run this script from a machine that is joined to the domain. Best is to save the **ManualJoinAzFilesToADDS.ps1** script file to a local folder on the machine and open it from Powershell ISE or Visual Studio Code.

The script requires the following parameters to be set:

```powershell
$JoinAzFilesParams = @{
    SubscriptionId     = 'Azure Subscription ID'
    ResourceGroupName  = 'Resource Group Name'
    StorageAccountName = 'Name of Strorage Account'
    FileShareName      = 'Name of File Share in Storage Account'
    StorageAccountKey  = 'Storage Account Key'
    OrganizationUnit   = 'OU=AzFiles,OU=Nerdio Sales,DC=nerdiosales,DC=local' #Example value
    EncryptionType     = 'AES256'
    TenantID           = 'Tenant ID'
    Debug              = $false
}

JoinAzFilesToADDS @JoinAzFilesParams
```

Afther all the parameters are set, you can select all the code and run it in the Powershell ISE or Visual Studio Code. By pressing **F8** or Right Click and choose **Run Selection**.

It will first check if the needed modules are installed, if not it will install them. Keep in mind that sometimes you need to restart you Powershell ISE or Visual Studio Code to make sure the modules are loaded correctly.

You can also set **Debug** to **$true** to run the Debug feature of the AzFilesHybrid module, and do a extra checkup if everything is set correctly.