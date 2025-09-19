<#
.SYNOPSIS
    Uninstalls any version of FSLogix that is installed.

.DESCRIPTION
    This script performs the following actions:
    1. Uninstalls existing FSlogix installations.

.EXECUTION MODE NMM
    Individual with Restart

.TAGS
    Nerdio, Apps Uninstall, FSLogix

.NOTES
    - Ensure that the script is run with appropriate privileges for software un-installation.

#>


# Define script variables


# Define the path to search
$searchPath = "C:\ProgramData\Package Cache"

# Define the file name to search for
$fileName = "FSLogixAppsSetup.exe"

# Use Get-ChildItem to search recursively
$foundFiles = Get-ChildItem -Path $searchPath -Recurse -Filter $fileName -ErrorAction SilentlyContinue

# Check if any files were found and perform uninstall
if ($foundFiles) {
    foreach ($file in $foundFiles) {
        Write-Host "Found: $($file.FullName)"
        
        try {
            # Start the uninstall process
            Start-Process -FilePath $file.FullName -ArgumentList "/uninstall /quiet /norestart" -Wait
            
            Write-Host "Successfully executed uninstall command for: $($file.FullName)"
        } catch {
            Write-Host "Failed to execute uninstall command for: $($file.FullName) - $_"
        }
    }
} else {
    Write-Host "No files found matching: $fileName"
}
