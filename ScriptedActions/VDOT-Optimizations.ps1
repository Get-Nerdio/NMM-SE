<#
.SYNOPSIS
    Runs the Virtual Desktop Optimization Tool (VDOT) from the VDOT GitHub (https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool) by utilizing Inherited Variables for the installer arguments that can be adjusted at the Account level in NMM.
    ***WARNING***
    This script just calls the latest version of the VDOT script.
    If there are any issues with the VDOT script itself, please create an issue in the Virtual Desktop Team GitHub repo.

.REQUIREMENTS
    The following Inherited Variables are required to be created at the MSP Level of Nerdio Manager for MSP
    The values listed are the recommended default actions.
    You can change these values at the Account Level. You can read more about the parameters HERE (https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool?tab=readme-ov-file#-optimizations-parameter-and-new--advancedoptimizations-parameters)

    Inherited Variables:
    VDOTopt = All
    VDOTadvopt = All
    VDOTrestart = -Restart

    NOTE: If you want to use different variable names, you will need to update lines 64-66 accordingly.

.EXECUTION MODE
    Individual or Individual with Restart
#>

# Define GitHub ZIP download URL
$vdotUrl = "https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/refs/heads/main.zip"

# Temp paths
$tempPath = "$env:SystemRoot\TEMP\VDOT"
$zipPath = "$tempPath\vdot.zip"
$extractPath = "$tempPath\Extracted"

# Create working directory
New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

# Download and unblock the ZIP
Write-Host "Downloading VDOT from GitHub..."
Invoke-WebRequest -Uri $vdotUrl -OutFile $zipPath -ErrorAction Stop
Unblock-File -Path $zipPath

# Extract contents
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Locate the script folder
$vdotScriptPath = Get-ChildItem -Path $extractPath -Directory |
    Where-Object { $_.Name -like "Virtual-Desktop-Optimization-Tool*" } |
    Select-Object -First 1

if (-not $vdotScriptPath) {
    Write-Error "Could not find extracted VDOT folder."
    exit 1
}

# Unblock all files in the folder
Get-ChildItem -Path $vdotScriptPath.FullName -Recurse | Unblock-File

# Set path to main script
$fullScriptPath = Join-Path $vdotScriptPath.FullName "Windows_VDOT.ps1"
if (-not (Test-Path $fullScriptPath)) {
    Write-Error "Windows_VDOT.ps1 not found."
    exit 1
}

# Inherited variables for script arguments
$opt = "$($InheritedVars.VDOTOpt)"
$advOpt = "$($InheritedVars.VDOTAdvOpt)"
$restart = "$($InheritedVars.VDOTRestart)"

# Validate required arguments
if ([string]::IsNullOrWhiteSpace($opt)) {
    Write-Error "Missing required variable: VDOT-Opt."
    exit 1
}

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Build full argument string
$arguments = @(
    "-Optimizations $opt"
    "-Verbose"
    "-AcceptEULA"
)

# Add advanced optimizations if provided (exclude if blank, "No", or "None")
$advOptTrimmed = $advOpt.Trim()
if (-not [string]::IsNullOrWhiteSpace($advOptTrimmed) -and 
    $advOptTrimmed -notmatch '^(?i)(No|None)$') {
    $arguments += "-AdvancedOptimizations $advOptTrimmed"
}

# Add restart flag if provided (exclude if blank, "No", or "None")
$restartTrimmed = $restart.Trim()
if (-not [string]::IsNullOrWhiteSpace($restartTrimmed) -and 
    $restartTrimmed -notmatch '^(?i)(No|None)$' -and 
    $restartTrimmed -ieq "-Restart") {
    $arguments += "-Restart"
}

# Build and run the final command
$command = "& `"$fullScriptPath`" $($arguments -join ' ')"
Write-Host "Executing: $command"
Invoke-Expression $command

# Cleanup
Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "VDOT optimization complete."
