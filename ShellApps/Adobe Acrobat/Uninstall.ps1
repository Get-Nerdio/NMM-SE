#description: Uninstall Adobe Acrobat Pro using re-downloaded Setup.exe
# Define variables
$downloadUrl = "https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip"
$destinationPath = "$env:TEMP\AdobeUninstall"
$zipFile = "$destinationPath\AcrobatInstaller.zip"
$extractPath = "$destinationPath\Extracted"
$acrobatPath = "C:\Program Files\Adobe\Acrobat DC"
$uninstallLog = "$env:TEMP\AdobeUninstall.log"
# Function to log messages
function Show-LogMessage {
    param ([string]$message)
    $Context.Log($message)
    Add-Content -Path $uninstallLog -Value $message
}
# Function to download and extract Setup.exe
function Set-Uninstaller {
    try {
        Show-LogMessage "Creating temp directories..."
        New-Item -ItemType Directory -Force -Path $destinationPath, $extractPath | Out-Null
        Show-LogMessage "Downloading Adobe Acrobat installer ZIP..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile
        Show-LogMessage "Download complete."
        Show-LogMessage "Extracting ZIP..."
        Expand-Archive -Path $zipFile -DestinationPath $extractPath -Force
        Show-LogMessage "Extraction complete."
        $setupPath = Get-ChildItem -Path $extractPath -Filter "Setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $setupPath) {
            throw "Setup.exe not found in extracted files."
        }
        return $setupPath.FullName
    } catch {
        Show-LogMessage "Error preparing uninstaller: $_"
        throw $_
    }
}
# Function to uninstall Adobe Acrobat
function Uninstall-Adobe {
    Show-LogMessage "Starting Adobe Acrobat Pro uninstallation..."
    try {
        $setupExe = Set-Uninstaller
        Show-LogMessage "Running Setup.exe with uninstall arguments..."
        Start-Process -Wait -NoNewWindow -FilePath $setupExe -ArgumentList "/sALL", "/remove=ALL", "/quiet", "/norestart"
        # Remove leftover files
        if (Test-Path $acrobatPath) {
            Show-LogMessage "Removing leftover Acrobat files..."
            Remove-Item -Path $acrobatPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Show-LogMessage "Adobe Acrobat Pro uninstallation complete."
    } catch {
        Show-LogMessage "Error during uninstallation: $_"
        throw $_
    } finally {
        Show-LogMessage "Cleaning up temporary files..."
        Remove-Item -Path $destinationPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $uninstallLog -Force -ErrorAction SilentlyContinue
    }
}
# Main execution
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
Uninstall-Adobe