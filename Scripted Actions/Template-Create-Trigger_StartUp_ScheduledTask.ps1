$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = 'continue'
$VMTime = Get-Date
$LogTime = $VMTime.ToUniversalTime()
$folderPath = "C:\MDM\Logs"
$LognameTXT = "RegisterTask.txt"
if (-not (Test-Path $folderPath)) {
    mkdir $folderPath -Force
    Write-Output "$folderPath has been created."
}
else {
    Write-Output "$folderPath already exists, continue script"
}
Start-Transcript -Path "C:\MDM\Logs\$($LognameTXT)" -Append -IncludeInvocationHeader
Write-Output "################# New Script Run #################"
Write-Output "Current time (UTC-0): $LogTime"

try {
    #Create the Scripts Folder

    if ((Test-Path -Path 'C:\Scripts') -eq $false) {
        New-Item -ItemType Directory -Path 'C:\Scripts' -Force 
    }

    #Create the Script from the string block, so basically you put your full Powershell script between the @' '@
    $newScriptPath = "C:\Scripts\StartupTask.ps1"
    $TaskScript = @'
# Put in your mount drive script here
Write-Output "This is a test script that runs at startup."
'@

    $TaskScript | Out-File -FilePath $newScriptPath -Force

    # Define the trigger
    #Syntax -> https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger?view=windowsserver2022-ps

    $triggerParams = @{
        AtStartup = $true
    }

    $trigger = New-ScheduledTaskTrigger @triggerParams

    # Define the action
    # Syntax -> https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskaction?view=windowsserver2022-ps
    $actionParams = @{
        Execute  = "PowerShell.exe"
        Argument = "-ExecutionPolicy Bypass -File `"$newScriptPath`""
    }

    $action = New-ScheduledTaskAction @actionParams

    # Define the principal
    # Syntax -> https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal?view=windowsserver2022-ps
    $principalParams = @{
        UserId    = "SYSTEM"
        LogonType = "ServiceAccount"
        RunLevel  = "Highest"
    }

    $principal = New-ScheduledTaskPrincipal @principalParams

    # Define the settings
    # Syntax -> https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=windowsserver2022-ps
    $settingsParams = @{
        AllowStartIfOnBatteries    = $true
        DontStopIfGoingOnBatteries = $true
        StartWhenAvailable         = $true
        RestartInterval            = (New-TimeSpan -Minutes 5)
        RestartCount               = 3
        MultipleInstances          = "IgnoreNew"
    }

    $settings = New-ScheduledTaskSettingsSet @settingsParams

    # Register the scheduled task
    # Syntax -> https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2022-ps
    $registerParams = @{
        TaskName    = "StartupTask"
        Trigger     = $trigger
        Action      = $action
        Principal   = $principal
        Settings    = $settings
        TaskPath    = '\'
        Description = "This is a scheduled task to run a PowerShell script at startup."
    }

    Register-ScheduledTask @registerParams

}
catch {
    $_.Exception.Message
}

Stop-Transcript
$VerbosePreference = $SaveVerbosePreference