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

function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [string]$LogFilePath = "$env:TEMP\NerdioManagerLogs",

        [string]$LogName = "Install-Printix.txt",

        [bool]$throw = $false,

        [bool]$return = $false,

        [bool]$exit = $false
    )
    
    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType Directory -Path $LogFilePath -Force
        Write-Output "$LogFilePath has been created."
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
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
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

# Check if the script is running with admin privileges
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
            NMMLogOutput -Level 'Error' -Message "Failed to download the installer from $Url" -throw $true
        }
    }
    catch {
        NMMLogOutput -Level 'Error' -Message "Something went wrong donwloading the Printix Client: $($_.Exception.Message)" -throw $true
    }
    
    NMMLogOutput -Level 'Information' -Message "Successfully downloaded the Printix Client" -return $true
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
        NMMLogOutput -Level 'Error' -Message "The file '$Path' does not exist or is not a file." -throw $true
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
        NMMLogOutput -Level 'Error' -Message "Something went wrong installing the Printix Client: $($_.Exception.Message)" -throw $true
        
    }
    
    NMMLogOutput -Level 'Information' -Message 'Successfully installed the Printix Client' -return $true
}

# Check if the script is running with admin privileges
try {
    if (Get-AdminElevation) {
        NMMLogOutput -Level Information -Message 'You are running this script with administrative privileges.' -return $true
    }
    else {
        NMMLogOutput -Level Warning -Message 'You are NOT running this script with administrative privileges, please run as administrator or SYSTEM' -exit $true
    }
}
catch {
    NMMLogOutput -Level Error -Message "Failed to check for admin privileges: $($_.Exception.Message)" -throw $true
}

#Install Printix Client
try {

    #Get The Printix Tenant ID and Domain from Secure Variables set in NMM
    $PrintixTenantId = $SecureVars.printixTenantId
    $PrintixTenantDomain = $SecureVars.printixTenantDomain

    # Check if the variables are populated
    if ([string]::IsNullOrEmpty($PrintixTenantId) -or [string]::IsNullOrEmpty($PrintixTenantDomain)) {
        NMMLogOutput -Level 'Error' -Message 'Missing Printix Tenant ID or Domain in Secure Variables' -throw $true
    }
    NMMLogOutput -Level 'Information' -Message "Secure Variables Succefully populated: $PrintixTenantId ($PrintixTenantDomain)"

    # Set the MSI name and download path
    $PrintixMSI = "CLIENT_${PrintixTenantDomain}_$PrintixTenantId.msi"
    $DownloadPath = "$env:TEMP\Printix"

    # Check if the download directory exists, if not create it
    if (-not (Test-Path $DownloadPath)) {
        NMMLogOutput -Level 'Information' -Message "Creating download directory: $DownloadPath"
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