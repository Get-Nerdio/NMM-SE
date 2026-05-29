#Requires -RunAsAdministrator
<#+
.SYNOPSIS
Downloads the offline Windows Calculator installer and provisions it for all users.
.DESCRIPTION
This script detects whether Windows Calculator is already installed for any user. If it is not present, it downloads the offline MSIX bundle using winget and provisions it into the online Windows image so it becomes available for all users.
.NOTES
Run this script in an elevated PowerShell session.
#>

[CmdletBinding()]
param()

function Get-CalculatorInstalled {
    try {
        return [bool](Get-AppxPackage -AllUsers -Name Microsoft.WindowsCalculator -ErrorAction SilentlyContinue)
    } catch {
        return $false
    }
}

function Download-CalculatorOfflineInstaller {
    param(
        [string]$DownloadFolder = (Join-Path -Path $env:TEMP -ChildPath 'CalculatorOfflineInstaller')
    )

    Write-Host "Preparing offline installer download folder: $DownloadFolder"
    if (-not (Test-Path -LiteralPath $DownloadFolder)) {
        New-Item -ItemType Directory -Path $DownloadFolder -Force | Out-Null
    }

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'winget.exe is required to download the Calculator offline package. Install App Installer / winget and rerun this script.'
    }

    $packageId = 'Microsoft.WindowsCalculator'
    $downloadArgs = @(
        'download',
        '--id', $packageId,
        '--source', 'msstore',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--output', $DownloadFolder
    )

    Write-Host "Downloading Windows Calculator package with winget..."
    $process = Start-Process -FilePath 'winget.exe' -ArgumentList $downloadArgs -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "winget download failed with exit code $($process.ExitCode)."
    }

    $packageFile = Get-ChildItem -Path $DownloadFolder -Filter '*.msix*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $packageFile) {
        throw "No Calculator MSIX bundle was found in $DownloadFolder after winget download."
    }

    Write-Host "Downloaded installer to: $($packageFile.FullName)"
    return $packageFile.FullName
}

function Install-CalculatorForAllUsers {
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath
    )

    if (-not (Test-Path -LiteralPath $PackagePath)) {
        throw "Package path '$PackagePath' does not exist."
    }

    Write-Host "Provisioning Calculator for all users using DISM..."
    $dismArgs = @(
        '/Online',
        '/Add-ProvisionedAppxPackage',
        "/PackagePath:$PackagePath",
        '/SkipLicense',
        '/Region:all'
    )

    $process = Start-Process -FilePath 'DISM.exe' -ArgumentList $dismArgs -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "DISM failed with exit code $($process.ExitCode)."
    }

    Write-Host 'Calculator has been provisioned for all users.'
}

function Invoke-RepairCalculator {
    $installerFolder = Join-Path -Path $env:TEMP -ChildPath 'CalculatorOfflineInstaller'
    $installerPath = $null

    if (Get-CalculatorInstalled) {
        Write-Host 'Windows Calculator is already installed for at least one user. No action is required.'
        return
    }

    try {
        $installerPath = Download-CalculatorOfflineInstaller -DownloadFolder $installerFolder
        Install-CalculatorForAllUsers -PackagePath $installerPath

        if (Get-CalculatorInstalled) {
            Write-Host 'Windows Calculator is now installed for all users.'
        } else {
            Write-Warning 'Calculator provisioning completed, but the package was not detected after installation.'
        }
    } catch {
        Write-Error "Repair failed: $($_.Exception.Message)"
        throw
    } finally {
        if ($installerPath -and (Test-Path -LiteralPath $installerPath)) {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $installerFolder) {
            Remove-Item -LiteralPath $installerFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-RepairCalculator
