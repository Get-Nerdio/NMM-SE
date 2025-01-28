# ****************************************************
# FSLogix Profile Size Scanner for Azure Files
# Scans Azure Files share for FSLogix profiles and logs sizes to Azure Table Storage
# J.Scholte, Nerdio - 2025-01-28
# ****************************************************

function Get-FSLogixProfilesFromAzFiles {
    [CmdletBinding()]
    param (
        # Profile Storage Account Parameters
        [Parameter(Mandatory)]
        [string]$ProfileStorageAccountName,

        [Parameter(Mandatory)]
        [string]$ProfileStorageAccountKey,

        [Parameter(Mandatory)]
        [string]$FileShareName,

        [Parameter(Mandatory)]
        [int]$MaxSizeGB = 30,

        [Parameter()]
        [string]$ProfilePath,  # Optional - if not specified, will scan root of share

        # Table Storage Account Parameters
        [Parameter(Mandatory)]
        [string]$TableStorageAccountName,

        [Parameter(Mandatory)]
        [string]$TableStorageAccountKey,

        [Parameter()]
        [string]$TableName = "FSLogixProfileUsage",

        # General Parameters
        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 2,

        [Parameter()]
        [int]$MaxConcurrentJobs = 10  # Limit concurrent operations
    )

    try {
        # Ensure required modules are installed
        if (-not (Get-Module -ListAvailable Az.Storage)) {
            Install-Module -Name Az.Storage -Force
        }

        # Create storage contexts for Files and Table operations
        $profileCtx = New-AzStorageContext -StorageAccountName $ProfileStorageAccountName -StorageAccountKey $ProfileStorageAccountKey
        $tableCtx = New-AzStorageContext -StorageAccountName $TableStorageAccountName -StorageAccountKey $TableStorageAccountKey

        # Get or create the table
        $table = Get-AzStorageTable -Name $TableName -Context $tableCtx -ErrorAction SilentlyContinue
        if (-not $table) {
            $table = New-AzStorageTable -Name $TableName -Context $tableCtx
        }

        Write-Verbose "Scanning Azure Files share for FSLogix profiles..."

        # Get all VHDX files based on whether ProfilePath is specified
        if ([string]::IsNullOrEmpty($ProfilePath)) {
            Write-Verbose "Scanning root of share for VHDX files..."
            $vhdxFiles = Get-AzStorageFile -ShareName $FileShareName -Context $profileCtx | 
                Get-AzStorageFile | 
                Where-Object { $_.Name -like "*.vhdx" }
        }
        else {
            Write-Verbose "Scanning $ProfilePath folder for VHDX files..."
            $vhdxFiles = Get-AzStorageFile -ShareName $FileShareName -Context $profileCtx -Path $ProfilePath | 
                Get-AzStorageFile | 
                Where-Object { $_.Name -like "*.vhdx" }
        }

        if (-not $vhdxFiles) {
            Write-Warning "No VHDX files found in specified location"
            return
        }

        Write-Verbose "Found $($vhdxFiles.Count) VHDX files"

        # Process each profile
        foreach ($vhdxFile in $vhdxFiles) {
            $retryCount = 0
            $success = $false

            do {
                try {
                    
                    # Extract username from path (assuming path structure: Profiles/Username/disk.vhdx)
                    $username = $vhdxFile.Name -replace "Profile_|\.vhdx", ""

                    # Calculate sizes (converting bytes to GB)
                    $totalSizeGB = [Math]::Round($vhdxFile.Length / 1GB, 2)
                    
                    # For VHDX files, we can only get the file size, not the free space inside
                    # We'll estimate usage based on the file size compared to max possible size
                    
                    $usedSizeGB = $totalSizeGB
                    $freeSpacePercent = [Math]::Round((($maxSizeGB - $usedSizeGB) / $maxSizeGB) * 100, 1)

                    # Prepare data for Azure Table Storage
                    $usageData = [PSCustomObject]@{
                        PartitionKey     = $username
                        RowKey          = "Profile-$username"
                        Username        = $username
                        TotalSizeGB     = $maxSizeGB
                        UsedSizeGB      = $usedSizeGB
                        FreeSpacePercent = $freeSpacePercent
                        LastModified    = $vhdxFile.LastModified.UtcDateTime
                        Source          = "AzFiles"
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

                    Write-Verbose "Successfully processed profile for user: $username"
                    $success = $true
                    break
                }
                catch {
                    $retryCount++
                    if ($retryCount -ge $MaxRetries) {
                        Write-Error "Failed to process profile for $username after $MaxRetries attempts: $_"
                        break
                    }
                    Write-Warning "Retry attempt $retryCount of $MaxRetries for $username. Retrying in $RetryDelaySeconds seconds..."
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            } while (-not $success)
        }

        Write-Output "Completed scanning FSLogix profiles in Azure Files"
    }
    catch {
        Write-Error "Error in FSLogix profile scanner: $_"
        throw
    }
}

# Example usage with separate storage accounts
$params = @{
    # Profile Storage Account
    ProfileStorageAccountName = $InheritedVars.StorageAccountName
    ProfileStorageAccountKey  = $SecureVars.StorageAccountKey
    FileShareName            = $InheritedVars.FileShareName
    #ProfilePath             = "*" Optional - if not specified, will scan root of share
    MaxSizeGB                = 30

    # Table Storage Account
    TableStorageAccountName  = $InheritedVars.TableStorageAccountName
    TableStorageAccountKey   = $SecureVars.TableStorageAccountKey
    TableName               = $InheritedVars.TableName

    # General Settings
    MaxRetries              = 3
    RetryDelaySeconds       = 2
}

Get-FSLogixProfilesFromAzFiles @params