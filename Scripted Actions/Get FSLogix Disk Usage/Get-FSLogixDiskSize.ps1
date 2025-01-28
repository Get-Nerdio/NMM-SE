# ****************************************************
# FSLogix Profile Size Warning and Azure Table Storage Logging
# J.Scholte, Nerdio - 2025-01-28
# ****************************************************

function Get-FSLogixDiskUsage {
    <#
    .SYNOPSIS
    Shows a message to the user in the notification area if the FSLogix profile is almost full and saves the usage data to Azure Table Storage.

    .DESCRIPTION
    Gets information about the user's FSLogix profile (size and remaining size) and calculates the free space in percent.
    If free space falls below the threshold, a notification is shown to the user, and the data is saved to Azure Table Storage.

    .PARAMETER PercentThreshold
    Specifies the percentage of free space at which a notification is shown.

    .PARAMETER NotificationTimeout
    Specifies how long (in seconds) to wait before showing the notification.

    .PARAMETER StorageAccountName
    Specifies the name of the Azure Storage account.

    .PARAMETER StorageAccountKey
    Specifies the key for the Azure Storage account.

    .PARAMETER TableName
    Specifies the name of the Azure Table where data will be stored.

    .PARAMETER MaxRetries
    Specifies the number of retry attempts for saving data to Azure Table Storage.

    .PARAMETER RetryDelaySeconds
    Specifies the delay between retry attempts in seconds.

    .OUTPUTS
    PSCustomObject containing the FSLogix profile usage data
    #>

    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$PercentThreshold = 10,

        [Parameter()]
        [ValidateRange(0, 3600)]
        [int]$NotificationTimeout = 10,

        [Parameter(Mandatory)]
        [string]$StorageAccountName,

        [Parameter(Mandatory)]
        [string]$StorageAccountKey,

        [Parameter()]
        [string]$TableName = "FSLogixProfileUsage",

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 2
    )

    # Ensure required modules are installed
    if (-not (Get-Module -ListAvailable Az.Storage)) {
        Install-Module -Name Az.Storage -Force
    }

    # Wait for the specified timeout before showing the message
    Start-Sleep -Seconds $NotificationTimeout

    # Get the FSLogix profile size for the current user
    $fsLogixVolume = Get-Volume -FileSystemLabel "Profile-*" -ErrorAction SilentlyContinue

    if ($null -eq $fsLogixVolume) {
        Write-Warning "FSLogix profile not found for user: $ENV:USERNAME"
        return $null
    }

    # Calculate free space percentage
    $freeSpacePercent = [Math]::Round(($fsLogixVolume.SizeRemaining / $fsLogixVolume.Size) * 100)
    
    # Prepare data for Azure Table Storage
    $usageData = [PSCustomObject]@{
        PartitionKey     = $fsLogixVolume.FileSystemLabel -replace "Profile-", ""  # Using a constant partition key for better querying
        RowKey          = $fsLogixVolume.FileSystemLabel  # Using full profile name as RowKey
        Username        = $fsLogixVolume.FileSystemLabel -replace "Profile-", ""
        TotalSizeGB     = $fsLogixVolume.Size / 1GB
        UsedSizeGB      = ($fsLogixVolume.Size - $fsLogixVolume.SizeRemaining) / 1GB
        FreeSpacePercent = $freeSpacePercent
        LastModified    = Get-Date
    }

    # Save data to Azure Table Storage with retry logic
    $retryCount = 0
    do {
        try {
            # Create storage context
            $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
            
            # Get or create the table
            $table = Get-AzStorageTable -Name $TableName -Context $ctx -ErrorAction SilentlyContinue
            if (-not $table) {
                $table = New-AzStorageTable -Name $TableName -Context $ctx
            }

            # Create table entity
            $entity = New-Object Microsoft.Azure.Cosmos.Table.DynamicTableEntity
            $entity.PartitionKey = $usageData.PartitionKey
            $entity.RowKey = $usageData.RowKey

            # Convert properties to EntityProperty objects
            $entityProperties = New-Object 'System.Collections.Generic.Dictionary[string,Microsoft.Azure.Cosmos.Table.EntityProperty]'
            foreach ($prop in $usageData.PSObject.Properties) {
                if ($prop.Name -notin @('PartitionKey', 'RowKey')) {
                    $value = $prop.Value
                    $entityProperty = switch ($value) {
                        { $_ -is [datetime] } { 
                            New-Object Microsoft.Azure.Cosmos.Table.EntityProperty([datetime]$_)
                        }
                        { $_ -is [double] } { 
                            New-Object Microsoft.Azure.Cosmos.Table.EntityProperty([double]$_)
                        }
                        default { 
                            New-Object Microsoft.Azure.Cosmos.Table.EntityProperty([string]$_)
                        }
                    }
                    $entityProperties.Add($prop.Name, $entityProperty)
                }
            }
            $entity.Properties = $entityProperties

            # Use InsertOrReplace operation to update existing records
            $operation = [Microsoft.Azure.Cosmos.Table.TableOperation]::InsertOrReplace($entity)
            $table.CloudTable.Execute($operation)

            Write-Output "Successfully saved/updated FSLogix usage data in Azure Table Storage"
            break
        }
        catch {
            $retryCount++
            if ($retryCount -ge $MaxRetries) {
                Write-Error "Failed to save FSLogix usage data to Azure Table Storage after $MaxRetries attempts: $_"
                throw
            }
            Write-Warning "Retry attempt $retryCount of $MaxRetries - Failed to save data. Retrying in $RetryDelaySeconds seconds..."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    } while ($true)

    # Return the usage data
    return $usageData
}

# Example usage with Nerdio Environment Variables
Get-FSLogixDiskUsage -StorageAccountName $InheritedVars.StorageAccountName -StorageAccountKey $InheritedVars.StorageAccountKey -TableName $InheritedVars.TableName -PercentThreshold 15