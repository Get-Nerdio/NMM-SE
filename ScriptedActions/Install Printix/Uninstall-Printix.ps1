<#
    .SYNOPSIS
        Uninstall the Printix client.

    .LINK
        Github: https://github.com/Get-Nerdio/NMM-SE/blob/main/Scripted%20Actions/Install%20Printix/Uninstall-Printix.ps1
#>

function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$LogFilePath = "$env:TEMP\NerdioManagerLogs",

        [string]$LogName = "Uninstall-Printix.txt",

        [bool]$throw = $false,

        [bool]$break = $false,

        [bool]$return = $false,

        [bool]$exit = $false
    )
    
    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType Directory $LogFilePath -Force
        Write-Output "$LogFilePath has been created."
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level]: $Message"
    
    try {
        Add-Content -Path "$($LogFilePath)\$($LogName)" -Value $logEntry

        if ($throw -eq $true) {
            throw $Message
        }

        if ($break -eq $true) {
            break
        }

        if ($return -eq $true) {
            return $Message
        }

        if ($exit -eq $true) {
            Write-Output $($Message)
            exit
        }
    }
    catch {
        $_.Exception.Message
    }
}

function Get-AdminElevation {
    try {
        # Get the current Windows identity
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

        # Check if the current identity has the administrator role or is the system account
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
        $currentIdentity.Name -eq 'NT AUTHORITY\SYSTEM'

        # Return the result
        return $isAdmin
    }
    catch {
        NMMLogOutput -Level 'Error' -Message "Failed to check for admin privileges: $($_.Exception.Message)" -throw
    }
}

function Uninstall-PrintixClient {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ProductName
    )

    try {
        # Get the product information using CIM with a filter
        $product = Get-CimInstance -ClassName Win32_Product -Filter "Name = '$ProductName'"

        if (-not $product) {
            NMMLogOutput -Level Warning -Message "Product '$ProductName' is not installed or could not be found." -throw $true
        }

        # Uninstall the product using CIM method
        $uninstallResult = Invoke-CimMethod -InputObject $product -MethodName Uninstall

        if ($uninstallResult.ReturnValue -eq 0) {

            NMMLogOutput -Level Information -Message "Successfully uninstalled the Printix Client" -return $true
        }
        else {
            NMMLogOutput -Level Error -Message "Uninstallation failed with error code: $($uninstallResult.ReturnValue)" -throw $true
        }
    }
    catch {
        NMMLogOutput -Level Error -Message "Something went wrong uninstalling the Printix Client: $($_.Exception.Message)" -throw $true
    }
}


# Check if the script is running with admin privileges
try {
    if (Get-AdminElevation) {
        NMMLogOutput -Level Information -Message 'You are running this script with administrative privileges.' -return $true
    }
    else {
        NMMLogOutput -Level Warning -Message 'You are NOT running this script with administrative privileges, please run as administrator or SYSTEM' -throw $true
    }
}
catch {
    NMMLogOutput -Level Error -Message "Failed to check for admin privileges: $($_.Exception.Message)" -throw $true
}

# Uninstall the Printix client
try {
    $result = Uninstall-PrintixClient -ProductName 'Printix Client'
    Write-Output $result

    #Check if download files are still present
    $DownloadPath = "$env:TEMP\Printix"

    if (Test-Path $DownloadPath) {
        NMMLogOutput -Level Information -Message "Cleaning up download directory: $DownloadPath"
        Remove-Item -Path $DownloadPath -Recurse -Force
    }
}
catch {
    NMMLogOutput -Level Error -Message "Failed to uninstall the Printix Client: $($_.Exception.Message)" -throw $true
}

