#Requires -RunAsAdministrator
# Provisions Windows App (MSIX) for all users via DISM. Run in system/admin context.
# Optionally configures the app to run automatically when any user logs in.

param(
    # Set to $true to run the app automatically at user logon (all users). Default: $true.
    [bool]$RunAtLogon = $true
)

$Url = "https://go.microsoft.com/fwlink/?linkid=2262633"
$FullPath = "C:\Windows\Temp\WindowsApp.msix"
$RunKeyPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunKeyName = "Windows App"

try {
    # Ensure temp directory exists
    $tempDir = Split-Path -Parent $FullPath
    if (-not (Test-Path -LiteralPath $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    Write-Host "Downloading Windows App package..."
    Invoke-WebRequest -Uri $Url -OutFile $FullPath -UseBasicParsing -ErrorAction Stop

    # Capture packages before DISM so we can find the one we just added
    $packagesBefore = @((Get-AppxPackage -AllUsers).PackageFullName)

    Write-Host "Provisioning app for all users..."
    & DISM.exe /Online /Add-ProvisionedAppxPackage /PackagePath:"$FullPath" /SkipLicense /Region:all

    if ($LASTEXITCODE -ne 0) {
        Write-Error "DISM failed (exit code $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
    Write-Host "SUCCESS"

    if ($RunAtLogon) {
        $packagesAfter = (Get-AppxPackage -AllUsers).PackageFullName
        $newPkg = Compare-Object -ReferenceObject $packagesBefore -DifferenceObject $packagesAfter |
            Where-Object { $_.SideIndicator -eq '=>' } |
            Select-Object -First 1 -ExpandProperty InputObject

        if ($newPkg) {
            $pkg = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFullName -eq $newPkg }
            $manifestPath = Join-Path -Path $pkg.InstallLocation -ChildPath "AppxManifest.xml"
            if (Test-Path -LiteralPath $manifestPath) {
                [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
                $appId = ($manifest.Package.Applications.Application | Select-Object -First 1).Id
                $aumid = "$($pkg.PackageFamilyName)!$appId"
                Set-ItemProperty -Path $RunKeyPath -Name $RunKeyName -Value "explorer.exe shell:AppsFolder\$aumid" -Type String -Force
                Write-Host "Run at logon enabled for all users."
            } else {
                Write-Warning "Could not read app manifest; run at logon was not configured."
            }
        } else {
            Write-Warning "Could not detect newly installed package; run at logon was not configured."
        }
    }
} finally {
    if (Test-Path -LiteralPath $FullPath) {
        Remove-Item -LiteralPath $FullPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Done."
