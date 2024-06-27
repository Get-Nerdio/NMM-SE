<#
    .SYNOPSIS
        Uninstall the Printix client.

    .LINK
        Github: https://github.com/Get-Nerdio/NMM-SE/blob/main/Scripted%20Actions/Install%20Printix/Uninstall-Printix.ps1
#>

$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = 'continue'
$folderPath = "$env:TEMP\NerdioManagerLogs"
$LognameTXT = "Uninstall-Printix.txt"

if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory $folderPath -Force
    Write-Output "$folderPath has been created."
}
else {
    Write-Output "$folderPath already exists, continue script"
}

Start-Transcript -Path (Join-Path $folderPath -ChildPath $LognameTXT) -Append -IncludeInvocationHeader

Write-Output "################# New Script Run #################"
Write-Output "Current time (UTC-0): $((Get-Date).ToUniversalTime())"

function Get-AdminElevation {
    # Get the current Windows identity
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    # Check if the current identity has the administrator role or is the system account
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    $currentIdentity.Name -eq 'NT AUTHORITY\SYSTEM'

    # Return the result
    return $isAdmin
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
            throw "Product '$ProductName' is not installed or could not be found."
        }

        # Uninstall the product using CIM method
        $uninstallResult = Invoke-CimMethod -InputObject $product -MethodName Uninstall

        if ($uninstallResult.ReturnValue -eq 0) {
            return 'Successfully uninstalled the Printix Client'
        }
        else {
            throw "Uninstallation failed with error code: $($uninstallResult.ReturnValue)"
        }
    }
    catch {
        throw "Something went wrong uninstalling the Printix Client: $($_.Exception.Message)"
    }
}


# Check if the script is running with admin privileges
if (Get-AdminElevation) {
    Write-Output 'You are running this script with administrative privileges.'
}
else {
    Write-Output 'You are NOT running this script with administrative privileges, please run as administrator or SYSTEM'
    Stop-Transcript
    $VerbosePreference = $SaveVerbosePreference
    break
}

# Uninstall the Printix client
try {
    $result = Uninstall-PrintixClient -ProductName 'Printix Client'
    Write-Output $result

    #Check if download files are still present
    $DownloadPath = "$env:TEMP\Printix"

    if (Test-Path $DownloadPath) {
        Write-Verbose "Cleaning up download directory: $DownloadPath"
        Remove-Item -Path $DownloadPath -Recurse -Force
    }
}
catch {
    $_.Exception.Message
}

Stop-Transcript
$VerbosePreference = $SaveVerbosePreference