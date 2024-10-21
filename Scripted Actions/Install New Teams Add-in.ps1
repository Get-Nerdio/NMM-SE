<#
This scripted action comes from the NMM Forums and was written by Nerdio's own Sam Airey.
See https://nmmhelp.getnerdio.com/hc/en-us/community/posts/28548687700109-Resolution-for-new-Teams-add-in-issues

It checks for the Teams Outlook Addin being available for all users.
It is recommended to have 
#>


# Confirming that the account that is running this script is an administrator
If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator') ){
    Write-Error "Need to run as administrator. Exiting.."
    exit 1
}

# Get Version of currently installed new Teams Package
if (-not ($NewTeamsPackageVersion = (Get-AppxPackage -Name MSTeams -AllUsers).Version)) {
    Write-Host "New Teams Package not found. Please install new Teams from https://aka.ms/GetTeams ."
    exit 1
}
Write-Host "Found new Teams Version: $NewTeamsPackageVersion"

# Get Teams Meeting Addin Version
$TMAPath = "{0}\WINDOWSAPPS\MSTEAMS_{1}_X64__8WEKYB3D8BBWE\MICROSOFTTEAMSMEETINGADDININSTALLER.MSI" -f $env:programfiles,$NewTeamsPackageVersion
if (-not ($TMAVersion = (Get-AppLockerFileInformation -Path $TMAPath | Select-Object -ExpandProperty Publisher).BinaryVersion))
{
    Write-Host "Teams Meeting Addin not found in $TMAPath."
    exit 1
}
Write-Host "Found Teams Meeting Addin Version: $TMAVersion"


# Install parameters
$TargetDir = "{0}\Microsoft\TeamsMeetingAddin\{1}\" -f ${env:ProgramFiles(x86)},$TMAVersion
$params = '/i "{0}" TARGETDIR="{1}" /qn ALLUSERS=1' -f $TMAPath, $TargetDir

# Start the install process
write-host "executing msiexec.exe $params"
Start-Process msiexec.exe -ArgumentList $params
write-host "Please confirm install result in Windows Eventlog"