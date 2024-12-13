# Function to get configuration value
function Get-MAUReportConfigValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    
    try {
        if (-not (Test-Path $script:ConfigPath)) {
            throw "Configuration file not found at: $script:ConfigPath"
        }
        
        $config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
        
        if (-not (Get-Member -InputObject $config -Name $Key)) {
            throw "Configuration key '$Key' not found"
        }
        
        return $config.$Key
    }
    catch {
        Write-Error "Error getting configuration value for '$Key': $_"
        return $null
    }
}

# Function to set configuration value
function Set-MAUReportConfigValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter(Mandatory = $true)]
        [object]$Value
    )
    
    try {
        # Create config file if it doesn't exist
        if (-not (Test-Path $script:ConfigPath)) {
            $config = @{}
        }
        else {
            $config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            # Convert from PSCustomObject to hashtable
            $config = @{} + $config
        }
        
        # Update or add the key-value pair
        $config[$Key] = $Value
        
        # Create config directory if it doesn't exist
        $configDir = Split-Path $script:ConfigPath -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        
        # Save the updated config
        $config | ConvertTo-Json | Out-File $script:ConfigPath -Force
        
        Write-Verbose "Successfully updated configuration value for '$Key'"
        return $true
    }
    catch {
        Write-Error "Error setting configuration value for '$Key': $_"
        return $false
    }
}

# Function to initialize default configuration
function Initialize-MAUReportConfig {
    [CmdletBinding()]
    param()
    
    try {
        if (-not (Test-Path $script:ConfigPath)) {
            $defaultConfig = @{
                DefaultWorkspaceId = ''
                DefaultHostPoolName = ''
                ReportPath = Join-Path $PSScriptRoot '..' 'Reports'
                TemplatePath = Join-Path $PSScriptRoot '..' 'template.html'
                LogoPath = Join-Path $PSScriptRoot '..' 'Static' 'NerrdioMSPLogo.png'
            }
            
            # Create config directory if it doesn't exist
            $configDir = Split-Path $script:ConfigPath -Parent
            if (-not (Test-Path $configDir)) {
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            }
            
            # Save default config
            $defaultConfig | ConvertTo-Json | Out-File $script:ConfigPath -Force
            Write-Verbose "Initialized default configuration"
            return $true
        }
        
        Write-Verbose "Configuration file already exists"
        return $true
    }
    catch {
        Write-Error "Error initializing configuration: $_"
        return $false
    }
}

# Initialize configuration when module loads
Initialize-MAUReportConfig
