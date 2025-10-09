# ShareFile Outlook Add-in Uninstallation Script
# This script uninstalls the ShareFile Outlook add-in

try {
    $Context.Log("INFO: Starting ShareFile Outlook add-in uninstallation")
    
    # Kill Outlook process if running
    try {
        $outlook = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
        if ($outlook) {
            $Context.Log("INFO: Outlook is running. Attempting to close it...")
            $outlook | Stop-Process -Force
            Start-Sleep -Seconds 5
            $Context.Log("INFO: Outlook process stopped.")
        } else {
            $Context.Log("INFO: Outlook is not running.")
        }
    } catch {
        $Context.Log("WARNING: Failed to check or kill Outlook: $($_.Exception.Message)")
    }

    # Find and uninstall ShareFile Outlook add-ins
    try {
        $installed = Get-CimInstance Win32_Product | Where-Object {
            $_.Name -like "*ShareFile Outlook*" -or 
            $_.Name -like "*Citrix Files for Outlook*" -or
            $_.Name -like "*ShareFile*" -and $_.Name -like "*Outlook*"
        }

        if ($installed) {
            foreach ($app in $installed) {
                $Context.Log("INFO: Uninstalling $($app.Name)...")
                $uninstallProcess = Start-Process msiexec.exe -ArgumentList "/x $($app.IdentifyingNumber) /qn /norestart" -Wait -PassThru
                
                if ($uninstallProcess.ExitCode -eq 0) {
                    $Context.Log("INFO: $($app.Name) uninstalled successfully.")
                } else {
                    $Context.Log("WARNING: Uninstall of $($app.Name) completed with exit code: $($uninstallProcess.ExitCode)")
                }
            }
        } else {
            $Context.Log("INFO: No ShareFile Outlook add-in found to uninstall.")
        }
    } catch {
        $Context.Log("ERROR: Uninstall failed: $($_.Exception.Message)")
        throw $_
    }

    $Context.Log("INFO: ShareFile Outlook add-in uninstallation completed.")
}
catch {
    $Context.Log("ERROR: ShareFile Outlook add-in uninstallation failed: $($_.Exception.Message)")
    throw $_
}
