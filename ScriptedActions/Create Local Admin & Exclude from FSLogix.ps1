<#
Execution Mode: Individual
.Tags: Nerdio, FSLogix, LocalAdmin
.SYNOPSIS
    Creates a local administrator account and excludes it from FSLogix profile management.
.DESCRIPTION
    This script will create a local administrator account and exclude it from FSLogix profile management.
    Username and password will need to be stored as secure variables before running the script as LocalAdminUserName and LocalAdminUserPassword respectively.
    This script is intended for AVD session hosts which are using FSLogix for profile management and need a local admin account that is not managed by FSLogix.
.NOTES
    Date: 11/14/2025
    Version: 1.0
    Author: Nick Tria
#>

# Start Logging
$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = "Continue"
$vmtime = Get-Date
$logtime = $vmtime.ToUniversalTime()
New-Item -Path "C:\Windows\Temp\NerdioManagerLogs\ScriptedActions\CreateLocalAdminExcludeFSLogix" -ItemType Directory -ErrorAction SilentlyContinue -Force| Out-Null
$logfile = "C:\Windows\Temp\NerdioManagerLogs\ScriptedActions\CreateLocalAdminExcludeFSLogix\ps_log.txt"
Start-Transcript -Path $logfile -Append
Write-Verbose "########## Script Execution Started: $logtime ##########"

# Retreive secure variables
try {
    Write-Verbose "Retrieving secure variables..."
    $LocalAdminUserName = $SecureVars.LocalAdminUserName
    $LocalAdminUserPassword = $SecureVars.LocalAdminUserPassword
}
catch {
    Write-Verbose "Unable to retrieve secure variables. Exiting script."
}

# Create Local Admin User
try {  
    Write-Verbose "Creating local administrator account: $LocalAdminUserName"
    $securePassword = ConvertTo-SecureString $LocalAdminUserPassword -AsPlainText -Force
    New-LocalUser -Name $LocalAdminUserName -Password $securePassword -FullName "Local Administrator" -Description "Local Administrator Account Created by Scripted Action" -ErrorAction Stop
    Add-LocalGroupMember -Group "Administrators" -Member $LocalAdminUserName -ErrorAction Stop
    Write-Verbose "Local administrator account created successfully."
}
catch {
    Write-Verbose "Error creating local administrator account: $_"
}

# Check if FSLogix exclusion group exists and add user to it
try {
    $fslogixGroupName = "FSLogix Profile Exclude List"
    Write-Verbose "Checking for FSLogix exclusion group: $fslogixGroupName"
    $fslogixGroup = Get-LocalGroup -Name $fslogixGroupName -ErrorAction SilentlyContinue
    if ($null -ne $fslogixGroup) {
        Write-Verbose "FSLogix exclusion group found. Adding user to the group."
        Add-LocalGroupMember -Group $fslogixGroupName -Member $LocalAdminUserName -ErrorAction Stop
        Write-Verbose "User added to FSLogix exclusion group successfully."
    }
    else {
        Write-Verbose "FSLogix exclusion group not found. Skipping addition to group."
    }
}
catch {
    Write-Verbose "Error adding user to FSLogix exclusion group: $_"
}

# End Logging
$endvmtime = Get-Date
$endlogtime = $endvmtime.ToUniversalTime()
Write-Verbose "########## Script Execution Ended: $endlogtime ##########"
Stop-Transcript
$VerbosePreference = $SaveVerbosePreference