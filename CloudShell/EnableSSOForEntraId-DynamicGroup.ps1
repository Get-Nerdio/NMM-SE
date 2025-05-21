<#
Azure Virtual Desktop SSO Configuration Script
No module dependencies - uses REST API calls directly

This script automatically:
- Creates a dynamic device security group
- Enables SSO for AVD by configuring Remote Desktop Protocol
- Associates the security group with the appropriate service principals

Requirements:
- Modern browser for authentication
#>

# Define variables
$groupName = "Device | AVD&W365Hosts"
$groupDescription = "This is a dynamic device group for EntraID joined AVD & W365 Hosts"
$dynamicRule = '(device.devicePhysicalIds -any (_ -contains "[AzureResourceId]")) or (device.deviceModel -startsWith "Cloud PC")'

# App IDs for service principals
$msrdAppId = "a4a365df-50f1-4397-bc59-1a1564b8bb9c" # Microsoft Remote Desktop
$wclAppId = "270efc09-cd0d-444b-a71f-39af4910ec45"  # Windows Cloud Login


# Function to acquire access token using device code flow (no modules required)
function Get-AccessToken {
    param (
        [string]$TenantId,
        [string]$ClientId = "1950a258-227b-4e31-a9cf-717495945fc2", # Microsoft Azure PowerShell
        [string]$Scope = "https://graph.microsoft.com/.default"
    )
    
    # Step 1: Get device code
    $deviceCodeRequestParams = @{
        Method = "POST"
        Uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
        ContentType = "application/x-www-form-urlencoded"
        Body = @{
            client_id = $ClientId
            scope = $Scope
        }
    }
    
    $deviceCodeResponse = Invoke-RestMethod @deviceCodeRequestParams
    Write-Host $deviceCodeResponse.message -ForegroundColor Cyan
    
    # Step 2: Poll for token
    $tokenRequestParams = @{
        Method = "POST"
        Uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        ContentType = "application/x-www-form-urlencoded"
        Body = @{
            grant_type = "device_code"
            client_id = $ClientId
            device_code = $deviceCodeResponse.device_code
        }
    }
    
    $secondsToWait = 5
    $maxWaitTimeSeconds = $deviceCodeResponse.expires_in
    $startTime = Get-Date
    
    do {
        Start-Sleep -Seconds $secondsToWait
        
        try {
            $tokenResponse = Invoke-RestMethod @tokenRequestParams
            return $tokenResponse
        }
        catch {
            $errorObj = ConvertFrom-Json $_.ErrorDetails.Message -ErrorAction SilentlyContinue
            
            if ($errorObj.error -eq "authorization_pending") {
                Write-Host "." -NoNewline
                continue
            }
            elseif ($errorObj.error -eq "slow_down") {
                $secondsToWait += 5
                continue
            }
            else {
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
        }
        
        $elapsedTime = (Get-Date) - $startTime
    } while ($elapsedTime.TotalSeconds -lt $maxWaitTimeSeconds)
    
    throw "Authentication timed out"
}

# Function to make Graph API calls
function Invoke-CustomGraphRequest {
    param (
        [string]$Method = "GET",
        [string]$ApiVersion = "v1.0",
        [string]$Uri,
        [object]$Body,
        [string]$ContentType = "application/json",
        [string]$AccessToken
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type" = $ContentType
    }
    
    $fullUri = "https://graph.microsoft.com/$ApiVersion/$Uri"
    
    $splat = @{
        Method = $Method
        Uri = $fullUri
        Headers = $headers
    }
    
    if ($Body -and $Method -ne "GET") {
        if ($Body -is [hashtable] -or $Body -is [System.Collections.Specialized.OrderedDictionary]) {
            $splat.Body = $Body | ConvertTo-Json -Depth 10
        }
        else {
            $splat.Body = $Body
        }
    }
    
    try {
        Invoke-RestMethod @splat
    }
    catch {
        Write-Host "Error calling Graph API ($fullUri): $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails) {
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }
        throw
    }
}

