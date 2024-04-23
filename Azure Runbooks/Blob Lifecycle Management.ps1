#description: This script sets up a rule to move blobs to the archive tier after 90 days and optionally delete them after a much longer period (10 years in this example), which you can adjust according to your needs. Make sure to tailor the blob type and prefix match to fit your specific requirements.
#tags: Nerdio-SE

<# Notes:
    Key Points:
az login: Logs into Azure CLI.
$jsonPolicy: Defines the lifecycle management rule in JSON format. Adjust the prefixMatch to specify the path of blobs within your storage account containers you want this rule to apply to.
az storage account management-policy create: Applies the lifecycle management policy to the specified storage account.
Steps to Execute:
Replace Placeholder Values: Replace "YourResourceGroupName", "YourStorageAccountName", and "yourContainerName/" with your actual Azure resource group name, storage account name, and blob container prefix.
Execution: Run this script in a PowerShell environment where both Azure PowerShell and Azure CLI are configured.
#>

# Define variables
$resourceGroupName = "YourResourceGroupName"
$storageAccountName = "YourStorageAccountName"
$scope = "/subscriptions/{subscriptionId}/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName"

# Login to Azure CLI
az login

# Set the lifecycle management policy
$ruleName = "MoveToArchiveAfter90Days"
$jsonPolicy = @"
{
    "rules": [
        {
            "name": "$ruleName",
            "enabled": true,
            "type": "Lifecycle",
            "definition": {
                "filters": {
                    "blobTypes": ["blockBlob"],
                    "prefixMatch": ["yourContainerName/"]
                },
                "actions": {
                    "baseBlob": {
                        "tierToArchive": {
                            "daysAfterModificationGreaterThan": 90
                        },
                        "delete": {
                            "daysAfterModificationGreaterThan": 3650
                        }
                    }
                }
            }
        }
    ]
}
"@

# Apply the lifecycle management policy
az storage account management-policy create --account-name $storageAccountName --resource-group $resourceGroupName --policy "$jsonPolicy"
