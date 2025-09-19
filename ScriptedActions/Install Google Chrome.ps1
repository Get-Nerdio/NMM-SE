<#
    This script will download and install the latest version of Google Chrome at the machine wide scope.
#>

#Set Variables
$Path = $env:TEMP
$Installer = "chrome_installer.exe"

try {
    Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $Path\$Installer
    Start-Process -FilePath $Path\$Installer -Args "/silent /install" -Verb RunAs -Wait
}
catch {
    WriteOutput "Failed to download and install Chrome."
}
finally {
    if (Test-Path $Path\$Installer) {
        Remove-Item $Path\$Installer
    }
}