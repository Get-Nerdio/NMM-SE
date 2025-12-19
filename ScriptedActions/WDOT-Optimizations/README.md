# WDOT Optimizations Script - Custom Configuration Profiles Guide

## Overview

The WDOT-Optimizations.ps1 script supports downloading custom configuration profiles from external sources, allowing MSPs to maintain customer-specific optimization settings without modifying the script itself. The script supports multiple methods for obtaining configuration profiles including HTTP/HTTPS URLs, UNC file shares, Azure Blob Storage, and individual JSON file overrides.

## Configuration Profile Sources

The script supports five methods for obtaining configuration profiles:

0. **Automatic GitHub Download** - Automatically downloads standard profiles (like 2009, Windows11_24H2) directly from the official WDOT GitHub repository
1. **Templates (Default)** - Uses WDOT's built-in Templates folder (automatically created if profile doesn't exist)
2. **Direct URL/UNC (Recommended)** - Download from HTTP/HTTPS URL or UNC file share path
3. **Azure Blob Storage** - Download from Azure Storage Account
4. **Individual JSON File Overrides** - Override specific JSON files within a profile

## Setup Options

### Option 0: Use Standard Profiles from GitHub (Automatic - Recommended for Standard Profiles)

**Inherited Variables:**
- `WDOTConfigProfile` = `2009` (or `Windows11_24H2`, or any standard profile name from the WDOT GitHub repository)
- `WDOTopt` = `All`
- `WDOTadvopt` = (optional)
- `WDOTrestart` = `-Restart` (optional)

**How it works:**
- Script automatically downloads the latest JSON files directly from the official WDOT GitHub repository
- No additional setup required - just specify the standard profile name
- Always gets the latest version from GitHub, even if missing from the extracted repository
- Works for standard profiles like: `2009`, `Windows11_24H2`, `Templates`, etc.
- Falls back to other methods if GitHub is unavailable

**Benefits:**
- Always uses the latest configuration files from the official repository
- No need to host or maintain your own copies of standard profiles
- Automatic updates when the WDOT team releases new versions
- Works seamlessly - just specify the profile name, no additional setup required

**How it works:**
- Script uses the GitHub API to list files in the profile folder
- Downloads each JSON/XML file directly from GitHub's raw content
- Creates the profile directory and places all files automatically
- Falls back to other methods (Templates, custom URLs, etc.) if GitHub is unavailable
- No authentication required for public repositories (GitHub API rate limits apply)

**GitHub API Notes:**
- Uses unauthenticated GitHub API (60 requests/hour limit)
- If you have a GitHub token, set it as environment variable `GITHUB_TOKEN` for higher rate limits
- Automatically handles API failures gracefully by falling back to other methods

### Option 1: Use Default Templates (No Custom Config)

**Inherited Variables:**
- `WDOTConfigProfile` = `MyCustomProfile` (or any name - will be created from Templates)
- `WDOTopt` = `All`
- `WDOTadvopt` = (optional)
- `WDOTrestart` = `-Restart` (optional)

**How it works:**
- Script automatically creates the profile from Templates if it doesn't exist
- No additional setup required
- **Note:** Templates profile has all optimizations set to "Skip" by default - you'll need to customize the JSON files to set items to "Apply"

### Option 2: Direct URL/UNC Path (Simplest Method - Recommended for Custom Profiles)

**Inherited Variables:**
- `WDOTConfigProfile` = `CustomerA-Production` (your profile name)
- `WDOTConfigProfileURL` = `https://raw.githubusercontent.com/yourorg/configs/main/CustomerA-Production.zip`
  - OR `\\fileserver\configs\CustomerA-Production.zip`
  - OR `\\storageaccount.file.core.windows.net\share\CustomerA-Production.zip`
- `WDOTopt` = `All`
- `WDOTadvopt` = (optional)
- `WDOTrestart` = `-Restart` (optional)

**Supported Path Types:**
- **HTTP/HTTPS URLs**: `https://raw.githubusercontent.com/org/repo/branch/path/profile.zip`
- **UNC Paths**: `\\server\share\configs\profile.zip`
- **Azure Files Shares**: `\\storageaccount.file.core.windows.net\share\profile.zip`

**Steps to Set Up:**

1. **Host your configuration profiles** in a ZIP file
   - GitHub repository (raw content)
   - File server share
   - Azure Files share
   - Any web server
