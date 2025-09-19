# Get the directory where this script is located
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Script-level variables
$script:ModuleRoot = $PSScriptRoot
$script:ConfigPath = Join-Path $PSScriptRoot 'Config' 'config.json'
$script:TemplatePath = Join-Path $PSScriptRoot 'template.html'
$script:LogoPath = Join-Path $PSScriptRoot 'Static' 'NerrdioMSPLogo.png'
$script:ReportsPath = Join-Path $PSScriptRoot 'Reports'

# Create necessary directories if they don't exist
$directories = @(
    'Config',
    'Reports',
    'Static',
    'Public',
    'Private',
    'Queries'
)

foreach ($dir in $directories) {
    $path = Join-Path $PSScriptRoot $dir
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Verbose "Created directory: $path"
    }
}

# Get all script files
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)
$Config = @(Get-ChildItem -Path $PSScriptRoot\Config\*.ps1 -ErrorAction SilentlyContinue)
$Queries = @(Get-ChildItem -Path $PSScriptRoot\Queries\*.ps1 -ErrorAction SilentlyContinue)

# Dot source the files
foreach ($import in @($Private + $Config + $Queries + $Public)) {
    try {
        Write-Verbose "Importing $($import.FullName)"
        . $import.FullName
    }
    catch {
        Write-Error "Failed to import function $($import.FullName): $_"
        throw
    }
}

# Initialize module configuration
if (-not (Test-Path $script:ConfigPath)) {
    $defaultConfig = @{
        DefaultWorkspaceId = ''
        DefaultHostPoolName = ''
        ReportPath = $script:ReportsPath
        TemplatePath = $script:TemplatePath
        LogoPath = $script:LogoPath
    }
    
    # Create config directory if it doesn't exist
    $configDir = Split-Path $script:ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    # Save default config
    $defaultConfig | ConvertTo-Json | Out-File $script:ConfigPath -Force
}

# Export public functions
Export-ModuleMember -Function $Public.BaseName

# Export any aliases
Export-ModuleMember -Alias *

Write-Verbose "MAUReport module loaded successfully"
