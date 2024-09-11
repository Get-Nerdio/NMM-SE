<#
.SYNOPSIS
    Installs or updates the MS Teams client and enables Teams WVD Optimization mode.

.DESCRIPTION
    This script performs the following actions:
    1. Uninstalls New Outlook (if it is installed)
    2. Makes an install folder
    3. Downloads the latest version of New outlook
    4. Installes the downloaded version of New Outlook

.EXECUTION MODE NMM
    IndividualWithRestart

.TAGS
    Nerdio, Apps install, Outlook

.NOTES


#> 

#Uninstall New Outlook if it is installed
$Apps =  Get-AppxPackage -AllUsers | Where-Object {$_.Name -Like '*OutlookForWindows*'-and $_.Publisher -like "*Microsoft Corporation*" }
foreach ($App in $Apps) {
    Remove-AppxPackage -Package $App.PackageFullName
}


# make directories to hold new install
mkdir "C:\Windows\Temp\Outlook\install" -Force
 
# grab exe installer for Outlook
$DLink = "https://go.microsoft.com/fwlink/?linkid=2207851"
Invoke-WebRequest -Uri $DLink -OutFile "C:\Windows\Temp\outlook\install\setup.exe" -UseBasicParsing
 
# use installer to install Machine-Wide
Write-Host "INFO: Installing New Outlook"
Start-Process C:\Windows\Temp\Outlook\install\setup.exe -ArgumentList '--provision true --quiet --start-*'