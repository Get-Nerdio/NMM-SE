#description: Reinstalls the RDAgent on target VM
#tags: Nerdio, Preview

<#
Notes:

This scripted action is intended to be used with Nerdio's Auto-heal feature. It uninstalls
the RDAgent, removes the VM from the host pool, reinstalls the RDAgent, and adds the host
back to the host pool. 

This script is compatible with the ARM version of AVD (Spring 2020), and is not compatible with 
v1 (Fall 2019) Azure WVD.

#>

Write-output "Getting Host Pool Information"
$HostPool = Get-AzResource -ResourceId $HostpoolID
$HostPoolResourceGroupName = $HostPool.ResourceGroupName
$HostPoolName = $Hostpool.Name

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

`$AgentGuids = get-wmiobject Win32_Product | where-Object Name -eq 'Remote Desktop Services Infrastructure Agent' | select identifyingnumber -ExpandProperty identifyingnumber
Write-Output "Uninstalling any previous versions of RD Agent on VM"
Foreach (`$guid in `$AgentGuids) {
    `$avd_uninstall_status = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `$guid", "/quiet", "/qn", "/norestart", "/passive", "/l* `$wvdAppsLogsPath\RDAgentUninstall.log" -Wait -Passthru
    `$sts = `$avd_uninstall_status.ExitCode
    Write-Output "Uninstalling AVD Agetnt on VM Complete. Exit code=`$sts"
    
}
"@

$VM = get-azvm -VMName $azureVMName

$Script | Out-File ".\Uninstall-AVDAgent-$($vm.Name).ps1"

    # Execute local script on remote VM
write-output "Execute uninstall script on remote VM"
$RunCommand = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName "$AzureVMName" -CommandId 'RunPowerShellScript' -ScriptPath ".\Uninstall-AVDAgent-$($vm.Name).ps1"

#Check for errors
$errors = $RunCommand.Value | ? Code -eq 'ComponentStatus/StdErr/succeeded'
if ($errors.message) {
    Throw "Error when uninstalling RD components. $($errors.message)"
}
Write-output "Output from RunCommand:"
$RunCommand.Value | ? Code -eq 'ComponentStatus/StdOut/succeeded' | select message -ExpandProperty message

write-output "Restarting VM after uninstall"
$vm | Restart-AzVM 

$SessionHost = Get-AzWvdSessionHost -HostPoolName $hostpoolname -ResourceGroupName $HostPoolResourceGroupName | ? name -match $azureVMName
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

`$AgentInstaller = (Get-ChildItem 'C:\Program Files\Microsoft RDInfra\' | ? name -Match Microsoft.RDInfra.RDAgent.Installer | sort lastwritetime -Descending | select -First 1).fullname
`$InstallerPath = '"' + `$AgentInstaller + '"'

Write-Output "Installing RD Infra Agent on VM `$InstallerPath"

`$agent_deploy_status = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `$installerPath", "/quiet", "/qn", "/norestart", "/passive", "REGISTRATIONTOKEN=$RegistrationToken", "/l* `$wvdAppsLogsPath\RDInfraAgentInstall.log" -Wait -Passthru
`$sts = `$agent_deploy_status.ExitCode
Write-Output "Installing RD Infra Agent on VM Complete. Exit code=`$sts"
`$Log = get-content `$wvdAppsLogsPath\RDInfraAgentInstall.log 
Write-output `$log
"@

$VM = get-azvm -VMName $azureVMName

$Script | Out-File ".\Reinstall-AVDAgent-$($vm.Name).ps1"

    # Execute local script on remote VM
write-output "Execute reinstall script on remote VM"
$RunCommand = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName "$AzureVMName" -CommandId 'RunPowerShellScript' -ScriptPath ".\Reinstall-AVDAgent-$($vm.Name).ps1"

#check for errors
$errors = $RunCommand.Value | ? Code -eq 'ComponentStatus/StdErr/succeeded'
if ($errors.message) {
    Throw "Error when reinstalling RD agent. $($errors.message)"
}
Write-output "Output from RunCommand:"
$RunCommand.Value | ? Code -eq 'ComponentStatus/StdOut/succeeded' | select message -ExpandProperty message

write-output "Restarting VM after reinstall"
$vm | Restart-AzVM 

# re-assigning user
if ($SessionHost.assigneduser) {
    Update-AzWvdSessionHost -HostPoolName $hostpoolname -Name ($SessionHost.name -split '/')[1] -AssignedUser $SessionHost.AssignedUser -ResourceGroupName $HostPoolResourceGroupName
}