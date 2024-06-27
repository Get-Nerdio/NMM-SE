<#
    .SYNOPSIS
        Install Printix with NMM Scripted Actions
    .DESCRIPTION
        Uses NMM Secure Variables to install the Printix client on a Windows machine.
    .NOTES
        You need to set NMM Secure Variables for the Printix Tenant ID and Domain.
    .LINK
        Github: https://github.com/Get-Nerdio/NMM-SE/blob/main/Scripted%20Actions/Install%20Printix/Install-Printix.ps1
#>

$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = 'continue'
$folderPath = "$env:TEMP\NerdioManagerLogs"
$LognameTXT = "Install-Printix.txt"

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

# Check if the script is running with admin privileges
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

# Function to download the Printix installer
function Get-PrintixInstaller {
    param (
        [Parameter(Mandatory = $true)]
        [String]$TenantId,
        [Parameter(Mandatory = $true)]
        [String]$Path
    )

    $Url = "https://api.printix.net/v1/software/tenants/$PrintixTenantId/appl/CLIENT/os/WIN/type/MSI"

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Path -Headers @{ 'Accept' = 'application/octet-stream' }
        if (-not (Test-Path $Path)) {
            throw "Failed to download the installer from $Url"
        }
    }
    catch {
        throw "Something went wrong donwloading the Printix Client: $($_.Exception.Message)"
    }

    return 'Scuccessfully downloaded the Printix Client'
}

# Function to install the Printix client
function Install-PrintixClient {
    param (
        [Parameter(Mandatory = $true)]
        [String]$Path,
        [Parameter(Mandatory = $true)]
        [String]$TenantId
    )
    
    # Check if the file exists and is a file
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "The file '$Path' does not exist or is not a file."
    }

    try {
        $Arguments = @(
            '/i',
            "`"$Path`"",
            '/quiet',
            "WRAPPED_ARGUMENTS=/id:$TenantId",
            '/log',
            "`"$env:TEMP\PrintixClientInstall.log`""
        )

        $ProcessParams = @{
            FilePath     = 'msiexec.exe'
            ArgumentList = $Arguments
            Wait         = $true
        }

        Start-Process @ProcessParams

    }
    catch {
        throw "Something went wrong installing the Printix Client: $($_.Exception.Message)"
    }
    
    return 'Successfully installed the Printix Client'
}

try {

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

    #Get The Printix Tenant ID and Domain from Secure Variables set in NMM
    $PrintixTenantId = $SecureVars.printixTenantId
    $PrintixTenantDomain = $SecureVars.printixTenantDomain

    # Check if the variables are populated
    if ([string]::IsNullOrEmpty($PrintixTenantId) -or [string]::IsNullOrEmpty($PrintixTenantDomain)) {
        throw 'Missing Printix Tenant ID or Domain in Secure Variables'
    }

    Write-Verbose "Secure Variables Succefully populated: $PrintixTenantId ($PrintixTenantDomain)"

    # Set the MSI name and download path
    $PrintixMSI = "CLIENT_${PrintixTenantDomain}_$PrintixTenantId.msi"
    $DownloadPath = "$env:TEMP\Printix"

    # Check if the download directory exists, if not create it
    if (-not (Test-Path $DownloadPath)) {
        Write-Verbose "Creating download directory: $DownloadPath"
        New-Item -Path $DownloadPath -ItemType Directory
    }

    # Contruct the full path to the installer
    $InstallerPath = Join-Path -Path $DownloadPath -ChildPath $PrintixMSI

    # Download and install the Printix client
    Get-PrintixInstaller -TenantId $PrintixTenantId -Path $InstallerPath

    Install-PrintixClient -Path $InstallerPath -TenantId $PrintixTenantId

    #Cleanup the downloaded installer
    Remove-Item -Path $DownloadPath -Recurse -Force

}
catch {
    $_.Exception.Message
}

Stop-Transcript
$VerbosePreference = $SaveVerbosePreference