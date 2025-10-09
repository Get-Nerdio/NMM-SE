# ShareFile Outlook Add-in Detection Script
# This script detects if the ShareFile Outlook add-in is installed

try {
    # Check for ShareFile Outlook add-in using Win32_Product
    $installedApps = Get-CimInstance Win32_Product | Where-Object {
        $_.Name -like "*ShareFile Outlook*" -or 
        $_.Name -like "*Citrix Files for Outlook*" -or
        $_.Name -like "*ShareFile*" -and $_.Name -like "*Outlook*"
    }

    if ($installedApps) {
        # Application is installed
        $Context.Log("INFO: ShareFile Outlook add-in detected - $($installedApps.Name)")
        exit 0  # Exit code 0 means application is detected/installed
    } else {
        # Application is not installed
        $Context.Log("INFO: ShareFile Outlook add-in not detected")
        exit 1  # Exit code 1 means application is not detected/not installed
    }
}
catch {
    $Context.Log("ERROR: Detection failed - $($_.Exception.Message)")
    exit 1  # Exit code 1 on error (assume not installed)
}
