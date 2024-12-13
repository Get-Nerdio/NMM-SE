# Helper function to calculate percentages for distribution data
function Get-DistributionPercentages {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Items
    )
    
    if ($Items.Count -eq 0) { return @() }
    
    # Count occurrences of each item using a Generic List for better performance
    $itemCounts = [System.Collections.Generic.Dictionary[string,int]]::new()
    foreach ($item in $Items) {
        $itemKey = if ($null -eq $item -or $item -eq '') { '<>' } else { $item.ToString().Trim() }
        if ($itemCounts.ContainsKey($itemKey)) {
            $itemCounts[$itemKey]++
        }
        else {
            $itemCounts[$itemKey] = 1
        }
    }
    
    # Calculate percentages
    $total = $Items.Count
    $percentages = $itemCounts.GetEnumerator() | ForEach-Object {
        @{
            Item       = $_.Key
            Count      = $_.Value
            Percentage = [math]::Round(($_.Value / $total) * 100, 1)
        }
    } | Sort-Object -Property Count -Descending
    
    Write-Verbose "Distribution Analysis:"
    Write-Verbose "Total items: $total"
    $percentages | ForEach-Object {
        Write-Verbose "  $($_.Item): $($_.Count) occurrences ($($_.Percentage)%)"
    }
    
    return $percentages
}

# Function to process metrics for charts
function Process-MetricsForCharts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Stats
    )
    
    try {
        # Initialize result object
        $result = @{
            transportTypes = @{
                labels = @()
                data = @()
            }
            gatewayRegions = @{
                labels = @()
                data = @()
            }
            clientTypes = @{
                labels = @()
                data = @()
            }
            clientOSs = @{
                labels = @()
                data = @()
            }
        }

        # Function to flatten and clean array from JSON string
        function Expand-JsonArray {
            param([string]$JsonString)
            if ([string]::IsNullOrEmpty($JsonString)) { return @() }
            try {
                $array = $JsonString | ConvertFrom-Json
                if ($array -is [array]) {
                    return $array | Where-Object { $_ } | ForEach-Object { $_.ToString().Trim() }
                }
                return @($array.ToString().Trim())
            }
            catch {
                Write-Warning "Error parsing JSON array: $_"
                return @()
            }
        }

        # Process transport types
        Write-Verbose "Processing transport types..."
        $transportTypes = $Stats | ForEach-Object { 
            $types = Expand-JsonArray $_.TransportTypes
            Write-Verbose "Found types: $($types -join ', ')"
            $types
        }
        $transportTypeStats = Get-DistributionPercentages -Items $transportTypes
        $result.transportTypes.labels = @($transportTypeStats | Select-Object -ExpandProperty Item)
        $result.transportTypes.data = @($transportTypeStats | Select-Object -ExpandProperty Percentage)

        # Process gateway regions
        Write-Verbose "Processing gateway regions..."
        $gatewayRegions = $Stats | ForEach-Object { 
            $regions = Expand-JsonArray $_.GatewayRegions
            Write-Verbose "Found regions: $($regions -join ', ')"
            $regions
        }
        $gatewayRegionStats = Get-DistributionPercentages -Items $gatewayRegions
        $result.gatewayRegions.labels = @($gatewayRegionStats | Select-Object -ExpandProperty Item)
        $result.gatewayRegions.data = @($gatewayRegionStats | Select-Object -ExpandProperty Percentage)

        # Process client types
        Write-Verbose "Processing client types..."
        $clientTypes = $Stats | ForEach-Object { 
            $types = Expand-JsonArray $_.ClientTypes
            Write-Verbose "Found types: $($types -join ', ')"
            $types
        }
        $clientTypeStats = Get-DistributionPercentages -Items $clientTypes
        $result.clientTypes.labels = @($clientTypeStats | Select-Object -ExpandProperty Item)
        $result.clientTypes.data = @($clientTypeStats | Select-Object -ExpandProperty Percentage)

        # Process client OSs
        Write-Verbose "Processing client OSs..."
        $clientOSs = $Stats | ForEach-Object { 
            $oss = Expand-JsonArray $_.ClientOSs
            Write-Verbose "Found OSs: $($oss -join ', ')"
            $oss
        }
        $clientOSStats = Get-DistributionPercentages -Items $clientOSs
        $result.clientOSs.labels = @($clientOSStats | Select-Object -ExpandProperty Item)
        $result.clientOSs.data = @($clientOSStats | Select-Object -ExpandProperty Percentage)

        Write-Verbose "Processed metrics:"
        Write-Verbose "Transport Types: $($result.transportTypes.labels.Count) unique items"
        Write-Verbose "Gateway Regions: $($result.gatewayRegions.labels.Count) unique items"
        Write-Verbose "Client Types: $($result.clientTypes.labels.Count) unique items"
        Write-Verbose "Client OSs: $($result.clientOSs.labels.Count) unique items"

        return $result
    }
    catch {
        Write-Error "Error processing metrics for charts: $_"
        Write-Verbose "Full error details: $($_.Exception.Message)"
        Write-Verbose "Stack trace: $($_.ScriptStackTrace)"
        throw
    }
}

# Function to verify Azure connection
function Test-AzureConnection {
    [CmdletBinding()]
    param()
    
    try {
        $context = Get-AzContext
        if (-not $context) {
            throw "Not connected to Azure. Please run Connect-AzAccount first."
        }
        Write-Verbose "Connected to Azure subscription: $($context.Subscription.Name)"
        Write-Verbose "Account: $($context.Account.Id)"
        Write-Verbose "Tenant: $($context.Tenant.Id)"
        return $true
    }
    catch {
        Write-Error "Error checking Azure connection: $_"
        return $false
    }
}

# Function to verify workspace exists
function Test-WorkspaceExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId
    )
    
    try {
        Write-Verbose "Getting all Log Analytics workspaces..."
        $workspaces = Get-AzOperationalInsightsWorkspace
        Write-Verbose "Found $($workspaces.Count) workspaces"
        
        foreach ($ws in $workspaces) {
            Write-Verbose "Checking workspace: $($ws.Name)"
            Write-Verbose "  CustomerId: $($ws.CustomerId)"
            Write-Verbose "  Location: $($ws.Location)"
            Write-Verbose "  ResourceGroupName: $($ws.ResourceGroupName)"
        }
        
        $workspace = $workspaces | Where-Object { $_.CustomerId -eq $WorkspaceId }
        if (-not $workspace) {
            Write-Error "Could not find Log Analytics workspace with ID: $WorkspaceId"
            Write-Verbose "Available workspace IDs:"
            $workspaces | ForEach-Object {
                Write-Verbose "  $($_.CustomerId)"
            }
            return $false
        }
        
        Write-Verbose "Found workspace: $($workspace.Name)"
        Write-Verbose "ResourceId: $($workspace.ResourceId)"
        Write-Verbose "Location: $($workspace.Location)"
        Write-Verbose "ResourceGroupName: $($workspace.ResourceGroupName)"
        return $true
    }
    catch {
        Write-Error "Error checking workspace: $_"
        Write-Verbose "Full error details: $($_.Exception.Message)"
        Write-Verbose "Stack trace: $($_.ScriptStackTrace)"
        return $false
    }
}
