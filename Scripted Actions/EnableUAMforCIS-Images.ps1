<#
.SYNOPSIS
This script enables Desktop App Installer (Winget) to make Nerdio UAM work with CIS hardening images. This will break the compliancew with the CIS benchmark.

.DESCRIPTION
The script automates the process of enabling UAM for the CIS benchmark on a Windows system. It changes the registry key value to Enable the Desktop Installer (Winget). This will break the current CIS compliance, but it is necessary if you want to use UAM with a CIS Windows Image. You are fully responsible for the consequences of running this script and not being compliant with the CIS benchmark. Use at your own risk!

.EXAMPLE
Upload this script in the NMM Scripted Actions section and run it on the target Host Pool when a VM is created or run it on the creation of a Desktop Image. Like mentioned before, use at your own risk!

.NOTES
Date: 08/29/2024
Version: 1.0
#>


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

function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateSet('String', 'DWORD', 'QWORD', 'Binary', 'MultiString', 'ExpandString')]
        [string]$Type
    )

    try {
        if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set registry value")) {
            # Check if the registry key exists, create it if it doesn't
            if (-not (Test-Path $Path)) {
                Write-Output "The registry key '$Path' does not exist. Creating it..."
                New-Item -Path $Path -Force | Out-Null
            }

            # Set the registry value using the appropriate type
            switch ($Type) {
                'String' {
                    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type String
                }
                'DWORD' {
                    Set-ItemProperty -Path $Path -Name $Name -Value ([Convert]::ToInt32($Value)) -Type DWord
                }
                'QWORD' {
                    Set-ItemProperty -Path $Path -Name $Name -Value ([Convert]::ToInt64($Value)) -Type Qword
                }
                'Binary' {
                    $binaryValue = $Value -split ' ' | ForEach-Object { [Convert]::ToByte($_, 16) }
                    Set-ItemProperty -Path $Path -Name $Name -Value $binaryValue -Type Binary
                }
                'MultiString' {
                    $multiStringValue = $Value -split ';'
                    Set-ItemProperty -Path $Path -Name $Name -Value $multiStringValue -Type MultiString
                }
                'ExpandString' {
                    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type ExpandString
                }
            }

            Write-Output "Successfully set $Name in $Path to $Value as $Type"
        } else {
            Write-Output 'Operation canceled by user.'
        }
    } catch {
        Write-Error "Failed to set $Name in $Path : $_"
    }
}


try {
    
    Set-RegistryValue  -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller" -Name "EnableAppInstaller" -Value "1" -Type "DWORD"
    
    NMMLogOutput -Level 'Information' -Message 'Successfully enabled Desktop App Installer (Winget) for UAM.' -WriteOutput $true

}
catch {
    NMMLogOutput -Level 'Error' -Message $_.Exception.Message -throw $true
}


