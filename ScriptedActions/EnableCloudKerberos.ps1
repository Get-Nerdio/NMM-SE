<#
.SYNOPSIS
    Configure registry for Cloud Kerberos ticket retrieval and AzureADAccount LoadCredKeyFromProfile
 
.DESCRIPTION
    Sets:
      HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters\CloudKerberosTicketRetrievalEnabled = 1 (DWORD)
      HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount\LoadCredKeyFromProfile = 1 (DWORD)
 
    Designed for Nerdio Scripted Action usage on Windows 11 AVD session hosts / images.
 
.NOTES
    Requires administrator privileges to modify HKLM registry keys.
#>
 
#Requires -RunAsAdministrator
 
# region Helper Functions
 
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
 
function Set-RegistryDword {
    param (
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [int]$Value
    )
 
    try {
        if (-not (Test-Path -Path $Path)) {
            Write-Output "Path '$Path' does not exist. Creating..."
            New-Item -Path $Path -Force | Out-Null
        }
 
        $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
 
        if ($null -eq $existing) {
            Write-Output "Creating new DWORD '$Name' at '$Path' with value '$Value'."
            New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
        }
        else {
            if ($existing.$Name -ne $Value) {
                Write-Output "Updating DWORD '$Name' at '$Path' from '$($existing.$Name)' to '$Value'."
                Set-ItemProperty -Path $Path -Name $Name -Value $Value
            }
            else {
                Write-Output "DWORD '$Name' at '$Path' already set to '$Value'. No change needed."
            }
        }
 
        # Verify the value was set correctly
        $verify = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $verify -or $verify.$Name -ne $Value) {
            Write-Output "WARNING: Verification failed. Expected '$Value' but registry may not be set correctly."
            return $false
        }
 
        return $true
    }
    catch {
        Write-Output "ERROR: Failed to set '$Name' at '$Path'. Details: $($_.Exception.Message)"
        Write-Output "Stack trace: $($_.ScriptStackTrace)"
        return $false
    }
}
 
# endregion
 
Write-Output "=== Starting registry configuration for Cloud Kerberos and AzureADAccount settings ==="
Write-Output "Script started at: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC'))"
 
# Verify administrator privileges
if (-not (Test-Administrator)) {
    Write-Output "ERROR: This script requires administrator privileges to modify HKLM registry keys."
    Write-Output "Please run this script as an administrator."
    exit 1
}
 
$overallSuccess = $true
 
# 1) CloudKerberosTicketRetrievalEnabled
$kerberosPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
$kerberosName  = "CloudKerberosTicketRetrievalEnabled"
$kerberosValue = 1
 
Write-Output ""
Write-Output "Configuring $kerberosName..."
if (-not (Set-RegistryDword -Path $kerberosPath -Name $kerberosName -Value $kerberosValue)) {
    $overallSuccess = $false
}
 
# 2) LoadCredKeyFromProfile
$azureADPath  = "HKLM:\Software\Policies\Microsoft\AzureADAccount"
$azureADName  = "LoadCredKeyFromProfile"
$azureADValue = 1
 
Write-Output ""
Write-Output "Configuring $azureADName..."
if (-not (Set-RegistryDword -Path $azureADPath -Name $azureADName -Value $azureADValue)) {
    $overallSuccess = $false
}
 
Write-Output ""
if ($overallSuccess) {
    Write-Output "=== Completed successfully. All registry values are set as expected. ==="
    exit 0
}
else {
    Write-Output "=== Completed with errors. One or more registry values failed to set. ==="
    exit 1
}