2. **Set Inherited Variables** in Nerdio Manager
3. **Set `WDOTConfigProfileURL`** to the full URL or UNC path

**Note:** For Azure Files shares, ensure credentials are configured (e.g., via `cmdkey` or Azure Files identity-based authentication).

### Option 3: Azure Blob Storage

**Inherited Variables:**
- `WDOTConfigProfile` = `CustomerA-Production` (your profile name)
- `WDOTConfigSource` = `AzureBlob`
- `WDOTStorageAccount` = `yourstorageaccount`
- `WDOTStorageContainer` = `wdot-configs` (optional, defaults to `wdot-configs`)
- `WDOTopt` = `All`
- `WDOTadvopt` = (optional)
- `WDOTrestart` = `-Restart` (optional)

**Secure Variables:**
- `WDOTStorageKey` = `your-storage-account-key`

**Blob Storage Structure:**

You can organize your configuration profiles in two ways:

**Method A: ZIP Files**
```
Container: wdot-configs
├── CustomerA-Production.zip
├── CustomerB-Development.zip
└── CustomerC-Testing.zip
```

**Method B: Folder Structure**
```
Container: wdot-configs
├── CustomerA-Production/
│   ├── Services.json
│   ├── AppxPackages.json
│   ├── ScheduledTasks.json
│   └── ... (other JSON files)
├── CustomerB-Development/
│   └── ...
```

**Steps to Set Up:**

