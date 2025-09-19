#description: Updates the RDAgent on target VM
#tags: Nerdio, Preview

<#
Notes:

This scripted action is intended to be used with Nerdio's Auto-heal feature. It uninstalls
the RDAgent and all Remote Desktop related software, removes the VM from the host pool, downloads
and installs the most RDAgent and bootloader, and adds the host back to the host pool. Because
this process requires removing and re-adding the host to the host pool, this can take several 
minutes to complete. It is recommended that you allow Azure to update the RDAgent automatically
rather than to force the update, but for troubleshooting and host recovery, this script can be 
used to install the latest version of the RDAgent software.

This script is compatible with the ARM version of AVD (Spring 2020), and is not compatible with 
v1 (Fall 2019) Azure WVD.

#>

$ErrorActionPreference = 'Stop'

Write-output "Getting Host Pool Information"
$HostPool = Get-AzResource -ResourceId $HostpoolID
$HostPoolResourceGroupName = $HostPool.ResourceGroupName
$HostPoolName = $Hostpool.Name

$AvdAgentUrl = 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv'
$BootLoaderUrl = 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH'

$Script = @'
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Ensure download directory exists
$destDir = 'C:\Program Files\Microsoft RDInfra\'
if (-not (Test-Path -Path $destDir)) {
    New-Item -Path 'C:\Program Files' -Name 'Microsoft RDInfra' -ItemType Directory -Force | Out-Null
}

# Download Agent
Try {
    $req = Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv' -UseBasicParsing -Method Head -MaximumRedirection 5
    $filename = if ($req.Headers['Content-Disposition'] -match 'filename="?([^"]+)"?') { $matches[1] } else { [System.IO.Path]::GetFileName($req.BaseResponse.ResponseUri.AbsoluteUri) }
    $path = Join-Path $destDir $filename
    Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv' -UseBasicParsing -OutFile $path
}
Catch {
    Throw "Unable to download RD Agent from https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv. Error: $($_.Exception.Message)"
}

# Download BootLoader
Try {
    $req = Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH' -UseBasicParsing -Method Head -MaximumRedirection 5
    if ($req.Headers['Content-Disposition'] -match 'filename="?([^"]+)"?') {
        $blFilename = $matches[1]
    } else {
        $blFilename = [System.IO.Path]::GetFileName($req.BaseResponse.ResponseUri.AbsoluteUri)
    }
    $path = Join-Path $destDir $blFilename
    Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH' -UseBasicParsing -OutFile $path
}
Catch {
    Throw "Unable to download BootLoader from https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH. Error: $($_.Exception.Message)"
}
'@


$VM = get-azvm -VMName $azureVMName

$Script | Out-File ".\Download-Installers-$($vm.Name).ps1"

    # Execute local script on remote VM
write-output "Execute download script on remote VM"
$RunCommand = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName "$AzureVMName" -CommandId 'RunPowerShellScript' -ScriptPath ".\Download-Installers-$($vm.Name).ps1"

# Check for errors
$errors = $RunCommand.Value | Where-Object Code -eq 'ComponentStatus/StdErr/succeeded'
if ($errors.message) {
    Throw "Error when downloading installers. $($errors.message)"
}
Write-output "Output from RunCommand:"
$RunCommand.Value | Where-Object Code -eq 'ComponentStatus/StdOut/succeeded' | Select-Object message -ExpandProperty message

$Script = @"
`$tempFolder = [environment]::GetEnvironmentVariable('TEMP', 'Machine')
`$logsFolderName = "NMWLogs"
`$logsPath = "`$tempFolder\`$logsFolderName"
if (-not (Test-Path -Path `$logsPath)) {
    New-Item -Path `$tempFolder -Name `$logsFolderName -ItemType Directory -Force | Out-Null
}

