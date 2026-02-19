
#description: Delete an FSLogix user profile container from an Azure file share (NMM: uses $SecureVars.FslStorageKey)
#tags: Nerdio, FSLogix, NMM

<# Variables:
{
    "ProfileUsername": {
        "Description": "Username for the FSLogix profile to delete (e.g. JohnD or JDoe). Required if ProfileFolderName is not set; script then searches the share for a folder matching this name.",
        "IsRequired": false
    },
    "ProfileFolderName": {
        "Description": "Exact profile folder name (e.g. S-1-5-21-...-3780_JohnD or JDoe_S-1-5-21-...). If set, used directly—no search. Copy from Azure Portal path.",
        "IsRequired": false
    },
    "FileShareName": {
        "Description": "Name of the Azure file share from which to delete the FSLogix profile container.",
        "IsRequired": true
    },
    "StorageAccountName": {
        "Description": "Name of the Azure storage account containing the file share.",
        "IsRequired": true
    },
    "FslStorageKey": {
        "Description": "Optional override. In NMM, create secure variable FslStorageKey in Nerdio Manager; the script uses $SecureVars.FslStorageKey.",
        "IsRequired": false
    }
}
#>

# Set error action preference to stop on errors
$ErrorActionPreference = 'Stop'

# Log to runbook output (no local file; runbooks often have no writable C:\ or run in sandbox)
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "$timestamp - $Message"
}

# Storage account key: NMM uses $SecureVars.FslStorageKey. Optional runtime override via FslStorageKey parameter.
function Get-KeyFromSecureVar {
    param ($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    $s = [string]$Value
    if ($s) { $s = $s.Trim() }
    return $s
}

$rawKey = $SecureVars.FslStorageKey
if ($FslStorageKey -and ([string]::IsNullOrWhiteSpace($FslStorageKey) -eq $false -or $FslStorageKey -is [SecureString])) {
    $rawKey = $FslStorageKey
}
$storageAccountKey = Get-KeyFromSecureVar -Value $rawKey
if ([string]::IsNullOrWhiteSpace($storageAccountKey)) {
    throw "Storage account key is missing. In NMM, create the FslStorageKey secure variable in Nerdio Manager (Settings -> Nerdio Integrations) with the storage account key value."
}
if ($storageAccountKey.Length -lt 80) {
    throw "Storage account key is invalid (length=$($storageAccountKey.Length); expected ~88). Ensure the FslStorageKey secure variable contains the storage account key, not the variable name."
}

# Create a context for the storage account
$context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageAccountKey

# Recursively delete a directory and all its contents (Azure File Share does not allow deleting non-empty directories in one call)
function Remove-AzStorageDirectoryRecursive {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Context,
        [Parameter(Mandatory = $true)]
        [string]$ShareName,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Get-AzStorageFile -Context $Context -ShareName $ShareName -Path $Path -ErrorAction SilentlyContinue
    if (-not $directory) { return }

    $items = $directory | Get-AzStorageFile
    if (-not $items) { $items = @() }

    foreach ($item in @($items)) {
        $leafName = $item.Name
        if ($leafName -match '[/\\]') { $leafName = $leafName -replace '^.*[/\\]', '' }
        $itemPath = if ($Path) { "$Path/$leafName" } else { $leafName }

        if ($item.GetType().Name -match 'Directory') {
            Remove-AzStorageDirectoryRecursive -Context $Context -ShareName $ShareName -Path $itemPath
        } else {
            Remove-AzStorageFile -Context $Context -ShareName $ShareName -Path $itemPath -ErrorAction Stop
        }
    }

    Remove-AzStorageDirectory -Context $Context -ShareName $ShareName -Path $Path -ErrorAction Stop
}

# Resolve profile directory name. Use ProfileFolderName if provided; otherwise search share by ProfileUsername.
$profileDirName = $null
$searchUser = [string]$ProfileUsername
$searchUser = $searchUser.Trim()

if ([string]::IsNullOrWhiteSpace($ProfileFolderName) -eq $false) {
    $profileDirName = [string]$ProfileFolderName.Trim()
    $check = Get-AzStorageFile -Context $context -ShareName $FileShareName -Path $profileDirName -ErrorAction SilentlyContinue
    if (-not $check) {
        throw "Profile folder '$profileDirName' not found in share $FileShareName. Check the name (e.g. copy from Azure Portal path)."
    }
} elseif ([string]::IsNullOrWhiteSpace($searchUser)) {
    throw "Provide either ProfileUsername (e.g. JohnD or JDoe) or ProfileFolderName (exact folder name from Azure Portal)."
} else {
    $exact = Get-AzStorageFile -Context $context -ShareName $FileShareName -Path $searchUser -ErrorAction SilentlyContinue
    if ($exact) {
        $profileDirName = $searchUser
    } else {
        $topLevel = $null
        $share = Get-AzStorageShare -Context $context -Name $FileShareName -ErrorAction SilentlyContinue
        if ($share) {
            $topLevel = $share | Get-AzStorageFile -ErrorAction SilentlyContinue
        }
        if (-not $topLevel) {
            $rootDir = Get-AzStorageFile -Context $context -ShareName $FileShareName -Path "" -ErrorAction SilentlyContinue
            if ($rootDir) { $topLevel = $rootDir | Get-AzStorageFile }
        }
        if (-not $topLevel) {
            $topLevel = Get-AzStorageFile -Context $context -ShareName $FileShareName -ErrorAction SilentlyContinue
        }
        if ($topLevel) {
            foreach ($item in @($topLevel)) {
                if ($item.GetType().Name -notmatch 'Directory') { continue }
                $name = $item.Name
                if ($name -eq $searchUser -or $name -like "*_$searchUser" -or $name -like "${searchUser}_*") {
                    $profileDirName = $name
                    break
                }
            }
        }
    }
}

$profileContainerPath = "$FileShareName/$profileDirName"

# Check if the profile container exists and delete it (folder and all subfiles)
try {
    if ($profileDirName) {
        Write-Log "Profile container found: $profileContainerPath. Deleting recursively."
        Remove-AzStorageDirectoryRecursive -Context $context -ShareName $FileShareName -Path $profileDirName
        Write-Log "Profile container deleted: $profileContainerPath"
    } else {
        Write-Log "Profile container does not exist for user '$searchUser'. Looked for exact name, *_$searchUser, and ${searchUser}_* in share $FileShareName. Tip: use ProfileFolderName with the exact folder name from Azure Portal (e.g. S-1-5-21-...-3780_JohnD or JDoe_S-1-5-21-...)."
    }
} catch {
    throw "Failed to delete profile container: $_"
}
