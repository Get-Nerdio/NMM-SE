<#
.SYNOPSIS
    Installs all required MSIX and APPX dependency packages on the AVD Desktop Image VM to support MSIX App Attach applications.

.DESCRIPTION
    This script provisions all MSIX and APPX packages found in the specified `Dependencies` folder to the base Windows image.
    These dependency packages are necessary for MSIX App Attach apps to function properly once mounted on AVD session hosts.

    It is intended to be executed on the AVD Desktop Image VM after copying the `Dependencies` directory (usually from a build or packaging machine).

    Provisioning the dependencies at the image level ensures they are available to all users and prevents runtime issues with missing frameworks.

.PARAMETER None
    All paths are hardcoded. See customization notes below.

.NOTES
    - Must be run with administrator privileges (auto-elevates if not).
    - Only installs `.msix` and `.appx` files found under `C:\Installs\Dependencies` and subdirectories.
    - Uses `Add-AppxProvisionedPackage` to install dependencies system-wide.
    - All packages must be trusted and signed with a valid certificate (already installed on the image).
    - Do **not** use this script to install the App Attach application packages themselves — only their required runtime dependencies.

.CUSTOMIZATION
    - Modify `$sourceFolder` to match the location of your `Dependencies` folder.
    - Extend or restrict file types by changing the extension filter (`.msix`, `.appx`).
    - If needed, add logic to install supporting certificates before provisioning.

.EXAMPLE
    # After copying dependencies to the image:
    PS> .\Install-Dependencies.ps1

#>




# Check if the script is running with admin privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {

    # Relaunch the script as Administrator
    Start-Process PowerShell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Path to the folder where your MSIX and APPX packages are located
$sourceFolder = "C:\Installs\Dependencies"

# Get all .msix and .appx files in subfolders
$msixAppxFiles = Get-ChildItem -Path $sourceFolder -Recurse | Where-Object { $_.Extension -in ('.msix', '.appx') }

foreach ($file in $msixAppxFiles) {
    Write-Host "Provisioning package: $($file.FullName)"
    try {
        # You must provide the folder path, not the file path, for provisioning
        $packagePath = $file.DirectoryName
        $packageName = $file.FullName

        Add-AppxProvisionedPackage -Online -PackagePath $packageName -SkipLicense
        Write-Host "Successfully provisioned: $($file.Name)"
    } catch {
        Write-Warning "Failed to provision: $($file.Name) $packagePath - $($_.Exception.Message)"
    }
}
