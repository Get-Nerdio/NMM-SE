# Microsoft OneDrive per Machine Detection Script
# This script always triggers a reinstall to ensure the latest version is installed

try {
    # Always return exit code 1 to trigger installation/reinstallation
    # This ensures we always get the latest version of OneDrive
    $Context.Log("INFO: Always reinstalling OneDrive to ensure latest version")
    exit 1  # Exit code 1 means application needs to be installed/updated
}
catch {
    $Context.Log("ERROR: Detection failed - $($_.Exception.Message)")
    exit 1  # Exit code 1 on error (assume needs installation)
}
