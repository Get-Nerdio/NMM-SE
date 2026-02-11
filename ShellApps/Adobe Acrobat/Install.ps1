<#
.DESCRIPTION
    This script downloads the latest Adobe Acrobat Pro Unified Installer, extracts it, and installs it using Setup.exe with the specified arguments.
.WARNING: DO NOT OPEN ADOBE ACROBAT ON A GOLDEN IMAGE AFTER INSTALL
.PARAMETER downloadUrl
    The URL to download the Adobe Acrobat Pro Unified Installer ZIP file. Update this it may change.
.PARAMETER destinationPath
    The path where the ZIP file and extracted contents will be stored.
.PARAMETER transformFile
    The path to the MST file for customization.
.DIRECTIONS
    Create a transform file using the Adobe Customization Wizard https://www.adobe.com/devnet-docs/acrobatetk/tools/Wizard/index.html?msockid=3b342306c4ad6a4123a73693c5cf6b2c
    Upload the transform to the Shell App > Versions 
    Use at least one of the following Detection options in Shell App > Detection
    File: C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe (no version options selected)
    Registry Key: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AC76BA86-1033-FFFF-7760-BC15014EA700}
    Copy and paste the Install Script to the Shell App > Install
    Copy and paste the Uninstall Script to Shell App > Uninstall
#>
# Define variables
$downloadUrl = "https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip" # Update Path from Adobe if changed
$destinationPath = "C:\Temp\AdobeInstaller"
$zipFile = "$destinationPath\AcrobatInstaller.zip"
$extractPath = "$destinationPath\Extracted"
$transformFile = $Context.GetAttachedBinary()  # Retrieve the MST file from Nerdio Shell Apps
# Create directories
New-Item -ItemType Directory -Force -Path $destinationPath, $extractPath
# Download the installer ZIP
try {
    $Context.Log("Downloading Adobe Acrobat Pro Unified Installer...")
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile
    $Context.Log("Download completed successfully.")
} catch {
    $Context.Log("Error downloading the installer ZIP:")
    $Context.Log($_)
    throw $_
}
# Extract the ZIP
try {
    $Context.Log("Preparing to extract the installer ZIP...")
    if (-Not (Test-Path -Path $zipFile)) {
        throw "ZIP file not found at path: $zipFile"
    }
    $zipSize = (Get-Item $zipFile).Length / 1MB
    $Context.Log("ZIP file found. Size: {0:N2} MB" -f $zipSize)
    $Context.Log("Extracting the installer ZIP to: $extractPath")
    Expand-Archive -Path $zipFile -DestinationPath $extractPath -Force
    $Context.Log("Extraction completed successfully.")
    $Context.Log("Listing contents of extracted folder:")
    Get-ChildItem -Path $extractPath -Recurse | ForEach-Object {
        $Context.Log($_.FullName)
    }
} catch {
    $Context.Log("Error extracting the installer ZIP:")
    $Context.Log("Exception Message: " + $_.Exception.Message)
    $Context.Log("Stack Trace: " + $_.ScriptStackTrace)
    throw $_
}
# Run the silent install using Setup.exe
try {
    $Context.Log("Starting the silent installation using Setup.exe...")
    # Search recursively for Setup.exe in the extracted folder
    $setupPath = Get-ChildItem -Path $extractPath -Filter "Setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $setupPath) {
        throw "Setup.exe not found in extracted files."
    }
    $Context.Log("Found Setup.exe at: $($setupPath.FullName)")
    Start-Process -FilePath $setupPath.FullName -ArgumentList @(
        "/sAll",  # Silent mode for all users (no UI)
        "/rs",  # Suppresses reboot after installation
        "/rps",  # Suppresses reboot prompt
        "/msi TRANSFORMS=`"$transformFile`" ROAMIDENTITY=1 ROAMLICENSING=1",  # Passes additional parameters to the MSI installer
        "/norestart",  # Prevents automatic system restart
        "/quiet",  # Fully silent install (no prompts or UI)
        "EULA_ACCEPT=YES"  # Automatically accepts the license agreement
    ) -Wait
    $Context.Log("Installation completed successfully.")
} catch {
    $Context.Log("Error during installation:")
    $Context.Log($_)
    throw $_
}
# Optional: Clean up
try {
    $Context.Log("Cleaning up temporary files...")
    Remove-Item -Path $zipFile -Force
    $Context.Log("Cleanup completed successfully.")
} catch {
    $Context.Log("Error during cleanup:")
    $Context.Log($_)
    throw $_
}