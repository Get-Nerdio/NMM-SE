# Description: Simple script to add a user (Active Directory or EntraID) to the FSLogix Profile Exclude List local security group
# 
# USAGE INSTRUCTIONS:
# 
# For Active Directory users:
#   - Format: "DOMAIN\username" or just "username"
#   - Example: "CONTOSO\jdoe" or "jdoe"
#   - Multiple users: "DOMAIN\user1,DOMAIN\user2,user3"
#
# For EntraID users:
#   - Format: "AzureAD\UserName@tenant.onmicrosoft.com" or "AzureAD\UserName@domain.com"
#   - Example: "AzureAD\jdoe@contoso.onmicrosoft.com"
#   - Multiple users: "AzureAD\user1@contoso.onmicrosoft.com,AzureAD\user2@contoso.onmicrosoft.com"
#   - The UPN (User Principal Name) is typically the user's email address
#   - You can find it in Azure Portal > Microsoft Entra ID > Users > Select user > User principal name
#
# Mixed AD and EntraID users are supported:
#   - Example: "DOMAIN\jdoe,AzureAD\asmith@contoso.onmicrosoft.com,user3"
#   - The script will auto-detect EntraID users by the "AzureAD\" prefix

# Define the group name and the user to add
$GroupName = "FSLogix Profile Exclude List"
$UserToAdd = "DOMAIN\\username"   # <-- Change this to the user(s) you want to add
# See usage instructions above for AD and EntraID formats

# Function to get AD user SID (for membership checking)
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

# Check whether the group exists
try {
    $null = Get-LocalGroup -Name $GroupName -ErrorAction Stop
}
catch {
    Write-Error "The group '$GroupName' does not exist on this system."
    exit 1
}

# Split comma-separated users if multiple are provided
$usersToProcess = @($UserToAdd -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($usersToProcess.Count -eq 0) {
    Write-Error "No valid user(s) specified. Please set the UserToAdd variable."
    exit 1
}

# Process each user
$successCount = 0
$skipCount = 0
$errorCount = 0

# Get existing members once for efficiency
$existingMembers = Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue

foreach ($user in $usersToProcess) {
    try {
        # Determine if this is an EntraID user (AzureAD\ prefix) or AD user
        $isEntraID = $user -match '^AzureAD\\'
        
        # For EntraID users, use the UPN format directly
        # For AD users, we'll use the username directly or get SID for checking
        $userDisplayName = $user
        $memberToAdd = $user
        $userSid = $null
        
        if ($isEntraID) {
            # EntraID user - use UPN format directly
            Write-Host "Processing EntraID user: $user" -ForegroundColor Cyan
            # The format is already correct: AzureAD\UserName@domain.com
        }
        else {
            # Active Directory user
            Write-Host "Processing Active Directory user: $user" -ForegroundColor Cyan
            # Try to get SID for more reliable membership checking
            try {
                $userSid = Get-ADUserSid -Username $user
                # Check membership by SID for AD users
                $isMember = $existingMembers | Where-Object { $_.SID.Value -eq $userSid }
                if ($isMember) {
                    Write-Host "User '$userDisplayName' is already a member of '$GroupName'. Skipping." -ForegroundColor Yellow
                    $skipCount++
                    continue
                }
            }
            catch {
                # If we can't get SID, we'll proceed with name-based check
                Write-Host "Note: Could not resolve AD user SID, using name-based check" -ForegroundColor Yellow
            }
        }
        
        # Check if user is already a member by name (for EntraID) or if we couldn't get SID
        if (-not $isEntraID -and $null -ne $userSid) {
            # Already checked above for AD users with SID
        }
        else {
            # Check by name for EntraID users or AD users without SID
            $userNameOnly = ($user -split '\\')[-1]  # Get the part after the backslash
            $isMember = $existingMembers | Where-Object { 
                $memberName = ($_.Name -split '\\')[-1]
                $memberName -eq $userNameOnly -or $_.Name -eq $user -or $_.Name -like "*\$userNameOnly"
            }
            
            if ($isMember) {
                Write-Host "User '$userDisplayName' is already a member of '$GroupName'. Skipping." -ForegroundColor Yellow
                $skipCount++
                continue
            }
        }
        
        # Add the user to the group
        Add-LocalGroupMember -Group $GroupName -Member $memberToAdd -ErrorAction Stop
        Write-Host "Successfully added '$userDisplayName' to '$GroupName'." -ForegroundColor Green
        $successCount++
    }
    catch {
        # Check if the error is because the user is already a member
        if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*is already a member*") {
            Write-Host "User '$user' is already a member of '$GroupName'. Skipping." -ForegroundColor Yellow
            $skipCount++
        }
        else {
            Write-Error "Failed to add user '$user': $_"
            $errorCount++
        }
    }
}

# Summary
if ($usersToProcess.Count -gt 1) {
    Write-Host "`nSummary: $successCount added, $skipCount skipped, $errorCount errors" -ForegroundColor Cyan
}
