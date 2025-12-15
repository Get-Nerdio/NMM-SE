<#
.SYNOPSIS
    Runs the Windows Desktop Optimization Tool (WDOT) from the WDOT GitHub (https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool) by utilizing Inherited Variables for the installer arguments that can be adjusted at the Account level in NMM.
    ***WARNING***
    This script just calls the latest version of the WDOT script.
    If there are any issues with the WDOT script itself, please create an issue in the Virtual Desktop Team GitHub repo.

.REQUIREMENTS
    The following Inherited Variables are required to be created at the MSP Level of Nerdio Manager for MSP
    The values listed are the recommended default actions.
    You can change these values at the Account Level. You can read more about the parameters HERE (https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool?tab=readme-ov-file#-windows_optimizationps1---main-script)

    Required Inherited Variables:
    WDOTConfigProfile = 2009 (or any valid config profile name - common: 2009, Templates, Windows11_24H2)
    WDOTopt = All (or array like: Services,AppxPackages,ScheduledTasks)
    WDOTadvopt = (leave empty or specify: All,Edge,RemoveLegacyIE,RemoveOneDrive)
    WDOTrestart = -Restart (or leave empty to skip restart)
    
    Optional Inherited Variables (for custom configuration profiles):
    
    Method 1 - Direct Profile URL/UNC (Simplest, Recommended):
    WDOTConfigProfileURL = https://raw.githubusercontent.com/yourorg/configs/main/MyProfile.zip
        OR
    WDOTConfigProfileURL = \\server\share\configs\MyProfile.zip
        OR
    WDOTConfigProfileURL = \\storageaccount.file.core.windows.net\share\MyProfile.zip
        - Direct URL or UNC path to download the entire configuration profile ZIP file
        - Supports HTTP/HTTPS URLs, UNC paths (\\server\share), and Azure Files shares
        - Takes priority over other methods
        - Examples:
          * https://raw.githubusercontent.com/yourorg/configs/main/CustomerA-Prod.zip
          * \\fileserver\configs\CustomerA-Prod.zip
          * \\mystorage.file.core.windows.net\wdot-configs\CustomerA-Prod.zip
    
    Method 2 - Azure Blob Storage:
    WDOTConfigSource = AzureBlob (required if using Azure Blob Storage)
    WDOTStorageAccount = Name of Azure Storage Account
    WDOTStorageContainer = Name of blob container (default: wdot-configs)
    WDOTStorageKey = Storage Account Key (create as Secure Variable)
    
    Method 3 - Legacy URL/UNC via ConfigSource:
    WDOTConfigSource = https://raw.githubusercontent.com/yourorg/configs/main/MyProfile.zip
        OR
    WDOTConfigSource = \\server\share\configs\MyProfile.zip
        - Alternative to WDOTConfigProfileURL (for backward compatibility)
        - Supports HTTP/HTTPS URLs and UNC paths
    
    Method 4 - Individual JSON File Overrides:
    WDOTConfigFiles = Services.json=https://url1,AppxPackages.json=\\server\share\AppxPackages.json
        - Override specific JSON files within a profile without replacing the entire profile
        - Format: filename.json=url/unc,filename2.json=url/unc
        - Can also use just URLs/UNC paths if filename is in the path
        - Supports HTTP/HTTPS URLs and UNC paths (\\server\share)
        - Applied AFTER the profile is downloaded/created
        - Examples:
          * Services.json=https://raw.githubusercontent.com/yourorg/configs/main/Services.json
          * AppxPackages.json=\\fileserver\configs\AppxPackages.json
          * ScheduledTasks.json=\\storageaccount.file.core.windows.net\share\ScheduledTasks.json
    
    NOTE: The script will process in this order:
    1. First try WDOTConfigProfileURL (if set) - simplest method
    2. Then try WDOTConfigSource (AzureBlob or URL/UNC method)
    3. If not found, automatically create the specified configuration profile from Templates
    4. Finally, apply any individual JSON file overrides from WDOTConfigFiles

    NOTE: If you want to use different variable names, you will need to update the script accordingly.

.EXECUTION MODE
    Individual or Individual with Restart
#>

# Define GitHub ZIP download URL
$wdotUrl = "https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool/archive/refs/heads/main.zip"

# Temp paths
$tempPath = "$env:SystemRoot\TEMP\WDOT"
$zipPath = "$tempPath\wdot.zip"
$extractPath = "$tempPath\Extracted"

# Create working directory
New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

# Download and unblock the ZIP
Write-Host "Downloading WDOT from GitHub..."
Invoke-WebRequest -Uri $wdotUrl -OutFile $zipPath -ErrorAction Stop
Unblock-File -Path $zipPath

# Extract contents
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Locate the script folder
$wdotScriptPath = Get-ChildItem -Path $extractPath -Directory |
    Where-Object { $_.Name -like "Windows-Desktop-Optimization-Tool*" } |
    Select-Object -First 1

if (-not $wdotScriptPath) {
    Write-Error "Could not find extracted WDOT folder."
    exit 1
}

# Unblock all files in the folder
Get-ChildItem -Path $wdotScriptPath.FullName -Recurse | Unblock-File

# Set path to main script
$fullScriptPath = Join-Path $wdotScriptPath.FullName "Windows_Optimization.ps1"
if (-not (Test-Path $fullScriptPath)) {
    Write-Error "Windows_Optimization.ps1 not found."
    exit 1
}

# Inherited variables for script arguments
$configProfile = "$($InheritedVars.WDOTConfigProfile)"
$opt = "$($InheritedVars.WDOTOpt)"
$advOpt = "$($InheritedVars.WDOTAdvOpt)"
$restart = "$($InheritedVars.WDOTRestart)"

# Optional variables for custom configuration profiles
$configProfileURL = "$($InheritedVars.WDOTConfigProfileURL)".Trim()
$configSource = "$($InheritedVars.WDOTConfigSource)".Trim()
$storageAccount = "$($InheritedVars.WDOTStorageAccount)".Trim()
$storageContainer = if ([string]::IsNullOrWhiteSpace("$($InheritedVars.WDOTStorageContainer)")) { "wdot-configs" } else { "$($InheritedVars.WDOTStorageContainer)".Trim() }
$storageKey = "$($SecureVars.WDOTStorageKey)".Trim()
$configFiles = "$($InheritedVars.WDOTConfigFiles)".Trim()

# Validate required arguments
if ([string]::IsNullOrWhiteSpace($configProfile)) {
    Write-Error "Missing required variable: WDOTConfigProfile. This must specify a configuration profile name (e.g., Windows11_24H2)."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($opt)) {
    Write-Error "Missing required variable: WDOTOpt. This must specify optimizations (e.g., All or Services,AppxPackages)."
    exit 1
}

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Parse optimizations - handle comma-separated string or single value
$optArray = if ($opt -match ',') { 
    $opt -split ',' | ForEach-Object { $_.Trim() }
} else { 
    @($opt.Trim())
}

# Parse advanced optimizations if provided
$advOptArray = @()
$advOptTrimmed = $advOpt.Trim()
if (-not [string]::IsNullOrWhiteSpace($advOptTrimmed) -and 
    $advOptTrimmed -notmatch '^(?i)(No|None)$') {
    $advOptArray = if ($advOptTrimmed -match ',') { 
        $advOptTrimmed -split ',' | ForEach-Object { $_.Trim() }
    } else { 
        @($advOptTrimmed)
    }
}

# Validate and create/download configuration profile if needed
$configPath = Join-Path $wdotScriptPath.FullName "Configurations\$configProfile"
$configurationsPath = Join-Path $wdotScriptPath.FullName "Configurations"
$templatesPath = Join-Path $configurationsPath "Templates"
$newConfigScript = Join-Path $wdotScriptPath.FullName "New-WVDConfigurationFiles.ps1"
$customConfigDownloaded = $false

if (-not (Test-Path $configPath)) {
    # Priority 1: Try WDOTConfigProfileURL (direct URL or UNC path - simplest method)
    if (-not [string]::IsNullOrWhiteSpace($configProfileURL)) {
        try {
            Write-Host "Downloading configuration profile from: $configProfileURL"
            $tempZipPath = Join-Path $tempPath "$configProfile.zip"
            $tempExtractPath = Join-Path $tempPath "CustomConfig"
            
            # Check if it's a UNC path (file share) or HTTP/HTTPS URL
            if ($configProfileURL -like "\\*") {
                # UNC path - use Copy-Item
                Write-Host "Detected UNC file share path, copying file..."
                Copy-Item -Path $configProfileURL -Destination $tempZipPath -Force -ErrorAction Stop
            }
            elseif ($configProfileURL -like "http*") {
                # HTTP/HTTPS URL - use Invoke-WebRequest
                Invoke-WebRequest -Uri $configProfileURL -OutFile $tempZipPath -ErrorAction Stop
            }
            else {
                throw "Invalid path format. Must be a UNC path (\\server\share\path) or HTTP/HTTPS URL."
            }
            
            Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractPath -Force
            
            # Copy downloaded config to WDOT configurations folder
            $downloadedConfigPath = Get-ChildItem -Path $tempExtractPath -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($downloadedConfigPath) {
                $finalConfigPath = Join-Path $configurationsPath $configProfile
                Copy-Item -Path $downloadedConfigPath.FullName -Destination $finalConfigPath -Recurse -Force
                Write-Host "Successfully downloaded and installed custom configuration profile from URL."
                $customConfigDownloaded = $true
            }
            else {
                # Assume the extracted folder IS the config
                $finalConfigPath = Join-Path $configurationsPath $configProfile
                Copy-Item -Path $tempExtractPath -Destination $finalConfigPath -Recurse -Force
                Write-Host "Successfully downloaded and installed custom configuration profile from URL."
                $customConfigDownloaded = $true
            }
        }
        catch {
            Write-Warning "Failed to download from WDOTConfigProfileURL: $_`nFalling back to other methods."
        }
    }
    
    # Priority 2: Try WDOTConfigSource (Azure Blob or URL method)
    if (-not $customConfigDownloaded -and -not [string]::IsNullOrWhiteSpace($configSource)) {
        Write-Host "Custom configuration source specified: $configSource"
        
        if ($configSource -ieq "AzureBlob" -or $configSource -ieq "Azure") {
            # Download from Azure Blob Storage
            if ([string]::IsNullOrWhiteSpace($storageAccount) -or [string]::IsNullOrWhiteSpace($storageKey)) {
                Write-Warning "WDOTConfigSource is set to AzureBlob but WDOTStorageAccount or WDOTStorageKey is missing. Falling back to Templates."
            }
            else {
                try {
                    Write-Host "Downloading configuration profile from Azure Blob Storage..."
                    Write-Host "  Storage Account: $storageAccount"
                    Write-Host "  Container: $storageContainer"
                    Write-Host "  Profile: $configProfile"
                    
                    # Check if Az.Storage module is available
                    $azStorageModule = Get-Module -ListAvailable -Name Az.Storage
                    if (-not $azStorageModule) {
                        Write-Host "Installing Az.Storage module..."
                        Install-Module -Name Az.Storage -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck
                    }
                    Import-Module Az.Storage -Force
                    
                    # Create storage context
                    $storageContext = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageKey
                    
                    # Try to download as ZIP first, then as folder
                    $blobZipName = "$configProfile.zip"
                    $blobFolderName = "$configProfile/"
                    
                    $tempZipPath = Join-Path $tempPath "$configProfile.zip"
                    $tempExtractPath = Join-Path $tempPath "CustomConfig"
                    
                    # Try ZIP blob first
                    try {
                        Get-AzStorageBlob -Container $storageContainer -Blob $blobZipName -Context $storageContext -ErrorAction Stop | Out-Null
                        Write-Host "Found ZIP blob: $blobZipName"
                        Get-AzStorageBlobContent -Container $storageContainer -Blob $blobZipName -Destination $tempZipPath -Context $storageContext -Force
                        Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractPath -Force
                        $customConfigDownloaded = $true
                    }
                    catch {
                        # Try folder/blob prefix
                        Write-Host "ZIP not found, trying folder structure..."
                        $blobs = Get-AzStorageBlob -Container $storageContainer -Prefix $blobFolderName -Context $storageContext -ErrorAction SilentlyContinue
                        if ($blobs) {
                            Write-Host "Found folder structure with $($blobs.Count) files"
                            New-Item -ItemType Directory -Path $tempExtractPath -Force | Out-Null
                            
                            foreach ($blob in $blobs) {
                                $relativePath = $blob.Name.Replace($blobFolderName, "")
                                $destinationPath = Join-Path $tempExtractPath $relativePath
                                $destinationDir = Split-Path $destinationPath -Parent
                                if (-not (Test-Path $destinationDir)) {
                                    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                                }
                                Get-AzStorageBlobContent -Container $storageContainer -Blob $blob.Name -Destination $destinationPath -Context $storageContext -Force
                            }
                            $customConfigDownloaded = $true
                        }
                    }
                    
                    if ($customConfigDownloaded) {
                        # Copy downloaded config to WDOT configurations folder
                        $downloadedConfigPath = Get-ChildItem -Path $tempExtractPath -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($downloadedConfigPath) {
                            $finalConfigPath = Join-Path $configurationsPath $configProfile
                            Copy-Item -Path $downloadedConfigPath.FullName -Destination $finalConfigPath -Recurse -Force
                            Write-Host "Successfully downloaded and installed custom configuration profile from Azure Blob Storage."
                        }
                        else {
                            # Assume the extracted folder IS the config
                            $finalConfigPath = Join-Path $configurationsPath $configProfile
                            Copy-Item -Path $tempExtractPath -Destination $finalConfigPath -Recurse -Force
                            Write-Host "Successfully downloaded and installed custom configuration profile from Azure Blob Storage."
                        }
                    }
                    else {
                        Write-Warning "Configuration profile '$configProfile' not found in Azure Blob Storage. Falling back to Templates."
                    }
                }
                catch {
                    Write-Warning "Failed to download from Azure Blob Storage: $_`nFalling back to Templates."
                }
            }
        }
        elseif ($configSource -like "http*" -or $configSource -like "\\*") {
            # Download from URL or UNC path
            try {
                Write-Host "Downloading configuration profile from: $configSource"
                $tempZipPath = Join-Path $tempPath "$configProfile.zip"
                $tempExtractPath = Join-Path $tempPath "CustomConfig"
                
                # Check if it's a UNC path (file share) or HTTP/HTTPS URL
                if ($configSource -like "\\*") {
                    # UNC path - use Copy-Item
                    Write-Host "Detected UNC file share path, copying file..."
                    Copy-Item -Path $configSource -Destination $tempZipPath -Force -ErrorAction Stop
                }
                else {
                    # HTTP/HTTPS URL - use Invoke-WebRequest
                    Invoke-WebRequest -Uri $configSource -OutFile $tempZipPath -ErrorAction Stop
                }
                
                Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractPath -Force
                
                # Copy downloaded config to WDOT configurations folder
                $downloadedConfigPath = Get-ChildItem -Path $tempExtractPath -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($downloadedConfigPath) {
                    $finalConfigPath = Join-Path $configurationsPath $configProfile
                    Copy-Item -Path $downloadedConfigPath.FullName -Destination $finalConfigPath -Recurse -Force
                    Write-Host "Successfully downloaded and installed custom configuration profile from URL."
                    $customConfigDownloaded = $true
                }
                else {
                    # Assume the extracted folder IS the config
                    $finalConfigPath = Join-Path $configurationsPath $configProfile
                    Copy-Item -Path $tempExtractPath -Destination $finalConfigPath -Recurse -Force
                    Write-Host "Successfully downloaded and installed custom configuration profile from URL."
                    $customConfigDownloaded = $true
                }
            }
            catch {
                Write-Warning "Failed to download from URL: $_`nFalling back to Templates."
            }
        }
        else {
            Write-Warning "Unknown WDOTConfigSource value: $configSource. Expected 'AzureBlob', 'URL', or a valid URL. Falling back to Templates."
        }
    }
    
    # If custom config wasn't downloaded, create from Templates
    if (-not $customConfigDownloaded -and -not (Test-Path $configPath)) {
        Write-Host "Configuration Profile '$configProfile' not found. Attempting to create it..."
        
        # Save current location before changing
        $preConfigLocation = Get-Location
    
    # Check if Templates folder exists to use as a base
    if (Test-Path $templatesPath) {
        Write-Host "Found Templates folder. Creating new profile '$configProfile' from Templates..."
        
        # Check if New-WVDConfigurationFiles.ps1 exists
        if (Test-Path $newConfigScript) {
            try {
                # Create the new configuration profile using WDOT's built-in script
                Set-Location -Path $wdotScriptPath.FullName
                & $newConfigScript -FolderName $configProfile -ErrorAction Stop
                Write-Host "Successfully created configuration profile '$configProfile' from Templates."
            }
            catch {
                Write-Warning "Failed to create profile using New-WVDConfigurationFiles.ps1: $_"
                Write-Host "Attempting manual copy from Templates..."
                
                # Fallback: manually copy Templates folder
                $newConfigPath = Join-Path $configurationsPath $configProfile
                Copy-Item -Path $templatesPath -Destination $newConfigPath -Recurse -Force
                Write-Host "Successfully copied Templates to create profile '$configProfile'."
            }
            finally {
                # Restore location
                if ($preConfigLocation) {
                    Set-Location -Path $preConfigLocation.Path
                }
            }
        }
        else {
            # Fallback: manually copy Templates folder if script doesn't exist
            Write-Host "New-WVDConfigurationFiles.ps1 not found. Copying Templates folder directly..."
            $newConfigPath = Join-Path $configurationsPath $configProfile
            Copy-Item -Path $templatesPath -Destination $newConfigPath -Recurse -Force
            Write-Host "Successfully copied Templates to create profile '$configProfile'."
        }
        
        # Verify the profile was created
        if (-not (Test-Path $configPath)) {
            $availableProfiles = Get-ChildItem -Path $configurationsPath -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            Write-Error "Failed to create configuration profile '$configProfile'.`nAvailable Configuration Profiles: $($availableProfiles -join ', ')`nPlease ensure the Templates folder exists or specify an existing profile name."
            exit 1
        }
    }
    else {
        # No Templates folder available - list available profiles
        $availableProfiles = Get-ChildItem -Path $configurationsPath -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        if ($availableProfiles.Count -eq 0) {
            Write-Error "No configuration profiles found and Templates folder is missing.`nWDOT installation may be incomplete. Please check the WDOT repository."
        }
        else {
            Write-Error "Configuration Profile '$configProfile' not found and Templates folder is missing.`nAvailable Configuration Profiles: $($availableProfiles -join ', ')`nPlease update the WDOTConfigProfile inherited variable with a valid profile name, or ensure Templates folder exists."
        }
        exit 1
        }
    }
}

# Download and override individual JSON configuration files if specified
if (-not [string]::IsNullOrWhiteSpace($configFiles) -and (Test-Path $configPath)) {
    Write-Host "Processing individual configuration file overrides..."
    
    # Parse the config files variable (format: FileName.json=URL,FileName2.json=URL)
    $fileMappings = @{}
    $fileEntries = $configFiles -split ','
    
    foreach ($entry in $fileEntries) {
        $entry = $entry.Trim()
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        
        if ($entry -match '^(.+?\.(json|Json|JSON|xml|Xml|XML))\s*=\s*(.+)$') {
            $fileName = $matches[1].Trim()
            $fileUrl = $matches[3].Trim()
            $fileMappings[$fileName] = $fileUrl
            Write-Host "  Will override: $fileName from $fileUrl"
        }
        elseif ($entry -like "http*" -or $entry -like "\\*") {
            # If just a URL or UNC path, try to extract filename from path
            if ($entry -like "\\*") {
                # UNC path
                $fileName = [System.IO.Path]::GetFileName($entry)
            }
            else {
                # HTTP/HTTPS URL - remove query string
                $fileName = [System.IO.Path]::GetFileName($entry).Split('?')[0]
            }
            
            if ($fileName -match '\.(json|Json|JSON|xml|Xml|XML)$') {
                $fileMappings[$fileName] = $entry
                Write-Host "  Will override: $fileName from $entry"
            }
            else {
                Write-Warning "Could not determine filename from path: $entry. Skipping."
            }
        }
        else {
            Write-Warning "Invalid format for configuration file entry: $entry. Expected format: FileName.json=URL/UNC or just URL/UNC. Skipping."
        }
    }
    
    # Download and place each file
    foreach ($fileName in $fileMappings.Keys) {
        $fileUrl = $fileMappings[$fileName]
        $destinationPath = Join-Path $configPath $fileName
        
        try {
            Write-Host "Downloading $fileName from $fileUrl..."
            $tempFilePath = Join-Path $tempPath $fileName
            
            # Check if it's a UNC path (file share) or HTTP/HTTPS URL
            if ($fileUrl -like "\\*") {
                # UNC path - use Copy-Item
                Copy-Item -Path $fileUrl -Destination $tempFilePath -Force -ErrorAction Stop
            }
            else {
                # HTTP/HTTPS URL - use Invoke-WebRequest
                Invoke-WebRequest -Uri $fileUrl -OutFile $tempFilePath -ErrorAction Stop
            }
            
            # Validate it's a valid JSON/XML file
            if ($fileName -match '\.json$') {
                try {
                    $null = Get-Content $tempFilePath -Raw | ConvertFrom-Json
                    Write-Host "  Validated JSON structure for $fileName"
                }
                catch {
                    Write-Warning "  $fileName does not appear to be valid JSON. Proceeding anyway, but WDOT may fail."
                }
            }
            
            # Copy to configuration profile folder
            Copy-Item -Path $tempFilePath -Destination $destinationPath -Force
            Write-Host "  Successfully overrode $fileName in configuration profile."
        }
        catch {
            Write-Warning "Failed to download $fileName from $fileUrl : $_`nThe original file from the profile will be used instead."
        }
    }
    
    if ($fileMappings.Count -gt 0) {
        Write-Host "Completed processing $($fileMappings.Count) configuration file override(s)."
    }
}

# Build argument hashtable for splatting
$scriptParams = @{
    ConfigProfile = $configProfile
    Optimizations = $optArray
    AcceptEULA = $true
    Verbose = $true
}

# Add advanced optimizations if provided
if ($advOptArray.Count -gt 0) {
    $scriptParams['AdvancedOptimizations'] = $advOptArray
}

# Add restart flag if provided (exclude if blank, "No", or "None")
$restartTrimmed = $restart.Trim()
if (-not [string]::IsNullOrWhiteSpace($restartTrimmed) -and 
    $restartTrimmed -notmatch '^(?i)(No|None)$' -and 
    $restartTrimmed -ieq "-Restart") {
    $scriptParams['Restart'] = $true
}

# Save current location and change to WDOT script directory
# This is required because WDOT uses relative paths for configuration files
$originalLocation = Get-Location
try {
    Set-Location -Path $wdotScriptPath.FullName
    
    # Execute the script with splatting
    Write-Host "Executing Windows_Optimization.ps1 with parameters:"
    Write-Host "  ConfigProfile: $configProfile"
    Write-Host "  Optimizations: $($optArray -join ', ')"
    if ($advOptArray.Count -gt 0) {
        Write-Host "  AdvancedOptimizations: $($advOptArray -join ', ')"
    }
    if ($scriptParams.ContainsKey('Restart')) {
        Write-Host "  Restart: True"
    }
    Write-Host "  Working Directory: $($wdotScriptPath.FullName)"
    
    # Execute the script - suppress errors from WDOT's internal bugs
    try {
        & $fullScriptPath @scriptParams
    }
    catch {
        # WDOT script may have internal errors but still complete successfully
        # Log the error but don't fail the entire operation
        Write-Warning "WDOT script reported errors: $_"
        # Check if the error is just the known Set-Location/New-TimeSpan bug
        if ($_ -match "Set-Location|New-TimeSpan") {
            Write-Host "Note: This appears to be a known WDOT script cleanup issue and can be safely ignored."
        }
    }
}
finally {
    # Always restore the original location
    if ($originalLocation) {
        Set-Location -Path $originalLocation.Path
    }
}

# Cleanup
Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "WDOT optimization complete."

