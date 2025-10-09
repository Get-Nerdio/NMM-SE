# ShareFile Outlook Add-in Installation Script
# This script installs the latest version of ShareFile Outlook add-in

try {
    # Define installer URL and paths
    $ShareFileInstallerUrl = "https://dl.sharefile.com/sfo-msi"
    $InstallerPath = "$env:TEMP\ShareFileOutlookPlugin.msi"
    
    $Context.Log("INFO: Starting ShareFile Outlook add-in installation")
    
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

    # Uninstall existing ShareFile Outlook add-ins first
    try {
        $installed = Get-CimInstance Win32_Product | Where-Object {
            $_.Name -like "*ShareFile Outlook*" -or $_.Name -like "*Citrix Files for Outlook*"
        }

        if ($installed) {
            foreach ($app in $installed) {
                $Context.Log("INFO: Uninstalling existing $($app.Name)...")
                Start-Process msiexec.exe -ArgumentList "/x $($app.IdentifyingNumber) /qn /norestart" -Wait
                $Context.Log("INFO: $($app.Name) uninstalled successfully.")
            }
        } else {
            $Context.Log("INFO: No existing ShareFile Outlook add-in found.")
        }
    } catch {
        $Context.Log("WARNING: Uninstall of existing version failed: $($_.Exception.Message)")
    }

    # Download and install new ShareFile Outlook add-in
    try {
        $Context.Log("INFO: Downloading ShareFile installer from $ShareFileInstallerUrl")
        Invoke-WebRequest -Uri $ShareFileInstallerUrl -OutFile $InstallerPath -UseBasicParsing
        $Context.Log("INFO: Download complete. Installing ShareFile Outlook add-in...")

        $installProcess = Start-Process msiexec.exe -ArgumentList "/i `"$InstallerPath`" /qn /norestart" -Wait -PassThru
        
        if ($installProcess.ExitCode -eq 0) {
            $Context.Log("INFO: ShareFile Outlook Add-in installed successfully.")
        } else {
            $Context.Log("ERROR: Installation failed with exit code: $($installProcess.ExitCode)")
            throw "Installation failed with exit code: $($installProcess.ExitCode)"
        }
    } catch {
        $Context.Log("ERROR: Installation failed: $($_.Exception.Message)")
        throw $_
    } finally {
        # Clean up installer file
        if (Test-Path $InstallerPath) {
            Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
            $Context.Log("INFO: Cleaned up installer file.")
        }
    }

    $Context.Log("INFO: ShareFile Outlook add-in installation completed successfully.")
}
catch {
    $Context.Log("ERROR: ShareFile Outlook add-in installation failed: $($_.Exception.Message)")
    throw $_
}
