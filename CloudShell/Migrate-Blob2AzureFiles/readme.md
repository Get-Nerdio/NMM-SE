# Migrate Blob to Azure Files

Scripts to create a matching folder structure (and optionally copy content) in an Azure File Share from blob container names. Useful when preparing Azure Files to mirror blob layout or when migrating from blob to file-based storage.

| Script | Description |
|--------|-------------|
| **Migrate-Blob2AzureFiles.ps1** | Creates one folder per blob container. Does **not** copy blob contents. |
| **Migrate-Blob2AzureFilesWithContent.ps1** | Creates the folders **and** copies all blob content. Runs from **Azure Cloud Shell**. Does **not** set NTFS owner or ACLs. After migration, run **Set-AzFilesFolderOwner.ps1** on a Windows machine with the share **already mounted** via SMB to set owner only. |
| **Set-AzFilesFolderOwner.ps1** | *(Windows only)* Run on a Windows machine where the Azure File Share is **already mounted** (e.g. Z:\ or UNC). Prompts for the mounted path (or pass `-SharePath`). If the path does not exist, the script exits with instructions to mount the share first. Sets the **owner only** (no ACL changes) for each top-level folder and its contents; the owner is the SID encoded in the folder name (e.g. `DTest_S-1-12-1-...` → owner `S-1-12-1-...`). Use **after** migration. |

---

## Migrate-Blob2AzureFiles.ps1 (folders only)

### What it does

- Connects to Azure (`Connect-AzAccount`).
- Reads **blob container names** from a source storage account.
- Creates **folders** in a specified Azure File Share with the same names as those containers.
- **Does not copy blob contents**—only the folder/directory structure is created.

### How to run

```powershell
.\Migrate-Blob2AzureFiles.ps1
```

When prompted, enter Blob storage (Resource Group, Storage Account) and Azure Files (Resource Group, Storage Account, File Share name). You can use the same account for both if blob containers and the file share are in the same account.

### Example

- Source blob account has containers: `logs`, `backups`, `data`.
- After the script runs, the file share has folders: `logs/`, `backups/`, `data/`. No files are copied.

---

## Migrate-Blob2AzureFilesWithContent.ps1 (folders + content)

### What it does

- Does everything **Migrate-Blob2AzureFiles.ps1** does (creates one folder per container).
- **Then** copies all blob content from each container into the corresponding file share folder.
- Preserves blob hierarchy (e.g. blobs under `subdir/file.txt` become `container/subdir/file.txt` in the share).
- **Folder name normalization:** Container names are normalized so the folder name matches what SMB/login creates (e.g. `dtest-s-1-12-1-...` → `DTest_S-1-12-1-...`).
- **Does not set NTFS owner/ACLs.** After migration, run **Set-AzFilesFolderOwner.ps1** on a Windows machine with the share **already mounted** via SMB to set owner only for each folder.’t“owner” 
### How to run (Azure Cloud Shell)
```powershell
.\Migrate-Blob2AzureFilesWithContent.ps1
```

When prompted, enter Blob storage and Azure Files (Resource Group, Storage Account, File Share name). The script migrates folders and content only. **Then**, on a Windows machine with the share already mounted via SMB, run **Set-AzFilesFolderOwner.ps1** to set owner only for each folder.

The script downloads each blob to a temp location, uploads it to the file share, then deletes the temp file. For very large containers or big blobs, ensure enough temp space. For huge migrations, consider [AzCopy](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-files) for server-side copy.

---

## Set-AzFilesFolderOwner.ps1 (owner only, after migration)

**Run this on a Windows machine** where the Azure File Share is **already mounted** via SMB (e.g. Z:\ or UNC). The script does **not** mount the share or prompt for storage account key. If the path you enter does not exist, the script exits with instructions to mount the share first. NTFS owner on Azure Files can only be set from a client with the share mounted—not from Cloud Shell or Az.Storage.

### What it does

- For each top-level folder under the mounted path, parses the **SID** from the folder name (the part after the first underscore, e.g. `DTest_S-1-12-1-458276005-...` → SID `S-1-12-1-458276005-...`).
- Sets the **owner only** of that folder and all its contents to that SID. **ACL permissions are not changed** (no Full Control or other rights are added).
- When finished, prompts **Unmount the share now? (Y/N)**; if you choose Y, the script unmounts the share (e.g. `net use Z: /delete` for a drive letter, or `net use \\server\share /delete` for a UNC path).

### Prerequisites

- Windows machine with the Azure File Share **mounted via SMB** (identity-based auth: Azure AD DS or AD DS so NTFS ACLs persist).
- Run PowerShell **as Administrator** (or with an account that has [Storage File Data SMB Share Elevated Contributor](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-ad-ds-assign-permissions) so you can change ownership).

### How to run

1. **Mount the Azure File Share first** (e.g. `net use Z: \\storageaccount.file.core.windows.net\sharename` with identity auth or key).
2. Run as Administrator:
   ```powershell
   .\Set-AzFilesFolderOwner.ps1
   ```
3. When prompted, enter the **mounted path** (e.g. `Z:\` or `\\storageaccount.file.core.windows.net\sharename`). If the path does not exist, the script exits with instructions to mount the share first.

Or pass the path:
```powershell
.\Set-AzFilesFolderOwner.ps1 -SharePath "Z:\"
```

Run this **after** you have run the migration script so that the folders and content exist; then the owner will match the SID encoded in each folder name. At the end, you can choose to unmount the share (Y/N).

---

## Setting permissions after migration (options)

After migrating folders and content, you need to set Windows ACLs (owner/NTFS permissions) so users can access their data. Azure Files supports several ways to do this; choose what fits your environment.

| Option | When to use |
|--------|-------------|
| **Azure portal** | Easiest for ad‑hoc or per-folder changes. Works when [Microsoft Entra Kerberos](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-configure-file-level-permissions) is your identity source (hybrid or cloud-only). Sign in at [https://aka.ms/portal/fileperms](https://aka.ms/portal/fileperms) → open your file share → **Browse** → right‑click a file or folder → **Manage access** to set permissions per Entra user or group. |
| **Set-AzFilesFolderOwner.ps1** | Bulk automation to set **owner only** when folder names encode the SID (e.g. `DTest_S-1-12-1-...`). Run on a Windows machine where the share is already mounted via SMB; see section above. Does not add or change ACL permissions. |
| **PowerShell (cloud-only, bulk)** | For bulk ACLs for cloud-only identities, use the Azure Files REST API (e.g. [RestSetAcls](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-configure-file-level-permissions#configure-windows-acls-for-cloud-only-identities-using-powershell) / `Add-AzFileAce`). |

Full details (share-level RBAC, mounting with identity vs key, icacls, and portal steps): [Configure directory and file-level permissions for Azure file shares](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-configure-file-level-permissions).

---

## Prerequisites

- Azure PowerShell (`Az` module); in Azure Cloud Shell this is already available.
- Permissions to read storage account keys and list containers (source), and to create files/directories in the file share (destination).

## Verify results

After either script completes, you can list the file share contents:

```powershell
Get-AzStorageFile -ShareName $fileShareName -Context $filesContext
```

(Use the same `$fileShareName` and `$filesContext` from your run, or substitute your share name and context.)
