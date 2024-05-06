#Get-NMMToken will set a global variable $tokenInfo with the token information. If the token is missing or expired, it will retrieve a new one.

$tokenParams = @{
    BaseUri  = $nmmBaseURI #Or fill out the base URI as a string
    TenantId = $nmmTenantId #Or fill out the tenant ID as a string
    ClientId = $nmmClientId #Or fill out the client ID as a string
    Scope    = $nmmScope #Or fill out the scope as a string
    Secret  = $nmmSecret #Or fill out the secret as a string
}

function Get-NMMToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseURI,

        [Parameter(Mandatory=$true)]
        [string]$TenantId,

        [Parameter(Mandatory=$true)]
        [string]$ClientId,

        [Parameter(Mandatory=$true)]
        [string]$Scope,
        
        [Parameter(Mandatory=$true)]
        [string]$Secret
    )

    try {
        $tokenSplat = @{
            grant_type    = "client_credentials"
            client_secret = $Secret
            client_id     = $ClientId
            scope         = $Scope
        }

        $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $nmmOAToken = Invoke-RestMethod -Uri $tokenUri -Method POST -Body $tokenSplat

        $nmmTokenExp = (Get-Date).AddMinutes(59)

        # Return an object with the token and its expiration time
        $tokenObject = [PSCustomObject]@{
            Expires    = $nmmTokenExp
            APIConstruct = "$BaseURI/rest-api/v1"
            Token      = $nmmOAToken.access_token
        }

        Set-Variable -Name 'tokenInfo' -Value $tokenObject -Scope Global
        return $tokenInfo
    }
    catch {
        throw $_.Exception.Message
    }
}

function Get-NMMCustomers {
    [CmdletBinding()]
    Param(
        [Parameter()]
        [int[]]$id, # Array of integers for IDs

        [Parameter()]
        [string[]]$Name, # Array of strings for Names

        [Parameter()]
        [string[]]$TenantId  # Array of strings for Tenant IDs
    )

    BEGIN {
        # Attempt to fetch the token using a previously defined method
        #$tokenInfo = Get-NMMToken @tokenParams
        if (!$tokenInfo.Token -or ((New-TimeSpan -Start $tokenInfo.Expires -End (Get-Date)).TotalMinutes -gt 1)) {
            Write-Warning "Token is missing or expired, retrieving a new one."
            $tokenInfo = Get-NMMToken @tokenParams
        }
        $requestHeaders = @{
            'accept'        = 'application/json'
            'authorization' = "Bearer $($tokenInfo.Token)"
        }
        $begin = Get-Date
        $uri = "$($tokenInfo.APIConstruct)/accounts"
        $results = New-Object System.Collections.ArrayList  # Initialize an ArrayList
    }

    PROCESS {
        Try {
            $allAccounts = Invoke-RestMethod -Uri $uri -Headers $requestHeaders

            # Filter results based on provided parameters
            if ($id -or $Name -or $TenantId) {
                if ($id) {
                    foreach ($singleId in $id) {
                        $idResults = $allAccounts | Where-Object { $_.id -eq $singleId }
                        foreach ($item in $idResults) {
                            [void]$results.Add($item)
                        }
                    }
                }
                if ($Name) {
                    foreach ($singleName in $Name) {
                        $nameResults = $allAccounts | Where-Object { $_.name -like "*$singleName*" }
                        foreach ($item in $nameResults) {
                            [void]$results.Add($item)
                        }
                    }
                }
                if ($TenantId) {
                    foreach ($singleTenantId in $TenantId) {
                        $tenantResults = $allAccounts | Where-Object { $_.tenantId -eq $singleTenantId }
                        foreach ($item in $tenantResults) {
                            [void]$results.Add($item)
                        }
                    }
                }
                $results = $results | Sort-Object -Property id -Unique  # Remove duplicates and sort
            }
            else {
                # Return all accounts if no filters are specified
                $results = $allAccounts
            }
            $OK = $True
        }
        Catch {
            $OK = $false
            if ($_.Exception.Response) {
                $message = $_.Exception.Response.StatusDescription
                Write-Error "HTTP error: $message"
            }
            else {
                Write-Error "Error: $_"
            }
        }
        If ($OK) {
            Write-Output $results
        }
    }

    END {
        $runtime = New-TimeSpan -Start $begin -End (Get-Date)
        Write-Verbose "Execution completed in $runtime"
    }
}

# Example usage
# So basically you can combine the filters as you see fit. The function will return the results based on the filters you provide.

Get-NMMCustomers -TenantId 'TenantID1', 'TenantID2'

Get-NMMCustomers -id 2, 24

Get-NMMCustomers -Name 'Test1', 'Contoso' -id 2

