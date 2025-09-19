#!/usr/bin/env pwsh

# Ensure we're in the correct directory
$moduleRoot = $PSScriptRoot

# Create necessary directories if they don't exist
$directories = @(
    'Config',
    'Reports',
    'Static'
)

foreach ($dir in $directories) {
    $path = Join-Path $moduleRoot $dir
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "Created directory: $path"
    }
}

# Import module with force to get latest changes
try {
    Write-Host "Importing module..."
    Import-Module $moduleRoot/MAUReport.psd1 -Force -Verbose -ErrorAction Stop
    Write-Host "Module imported successfully"
}
catch {
    Write-Error "Failed to import module: $_"
    Write-Host "Full error details: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}

# Set workspace ID and host pool name
$workspaceId = '177678ee-d784-44b9-bebc-0e144b4db4fd'
$hostPoolName = 'nerdio desktop win10'

# Generate report
try {
    Write-Host "Generating report..."
    Write-Host "Parameters:"
    Write-Host "  WorkspaceId: $workspaceId"
    Write-Host "  HostPoolName: $hostPoolName"
    
    $report = Get-MAUReport -WorkspaceId $workspaceId -HostPoolName $hostPoolName -Verbose -ErrorAction Stop
    
    # Get the report file path
    $reportDate = Get-Date -Format 'yyyyMMdd'
    $reportPath = Join-Path $moduleRoot "Reports/AVDUsageReport_$reportDate.html"
    
    if (Test-Path $reportPath) {
        Write-Host "Report generated successfully at: $reportPath"
        
        # Open the report based on the OS
        if ($IsMacOS) {
            Write-Host "Opening report with default browser..."
            Invoke-Expression "open '$reportPath'"
        }
        elseif ($IsWindows) {
            Write-Host "Opening report with default browser..."
            Invoke-Expression "start '$reportPath'"
        }
        else {
            Write-Host "Please open the report manually at: $reportPath"
        }
    }
    else {
        Write-Error "Report file not found at: $reportPath"
    }
}
catch {
    Write-Error "Error generating report: $_"
    Write-Host "Full error details: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
