<#
.SYNOPSIS
    Converts MSIX bundle files into CIM and VHDX images for use with AVD MSIX App Attach.

.DESCRIPTION
    This script processes MSIX or MSIXBundle files from a specified source folder,
    automatically identifies the application based on filename keywords,
    and uses `msixmgr.exe` to generate both .cim and .vhdx disk images.

    The images are organized into versioned subdirectories within the App Attach structure,
    ready for integration into Microsoft AVD (Azure Virtual Desktop) environments.

    This is useful for staging Microsoft Store apps for MSIX App Attach deployment.

.PARAMETER None
    All paths and app keyword mappings are hardcoded in the script. See customization notes below.

.NOTES
    - Requires administrator privileges to run (auto-elevates if needed).
    - Requires `msixmgr.exe` from the MSIX Toolkit:
        https://learn.microsoft.com/en-us/windows/msix/app-attach/app-attach-how-to
    - Assumes each MSIX bundle filename includes the app name and version using the format: AppName_<version>_x64.msixbundle
    - No external dependencies other than `msixmgr.exe` and PowerShell 5.1+

.CUSTOMIZATION
    - Modify `$msixSourceFolder` to point to where your downloaded `.msixbundle` files are stored.
    - Change `$appAttachRoot` if you want to output to a different base directory.
    - Adjust the `$packageKeywordMap` to add or refine app name matching based on filename patterns.
        - The keys are logical app names, and the values are arrays of keywords used to match filenames.

.EXAMPLE
    # Run the script to generate CIM and VHDX images for all MSIX bundles in the source folder:
    PS> .\Generate-AppAttachImages.ps1

#>


# Check if the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Warning "This script is not running as Administrator. Restarting with elevated privileges..."

    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Define fuzzy keyword map for app names
$packageKeywordMap = @{
    "SnippingTool" = @("SnippingTool", "ScreenSketch")
    "Calculator"   = @("Calculator")
    "Notepad"      = @("Notepad")
    "Camera"       = @("Camera", "CameraApp")
    "Terminal"     = @("CascadiaPackage")
    "Paint"        = @("Paint")
    "Clock"        = @("Clock", "Alarms","TimeUniversal")
    "StickyNotes"  = @("StickyNotes", "StickyNoteApp","App")
    "ClipChamp"    = @("ClipChamp")
    "Photos"       = @("Photos","Photos.App")
}

# Define paths
$msixSourceFolder = "C:\Installs\MSIXBundles"
$appAttachRoot = "C:\Installs\AVD App Attach"
$msixMgrPath = "$appAttachRoot\MSIXMgr\msixmgr.exe"

# Get MSIX files
$msixFiles = Get-ChildItem -Path $msixSourceFolder -Filter *.msixbundle

foreach ($file in $msixFiles) {
    Write-Host "`nProcessing file: $($file.Name)"

    $matchedApp = $null

    foreach ($appName in $packageKeywordMap.Keys) {
        foreach ($keyword in $packageKeywordMap[$appName]) {
            if ($file.Name -like "*$keyword*") {
                $matchedApp = $appName
                break
            }
        }
        if ($matchedApp) { break }
    }

    if (-not $matchedApp) {
        Write-Warning "Could not determine app name for file: $($file.Name). Skipping."
        continue
    }

    # Extract version: assume format AppName_<version>_x64.msix
    $parts = $file.BaseName.Split("_")
    if ($parts.Count -ge 2) {
        $version = $parts[1]
    } else {
        Write-Warning "Could not extract version from filename: $($file.Name). Skipping."
        continue
    }

    # Create versioned folder
    $versionedFolderName = "${matchedApp}_$version"
    $appFolder = Join-Path -Path "$appAttachRoot\AppAttach" -ChildPath $matchedApp
    $versionedAppFolder = Join-Path -Path $appFolder -ChildPath $versionedFolderName

    # Ensure directory exists
    if (-not (Test-Path -Path $versionedAppFolder)) {
        New-Item -ItemType Directory -Path $versionedAppFolder -Force | Out-Null
    }

    # Output paths
    $msixPath = $file.FullName
    $cimPath = Join-Path -Path $versionedAppFolder -ChildPath "$versionedFolderName.cim"
    $vhdxPath = Join-Path -Path $versionedAppFolder -ChildPath "$versionedFolderName.vhdx"

    # Run msixmgr to create CIM image
    & $msixMgrPath `
        -Unpack `
        -packagePath $msixPath `
        -destination $cimPath `
        -applyACLs `
        -create `
        -fileType cim `
        -rootDirectory apps

    # Run msixmgr to create VHDX image
    & $msixMgrPath `
        -Unpack `
        -packagePath $msixPath `
        -destination $vhdxPath `
        -applyACLs `
        -create `
        -fileType vhdx `
        -rootDirectory apps

    Write-Host "Finished processing $matchedApp $version"
}

Write-Host "`nAll MSIX packages processed."