`$wvdAppsLogsFolderName = "WVDApps"
`$wvdAppsLogsPath = "`$logsPath\`$wvdAppsLogsFolderName"
if (-not (Test-Path -Path `$wvdAppsLogsPath)) {
    New-Item -Path `$logsPath -Name `$wvdAppsLogsFolderName -ItemType Directory -Force | Out-Null
}

`$RDPrograms = get-wmiobject Win32_Product | where-Object Name -match 'Remote Desktop Services|Remote Desktop Agent Boot Loader' 
Write-Output "Uninstalling any previous versions of RD components on VM"
Foreach (`$RDProgram in `$RDPrograms) {
    Write-Output "Uninstalling `$(`$RDProgram.name) on VM."
    `$guid = `$RDProgram.identifyingnumber
    `$avd_uninstall_status = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `$guid", "/quiet", "/qn", "/norestart", "/passive", "/l* `$wvdAppsLogsPath\RDAgentUninstall.log" -Wait -Passthru
    `$sts = `$avd_uninstall_status.ExitCode
    Write-Output "Uninstalling `$(`$RDProgram.name) on VM Complete. Exit code=`$sts"
}
"@

$Script | Out-File ".\Uninstall-AVDAgent-$($vm.Name).ps1"

    # Execute local script on remote VM
write-output "Execute uninstall script on remote VM"
$RunCommand = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName "$AzureVMName" -CommandId 'RunPowerShellScript' -ScriptPath ".\Uninstall-AVDAgent-$($vm.Name).ps1"

#Check runcommand output for errors
$errors = $RunCommand.Value | Where-Object Code -eq 'ComponentStatus/StdErr/succeeded'
if ($errors.message) {
    Throw "Error when uninstalling software. $($errors.message)"
}
Write-output "Output from RunCommand:"
$RunCommand.Value | Where-Object Code -eq 'ComponentStatus/StdOut/succeeded' | Select-Object message -ExpandProperty message

write-output "Restarting VM after uninstall"
$vm | Restart-AzVM 

$SessionHost = Get-AzWvdSessionHost -HostPoolName $hostpoolname -ResourceGroupName $HostPoolResourceGroupName | Where-Object name -match $azureVMName
Remove-AzWvdSessionHost -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName -Name ($SessionHost.name -split '/')[1]
write-output "Removed session host from host pool"

$RegistrationKey = Get-AzWvdRegistrationInfo -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName
if (-not $RegistrationKey.Token) {
    # Generate New Registration Token
    Write-Output "Generate New Registration Token"
    $RegistrationKey = New-AzWvdRegistrationInfo -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName -ExpirationTime $((get-date).ToUniversalTime().AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ'))
}

$RegistrationToken = $RegistrationKey.token


$Script = @"
`$ErrorActionPreference = 'Stop'
`$tempFolder = [environment]::GetEnvironmentVariable('TEMP', 'Machine')
`$logsFolderName = "NMWLogs"
`$logsPath = "`$tempFolder\`$logsFolderName"
if (-not (Test-Path -Path `$logsPath)) {
    New-Item -Path `$tempFolder -Name `$logsFolderName -ItemType Directory -Force | Out-Null
}

`$wvdAppsLogsFolderName = "WVDApps"
`$wvdAppsLogsPath = "`$logsPath\`$wvdAppsLogsFolderName"
if (-not (Test-Path -Path `$wvdAppsLogsPath)) {
    New-Item -Path `$logsPath -Name `$wvdAppsLogsFolderName -ItemType Directory -Force | Out-Null
}

`$BootLoaderInstaller = (Get-ChildItem 'C:\Program Files\Microsoft RDInfra\' | ? name -Match 'Microsoft.RDInfra.RDAgentBootLoader.*\.msi' | sort lastwritetime -Descending | select -First 1).fullname
`$BlInstallerPath = '"' + `$BootLoaderInstaller + '"'

Write-Output "Installing RDAgent BootLoader on VM `$BlInstallerPath"

`$bootloader_deploy_status = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `$BlInstallerPath", "/quiet", "/qn", "/norestart", "/passive", "/l* `$wvdAppsLogsPath\AgentBootLoaderInstall.log" -Wait -Passthru
`$sts = `$bootloader_deploy_status.ExitCode
Write-Output "Installing RDAgentBootLoader on VM Complete. Exit code=`$sts"


`$AgentInstaller = (Get-ChildItem 'C:\Program Files\Microsoft RDInfra\' | ? name -Match 'Microsoft.RDInfra.RDAgent.Installer.*\.msi' | sort lastwritetime -Descending | select -First 1).fullname
`$InstallerPath = '"' + `$AgentInstaller + '"'

Write-Output "Installing RD Infra Agent on VM `$InstallerPath"

`$agent_deploy_status = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `$installerPath", "/quiet", "/qn", "/norestart", "/passive", "REGISTRATIONTOKEN=$RegistrationToken", "/l* `$wvdAppsLogsPath\RDInfraAgentInstall.log" -Wait -Passthru
`$sts = `$agent_deploy_status.ExitCode
Write-Output "Installing RD Infra Agent on VM Complete. Exit code=`$sts"
"@

$VM = get-azvm -VMName $azureVMName

$Script | Out-File ".\Upgrade-AVDAgent-$($vm.Name).ps1"

    # Execute local script on remote VM
write-output "Execute reinstall script on remote VM"
$RunCommand = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName "$AzureVMName" -CommandId 'RunPowerShellScript' -ScriptPath ".\Upgrade-AVDAgent-$($vm.Name).ps1"

#Check runcommand output for errors
$errors = $RunCommand.Value | Where-Object Code -eq 'ComponentStatus/StdErr/succeeded'
if ($errors.message) {
    Throw "Error when reinstalling RD components. $($errors.message)"
}
Write-output "Output from RunCommand:"
$RunCommand.Value | Where-Object Code -eq 'ComponentStatus/StdOut/succeeded' | Select-Object message -ExpandProperty message

write-output "Restarting VM after reinstall"
$vm | Restart-AzVM 

# re-assigning user
if ($SessionHost.assigneduser) {
    Update-AzWvdSessionHost -HostPoolName $hostpoolname -Name ($SessionHost.name -split '/')[1] -AssignedUser $SessionHost.AssignedUser -ResourceGroupName $HostPoolResourceGroupName
}