# Main script execution
try {
    # Get tenant ID from the user
    $tenantId = Read-Host "Enter your Azure AD tenant ID (format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
    
    # Authenticate and get access token
    Write-Host "Starting authentication process..." -ForegroundColor Yellow
    $tokenResponse = Get-AccessToken -TenantId $tenantId
    $accessToken = $tokenResponse.access_token
    
    Write-Host "Authentication successful!" -ForegroundColor Green
    
    # Create dynamic security group
    Write-Host "Creating dynamic security group '$groupName'..." -ForegroundColor Yellow
    
    $groupBody = @{
        displayName = $groupName
        description = $groupDescription
        securityEnabled = $true
        mailEnabled = $false
        groupTypes = @("DynamicMembership")
        membershipRule = $dynamicRule
        membershipRuleProcessingState = "On"
        mailNickname = $groupName
    }
    
    $newGroup = Invoke-CustomGraphRequest -Method "POST" -Uri "groups" -Body $groupBody -AccessToken $accessToken
    Write-Host "Group created successfully with ID: $($newGroup.id)" -ForegroundColor Green
    
    # Wait for the group to be created and resolved
    Write-Host "Waiting for group to be processed..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Get service principal IDs
    Write-Host "Retrieving service principal information..." -ForegroundColor Yellow
    
    $msrdServicePrincipal = Invoke-CustomGraphRequest -Uri "servicePrincipals?`$filter=appId eq '$msrdAppId'" -AccessToken $accessToken
    $msrdSpId = $msrdServicePrincipal.value[0].id
    
    $wclServicePrincipal = Invoke-CustomGraphRequest -Uri "servicePrincipals?`$filter=appId eq '$wclAppId'" -AccessToken $accessToken
    $wclSpId = $wclServicePrincipal.value[0].id
    
    # Enable Remote Desktop Protocol for each service principal
    Write-Host "Configuring Remote Desktop Protocol settings..." -ForegroundColor Yellow
    
    # Check current RDP status for MSRD
    $msrdConfig = Invoke-CustomGraphRequest -Uri "servicePrincipals/$msrdSpId/remoteDesktopSecurityConfiguration" -AccessToken $accessToken
    
    if ($msrdConfig.isRemoteDesktopProtocolEnabled -ne $true) {
        $rdpBody = @{
            isRemoteDesktopProtocolEnabled = $true
        }
        Invoke-CustomGraphRequest -Method "PATCH" -Uri "servicePrincipals/$msrdSpId/remoteDesktopSecurityConfiguration" -Body $rdpBody -AccessToken $accessToken
    }
    
    # Check current RDP status for WCL
    $wclConfig = Invoke-CustomGraphRequest -Uri "servicePrincipals/$wclSpId/remoteDesktopSecurityConfiguration" -AccessToken $accessToken
    
    if ($wclConfig.isRemoteDesktopProtocolEnabled -ne $true) {
        $rdpBody = @{
            isRemoteDesktopProtocolEnabled = $true
        }
        Invoke-CustomGraphRequest -Method "PATCH" -Uri "servicePrincipals/$wclSpId/remoteDesktopSecurityConfiguration" -Body $rdpBody -AccessToken $accessToken
    }
    
    # Get updated RDP configurations
    $msrdConfig = Invoke-CustomGraphRequest -Uri "servicePrincipals/$msrdSpId/remoteDesktopSecurityConfiguration" -AccessToken $accessToken
    $wclConfig = Invoke-CustomGraphRequest -Uri "servicePrincipals/$wclSpId/remoteDesktopSecurityConfiguration" -AccessToken $accessToken
    
    Write-Host "Microsoft Remote Desktop Service Principal RDP Status: $($msrdConfig.isRemoteDesktopProtocolEnabled)" -ForegroundColor Cyan
    Write-Host "Windows Cloud Login Service Principal RDP Status: $($wclConfig.isRemoteDesktopProtocolEnabled)" -ForegroundColor Cyan
    
    # Configure target device group for both service principals
    Write-Host "Configuring target device groups..." -ForegroundColor Yellow
    
    $targetDeviceGroupBody = @{
        "@odata.type" = "#microsoft.graph.targetDeviceGroup"
        id = $newGroup.id
        displayName = $groupName
    }
    
    # Add group to MSRD service principal
    Invoke-CustomGraphRequest -Method "POST" -Uri "servicePrincipals/$msrdSpId/remoteDesktopSecurityConfiguration/targetDeviceGroups" -Body $targetDeviceGroupBody -AccessToken $accessToken
    
    # Add group to WCL service principal
    Invoke-CustomGraphRequest -Method "POST" -Uri "servicePrincipals/$wclSpId/remoteDesktopSecurityConfiguration/targetDeviceGroups" -Body $targetDeviceGroupBody -AccessToken $accessToken
    
    Write-Host "Successfully configured SSO for Azure Virtual Desktop!" -ForegroundColor Green
    Write-Host "Dynamic security group created and associated with the appropriate service principals." -ForegroundColor Green
}
catch {
    Write-Host "An error occurred: $($_.Exception.Message)" -ForegroundColor Red
}
