<#
.SYNOPSIS
Re-registers Microsoft Store (AppX) packages and optionally creates a scheduled task for automatic execution at user logon.

.DESCRIPTION
This script provides two main functions:
1. Re-registers all or specified native Microsoft Store (AppX) packages for the current user.
2. Creates a Windows scheduled task to automatically run the re-registration when users log on.

The re-registration process iterates through selected installed AppX packages and attempts to force
a re-registration using the AppxManifest.xml file. This is the standard method to fix issues where
default apps (like Calculator, Mail, Photos, etc.) are missing, corrupted, or not starting correctly.

When run as SYSTEM (e.g., during host creation), the script automatically creates a scheduled task
that will run in each user's context at logon. When run as a regular user or administrator, the
script executes the re-registration immediately unless the -CreateTask parameter is specified.

.EXAMPLE
.\ReregisterStoreApps-PerUser.ps1
When run as SYSTEM: Creates a scheduled task for all users.
When run as regular user/admin: Immediately re-registers all AppX packages.

.EXAMPLE
.\ReregisterStoreApps-PerUser.ps1 -AllPackages
Immediately re-registers all AppX packages (does not create a task).

.EXAMPLE
.\ReregisterStoreApps-PerUser.ps1 -AppNames "Microsoft.WindowsCalculator" "Microsoft.Windows.Photos"
Immediately re-registers only the specified AppX packages (does not create a task).

.EXAMPLE
.\ReregisterStoreApps-PerUser.ps1 -CreateTask
Explicitly creates a scheduled task that will run at user logon.

.EXAMPLE
.\ReregisterStoreApps-PerUser.ps1 -CreateTask -AppNames "Microsoft.WindowsCalculator"
Creates a scheduled task that will re-register only the specified apps at user logon.

.EXAMPLE
.\ReregisterStoreApps-PerUser.ps1 -RemoveTask
Removes the scheduled task if it exists.

.PARAMETER AppNames
(Command-line argument) An array of specific AppX package names to target (e.g., 'Microsoft.WindowsCalculator').
If provided, only these packages will be processed. Use this to run immediately without creating a task.

.PARAMETER AllPackages
(Command-line argument) A switch parameter that forces the script to iterate through and re-register
all non-system AppX packages for the current user. Use this to run immediately without creating a task.

.PARAMETER CreateTask
(Command-line argument) Creates a Windows scheduled task that will run the script at user logon.
When run as SYSTEM, the task is created for all users. When run as admin, it's created for the current user.

.PARAMETER RemoveTask
(Command-line argument) Removes the scheduled task created by this script.

.NOTES
Requires PowerShell 5.1 or later.

For scheduled task creation: Must be run with Administrator or SYSTEM privileges.
For immediate execution: Can be run by any user (re-registration runs in current user context).

When run as SYSTEM with no arguments: Automatically creates a scheduled task (ideal for host creation scenarios).
When run as regular user/admin with no arguments: Immediately executes the re-registration.

Use -Verbose for detailed output during execution.
#>

