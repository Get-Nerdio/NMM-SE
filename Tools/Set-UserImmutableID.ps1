<#
.SYNOPSIS
    Sets the ImmutableID for a Microsoft 365 cloud user based on their on-premises Active Directory GUID.

.DESCRIPTION
    This script helps synchronize user identities between on-premises Active Directory and Microsoft 365 
    by setting the ImmutableID attribute. The ImmutableID is derived from the on-premises user's ObjectGUID, 
    converted to a Base64-encoded string. This is essential for directory synchronization and hybrid identity scenarios.

    The script will:
    - Automatically install Microsoft Graph PowerShell modules if not present
    - Connect to Microsoft Graph with User.ReadWrite.All permissions
    - Retrieve the on-premises user's ObjectGUID from Active Directory
    - Convert the GUID to Base64 format
    - Update the cloud user's OnPremisesImmutableId attribute

.PARAMETER None
    This script prompts for user input interactively. No parameters are required when running the script.

.EXAMPLE
    .\Set-UserImmutableID.ps1
    
    When you run this script, it will prompt you for:
    - On-premises AD username (sAMAccountName): e.g., "jsmith"
    - Cloud username (UserPrincipalName): e.g., "jsmith@contoso.com"

.NOTES
    Prerequisites:
    - Active Directory module for Windows PowerShell (RSAT-AD-PowerShell feature)
    - Microsoft Graph PowerShell SDK (will be installed automatically if missing)
    - Appropriate permissions:
      * Read access to on-premises Active Directory
      * User.ReadWrite.All permission in Microsoft Graph (requires Global Administrator or User Administrator role)
    
    IMPORTANT:
    - You must run this script on a machine that has access to your on-premises Active Directory domain
    - You will be prompted to authenticate to Microsoft Graph when Connect-MgGraph is called
    - The script requires administrative privileges for Active Directory queries

.INPUTS
    Interactive prompts for:
    - On-premises AD username (sAMAccountName)
    - Cloud username (UserPrincipalName or Object ID)

.OUTPUTS
    Success message with the ImmutableID value, or error messages if the operation fails.

.LINK
    https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview
    https://learn.microsoft.com/en-us/azure/active-directory/hybrid/connect/how-to-connect-install-prerequisites
#>

# Script Name: Set-UserImmutableID.ps1 

# Check that Graph module is installed and install it if not 
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) { 
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force 
} 
# Import the Users sub-module which contains Update-MgUser cmdlet
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) { 
    Install-Module -Name Microsoft.Graph.Users -Scope CurrentUser -Force 
} 
Import-Module Microsoft.Graph.Users 

# Connect to Microsoft Graph 
Connect-MgGraph -Scopes "User.ReadWrite.All" 

# Check that Active Directory module is available
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "Active Directory module is not available. Please install RSAT-AD-PowerShell feature or run this script on a domain controller."
    exit 1
}
Import-Module ActiveDirectory 

# Function to set ImmutableID for a user 
function Set-UserImmutableID { 
    param ( 
        [string]$onPremUsername, 
        [string]$cloudUsername 
    ) 

    # Get the on-premises user object 
    $onPremUser = Get-ADUser -Identity $onPremUsername -Properties ObjectGUID 
    if (-not $onPremUser) { 
        Write-Error "On-premises user '$onPremUsername' not found." 
        return 
    } 

    # Convert ObjectGUID to byte array and then to Base64 string 
    $guidBytes = $onPremUser.ObjectGUID.ToByteArray() 
    $immutableID = [System.Convert]::ToBase64String($guidBytes) 

    # Set the ImmutableID for the cloud user 
    try { 
        Update-MgUser -UserId $cloudUsername -OnPremisesImmutableId $immutableID 
        Write-Host "Successfully set ImmutableID for user '$cloudUsername'." -ForegroundColor Green
        Write-Host "ImmutableID value: $immutableID" -ForegroundColor Cyan
    } catch { 
        Write-Error "Failed to set ImmutableID for user '$cloudUsername'. Error: $_" 
        return
    } 
} 

# Get user input with validation
$ADUsername = Read-Host "Enter the on-premises AD username (sAMAccountName)" 
if ([string]::IsNullOrWhiteSpace($ADUsername)) {
    Write-Error "On-premises username cannot be empty."
    exit 1
}

$365Username = Read-Host "Enter the cloud username (UserPrincipalName)" 
if ([string]::IsNullOrWhiteSpace($365Username)) {
    Write-Error "Cloud username cannot be empty."
    exit 1
}

Set-UserImmutableID -onPremUsername $ADUsername -cloudUsername $365Username