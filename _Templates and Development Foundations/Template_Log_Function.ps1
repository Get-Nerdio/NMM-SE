function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [string]$LogFilePath = "$env:TEMP\NerdioManagerLogs",

        [string]$LogName = 'Install-Teams.txt',

        [bool]$throw = $false,

        [bool]$return = $false,

        [bool]$exit = $false,

        [bool]$WriteOutput = $false,

        [bool]$FirstLogInnput = $false
    )
    
    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType Directory -Path $LogFilePath -Force
        Write-Output "$LogFilePath has been created."
    }
    else {
        if ($FirstLogInnput -eq $true) {
            Add-Content -Path "$($LogFilePath)\$($LogName)" -Value "################# New Script Run #################"
        }
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level]: $Message"
    
    try {
        Add-Content -Path "$($LogFilePath)\$($LogName)" -Value $logEntry

        if ($throw) {
            throw $Message
        }

        if ($return) {
            return $Message
        }

        if ($exit) {
            Write-Output "$($Message)"
            exit 
        }

        if ($WriteOutput) {
            Write-Output "$($Message)"
        }
    }
    catch {
        Write-Error $_.Exception.Message
    }
}
