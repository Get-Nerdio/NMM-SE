<#
.SYNOPSIS
    Runs the Windows Desktop Optimization Tool (WDOT) from the WDOT GitHub (https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool) by utilizing Inherited Variables for the installer arguments that can be adjusted at the Account level in NMM.
    ***WARNING***
    This script just calls the latest version of the WDOT script.
    If there are any issues with the WDOT script itself, please create an issue in the Virtual Desktop Team GitHub repo.

.REQUIREMENTS
    The following Inherited Variables are required to be created at the MSP Level of Nerdio Manager for MSP
    The values listed are the recommended default actions.
    You can change these values at the Account Level. You can read more about the parameters HERE (https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool?tab=readme-ov-file#-windows_optimizationps1---main-script)

    Inherited Variables:
    WDOTConfigProfile = Windows11_24H2 (or any valid config profile name)
    WDOTopt = All (or array like: Services,AppxPackages,ScheduledTasks)
    WDOTadvopt = (leave empty or specify: All,Edge,RemoveLegacyIE,RemoveOneDrive)
    WDOTrestart = -Restart (or leave empty to skip restart)

    NOTE: If you want to use different variable names, you will need to update lines 64-67 accordingly.

.EXECUTION MODE
    Individual or Individual with Restart
#>

# Define GitHub ZIP download URL
$wdotUrl = "https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool/archive/refs/heads/main.zip"

# Temp paths
$tempPath = "$env:SystemRoot\TEMP\WDOT"
$zipPath = "$tempPath\wdot.zip"
$extractPath = "$tempPath\Extracted"

# Create working directory
New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

# Download and unblock the ZIP
Write-Host "Downloading WDOT from GitHub..."
Invoke-WebRequest -Uri $wdotUrl -OutFile $zipPath -ErrorAction Stop
Unblock-File -Path $zipPath

# Extract contents
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Locate the script folder
$wdotScriptPath = Get-ChildItem -Path $extractPath -Directory |
    Where-Object { $_.Name -like "Windows-Desktop-Optimization-Tool*" } |
    Select-Object -First 1

if (-not $wdotScriptPath) {
    Write-Error "Could not find extracted WDOT folder."
    exit 1
}

# Unblock all files in the folder
Get-ChildItem -Path $wdotScriptPath.FullName -Recurse | Unblock-File

# Set path to main script
$fullScriptPath = Join-Path $wdotScriptPath.FullName "Windows_Optimization.ps1"
if (-not (Test-Path $fullScriptPath)) {
    Write-Error "Windows_Optimization.ps1 not found."
    exit 1
}

# Inherited variables for script arguments
$configProfile = "$($InheritedVars.WDOTConfigProfile)"
$opt = "$($InheritedVars.WDOTOpt)"
$advOpt = "$($InheritedVars.WDOTAdvOpt)"
$restart = "$($InheritedVars.WDOTRestart)"

# Validate required arguments
if ([string]::IsNullOrWhiteSpace($configProfile)) {
    Write-Error "Missing required variable: WDOTConfigProfile. This must specify a configuration profile name (e.g., Windows11_24H2)."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($opt)) {
    Write-Error "Missing required variable: WDOTOpt. This must specify optimizations (e.g., All or Services,AppxPackages)."
    exit 1
}

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Parse optimizations - handle comma-separated string or single value
$optArray = if ($opt -match ',') { 
    $opt -split ',' | ForEach-Object { $_.Trim() }
} else { 
    @($opt.Trim())
}

# Parse advanced optimizations if provided
$advOptArray = @()
if (-not [string]::IsNullOrWhiteSpace($advOpt)) {
    $advOptArray = if ($advOpt -match ',') { 
        $advOpt -split ',' | ForEach-Object { $_.Trim() }
    } else { 
        @($advOpt.Trim())
    }
}

# Build argument hashtable for splatting
$scriptParams = @{
    ConfigProfile = $configProfile
    Optimizations = $optArray
    AcceptEULA = $true
    Verbose = $true
}

# Add advanced optimizations if provided
if ($advOptArray.Count -gt 0) {
    $scriptParams['AdvancedOptimizations'] = $advOptArray
}

# Add restart flag if provided
if ($restart -and $restart -ieq "-Restart") {
    $scriptParams['Restart'] = $true
}

# Execute the script with splatting
Write-Host "Executing Windows_Optimization.ps1 with parameters:"
Write-Host "  ConfigProfile: $configProfile"
Write-Host "  Optimizations: $($optArray -join ', ')"
if ($advOptArray.Count -gt 0) {
    Write-Host "  AdvancedOptimizations: $($advOptArray -join ', ')"
}
if ($scriptParams.ContainsKey('Restart')) {
    Write-Host "  Restart: True"
}

& $fullScriptPath @scriptParams

# Cleanup
Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "WDOT optimization complete."
