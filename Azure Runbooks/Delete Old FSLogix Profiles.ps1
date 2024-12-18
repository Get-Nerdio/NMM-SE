
#description: Deletes FSlogix .vhd(x) files older than specified days and removes any empty directories in the specified Azure Files share.
#tags: Nerdio, FSLogix

<# Variables:
{
  "StorageAccountName": {
    "Description": "Name of the Azure Storage Account.",
    "IsRequired": true
  },
  "ShareName": {
    "Description": "Name of the Azure Files share.",
    "IsRequired": true
  },
  "DaysOld": {
    "Description": "Age of files to check for deletion.",
    "IsRequired": true
  },
  "StorageKeySecureVar": {
    "Description": "Secure variable containing the storage account key. Make sure this secure variable is passed to this script.",
    "IsRequired": false,
    "DefaultValue": "FslStorageKey"
  },
  "WhatIf": {
    "Description": "If set to true, the script will only output what it would do without actually doing it.",
    "IsRequired": false,
    "DefaultValue": false
  }
}
#>

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

[bool]$WhatIf = $WhatIf -eq 'true'

$StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageKeySecureVar
Write-Output "Storage Account Connected"

$Dirs = $StorageContext | Get-AzStorageFile -ShareName "$ShareName"  | Where-Object {$_.GetType().Name -eq "AzureStorageFileDirectory"}

# Get files from each directory, check if older than $DaysOld, delete it if it is
foreach ($dir in $Dirs) {
    $Files = Get-AzStorageFile -ShareName "$ShareName" -Path $dir.Name -Context $StorageContext | Get-AzStorageFile
    foreach ($file in $Files) {
        # check if file is not .vhd, if so, skip and move to next iteration
        if ($file.Name -notmatch '\.vhd') {
            write-output "$($file.Name) is not a VHD file, skipping..."
            continue
        }
        # get lastmodified property using Get-AzStorageFile; if lastmodified is older than $DaysOld, delete the file
        $File = Get-AzStorageFile -ShareName "$ShareName" -Path $($dir.name + '/' + $file.Name) -Context $StorageContext
        $LastModified = $file.LastModified.DateTime
        $DaysSinceModified = (Get-Date) - $LastModified
        if ($DaysSinceModified.Days -gt $DaysOld) {
          if ($WhatIf) {
            Write-Output "WHATIF: $($file.Name) is older than $DaysOld days, WOULD delete..."
          }
          else {
            Write-Output "$($file.Name) is older than $DaysOld days, deleting..." 
            $file | Remove-AzStorageFile 
          }
        }
        else {
            Write-Output "$($file.Name) is not older than $DaysOld days, skipping..."
        }
    }
    # if directory is now empty, delete it
    $Files = Get-AzStorageFile -ShareName "$ShareName" -Path $dir.Name -Context $StorageContext | Get-AzStorageFile
    if ($Files.Count -eq 0) {
        if ($WhatIf) {
            Write-Output "WHATIF: $($dir.Name) is empty, WOULD delete..."
        }
        else {
          Write-Output "$($dir.Name) is empty, deleting..."
          Remove-AzStorageDirectory -Context $StorageContext -ShareName "$ShareName" -Path $dir.name 
        }
    }
}