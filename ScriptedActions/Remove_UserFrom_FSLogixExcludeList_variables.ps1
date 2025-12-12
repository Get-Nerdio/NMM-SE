# Description: This script removes a user (either Active Directory or EntraID) from the FSLogix Profile Exclude List local security group

function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$LogFilePath = "$env:TEMP\NerdioManagerLogs",

        [string]$LogName = "Remove_UserFrom_FSLogixExcludeList.txt"
    )
    
    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType Directory $LogFilePath -Force
        Write-Output "$LogFilePath has been created."
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level]: $Message"
    
    try {
        Add-Content -Path "$($LogFilePath)\$($LogName)" -Value $logEntry
    }
    catch {
        $_.Exception.Message
    }
}

# Note: EntraID users are now handled using UPN format directly, no SID conversion needed

function Get-ADUserSid {
    param([String] $Username)
    
    try {
        # Check if Active Directory module is available
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            throw "Active Directory module is not available. Please install RSAT-AD-PowerShell feature."
        }
        
        Import-Module ActiveDirectory -ErrorAction Stop
        
        # Get the AD user
        $adUser = Get-ADUser -Identity $Username -ErrorAction Stop
        return $adUser.SID.Value
    }
    catch {
        throw "Failed to get AD user SID for '$Username': $_"
    }
}

