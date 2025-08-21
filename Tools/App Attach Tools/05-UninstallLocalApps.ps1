<#
.SYNOPSIS
    Removes preinstalled (built-in) Windows Store apps from the AVD Desktop Image to prepare for MSIX App Attach deployment.

.DESCRIPTION
    This script scans the system for preinstalled Microsoft Store apps (e.g., Notepad, Paint, Photos, Snipping Tool)
    and removes them from the base image for all users using `Remove-AppxPackage -AllUsers`.

    This ensures that these built-in app versions do not conflict with the MSIX App Attach versions that will be mounted during AVD sessions.

    Only apps explicitly listed in the `$appIdentifiers` array are targeted, and others can be enabled or commented out as needed.

.PARAMETER None
    All app identifiers are hardcoded in the `$appIdentifiers` array. See customization below.

.NOTES
    - Must be run as Administrator.
    - Intended for use during AVD Desktop Image preparation, prior to sealing or capturing the image.
    - Safe to run multiple times — if an app is not found, it will simply be skipped.
    - Removing built-in apps is necessary to avoid duplication and user confusion when App Attach versions are used.
    - This does **not** affect MSIX App Attach packages — it only removes existing built-in versions.

.CUSTOMIZATION
    - Uncomment or add entries in the `$appIdentifiers` array to control which built-in apps are removed.
    - Each identifier is a partial or full name of the app package (e.g., `Microsoft.WindowsNotepad`).
    - You can add other apps (e.g., Calculator, Camera) by uncommenting lines or adding new ones.

.EXAMPLE
    # To remove built-in apps and make way for MSIX App Attach:
    PS> .\Remove-BuiltInApps.ps1

#>



# List of built-in app identifiers to remove (from built-in versions)
$appIdentifiers = @(
    "Microsoft.ScreenSketch",      # Snipping Tool
    #"Microsoft.WindowsCalculator", # Calculator
    "Microsoft.WindowsNotepad",    # Notepad
    #"Microsoft.WindowsCamera",     # Camera
    "Microsoft.Paint",             # Paint
    #"Microsoft.WindowsAlarms",     # Clock
    #"Microsoft.MicrosoftStickyNotes", # Sticky Notes
    #"Microsoft.Todos",             # ToDos
    "Clipchamp.Clipchamp",         # ClipChamp
    "Microsoft.Windows.Photos",    # Photos
    "Microsoft.WindowsTerminal"    # Terminal
)

Write-Host "Starting removal of built-in Windows apps..."

foreach ($appId in $appIdentifiers) {
    Write-Host "`nChecking for: $appId"

    # Get packages for all users
    $packages = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*$appId*" }

    if ($packages) {
        foreach ($pkg in $packages) {
            try {
                Write-Host "Removing package: $($pkg.Name) for user: $($pkg.UserSid)"
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers
                Write-Host "Removed: $($pkg.PackageFullName)"
            } catch {
                Write-Warning "Failed to remove $($pkg.PackageFullName): $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "No installed packages found for $appId"
    }
}

Write-Host "`nAll matching built-in packages processed."
