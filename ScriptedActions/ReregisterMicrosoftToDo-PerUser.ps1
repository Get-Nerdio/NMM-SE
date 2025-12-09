<#
.SYNOPSIS
Re-registers the Microsoft ToDo AppX package and optionally creates a scheduled task for automatic execution at user logon.

.DESCRIPTION
This script provides two main functions:
1. Re-registers the Microsoft ToDo AppX package for the current user.
2. Creates a Windows scheduled task to automatically run the re-registration when users log on.

The re-registration process finds installed Microsoft ToDo AppX packages and attempts to force
a re-registration using the AppxManifest.xml file. This is useful for fixing issues where
the Microsoft ToDo app is missing, corrupted, or not starting correctly.

By default, the script creates a scheduled task that will run in each user's context at logon.
Use the -RunNow parameter to execute the re-registration immediately instead of creating a task.

.EXAMPLE
.\ReregisterMicrosoftToDo-PerUser.ps1
When run as SYSTEM: Creates a scheduled task for all users.
When run as regular user/admin: Immediately re-registers the Microsoft ToDo app.

.EXAMPLE
.\ReregisterMicrosoftToDo-PerUser.ps1 -CreateTask
Explicitly creates a scheduled task that will run at user logon.

.EXAMPLE
.\ReregisterMicrosoftToDo-PerUser.ps1 -RunNow
Immediately re-registers the Microsoft ToDo app (does not create a task).

.EXAMPLE
.\ReregisterMicrosoftToDo-PerUser.ps1 -RemoveTask
Removes the scheduled task if it exists.

.PARAMETER CreateTask
(Command-line argument) Explicitly creates a Windows scheduled task that will run the script at user logon.
When run as SYSTEM, the task is created for all users. When run as admin, it's created for the current user.

.PARAMETER RunNow
(Command-line argument) Immediately executes the re-registration without creating a scheduled task.
Use this to test the script or run it on-demand as the current user.

.PARAMETER RemoveTask
(Command-line argument) Removes the scheduled task created by this script.

.NOTES
Requires PowerShell 5.1 or later.

For scheduled task creation: Must be run with Administrator or SYSTEM privileges.
For immediate execution: Can be run by any user (re-registration runs in current user context).

When run as SYSTEM with no arguments: Automatically creates a scheduled task (ideal for host creation scenarios).
When run as regular user/admin with no arguments: Immediately executes the re-registration.
Use -RunNow to force immediate execution even when run as SYSTEM.

Use -Verbose for detailed output during execution.
#>

