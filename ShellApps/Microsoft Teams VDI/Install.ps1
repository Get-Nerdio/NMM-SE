# Microsoft Teams Installation Script
# This script installs the latest VDI-optimized version of Microsoft Teams
# Includes Teams, Teams Meeting Add-in for Outlook, and WebRTC component

[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [string] $TeamsInstallerUrl,
    [Parameter(Mandatory)]
    [string] $WebRTCInstallerUrl,
    [Parameter(Mandatory)]
    [string] $WebView2InstallerUrl
)

try {
    $Context.Log("INFO: Starting Microsoft Teams installation")
    
    # Install WebView2 Runtime if not present
    try {
        $WebView2RegPath1 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\'
        $WebView2RegPath2 = 'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\'
        
        if (!(Test-Path $WebView2RegPath1) -and !(Test-Path $WebView2RegPath2)) {
            $Context.Log("INFO: WebView2 not found, installing...")
            $WebView2Installer = "$env:TEMP\MicrosoftEdgeWebView2Setup.exe"
            
            Invoke-WebRequest -Uri $WebView2InstallerUrl -OutFile $WebView2Installer -UseBasicParsing
            Start-Process $WebView2Installer -ArgumentList '/silent /install' -Wait
            $Context.Log("INFO: WebView2 installation completed")
        } else {
            $Context.Log("INFO: WebView2 already installed")
        }
    }
    catch {
        $Context.Log("WARNING: WebView2 installation failed: $($_.Exception.Message)")
    }
    
    # Uninstall any previous versions of Teams (Per-user)
    try {
        $TeamsPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'Teams')
        $TeamsUpdateExePath = [System.IO.Path]::Combine($TeamsPath, 'Update.exe')
        
        if ([System.IO.File]::Exists($TeamsUpdateExePath)) {
            $Context.Log("INFO: Uninstalling per-user Teams installation")
            $proc = Start-Process $TeamsUpdateExePath -ArgumentList '-uninstall -s' -PassThru
            $proc.WaitForExit()
            $Context.Log("INFO: Per-user Teams uninstalled")
        } else {
            $Context.Log("INFO: No per-user Teams install found")
        }
        
        $Context.Log("INFO: Removing Teams directories (per-user)")
        Remove-Item -Path $TeamsPath -Recurse -ErrorAction SilentlyContinue
    }
    catch {
        $Context.Log("WARNING: Per-user Teams uninstall failed: $($_.Exception.Message)")
    }
    
    # Uninstall Teams (Per-Machine)
    try {
        $GetTeams = Get-CimInstance -ClassName Win32_Product | Where-Object { 
            $_.Name -like "Teams Machine-Wide*" -and $_.Vendor -eq "Microsoft Corporation" 
        }
        
        if ($null -ne $GetTeams.IdentifyingNumber) {
            $Context.Log("INFO: Uninstalling per-machine Teams installation")
            Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetTeams.IdentifyingNumber) /qn /norestart" -Wait
            $Context.Log("INFO: Per-machine Teams uninstalled")
        }
    }
    catch {
        $Context.Log("WARNING: Per-machine Teams uninstall failed: $($_.Exception.Message)")
    }
    
    # Uninstall Teams Meeting Add-in (Per-Machine)
    try {
        $GetTeamsAddin = Get-CimInstance -ClassName Win32_Product | Where-Object { 
            $_.Name -like "*Teams Meeting Add-in*" -and $_.Vendor -eq "Microsoft" 
        }
        
        if ($null -ne $GetTeamsAddin.IdentifyingNumber) {
            $Context.Log("INFO: Uninstalling Teams Meeting Add-in")
            Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetTeamsAddin.IdentifyingNumber) /qn /norestart" -Wait
            $Context.Log("INFO: Teams Meeting Add-in uninstalled")
        }
    }
    catch {
        $Context.Log("WARNING: Teams Meeting Add-in uninstall failed: $($_.Exception.Message)")
    }
    
    # Remove any AppX Teams packages
    try {
        $Apps = Get-AppxPackage -AllUsers | Where-Object { 
            $_.Name -like "*Teams*" -and $_.Publisher -like "*Microsoft Corporation*" 
        }
        foreach ($App in $Apps) {
            $Context.Log("INFO: Removing AppX Teams package: $($App.Name)")
            Remove-AppxPackage -Package $App.PackageFullName -AllUsers
        }
    }
    catch {
        $Context.Log("WARNING: AppX Teams removal failed: $($_.Exception.Message)")
    }
    
    # Uninstall WebRTC
    try {
        $GetWebRTC = Get-CimInstance -ClassName Win32_Product | Where-Object { 
            $_.Name -like "Remote Desktop WebRTC*" -and $_.Vendor -eq "Microsoft Corporation" 
        }
        
        if ($null -ne $GetWebRTC.IdentifyingNumber) {
            $Context.Log("INFO: Uninstalling WebRTC component")
            Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $($GetWebRTC.IdentifyingNumber) /qn /norestart" -Wait
            $Context.Log("INFO: WebRTC component uninstalled")
        }
    }
    catch {
        $Context.Log("WARNING: WebRTC uninstall failed: $($_.Exception.Message)")
    }
    
    # Install Teams and components
    try {
        # Create installation directory
        $InstallDir = 'C:\Windows\Temp\msteams_sa\install'
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        
        # Download and install Teams
        $Context.Log("INFO: Downloading MS Teams installer")
        Invoke-WebRequest -Uri $TeamsInstallerUrl -OutFile "$InstallDir\teamsbootstrapper.exe" -UseBasicParsing
        
        $Context.Log("INFO: Installing MS Teams with Teams Meeting Add-in")
        Start-Process "$InstallDir\teamsbootstrapper.exe" -ArgumentList '-p --installTMA' -Wait
        $Context.Log("INFO: MS Teams installation completed")
        
        # Set registry values for Teams VDI optimization
        $Context.Log("INFO: Setting Teams to WVD Environment mode")
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name IsWVDEnvironment -PropertyType DWORD -Value 1 -Force
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "disableAutoUpdate" -Value 1 -PropertyType DWord -Force
        $Context.Log("INFO: Teams VDI optimization enabled")
        
        # Download and install WebRTC
        $Context.Log("INFO: Downloading WebRTC installer")
        Invoke-WebRequest -Uri $WebRTCInstallerUrl -OutFile "$InstallDir\MsRdcWebRTCSvc_x64.msi" -UseBasicParsing
        
        $Context.Log("INFO: Installing WebRTC component")
        Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/i $InstallDir\MsRdcWebRTCSvc_x64.msi /log C:\Windows\temp\NerdioManagerLogs\WebRTC_install_log.txt /quiet /norestart" -Wait
        $Context.Log("INFO: WebRTC component installation completed")
        
        # Clean up installation files
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        $Context.Log("INFO: Installation files cleaned up")
        
    }
    catch {
        $Context.Log("ERROR: Teams installation failed: $($_.Exception.Message)")
        throw $_
    }
    
    $Context.Log("INFO: Microsoft Teams installation completed successfully")
    $Context.Log("INFO: Allow 5 minutes for Teams to appear in the Start Menu")
}
catch {
    $Context.Log("ERROR: Microsoft Teams installation failed: $($_.Exception.Message)")
    throw $_
}
