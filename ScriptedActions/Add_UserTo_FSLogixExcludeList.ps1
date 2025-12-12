# Description: This script adds a user (either Active Directory or EntraID) to the FSLogix Profile Exclude List local security group

function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$LogFilePath = "$env:TEMP\NerdioManagerLogs",

        [string]$LogName = "Add_UserTo_FSLogixExcludeList.txt"
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

function Convert-AzureAdObjectIdToSid {
    param([String] $ObjectId)
    
    $bytes = [Guid]::Parse($ObjectId).ToByteArray()
    $array = New-Object 'UInt32[]' 4
    
    [Buffer]::BlockCopy($bytes, 0, $array, 0, 16)
    $sid = "S-1-12-1-$array".Replace(' ', '-')
    
    return $sid
}

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
    # Configuration: Set the user identifier here
    # For Active Directory users: Use the SAMAccountName (e.g., "jdoe" or "DOMAIN\jdoe")
    # For EntraID users: Use the Object ID (e.g., "12345678-1234-1234-1234-123456789012")
    # Multiple users can be specified as comma-separated values (e.g., "jdoe,asmith,12345678-1234-1234-1234-123456789012")
    # You can also use InheritedVars or SecureVars if configured in Nerdio Manager
    # Example: $UserIdentifier = $InheritedVars.UserToExclude
    # Example: $UserIdentifier = $SecureVars.UserToExclude
    
    $UserIdentifier = ""  # Set this to the user's SAMAccountName (AD) or Object ID (EntraID), or comma-separated list
    $UserType = ""  # Set to "AD" for Active Directory users or "EntraID" for EntraID users (applies to all if specified)
    
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
    
    NMMLogOutput -Level Information -Message "Processing $($userIdentifiers.Count) user(s) for addition to $FSLogixExclusionGroup"
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
                # Try to auto-detect: if it's a GUID format, assume EntraID; otherwise assume AD
                if ($userIdentifierItem -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                    $currentUserType = "EntraID"
                }
                else {
                    $currentUserType = "AD"
                }
            }
            
            # Get the SID based on user type
            $userSid = $null
            $userDisplayName = $userIdentifierItem
            
            if ($currentUserType -eq "EntraID") {
                NMMLogOutput -Level Information -Message "Processing EntraID user with Object ID: $userIdentifierItem"
                $userSid = Convert-AzureAdObjectIdToSid -ObjectId $userIdentifierItem
                NMMLogOutput -Level Information -Message "Converted EntraID Object ID to SID: $userSid"
            }
            elseif ($currentUserType -eq "AD") {
                NMMLogOutput -Level Information -Message "Processing Active Directory user: $userIdentifierItem"
                $userSid = Get-ADUserSid -Username $userIdentifierItem
                NMMLogOutput -Level Information -Message "Retrieved AD user SID: $userSid"
                
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
            
            # Check if user is already a member
            $isAlreadyMember = $existingMembers | Where-Object { $_.SID.Value -eq $userSid }
            
            if ($isAlreadyMember) {
                NMMLogOutput -Level Warning -Message "User $userDisplayName (SID: $userSid) is already a member of $FSLogixExclusionGroup"
                Write-Output "  - ${userDisplayName}: Already a member (skipped)"
                $skipCount++
            }
            else {
                # Add the user to the group
                Write-Output "  - Adding $userDisplayName (SID: $userSid)..."
                Add-LocalGroupMember -Group $FSLogixExclusionGroup -Member $userSid -ErrorAction Stop
                NMMLogOutput -Level Information -Message "Successfully added $userDisplayName (SID: $userSid) to $FSLogixExclusionGroup"
                Write-Output "    Successfully added $userDisplayName"
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
    Write-Output "Summary: $successCount added, $skipCount skipped, $errorCount errors"
    NMMLogOutput -Level Information -Message "Processing complete: $successCount added, $skipCount skipped, $errorCount errors"
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