function Repair-MicrosoftToDo {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()

    Write-Verbose "Starting Microsoft ToDo AppX package re-registration."

    try {
        if ($PSCmdlet.ShouldProcess("Microsoft ToDo AppX Package", "Start re-registration process.")) {
            Write-Host "Searching for Microsoft ToDo AppX packages..." -ForegroundColor Cyan

            # Get all Microsoft ToDo packages (using wildcard to catch variations)
            $packages = Get-AppxPackage -AllUsers "*Microsoft.Todos*" -ErrorAction SilentlyContinue | 
                Where-Object { $null -ne $_.InstallLocation }

            if ($null -eq $packages -or $packages.Count -eq 0) {
                Write-Warning "No Microsoft ToDo packages found with InstallLocation. The app may not be installed."
                return
            }

            $total = ($packages | Measure-Object).Count
            $successCount = 0
            $errorCount = 0

            Write-Host "Found $($total) Microsoft ToDo package(s) to process." -ForegroundColor Green
            Write-Host "------------------------------------------------------------------------------------------------------------------"

            foreach ($package in $packages) {
                $manifestPath = Join-Path -Path $package.InstallLocation -ChildPath "AppxManifest.xml"
                $packageName = $package.Name

                Write-Verbose "Processing manifest: $($manifestPath)"
                Write-Host "Attempting to re-register: $($packageName)..." -ForegroundColor DarkGray

                if (-not (Test-Path $manifestPath)) {
                    Write-Warning "Manifest file not found at: $manifestPath"
                    $errorCount++
                    continue
                }

                try {
                    if ($PSCmdlet.ShouldProcess($packageName, "Register manifest at '$manifestPath'")) {
                        Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop
                        $successCount++
                        Write-Host "Successfully registered: $($packageName)" -ForegroundColor Green
                    }
                }
                catch {
                    $errorCount++
                    Write-Warning "ERROR re-registering $($packageName): $($_.Exception.Message)"
                }
            }

            Write-Host "------------------------------------------------------------------------------------------------------------------"
            Write-Host "Re-registration complete." -ForegroundColor Cyan
            Write-Host "Summary:" -ForegroundColor Cyan
            Write-Host "  Packages processed: $($total)" -ForegroundColor Cyan
            Write-Host "  Successful registrations: $($successCount)" -ForegroundColor Green
            Write-Host "  Errors encountered: $($errorCount)" -ForegroundColor Yellow

            if ($errorCount -gt 0) {
                Write-Host "Some errors are expected. Check the warnings above. If the Microsoft ToDo app is now available, the process worked." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Error "A critical error occurred during script execution: $($_.Exception.Message)"
    }
}

# --- Script Execution Logic ---
# This section determines what happens when the script is run directly.

# Check if script is being dot-sourced (imported) vs executed directly
$scriptIsBeingExecuted = $null -ne $MyInvocation.InvocationName -and $MyInvocation.InvocationName -ne '.'

if ($scriptIsBeingExecuted) {
    # Script is being executed directly (not dot-sourced)
    # Check for command-line parameters to determine execution mode
    
    # Check for -RunNow parameter (to run immediately)
    if ($args -contains '-RunNow' -or $args -contains '-Immediate') {
        Write-Host "Running Microsoft ToDo re-registration immediately..." -ForegroundColor Cyan
        Repair-MicrosoftToDo
        exit 0
    }
    # Check for -CreateTask parameter (to explicitly create scheduled task)
    elseif ($args -contains '-CreateTask') {
        Write-Host "Creating scheduled task..." -ForegroundColor Cyan
        New-ScheduledTaskForMicrosoftToDo
        exit 0
    }
    # Check for -RemoveTask parameter
    elseif ($args -contains '-RemoveTask') {
        Write-Host "Removing scheduled task..." -ForegroundColor Cyan
        Remove-ScheduledTaskForMicrosoftToDo
        exit 0
    }
    # Default behavior: 
    # - If running as SYSTEM, create scheduled task (common use case during host creation)
    # - Otherwise, run immediately
    else {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $isSystem = $currentIdentity.Name -eq "NT AUTHORITY\SYSTEM" -or $env:USERNAME -eq "SYSTEM"
        
        if ($isSystem) {
            Write-Host "Running as SYSTEM with no arguments - creating scheduled task..." -ForegroundColor Cyan
            New-ScheduledTaskForMicrosoftToDo
            exit 0
        }
        else {
            Write-Host "Running Microsoft ToDo re-registration immediately..." -ForegroundColor Cyan
            Repair-MicrosoftToDo
        }
    }
}

<#
.SYNOPSIS
Creates a scheduled task to run the Microsoft ToDo re-registration script at user logon.

.DESCRIPTION
This function creates a Windows scheduled task that will automatically run the
Repair-MicrosoftToDo function when a user logs on. The task runs in the user's context
and executes the script.

When run as SYSTEM (e.g., during host creation), the task will be created to run
for ANY user who logs on. When run as Administrator for a specific user, it will
create a task for that user only.

.PARAMETER TaskName
The name for the scheduled task. Defaults to "ReregisterMicrosoftToDo-PerUser".

.PARAMETER ScriptPath
The full path to this PowerShell script. If not provided, attempts to auto-detect
the script location.

.PARAMETER Force
If specified, removes any existing task with the same name before creating a new one.

.EXAMPLE
New-ScheduledTaskForMicrosoftToDo

Creates a scheduled task that runs Repair-MicrosoftToDo at user logon.

.EXAMPLE
New-ScheduledTaskForMicrosoftToDo -Force

Removes any existing task and creates a new one.
#>
function New-ScheduledTaskForMicrosoftToDo {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter()]
        [string]$TaskName = "ReregisterMicrosoftToDo-PerUser",

        [Parameter()]
        [string]$ScriptPath,

        [Parameter()]
        [switch]$Force
    )

    # Check if running as administrator or SYSTEM (required for scheduled task creation)
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $isSystem = $currentIdentity.Name -eq "NT AUTHORITY\SYSTEM" -or $env:USERNAME -eq "SYSTEM"
    
    if (-not $isAdmin -and -not $isSystem) {
        Write-Error "This function requires Administrator or SYSTEM privileges to create scheduled tasks. Please run PowerShell as Administrator or SYSTEM."
        return
    }

    # Auto-detect script path if not provided
    if ($null -eq $ScriptPath) {
        $ScriptPath = $PSCommandPath
        if ($null -eq $ScriptPath) {
            $ScriptPath = $MyInvocation.PSCommandPath
        }
        if ($null -eq $ScriptPath) {
            Write-Error "Unable to auto-detect script path. Please provide -ScriptPath parameter."
            return
        }
    }

    # Verify script exists
    if (-not (Test-Path $ScriptPath)) {
        Write-Error "Script file not found at: $ScriptPath"
        return
    }

    # Check if task already exists
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    if ($existingTask) {
        if ($Force) {
            Write-Host "Removing existing task: $TaskName" -ForegroundColor Yellow
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        else {
            Write-Warning "A scheduled task named '$TaskName' already exists. Use -Force to replace it, or choose a different task name."
            return
        }
    }

    # Build the PowerShell command
    $scriptDir = Split-Path -Parent $ScriptPath
    
    # Create the command arguments
    $commandArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    
    # Create action
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $commandArgs -WorkingDirectory $scriptDir

    # Create trigger (at user logon for any user)
    $trigger = New-ScheduledTaskTrigger -AtLogOn

    # Create principal - when run as SYSTEM, create task that runs in each user's context at logon
    # When run as admin for a specific user, use that user's context
    if ($isSystem) {
        # When run as SYSTEM, create task that runs for any user who logs on
        # Using "BUILTIN\Users" with Interactive logon type ensures the task runs
        # in the context of whichever user logs on (not as SYSTEM)
        Write-Host "Running as SYSTEM - creating task that will run in each user's context at logon..." -ForegroundColor Cyan
        $taskPrincipal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -LogonType Interactive -RunLevel Limited
    }
    else {
        # When run as admin, create task for the current user context
        Write-Host "Running as Administrator - creating task for user: $env:USERNAME" -ForegroundColor Cyan
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    }

    # Create settings
    # Hidden = false so users can see the task if needed
    # AllowStartIfOnBatteries = true so it runs on laptops
    # StartWhenAvailable = true so it runs even if the trigger time is missed
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false -Hidden:$false

    # Register the task
    try {
        $description = if ($isSystem) {
            "Re-registers Microsoft ToDo AppX package for any user at logon (created by SYSTEM)"
        }
        else {
            "Re-registers Microsoft ToDo AppX package for the current user at logon"
        }
        
        if ($PSCmdlet.ShouldProcess($TaskName, "Create scheduled task to run at user logon")) {
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Description $description | Out-Null
            
            Write-Host "Successfully created scheduled task: $TaskName" -ForegroundColor Green
            if ($isSystem) {
                Write-Host "The task will run when ANY user logs on, executing in that user's context." -ForegroundColor Cyan
                Write-Host "Task Principal: BUILTIN\Users (runs as the logging-on user)" -ForegroundColor Gray
            }
            else {
                Write-Host "The task will run when user '$env:USERNAME' logs on." -ForegroundColor Cyan
                Write-Host "Task Principal: $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
            }
            Write-Host "Task will execute: $commandArgs" -ForegroundColor Gray
            
            # Display task info
            $task = Get-ScheduledTask -TaskName $TaskName
            Write-Host "`nTask Status: $($task.State)" -ForegroundColor Cyan
            Write-Host "Task Run Level: $($task.Principal.RunLevel)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
        Write-Warning "If running as SYSTEM, ensure the script path is accessible to all users."
    }
}

<#
.SYNOPSIS
Removes the scheduled task created by New-ScheduledTaskForMicrosoftToDo.

.PARAMETER TaskName
The name of the scheduled task to remove. Defaults to "ReregisterMicrosoftToDo-PerUser".

.EXAMPLE
Remove-ScheduledTaskForMicrosoftToDo

Removes the default scheduled task.
#>
function Remove-ScheduledTaskForMicrosoftToDo {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter()]
        [string]$TaskName = "ReregisterMicrosoftToDo-PerUser"
    )

    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Error "This function requires Administrator privileges to remove scheduled tasks. Please run PowerShell as Administrator."
        return
    }

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    if (-not $existingTask) {
        Write-Warning "Scheduled task '$TaskName' not found."
        return
    }

    try {
        if ($PSCmdlet.ShouldProcess($TaskName, "Remove scheduled task")) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Successfully removed scheduled task: $TaskName" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to remove scheduled task: $($_.Exception.Message)"
    }
}