try {
    # ============================================================================================
    # CONFIGURATION: Set the user identifier here
    # ============================================================================================
    #
    # ACTIVE DIRECTORY USERS:
    #   - Format: SAMAccountName (e.g., "jdoe" or "DOMAIN\jdoe")
    #   - Example: "CONTOSO\jdoe" or "jdoe"
    #
    # ENTRAID USERS:
    #   - Format: "AzureAD\UserName@tenant.onmicrosoft.com" or "AzureAD\UserName@domain.com"
    #   - Example: "AzureAD\jdoe@contoso.onmicrosoft.com"
    #   - The UPN (User Principal Name) is typically the user's email address
    #   - How to find UPN:
    #     1. Go to Azure Portal (https://portal.azure.com)
    #     2. Navigate to: Microsoft Entra ID > Users
    #     3. Select the user you want to remove
    #     4. Copy the "User principal name" value (e.g., jdoe@contoso.onmicrosoft.com)
    #     5. Format it as: AzureAD\jdoe@contoso.onmicrosoft.com
    #
    # MULTIPLE USERS:
    #   - Comma-separated values (e.g., "jdoe,asmith,AzureAD\user1@contoso.onmicrosoft.com")
    #   - Mixed AD and EntraID users are supported
    #   - The script will auto-detect EntraID users by the "AzureAD\" prefix if UserType is not specified
    #
    # NERDIO MANAGER VARIABLES:
    #   - You can use InheritedVars or SecureVars if configured in Nerdio Manager
    #   - Example: Set InheritedVars.UserToExclude = "jdoe,12345678-1234-1234-1234-123456789012"
    #   - Example: Set InheritedVars.UserType = "AD" or "EntraID" (optional - auto-detected if not set)
    # ============================================================================================
    
    $UserIdentifier = ""  # Set this to the user's SAMAccountName (AD) or UPN format for EntraID (AzureAD\UserName@domain.com), or comma-separated list
    $UserType = ""  # Optional: Set to "AD" or "EntraID" to force type (applies to all if specified). If empty, auto-detects based on AzureAD\ prefix.
    
    # Alternative: Use variables from Nerdio Manager if provided
    if ($InheritedVars.UserToExclude) {
        $UserIdentifier = $InheritedVars.UserToExclude
    }
    if ($InheritedVars.UserType) {
        $UserType = $InheritedVars.UserType
    }
    
    # Validate input
    if ([string]::IsNullOrWhiteSpace($UserIdentifier)) {
        throw "UserIdentifier is required. Please set the UserIdentifier variable or configure InheritedVars.UserToExclude in Nerdio Manager."
    }
    
    $FSLogixExclusionGroup = 'FSLogix Profile Exclude List'
    
    # Verify the local group exists
    try {
        $null = Get-LocalGroup -Name $FSLogixExclusionGroup -ErrorAction Stop
        NMMLogOutput -Level Information -Message "Found local group: $FSLogixExclusionGroup"
    }
    catch {
        throw "Local group '$FSLogixExclusionGroup' does not exist. Please create it first."
    }
    
    # Split comma-separated users and trim whitespace
    $userIdentifiers = @($UserIdentifier -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    
    if ($userIdentifiers.Count -eq 0) {
        throw "No valid user identifiers found after parsing. Please provide at least one user identifier."
    }
    
    NMMLogOutput -Level Information -Message "Processing $($userIdentifiers.Count) user(s) for removal from $FSLogixExclusionGroup"
    Write-Output "Processing $($userIdentifiers.Count) user(s)..."
    
    # Get existing members once for efficiency
    $existingMembers = Get-LocalGroupMember -Group $FSLogixExclusionGroup -ErrorAction SilentlyContinue
    $successCount = 0
    $skipCount = 0
    $errorCount = 0
    
    # Process each user
    foreach ($userIdentifierItem in $userIdentifiers) {
        try {
            # Determine user type for this specific user
            $currentUserType = $UserType
            if ([string]::IsNullOrWhiteSpace($currentUserType)) {
                # Try to auto-detect: if it has AzureAD\ prefix, assume EntraID; otherwise assume AD
                if ($userIdentifierItem -match '^AzureAD\\') {
                    $currentUserType = "EntraID"
                }
                else {
                    $currentUserType = "AD"
                }
            }
            
            # Process based on user type
            $userDisplayName = $userIdentifierItem
            $memberToRemove = $userIdentifierItem
            $userSid = $null
            
            if ($currentUserType -eq "EntraID") {
                NMMLogOutput -Level Information -Message "Processing EntraID user with UPN: $userIdentifierItem"
                # EntraID users use UPN format directly: AzureAD\UserName@domain.com
                # No SID conversion needed - use the UPN format directly
            }
            elseif ($currentUserType -eq "AD") {
                NMMLogOutput -Level Information -Message "Processing Active Directory user: $userIdentifierItem"
                # Try to get SID for AD users for more reliable membership checking
                try {
                    $userSid = Get-ADUserSid -Username $userIdentifierItem
                    NMMLogOutput -Level Information -Message "Retrieved AD user SID: $userSid"
                }
                catch {
                    NMMLogOutput -Level Warning -Message "Could not resolve AD user SID for $userIdentifierItem, will use name-based check"
                }
                
                # Try to get the display name for better logging
                try {
                    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
                    $adUser = Get-ADUser -Identity $userIdentifierItem -Properties DisplayName -ErrorAction SilentlyContinue
                    if ($adUser) {
                        $userDisplayName = "$($adUser.DisplayName) ($userIdentifierItem)"
                    }
                }
                catch {
                    # Ignore errors getting display name
                }
            }
            else {
                throw "Invalid UserType specified. Must be 'AD' or 'EntraID'."
            }
            
            # Check if user is a member
            $isMember = $false
            if ($currentUserType -eq "AD" -and $null -ne $userSid) {
                # Check by SID for AD users when SID is available
                $isMember = $existingMembers | Where-Object { $_.SID.Value -eq $userSid }
            }
            else {
                # Check by name for EntraID users or AD users without SID
                $userNameOnly = ($userIdentifierItem -split '\\')[-1]  # Get the part after the backslash
                $isMember = $existingMembers | Where-Object { 
                    $memberName = ($_.Name -split '\\')[-1]
                    $memberName -eq $userNameOnly -or $_.Name -eq $userIdentifierItem -or $_.Name -like "*\$userNameOnly"
                }
            }
            
            if (-not $isMember) {
                NMMLogOutput -Level Warning -Message "User $userDisplayName is not a member of $FSLogixExclusionGroup"
                Write-Output "  - ${userDisplayName}: Not a member (skipped)"
                $skipCount++
            }
            else {
                # Remove the user from the group using UPN format for EntraID or username for AD
                Write-Output "  - Removing $userDisplayName..."
                Remove-LocalGroupMember -Group $FSLogixExclusionGroup -Member $memberToRemove -ErrorAction Stop
                NMMLogOutput -Level Information -Message "Successfully removed $userDisplayName from $FSLogixExclusionGroup"
                Write-Output "    Successfully removed $userDisplayName"
                $successCount++
            }
        }
        catch {
            $errorMessage = "Failed to process user '$userIdentifierItem': $($_.Exception.Message)"
            NMMLogOutput -Level Error -Message $errorMessage
            Write-Output "  - ERROR: $userIdentifierItem - $($_.Exception.Message)"
            $errorCount++
            # Continue processing other users even if one fails
        }
    }
    
    # Summary
    Write-Output ""
    Write-Output "Summary: $successCount removed, $skipCount skipped, $errorCount errors"
    NMMLogOutput -Level Information -Message "Processing complete: $successCount removed, $skipCount skipped, $errorCount errors"
}
catch {
    $errorMessage = $_.Exception.Message
    NMMLogOutput -Level Error -Message $errorMessage
    Write-Error $errorMessage
    throw
}
finally {
    NMMLogOutput -Level Information -Message "Script execution completed"
}


