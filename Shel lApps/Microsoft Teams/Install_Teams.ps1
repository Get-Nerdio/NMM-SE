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
    # Check if WebView2 is already installed
    $WebView2RegPath1 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\'
    $WebView2RegPath2 = 'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\'
    
    if (!(Test-Path $WebView2RegPath1) -and !(Test-Path $WebView2RegPath2)) {
        $Context.Log('INFO: WebView2 not found, installing...')
        $WebView2Installer = "$env:TEMP\MicrosoftEdgeWebView2Setup.exe"
        #$WebView2InstallerUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
        
        Invoke-WebRequest -Uri $WebView2InstallerUrl -OutFile $WebView2Installer -UseBasicParsing
        Start-Process $WebView2Installer -ArgumentList '/silent /install' -Wait
    }

    # Adjust registry for Teams VDI optimization
    $Context.Log('INFO: Setting Teams to WVD Environment mode')
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" -Value 1 -Force

    # Uninstall previous versions of Teams (Per-user)
    $TeamsPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'Teams')
    $TeamsUpdateExePath = [System.IO.Path]::Combine($TeamsPath, 'Update.exe')
    
    if ([System.IO.File]::Exists($TeamsUpdateExePath)) {
        $Context.Log('INFO: Uninstalling per-user Teams installation')
        Start-Process $TeamsUpdateExePath -ArgumentList "-uninstall -s" -Wait
    }
    else {
        $Context.Log('INFO: No per-user Teams install found.')
    }

    $Context.Log('INFO: Removing Teams directories (per-user)')
    Remove-Item -Path $TeamsPath -Recurse -ErrorAction SilentlyContinue

    # Uninstall Teams (Per-Machine)
    $GetTeams = Get-CimInstance -ClassName Win32_Product | Where-Object IdentifyingNumber -Match "{731F6BAA-A986-45A4-8936-7C3AAAAA760B}"
    if ($GetTeams) {
        $Context.Log('INFO: Uninstalling per-machine Teams installation')
        Start-Process "msiexec.exe" -ArgumentList '/x "{731F6BAA-A986-45A4-8936-7C3AAAAA760B}" /qn /norestart' -Wait
    }

    # Uninstall WebRTC
    $GetWebRTC = Get-CimInstance -ClassName Win32_Product | Where-Object Name -Like "*webrtc*"
    if ($GetWebRTC) {
        $Context.Log('INFO: Uninstalling WebRTC installation')
        Start-Process "msiexec.exe" -ArgumentList "/x $($GetWebRTC.IdentifyingNumber) /qn /norestart" -Wait
    }

    # Download and install the latest Teams and WebRTC
    $InstallDir = "$env:TEMP\msteams_sa\install"
    #$TeamsInstallerUrl = "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409"
    #$WebRTCInstallerUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RW1jLHP"

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    $Context.Log('INFO: Downloading MS Teams installer')
    Invoke-WebRequest -Uri $TeamsInstallerUrl -OutFile "$InstallDir\teamsbootstrapper.exe" -UseBasicParsing
    
    $Context.Log('INFO: Installing MS Teams')
    Start-Process "$InstallDir\teamsbootstrapper.exe" -ArgumentList '-p' -Wait
    
    $Context.Log('INFO: Downloading WebRTC installer')
    Invoke-WebRequest -Uri $WebRTCInstallerUrl -OutFile "$InstallDir\MsRdcWebRTCSvc_x64.msi" -UseBasicParsing

    $Context.Log('INFO: Installing WebRTC component')
    Start-Process "msiexec.exe" -ArgumentList "/i $InstallDir\MsRdcWebRTCSvc_x64.msi /l*v $env:TEMP\WebRTC_install_log.txt /qn /norestart" -Wait

    $Context.Log('INFO: Finished running installers. Check $env:TEMP\msteams_sa for logs on the MSI installations.')
    $Context.Log('INFO: All Commands Executed; script is now finished. Allow 5 minutes for Teams to appear.')
}
catch {
    $Context.Log("ERROR: $($_.Exception.Message)")
    throw $_
}