<#
function Repair-AppXPackages {
    [CmdletBinding(DefaultParameterSetName='AllPackages', SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='SpecificApps')]
        [string[]]$AppNames,

        [Parameter(Mandatory=$true, ParameterSetName='AllPackages')]
        [switch]$AllPackages
    )

    # Packages to exclude from the 'AllPackages' run to avoid common registration errors with core system components.
    $excludePackages = @(
        "Microsoft.Windows.Search",
        "Microsoft.Windows.ShellExperienceHost",
        "Microsoft.UI.Xaml",
        "Microsoft.VCLibs",
        "Microsoft.NET.Native"
    )

    Write-Verbose "Starting AppX package re-registration."

    try {
        if ($PSCmdlet.ShouldProcess("AppX Packages", "Start re-registration process.")) {

            # 1. Determine which packages to target
            if ($AllPackages) {
                Write-Host "Searching for all eligible AppX packages across all users..." -ForegroundColor Cyan
                # Get all installed AppX packages across all users
                $packages = Get-AppxPackage -AllUsers | Where-Object {
                    # Filter out exclusion list and ensure an InstallLocation exists
                    ($_.InstallLocation -ne $null) -and ($excludePackages -notcontains $_.Name)
                }
            }
            elseif ($AppNames) {
                Write-Host "Targeting specific AppX packages: $($AppNames -join ', ')" -ForegroundColor Cyan
                
                # Get only the packages specified by name
                $packages = Get-AppxPackage -AllUsers -Name $AppNames -ErrorAction SilentlyContinue | Where-Object {
                    $_.InstallLocation -ne $null
                }
                
                # Check for packages that were requested but not found (or had no install location)
                $foundNames = $packages.Name
                $missingNames = $AppNames | Where-Object { $foundNames -notcontains $_ }

                if ($missingNames.Count -gt 0) {
                    Write-Warning "The following requested packages were not found on the system or had no install location and will be skipped: $($missingNames -join ', ')"
                }
            }
            else {
                # This path should technically not be hit due to Mandatory parameters, but as a safeguard:
                throw "No packages specified. Use -AllPackages or provide package names with -AppNames."
            }

            $total = $packages.Count
            $successCount = 0
            $errorCount = 0

            Write-Host "Found $($total) packages to process." -ForegroundColor Green
            Write-Host "------------------------------------------------------------------------------------------------------------------"

            # 2. Iterate through each package and attempt to re-register it.
            foreach ($package in $packages) {
                $manifestPath = Join-Path -Path $package.InstallLocation -ChildPath "AppxManifest.xml"
                $packageName = $package.Name

                Write-Verbose "Processing manifest: $($manifestPath)"
                Write-Host "Attempting to re-register: $($packageName)..." -ForegroundColor DarkGray

                # The Add-AppxPackage command attempts to register the application manifest.
                # -DisableDevelopmentMode is required for this type of registration.
                # -ErrorAction Stop is used here to allow the catch block to handle errors gracefully.
                try {
                    if ($PSCmdlet.ShouldProcess($packageName, "Register manifest at '$manifestPath'")) {
                        Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop
                        $successCount++
                        Write-Host "Successfully registered: $($packageName)" -ForegroundColor Green
                    }
                }
                catch {
                    $errorCount++
                    # Use Write-Warning instead of Write-Host Red for better PowerShell integration
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
                Write-Host "Some errors are expected. Check the warnings above. If your missing apps are now available, the process worked." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Error "A critical error occurred during script execution: $($_.Exception.Message)"
    }
}
#>

function Repair-AppXPackages {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(ParameterSetName='SpecificApps')]
        [string[]]$AppNames,

        [Parameter(ParameterSetName='AllPackages')]
        [switch]$AllPackages,

        [Parameter()]
        [string[]]$Exclude
    )

    # Default exclusions (core system components that usually error if re-registered)
    $defaultExclude = @(
        "Microsoft.Windows.Search",
        "Microsoft.Windows.ShellExperienceHost",
        "Microsoft.UI.Xaml",
        "Microsoft.VCLibs",
        "Microsoft.NET.Native"
    )

    # Merge defaults with user-supplied exclusions (dedupe for safety)
    $excludePackages = @($defaultExclude + $Exclude) | Select-Object -Unique

    Write-Verbose "Starting AppX package re-registration."

    try {
        if ($PSCmdlet.ShouldProcess("AppX Packages", "Start re-registration process.")) {

            # 1. Determine which packages to target
            if ($AppNames) {
                Write-Host "Targeting specific AppX packages: $($AppNames -join ', ')" -ForegroundColor Cyan

                # Gather packages by iterating each name (fixes -Name expecting [string])
                $packages = foreach ($app in $AppNames) {
                    Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue |
                        Where-Object { $null -ne $_.InstallLocation }
                }

                $foundNames   = $packages.Name
                $missingNames = $AppNames | Where-Object { $foundNames -notcontains $_ }

                if ($missingNames.Count -gt 0) {
                    Write-Warning "The following requested packages were not found or had no install location: $($missingNames -join ', ')"
                }
            }
            else {
                # Default to AllPackages if nothing specified
                Write-Host "Searching for all eligible AppX packages across all users..." -ForegroundColor Cyan

                $packages = Get-AppxPackage -AllUsers | Where-Object {
                    ($null -ne $_.InstallLocation) -and ($excludePackages -notcontains $_.Name)
                }
            }

            # Apply exclusions again to the resolved set (helps when -AppNames includes an excluded item)
            $packages = $packages | Where-Object { $excludePackages -notcontains $_.Name }

            $total        = ($packages | Measure-Object).Count
            $successCount = 0
            $errorCount   = 0

            Write-Host "Found $($total) packages to process." -ForegroundColor Green
            Write-Host "------------------------------------------------------------------------------------------------------------------"

            foreach ($package in $packages) {
                $manifestPath = Join-Path -Path $package.InstallLocation -ChildPath "AppxManifest.xml"
                $packageName  = $package.Name

                Write-Verbose "Processing manifest: $($manifestPath)"
                Write-Host "Attempting to re-register: $($packageName)..." -ForegroundColor DarkGray

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
                Write-Host "Some errors are expected. Check the warnings above. If your missing apps are now available, the process worked." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Error "A critical error occurred during script execution: $($_.Exception.Message)"
    }
}

# --- Execution Examples (Commented Out) ---
# To run against all packages (original behavior):
# Repair-AppXPackages -AllPackages

# --- Script Execution Logic ---
# This section determines what happens when the script is run directly.
# If you want to create a scheduled task, use: New-ScheduledTaskForAppXRegistration

# Check if script is being dot-sourced (imported) vs executed directly
$scriptIsBeingExecuted = $null -ne $MyInvocation.InvocationName -and $MyInvocation.InvocationName -ne '.'

if ($scriptIsBeingExecuted) {
    # Script is being executed directly (not dot-sourced)
    # Check for command-line parameters to determine execution mode
    
    # Parse command-line arguments if provided
    $executionMode = $null
    $targetApps = @()
    
    # Check for -AllPackages switch
    if ($args -contains '-AllPackages' -or $args -contains '-All') {
        $executionMode = 'AllPackages'
    }
    # Check for -AppNames parameter
    elseif ($args -contains '-AppNames') {
        $executionMode = 'SpecificApps'
        $appNamesIndex = [array]::IndexOf($args, '-AppNames')
        if ($appNamesIndex -ge 0 -and ($appNamesIndex + 1) -lt $args.Count) {
            # Get all arguments after -AppNames until next parameter or end
            $targetApps = @()
            for ($i = $appNamesIndex + 1; $i -lt $args.Count; $i++) {
                if ($args[$i].StartsWith('-')) {
                    break
                }
                $targetApps += $args[$i]
            }
        }
    }
    # Check for -CreateTask parameter (to create scheduled task)
    elseif ($args -contains '-CreateTask') {
        Write-Host "Creating scheduled task..." -ForegroundColor Cyan
        New-ScheduledTaskForAppXRegistration
        exit 0
    }
    # Check for -RemoveTask parameter
    elseif ($args -contains '-RemoveTask') {
        Write-Host "Removing scheduled task..." -ForegroundColor Cyan
        Remove-ScheduledTaskForAppXRegistration
        exit 0
    }
    # Default behavior: 
    # - If running as SYSTEM, create scheduled task (common use case during host creation)
    # - Otherwise, run with AllPackages immediately
    else {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $isSystem = $currentIdentity.Name -eq "NT AUTHORITY\SYSTEM" -or $env:USERNAME -eq "SYSTEM"
        
        if ($isSystem) {
            Write-Host "Running as SYSTEM with no arguments - creating scheduled task..." -ForegroundColor Cyan
            New-ScheduledTaskForAppXRegistration
            exit 0
        }
        else {
            $executionMode = 'AllPackages'
        }
    }
    
    # Execute based on mode
    if ($executionMode -eq 'AllPackages') {
        Write-Host "Running AppX re-registration for all packages..." -ForegroundColor Cyan
        Repair-AppXPackages -AllPackages
    }
    elseif ($executionMode -eq 'SpecificApps' -and $targetApps.Count -gt 0) {
        Write-Host "Running AppX re-registration for specific apps: $($targetApps -join ', ')" -ForegroundColor Cyan
        Repair-AppXPackages -AppNames $targetApps
    }
    else {
        # Fallback: show usage
        Write-Host @"
Usage Examples:

To run immediately (without creating a task):
  .\ReregisterStoreApps-PerUser.ps1 -AllPackages
  .\ReregisterStoreApps-PerUser.ps1 -AppNames "Microsoft.WindowsCalculator" "Microsoft.Windows.Photos"

To create a scheduled task:
  .\ReregisterStoreApps-PerUser.ps1 -CreateTask
  .\ReregisterStoreApps-PerUser.ps1 -CreateTask -AppNames "Microsoft.WindowsCalculator"

To remove a scheduled task:
  .\ReregisterStoreApps-PerUser.ps1 -RemoveTask

Default behavior:
  - When run as SYSTEM with no arguments: Creates scheduled task
  - When run as regular user/admin with no arguments: Runs immediately with -AllPackages
"@ -ForegroundColor Yellow
        Repair-AppXPackages -AllPackages
    }
}

<#
.SYNOPSIS
Creates a scheduled task to run the AppX re-registration script at user logon.

.DESCRIPTION
This function creates a Windows scheduled task that will automatically run the
Repair-AppXPackages function when a user logs on. The task runs in the user's context
and executes the script with the specified parameters.

When run as SYSTEM (e.g., during host creation), the task will be created to run
for ANY user who logs on. When run as Administrator for a specific user, it will
create a task for that user only.

.PARAMETER TaskName
The name for the scheduled task. Defaults to "ReregisterStoreApps-PerUser".

.PARAMETER ScriptPath
The full path to this PowerShell script. If not provided, attempts to auto-detect
the script location.

.PARAMETER AppNames
Optional array of specific AppX package names to target when the task runs.
If not specified, the task will run with -AllPackages.

.PARAMETER Force
If specified, removes any existing task with the same name before creating a new one.

.EXAMPLE
New-ScheduledTaskForAppXRegistration

Creates a scheduled task that runs Repair-AppXPackages -AllPackages at user logon.

.EXAMPLE
New-ScheduledTaskForAppXRegistration -AppNames "Microsoft.WindowsCalculator", "Microsoft.Windows.Photos"

Creates a scheduled task that runs with specific app names at user logon.

.EXAMPLE
New-ScheduledTaskForAppXRegistration -Force

Removes any existing task and creates a new one.
#>
function New-ScheduledTaskForAppXRegistration {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter()]
        [string]$TaskName = "ReregisterStoreApps-PerUser",

        [Parameter()]
        [string]$ScriptPath,

        [Parameter()]
        [string[]]$AppNames,

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
    
    # Add parameters if AppNames are specified
    if ($AppNames -and $AppNames.Count -gt 0) {
        $appNamesString = ($AppNames | ForEach-Object { "`"$_`"" }) -join " "
        $commandArgs += " -AppNames $appNamesString"
    }
    else {
        # Default to AllPackages for scheduled task
        $commandArgs += " -AllPackages"
    }
    
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
            "Re-registers Microsoft Store AppX packages for any user at logon (created by SYSTEM)"
        }
        else {
            "Re-registers Microsoft Store AppX packages for the current user at logon"
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
Removes the scheduled task created by New-ScheduledTaskForAppXRegistration.

.PARAMETER TaskName
The name of the scheduled task to remove. Defaults to "ReregisterStoreApps-PerUser".

.EXAMPLE
Remove-ScheduledTaskForAppXRegistration

Removes the default scheduled task.
#>
function Remove-ScheduledTaskForAppXRegistration {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter()]
        [string]$TaskName = "ReregisterStoreApps-PerUser"
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