1. **Create Azure Storage Account** (if you don't have one)
2. **Create a container** (e.g., `wdot-configs`)
3. **Upload your configuration profiles:**
   - Option A: Upload ZIP files named `{ProfileName}.zip`
   - Option B: Upload folder structure with prefix `{ProfileName}/`
4. **Get Storage Account Key** from Azure Portal
5. **Set Inherited Variables** in Nerdio Manager at MSP or Account level
6. **Set Secure Variable** `WDOTStorageKey` with the storage account key

### Option 4: Individual JSON File Overrides

**Inherited Variables:**
- `WDOTConfigProfile` = `2009` (or any existing profile - can use standard profiles from GitHub)
- `WDOTConfigFiles` = `Services.json=https://url1,AppxPackages.json=\\server\share\AppxPackages.json`
- `WDOTopt` = `All`

**Format:**
- `filename.json=url/unc,filename2.json=url/unc`
- Can also use just URLs/UNC paths if filename is in the path
- Supports HTTP/HTTPS URLs and UNC paths

**Examples:**
```
WDOTConfigFiles = Services.json=https://raw.githubusercontent.com/yourorg/configs/main/Services.json,AppxPackages.json=\\fileserver\configs\AppxPackages.json
```

**How it works:**
- Applied AFTER the profile is downloaded/created
- Overrides specific JSON files without replacing the entire profile
- Useful for fine-tuning specific configuration files
- Can be combined with standard profiles from GitHub (e.g., use 2009 from GitHub but override specific files)

## Processing Order

The script processes configuration sources in this priority order:

0. **Automatic GitHub Download** - If profile is missing, attempts to download standard profiles (like 2009, Windows11_24H2) directly from the official WDOT GitHub repository
1. **WDOTConfigProfileURL** (if set) - Direct URL or UNC path (simplest method for custom profiles)
2. **WDOTConfigSource** (if set) - AzureBlob or URL/UNC method
3. **Templates** - Automatically creates profile from Templates if not found
4. **WDOTConfigFiles** - Applies individual JSON file overrides (if specified)

**Note:** When using standard profile names like "2009" or "Windows11_24H2", the script will automatically download the latest JSON files from GitHub if the profile is missing from the extracted repository. This ensures you always get the latest configuration files without needing to host them yourself.

## Creating Custom Configuration Profiles

### Using WDOT's Built-in Tools

1. **Download WDOT** from GitHub
2. **Run the configuration tool:**
   ```powershell
   .\New-WVDConfigurationFiles.ps1 -FolderName "MyCustomProfile"
   ```
3. **Customize the JSON files** in `Configurations\MyCustomProfile\`
   - Set `OptimizationState: "Apply"` for items you want optimized
   - Set `OptimizationState: "Skip"` for items you want to keep
4. **Package as ZIP** file
5. **Upload to your storage solution** (Blob Storage, file share, or web server)

### Manual Creation

1. **Start with Templates** - Copy the Templates folder
2. **Edit JSON files** to set `OptimizationState` to `Apply` or `Skip`
3. **Test locally** before deploying
4. **Package as ZIP** or upload folder structure

## Best Practices for MSPs

### 1. Organize by Customer

Create separate profiles for each customer:
- `CustomerA-Production`
- `CustomerA-Development`
- `CustomerB-Production`

### 2. Use Account-Level Variables

Set customer-specific variables at the Account level:
- `WDOTConfigProfile` = `CustomerA-Production`
- `WDOTConfigProfileURL` = `\\fileserver\configs\CustomerA-Production.zip` (or URL)
- `WDOTStorageAccount` = `msp-storage-account` (if using Azure Blob)

### 3. Version Control

Store your configuration profiles in:
- Azure Blob Storage with versioning enabled
- GitHub repository
- Azure DevOps artifacts
- File server with version folders

### 4. Testing

Always test new profiles in a non-production environment first.

## Example: Multi-Customer Setup

### MSP-Level Variables (Default)
```
WDOTConfigProfile = 2009
WDOTopt = All
WDOTadvopt = 
WDOTrestart = -Restart
```
**Note:** The `2009` profile will be automatically downloaded from the official WDOT GitHub repository if it's missing from the extracted repository. No additional configuration needed!

### Customer A Account-Level Variables
```
WDOTConfigProfile = CustomerA-Prod
WDOTConfigProfileURL = \\fileserver\configs\CustomerA-Prod.zip
```

### Customer B Account-Level Variables
```
WDOTConfigProfile = CustomerB-Prod
WDOTConfigProfileURL = https://raw.githubusercontent.com/msp/configs/main/CustomerB-Prod.zip
```

### Customer C Account-Level Variables (Azure Blob)
```
WDOTConfigProfile = CustomerC-Prod
WDOTConfigSource = AzureBlob
WDOTStorageAccount = mspstorage
WDOTStorageContainer = wdot-configs
WDOTStorageKey = (Secure Variable)
```

### Customer D Account-Level Variables (Individual File Overrides)
```
WDOTConfigProfile = 2009
WDOTConfigFiles = Services.json=\\fileserver\configs\Services-Custom.json,AppxPackages.json=\\fileserver\configs\AppxPackages-Custom.json
```

## Troubleshooting

### Profile Not Found
- Check that the profile name matches exactly (case-sensitive)
- For standard profiles (2009, Windows11_24H2), verify GitHub API access is available
- Verify the blob/URL/UNC path exists (for custom profiles)
- Check storage account key is correct (if using Azure Blob)
- Verify network connectivity for UNC paths and GitHub API
- Review script output for specific error messages
- Standard profiles will automatically download from GitHub if missing - check script logs for download status

### Configuration Not Applied
- Verify JSON files have `OptimizationState: "Apply"` for items you want optimized
- Check that the optimization category is included in `WDOTopt`
- Review WDOT logs in Windows Event Viewer (WDOT log)
- Templates profile has all items set to "Skip" by default - you need to customize it

### Download Failures
- Verify network connectivity
- Check storage account firewall rules (Azure Blob)
- Verify SAS token hasn't expired (if using URL with SAS)
- Check Azure Storage permissions
- For UNC paths, ensure credentials are configured and share is accessible
- Check file share permissions

### UNC Path Issues
- Ensure the VM has network access to the file share
- Verify credentials are configured (use `cmdkey` or Azure Files identity-based auth)
- Check that the account running the script has read access to the share
- For Azure Files, ensure proper authentication method is configured

## Security Considerations

1. **Storage Account Keys**: Always use Secure Variables, never Inherited Variables
2. **SAS Tokens**: Use time-limited SAS tokens for URL-based downloads
3. **Private Endpoints**: Consider using Azure Private Endpoints for Blob Storage
4. **Access Control**: Use RBAC to limit who can modify storage account contents
5. **UNC Paths**: Use least-privilege access for file shares
6. **Network Security**: Consider using private networks/VPNs for file share access

## Additional Resources

- [WDOT GitHub Repository](https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool)
- [WDOT Configuration Guide](https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool/blob/main/Configuration%20Files%20User%20Guide.md)
- [Nerdio Manager Inherited Variables Documentation](https://nmmhelp.getnerdio.com/hc/en-us/articles/25498222400269-Scripted-Actions-MSP-Level-Variables)

