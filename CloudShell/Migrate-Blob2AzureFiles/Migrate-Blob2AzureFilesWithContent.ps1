<#
.SYNOPSIS
    Migrates blob containers to an Azure File Share (folders + content). Runs from Azure Cloud Shell.

.DESCRIPTION
    - Creates one folder per blob container (name normalized for SMB, e.g. dtest-s-1-12-1-... -> DTest_S-1-12-1-...).
    - Copies all blob content into the corresponding folder.
    - Does not set NTFS owner/ACLs. After migration, run Set-AzFilesFolderOwner.ps1 on a Windows machine
      with the share mounted via SMB to set owner and Full Control for each folder (permission key is generated automatically over SMB).
#>
param()

# Authenticate to Azure
Connect-AzAccount

# --- Blob Storage Account (source: where container names and blobs are read from) ---
Write-Host "`n--- Blob Storage Account (source) ---" -ForegroundColor Cyan
$blobResourceGroupName = Read-Host "Blob storage Resource Group name"
$blobStorageAccountName = Read-Host "Blob storage Account name"
$blobStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $blobResourceGroupName -Name $blobStorageAccountName)[0].Value
$blobContext = New-AzStorageContext -StorageAccountName $blobStorageAccountName -StorageAccountKey $blobStorageAccountKey

# --- Azure Files Storage Account (destination: where folders and files will be created) ---
Write-Host "`n--- Azure Files Storage Account (destination) ---" -ForegroundColor Cyan
$filesResourceGroupName = Read-Host "Azure Files Resource Group name"
$filesStorageAccountName = Read-Host "Azure Files Storage Account name"
$fileShareName = Read-Host "Azure Files share name (where folders and files will be created)"
$filesStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $filesResourceGroupName -Name $filesStorageAccountName)[0].Value
$filesContext = New-AzStorageContext -StorageAccountName $filesStorageAccountName -StorageAccountKey $filesStorageAccountKey

# Temp directory for blob downloads (download -> upload to file share -> delete)
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "Blob2FilesMigrate_$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # Normalize container name to match folder name created when mounting/using the share (e.g. SMB/FSLogix).
    # Example: dtest-s-1-12-1-... -> DTest_S-1-12-1-... (first hyphen to underscore; first segment "DTest"-style casing)
    function Get-FileShareFolderName {
        param([string]$ContainerName)
        $idx = $ContainerName.IndexOf('-')
        if ($idx -le 0) { return $ContainerName }
        $first = $ContainerName.Substring(0, $idx)
        $rest = $ContainerName.Substring($idx + 1)
        # First segment: capitalize first two characters (e.g. dtest -> DTest)
        $firstLen = [Math]::Min(2, $first.Length)
        $firstNormalized = $first.Substring(0, $firstLen).ToUpper()
        if ($first.Length -gt $firstLen) { $firstNormalized += $first.Substring($firstLen).ToLower() }
        # Rest: capitalize first character (e.g. s-1-12-... -> S-1-12-...)
        $restNormalized = if ($rest.Length -gt 0) { $rest.Substring(0, 1).ToUpper() + $rest.Substring(1) } else { $rest }
        return $firstNormalized + '_' + $restNormalized
    }

    # Helper: ensure parent directory path exists in the file share (for blob names like "subdir/file.txt")
    function Ensure-FileSharePath {
        param([string]$ShareName, [string]$PathInShare, [object]$Context)
        $parts = $PathInShare -split '/' | Where-Object { $_ -ne '' }
        if ($parts.Count -le 1) { return }
        $current = $parts[0]
        for ($i = 1; $i -lt $parts.Count - 1; $i++) {
            $current = $current + '/' + $parts[$i]
            try {
                New-AzStorageDirectory -ShareName $ShareName -Path $current -Context $Context -ErrorAction Stop | Out-Null
            }
            catch {
                if ($_.Exception.Message -notmatch 'already exists') { throw }
            }
        }
    }

    # Get the list of all Blob Containers from the source storage account
    $containers = Get-AzStorageContainer -Context $blobContext

    foreach ($container in $containers) {
        # Folder name and owner SID are both derived from the container name (e.g. container dtest-s-1-12-1-... -> folder DTest_S-1-12-1-..., owner S-1-12-1-...)
        $folderName = Get-FileShareFolderName -ContainerName $container.Name

        # Step 1: Create the folder in the File Share
        try {
            if ($folderName -ne $container.Name) {
                Write-Host "Creating folder: $folderName (from container '$($container.Name)')"
            } else {
                Write-Host "Creating folder: $folderName"
            }
            New-AzStorageDirectory -ShareName $fileShareName -Path $folderName -Context $filesContext
        }
        catch {
            if ($_.Exception.Message -notmatch 'already exists') {
                Write-Host "Error creating folder '$folderName': $_"
                continue
            }
        }

        # Step 2: Copy blob contents into the corresponding folder
        $blobs = Get-AzStorageBlob -Container $container.Name -Context $blobContext -ErrorAction SilentlyContinue
        $blobCount = ($blobs | Measure-Object).Count
        if ($blobCount -eq 0) {
            Write-Host "  No blobs in container '$folderName'."
            continue
        }
        Write-Host "  Copying $blobCount blob(s) from container '$folderName'..."
        $copied = 0
        foreach ($blob in $blobs) {
            try {
                $destPathInShare = "$folderName/$($blob.Name)"
                Ensure-FileSharePath -ShareName $fileShareName -PathInShare $destPathInShare -Context $filesContext
                $localPath = Join-Path $tempDir $blob.Name
                $localDir = [System.IO.Path]::GetDirectoryName($localPath)
                if (-not [string]::IsNullOrEmpty($localDir) -and -not (Test-Path $localDir)) {
                    New-Item -ItemType Directory -Path $localDir -Force | Out-Null
                }
                Get-AzStorageBlobContent -Container $container.Name -Blob $blob.Name -Destination $tempDir -Context $blobContext -Force | Out-Null
                Set-AzStorageFileContent -ShareName $fileShareName -Path $destPathInShare -Source $localPath -Context $filesContext -Force | Out-Null
                Remove-Item -LiteralPath $localPath -Force -ErrorAction SilentlyContinue
                $copied++
                Write-Host "    Copied: $($blob.Name)"
            }
            catch {
                Write-Host "    Error copying '$($blob.Name)': $_"
            }
        }
        Write-Host "  Done. Copied $copied of $blobCount blob(s) for '$folderName'."
    }

    Write-Host "`nMigration complete. To set NTFS owner and Full Control on each folder, run Set-AzFilesFolderOwner.ps1 on a Windows machine with the share mounted via SMB (e.g. Z:\ or \\storageaccount.file.core.windows.net\share). The permission key is generated automatically when setting ACLs over SMB.`n" -ForegroundColor Cyan
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
}

# Optional: Verify (you can run after the script completes)
# Get-AzStorageFile -ShareName $fileShareName -Context $filesContext
