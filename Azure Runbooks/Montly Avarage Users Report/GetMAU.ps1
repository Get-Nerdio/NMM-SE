# Get Monthly Average Users Report
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$HostPoolName = "nerdio desktop win10",
    
    [Parameter(Mandatory = $false)]
    [string]$ReportName = "AVDUsageReport_$(Get-Date -Format 'yyyyMMdd')",
    
    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 30
)

# Function to calculate percentages for distribution data
function Get-DistributionPercentages {
    param (
        [Parameter(Mandatory = $true)]
        [array]$items
    )
    
    if ($items.Count -eq 0) { return @() }
    
    # Count occurrences of each item
    $itemCounts = @{}
    foreach ($item in $items) {
        if ($null -eq $item -or $item -eq '') {
            $item = '<>'
        }
        if ($itemCounts.ContainsKey($item)) {
            $itemCounts[$item]++
        }
        else {
            $itemCounts[$item] = 1
        }
    }
    
    # Calculate percentages
    $total = $items.Count
    $percentages = $itemCounts.GetEnumerator() | ForEach-Object {
        @{
            Item       = $_.Key
            Percentage = [math]::Round(($_.Value / $total) * 100, 2)
        }
    } | Sort-Object -Property Percentage -Descending
    
    return $percentages
}

# Function to parse JSON array string
function Parse-JsonArray {
    param (
        [string]$jsonString
    )
    try {
        return $jsonString | ConvertFrom-Json
    }
    catch {
        Write-Warning "Error parsing JSON array: $_"
        return @()
    }
}

# Function to process session data for a time period
function Get-SessionMetrics {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Sessions,
        
        [Parameter(Mandatory = $true)]
        [string]$GroupBy
    )
    
    $metrics = @{}
    
    $groupedSessions = $Sessions | Group-Object -Property $GroupBy
    
    foreach ($group in $groupedSessions) {
        $periodSessions = $group.Group
        
        # Get unique values
        $uniqueUsers = $periodSessions.UserPrincipalName | Select-Object -Unique
        $activeSessionCount = ($periodSessions | Where-Object { $_.State -eq 'Active' }).Count
        $completedSessionCount = ($periodSessions | Where-Object { $_.State -eq 'Completed' }).Count
        $uniqueClients = $periodSessions.ClientType | Select-Object -Unique
        $uniqueHosts = $periodSessions.SessionHostName | Select-Object -Unique
        
        # Get all client types, OS versions, and transport types for the period
        $clientTypes = $periodSessions.ClientType
        $clientOSs = $periodSessions.ClientOS
        $transportTypes = $periodSessions.TransportType
        $gatewayRegions = $periodSessions.GatewayRegion
        
        # Calculate average session duration for completed sessions
        $completedSessions = $periodSessions | Where-Object { $_.State -eq 'Completed' -and $_.SessionDuration }
        if ($completedSessions) {
            $avgDuration = [TimeSpan]::FromTicks(($completedSessions.SessionDuration | Measure-Object -Average).Average)
        }
        else {
            $avgDuration = [TimeSpan]::Zero
        }
        
        # Store metrics for this period
        $metrics[$group.Name] = @{
            PeriodName         = $group.Name
            Users              = $uniqueUsers.Count
            ActiveSessions     = $activeSessionCount
            CompletedSessions  = $completedSessionCount
            TotalSessions      = $periodSessions.Count
            UniqueClients      = $uniqueClients.Count
            UniqueHosts        = $uniqueHosts.Count
            ClientTypes        = $clientTypes
            ClientOSs          = $clientOSs
            TransportTypes     = $transportTypes
            GatewayRegions     = $gatewayRegions
            AvgSessionDuration = $avgDuration
        }
    }
    
    return $metrics
}

# Function to format data for Chart.js
function Format-ChartData {
    param (
        [Parameter(Mandatory = $true)]
        [array]$distributions
    )
    
    return @{
        labels = $distributions.Item
        data   = $distributions.Percentage
    }
}

# Function to process metrics for chart data
function Process-MetricsForCharts {
    param (
        [Parameter(Mandatory = $true)]
        [array]$stats
    )
    
    $allTransportTypes = @()
    $allGatewayRegions = @()
    $allClientTypes = @()
    $allClientOSs = @()
    
    foreach ($stat in $stats) {
        $allTransportTypes += Parse-JsonArray $stat.TransportTypes
        $allGatewayRegions += Parse-JsonArray $stat.GatewayRegions
        $allClientTypes += Parse-JsonArray $stat.ClientTypes
        $allClientOSs += Parse-JsonArray $stat.ClientOSs
    }
    
    $transportDist = Get-DistributionPercentages -items $allTransportTypes
    $gatewayDist = Get-DistributionPercentages -items $allGatewayRegions
    $clientTypesDist = Get-DistributionPercentages -items $allClientTypes
    $clientOSDist = Get-DistributionPercentages -items $allClientOSs
    
    return @{
        transportTypes = Format-ChartData -distributions $transportDist
        gatewayRegions = Format-ChartData -distributions $gatewayDist
        clientTypes    = Format-ChartData -distributions $clientTypesDist
        clientOSs      = Format-ChartData -distributions $clientOSDist
    }
}

try {
    # Get current date and start date
    $endDate = Get-Date
    $startDate = $endDate.AddDays(-$DaysToAnalyze)
    
    # Get session data
    $sessions = Get-AzWvdUserSession -HostPoolName $HostPoolName -StartTime $startDate -EndTime $endDate
    
    if (-not $sessions) {
        throw "No session data found for the specified time period"
    }
    
    # Calculate metrics for different time periods
    $monthlyMetrics = Get-SessionMetrics -Sessions $sessions -GroupBy 'Month1'
    $weeklyMetrics = Get-SessionMetrics -Sessions $sessions -GroupBy 'Week1'
    $dailyMetrics = Get-SessionMetrics -Sessions $sessions -GroupBy 'Date1'
    
    # Calculate averages
    $avgMonthlyUsers = ($monthlyMetrics.Values.Users | Measure-Object -Average).Average
    $avgWeeklyUsers = ($weeklyMetrics.Values.Users | Measure-Object -Average).Average
    $avgDailyUsers = ($dailyMetrics.Values.Users | Measure-Object -Average).Average
    $peakDailyUsers = ($dailyMetrics.Values.Users | Measure-Object -Maximum).Maximum
    
    # Get distribution data for the entire period
    $allClientTypes = $sessions.ClientType
    $allClientOSs = $sessions.ClientOS
    $allTransportTypes = $sessions.TransportType
    $allGatewayRegions = $sessions.GatewayRegion
    
    $clientTypesDist = Get-DistributionPercentages -items $allClientTypes
    $clientOSDist = Get-DistributionPercentages -items $allClientOSs
    $transportTypesDist = Get-DistributionPercentages -items $allTransportTypes
    $gatewayRegionsDist = Get-DistributionPercentages -items $allGatewayRegions
    
    # Create report data object
    $reportData = @{
        TimeRange      = "$($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))"
        HostPoolName   = $HostPoolName
        MonthlyMetrics = @{
            PerformanceMetrics  = @{
                AvgNetworkLatency = $null
                AvgFrameRate      = $null
                AvgBandwidth      = $null
            }
            AverageMonthlyUsers = $avgMonthlyUsers
            Stats               = $monthlyMetrics.Values | ForEach-Object {
                @{
                    Month              = $_.PeriodName
                    MonthlyUsers       = $_.Users.ToString()
                    ActiveSessions     = $_.ActiveSessions.ToString()
                    CompletedSessions  = $_.CompletedSessions.ToString()
                    TotalSessions      = $_.TotalSessions.ToString()
                    UniqueClients      = $_.UniqueClients.ToString()
                    UniqueHosts        = $_.UniqueHosts.ToString()
                    ClientOSs          = ConvertTo-Json $_.ClientOSs
                    ClientTypes        = ConvertTo-Json $_.ClientTypes
                    TransportTypes     = ConvertTo-Json $_.TransportTypes
                    GatewayRegions     = ConvertTo-Json $_.GatewayRegions
                    Month1             = $_.PeriodName
                    AvgSessionDuration = $_.AvgSessionDuration.ToString()
                }
            }
        }
        WeeklyMetrics  = @{
            AverageWeeklyUsers = $avgWeeklyUsers
            PeakWeeklySessions = $null
            Stats              = $weeklyMetrics.Values | ForEach-Object {
                @{
                    Week               = $_.PeriodName
                    WeeklyUsers        = $_.Users.ToString()
                    ActiveSessions     = $_.ActiveSessions.ToString()
                    CompletedSessions  = $_.CompletedSessions.ToString()
                    TotalSessions      = $_.TotalSessions.ToString()
                    UniqueHosts        = $_.UniqueHosts.ToString()
                    ClientOSs          = ConvertTo-Json $_.ClientOSs
                    ClientTypes        = ConvertTo-Json $_.ClientTypes
                    TransportTypes     = ConvertTo-Json $_.TransportTypes
                    GatewayRegions     = ConvertTo-Json $_.GatewayRegions
                    Week1              = $_.PeriodName
                    AvgSessionDuration = $_.AvgSessionDuration.ToString()
                }
            }
        }
        DailyMetrics   = @{
            PeakDailyUsers    = $peakDailyUsers
            AverageDailyUsers = $avgDailyUsers
            TrendAnalysis     = $dailyMetrics.Values | Sort-Object PeriodName | ForEach-Object {
                @{
                    Date               = $_.PeriodName
                    DailyUsers         = $_.Users.ToString()
                    ActiveSessions     = $_.ActiveSessions.ToString()
                    CompletedSessions  = $_.CompletedSessions.ToString()
                    TotalSessions      = $_.TotalSessions.ToString()
                    UniqueClients      = $_.UniqueClients.ToString()
                    UniqueHosts        = $_.UniqueHosts.ToString()
                    ClientOSs          = ConvertTo-Json $_.ClientOSs
                    ClientTypes        = ConvertTo-Json $_.ClientTypes
                    TransportTypes     = ConvertTo-Json $_.TransportTypes
                    GatewayRegions     = ConvertTo-Json $_.GatewayRegions
                    Date1              = $_.PeriodName
                    AvgSessionDuration = $_.AvgSessionDuration.ToString()
                }
            }
            Stats             = $dailyMetrics.Values | Sort-Object PeriodName -Descending | Select-Object -First 7 | ForEach-Object {
                @{
                    Date               = $_.PeriodName
                    DailyUsers         = $_.Users.ToString()
                    ActiveSessions     = $_.ActiveSessions.ToString()
                    CompletedSessions  = $_.CompletedSessions.ToString()
                    TotalSessions      = $_.TotalSessions.ToString()
                    UniqueClients      = $_.UniqueClients.ToString()
                    UniqueHosts        = $_.UniqueHosts.ToString()
                    ClientOSs          = ConvertTo-Json $_.ClientOSs
                    ClientTypes        = ConvertTo-Json $_.ClientTypes
                    TransportTypes     = ConvertTo-Json $_.TransportTypes
                    GatewayRegions     = ConvertTo-Json $_.GatewayRegions
                    Date1              = $_.PeriodName
                    AvgSessionDuration = $_.AvgSessionDuration.ToString()
                }
            }
        }
    }
    
    # Save data to JSON file
    $reportData | ConvertTo-Json -Depth 10 | Out-File "AVDUsageData_$(Get-Date -Format 'yyyyMMdd').json"
    
    # Read template
    $template = Get-Content -Path "template.html" -Raw
    
    # Process data for different time ranges
    $monthlyAnalytics = Get-AggregatedData -Data $ReportData.MonthlyMetrics.Stats -TimeRange 'Monthly'
    $weeklyAnalytics = Get-AggregatedData -Data $ReportData.WeeklyMetrics.Stats -TimeRange 'Weekly'
    $dailyAnalytics = Get-AggregatedData -Data $ReportData.DailyMetrics.Stats -TimeRange 'Daily'

    # Generate summary metrics HTML
    $summaryMetrics = @"
        <div class="metric-card">
            <div class="metric-title">Average Monthly Users</div>
            <div class="metric-value">$([math]::Round($avgMonthlyUsers))</div>
        </div>
        <div class="metric-card">
            <div class="metric-title">Average Weekly Users</div>
            <div class="metric-value">$([math]::Round($avgWeeklyUsers, 1))</div>
        </div>
        <div class="metric-card">
            <div class="metric-title">Average Daily Users</div>
            <div class="metric-value">$([math]::Round($avgDailyUsers, 1))</div>
        </div>
        <div class="metric-card">
            <div class="metric-title">Peak Daily Users</div>
            <div class="metric-value">$([math]::Round($peakDailyUsers))</div>
        </div>
"@
    
    # Create monthly statistics table
    $monthlyStatsHtml = @"
        <table>
            <thead>
                <tr>
                    <th>Month</th>
                    <th>Users</th>
                    <th>Active Sessions</th>
                    <th>Completed Sessions</th>
                    <th>Total Sessions</th>
                    <th>Unique Clients</th>
                    <th>Unique Hosts</th>
                    <th>Avg Session Duration</th>
                </tr>
            </thead>
            <tbody>$(
        $monthlyMetrics.Values | Sort-Object PeriodName | ForEach-Object {
            "                <tr>
                    <td>$($_.PeriodName)</td>
                    <td>$($_.Users)</td>
                    <td>$($_.ActiveSessions)</td>
                    <td>$($_.CompletedSessions)</td>
                    <td>$($_.TotalSessions)</td>
                    <td>$($_.UniqueClients)</td>
                    <td>$($_.UniqueHosts)</td>
                    <td class=`"session-duration`">$($_.AvgSessionDuration)</td>
                </tr>"
        })
            </tbody>
        </table>
"@
    
    # Create weekly statistics table
    $weeklyStatsHtml = @"
        <table>
            <thead>
                <tr>
                    <th>Week</th>
                    <th>Users</th>
                    <th>Active Sessions</th>
                    <th>Completed Sessions</th>
                    <th>Total Sessions</th>
                    <th>Unique Hosts</th>
                    <th>Avg Session Duration</th>
                </tr>
            </thead>
            <tbody>$(
        $weeklyMetrics.Values | Sort-Object PeriodName | ForEach-Object {
            "                <tr>
                    <td>$($_.PeriodName)</td>
                    <td>$($_.Users)</td>
                    <td>$($_.ActiveSessions)</td>
                    <td>$($_.CompletedSessions)</td>
                    <td>$($_.TotalSessions)</td>
                    <td>$($_.UniqueHosts)</td>
                    <td class=`"session-duration`">$($_.AvgSessionDuration)</td>
                </tr>"
        })
            </tbody>
        </table>
"@
    
    # Create daily statistics table (last 7 days)
    $dailyStatsHtml = @"
        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Users</th>
                    <th>Active Sessions</th>
                    <th>Completed Sessions</th>
                    <th>Total Sessions</th>
                    <th>Unique Clients</th>
                    <th>Avg Session Duration</th>
                </tr>
            </thead>
            <tbody>$(
        $dailyMetrics.Values | Sort-Object PeriodName -Descending | Select-Object -First 7 | ForEach-Object {
            "                <tr>
                    <td>$($_.PeriodName)</td>
                    <td>$($_.Users)</td>
                    <td>$($_.ActiveSessions)</td>
                    <td>$($_.CompletedSessions)</td>
                    <td>$($_.TotalSessions)</td>
                    <td>$($_.UniqueClients)</td>
                    <td class=`"session-duration`">$($_.AvgSessionDuration)</td>
                </tr>"
        })
            </tbody>
        </table>
"@
    
    # Format chart data
    $monthlyChartData = @{
        transportTypes = Format-ChartData -distributions $transportTypesDist
        gatewayRegions = Format-ChartData -distributions $gatewayRegionsDist
        clientTypes    = Format-ChartData -distributions $clientTypesDist
        clientOSs      = Format-ChartData -distributions $clientOSDist
    }
    
    $weeklyChartData = @{
        transportTypes = Format-ChartData -distributions (Get-DistributionPercentages -items ($weeklyMetrics.Values.TransportTypes | ForEach-Object { $_ }))
        gatewayRegions = Format-ChartData -distributions (Get-DistributionPercentages -items ($weeklyMetrics.Values.GatewayRegions | ForEach-Object { $_ }))
        clientTypes    = Format-ChartData -distributions (Get-DistributionPercentages -items ($weeklyMetrics.Values.ClientTypes | ForEach-Object { $_ }))
        clientOSs      = Format-ChartData -distributions (Get-DistributionPercentages -items ($weeklyMetrics.Values.ClientOSs | ForEach-Object { $_ }))
    }
    
    $dailyChartData = @{
        transportTypes = Format-ChartData -distributions (Get-DistributionPercentages -items ($dailyMetrics.Values | Select-Object -Last 7).TransportTypes)
        gatewayRegions = Format-ChartData -distributions (Get-DistributionPercentages -items ($dailyMetrics.Values | Select-Object -Last 7).GatewayRegions)
        clientTypes    = Format-ChartData -distributions (Get-DistributionPercentages -items ($dailyMetrics.Values | Select-Object -Last 7).ClientTypes)
        clientOSs      = Format-ChartData -distributions (Get-DistributionPercentages -items ($dailyMetrics.Values | Select-Object -Last 7).ClientOSs)
    }
    
    # Create chart data JavaScript
    $chartDataJs = @"
        const monthlyData = {
            transportTypes: {
                labels: $(ConvertTo-Json @($monthlyChartData.transportTypes.labels)),
                data: $(ConvertTo-Json @($monthlyChartData.transportTypes.data))
            },
            gatewayRegions: {
                labels: $(ConvertTo-Json @($monthlyChartData.gatewayRegions.labels)),
                data: $(ConvertTo-Json @($monthlyChartData.gatewayRegions.data))
            },
            clientTypes: {
                labels: $(ConvertTo-Json @($monthlyChartData.clientTypes.labels)),
                data: $(ConvertTo-Json @($monthlyChartData.clientTypes.data))
            },
            clientOSs: {
                labels: $(ConvertTo-Json @($monthlyChartData.clientOSs.labels)),
                data: $(ConvertTo-Json @($monthlyChartData.clientOSs.data))
            }
        };

        const weeklyData = {
            transportTypes: {
                labels: $(ConvertTo-Json @($weeklyChartData.transportTypes.labels)),
                data: $(ConvertTo-Json @($weeklyChartData.transportTypes.data))
            },
            gatewayRegions: {
                labels: $(ConvertTo-Json @($weeklyChartData.gatewayRegions.labels)),
                data: $(ConvertTo-Json @($weeklyChartData.gatewayRegions.data))
            },
            clientTypes: {
                labels: $(ConvertTo-Json @($weeklyChartData.clientTypes.labels)),
                data: $(ConvertTo-Json @($weeklyChartData.clientTypes.data))
            },
            clientOSs: {
                labels: $(ConvertTo-Json @($weeklyChartData.clientOSs.labels)),
                data: $(ConvertTo-Json @($weeklyChartData.clientOSs.data))
            }
        };

        const dailyData = {
            transportTypes: {
                labels: $(ConvertTo-Json @($dailyChartData.transportTypes.labels)),
                data: $(ConvertTo-Json @($dailyChartData.transportTypes.data))
            },
            gatewayRegions: {
                labels: $(ConvertTo-Json @($dailyChartData.gatewayRegions.labels)),
                data: $(ConvertTo-Json @($dailyChartData.gatewayRegions.data))
            },
            clientTypes: {
                labels: $(ConvertTo-Json @($dailyChartData.clientTypes.labels)),
                data: $(ConvertTo-Json @($dailyChartData.clientTypes.data))
            },
            clientOSs: {
                labels: $(ConvertTo-Json @($dailyChartData.clientOSs.labels)),
                data: $(ConvertTo-Json @($dailyChartData.clientOSs.data))
            }
        };
"@

    # Generate chart functions
    $chartFunctions = @"
        let charts = {
            transportTypes: null,
            gatewayRegions: null,
            clientTypes: null,
            clientOS: null
        };

        const chartOptions = {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'right',
                    labels: {
                        boxWidth: 12,
                        padding: 10,
                        font: {
                            size: 11
                        }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            let label = context.label || '';
                            let value = context.raw || 0;
                            let total = context.dataset.data.reduce((a, b) => a + b, 0);
                            let percentage = ((value / total) * 100).toFixed(1);
                            return `${label}: ${value} (${percentage}%)`;
                        }
                    }
                }
            }
        };

        function createChart(id, data, labels) {
            return new Chart(document.getElementById(id), {
                type: 'pie',
                data: {
                    labels: labels,
                    datasets: [{
                        data: data,
                        backgroundColor: [
                            '#1B9CB9', '#D7DF23', '#13BA7C', '#1D3557', '#FF6B6B',
                            '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEEAD', '#FF9F1C'
                        ]
                    }]
                },
                options: chartOptions
            });
        }

        function updateCharts(timeRange) {
            const data = timeRange === 'weekly' ? weeklyData :
                        timeRange === 'daily' ? dailyData : monthlyData;

            // Update time range description
            const timeDesc = timeRange === 'weekly' ? 'Last 4 Weeks' :
                           timeRange === 'daily' ? 'Last 7 Days' : 'Last 3 Months';
            document.querySelector('.chart-info').textContent = `Data shown for ${timeDesc}`;

            // Destroy existing charts
            Object.values(charts).forEach(chart => chart?.destroy());

            // Create new charts
            charts.transportTypes = createChart('transportTypesChart', 
                data.transportTypes.data, data.transportTypes.labels);
            charts.gatewayRegions = createChart('gatewayRegionsChart',
                data.gatewayRegions.data, data.gatewayRegions.labels);
            charts.clientTypes = createChart('clientTypesChart',
                data.clientTypes.data, data.clientTypes.labels);
            charts.clientOS = createChart('clientOSChart',
                data.clientOSs.data, data.clientOSs.labels);
        }

        // Initialize charts with monthly data
        updateCharts('monthly');
"@
    
    # Replace placeholders in template
    $html = $template
    $html = $html.Replace('{TITLE}', $Title)
    $html = $html.Replace('{LOGO_URL}', $LogoUrl)
    $html = $html.Replace('{TIME_RANGE}', $ReportData.TimeRange)
    $html = $html.Replace('{HOST_POOL}', $ReportData.HostPoolName)
    $html = $html.Replace('{SUMMARY_METRICS}', $summaryMetrics)
    $html = $html.Replace('{MONTHLY_STATS}', $monthlyStats)
    $html = $html.Replace('{WEEKLY_STATS}', $weeklyStats)
    $html = $html.Replace('{DAILY_STATS}', $dailyStats)
    $html = $html.Replace('{CHART_DATA}', $chartData)
    $html = $html.Replace('{CHART_FUNCTIONS}', $chartFunctions)

    return $html
}
catch {
    Write-Error "Error generating report: $_"
    return
}

function GetMAU {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
    
        [Parameter(Mandatory = $true)]
        [string]$HostPoolName,
    
        [Parameter(Mandatory = $true)]
        [int]$DaysToAnalyze = 30
    )

    # First verify Azure connection
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Error "Not connected to Azure. Please run Connect-AzAccount first."
            return
        }
        Write-Verbose "Connected to Azure subscription: $($context.Subscription.Name)"
    }
    catch {
        Write-Error "Error checking Azure connection: $_"
        return
    }

    # Verify workspace exists
    try {
        $workspace = Get-AzOperationalInsightsWorkspace | Where-Object { $_.CustomerId -eq $WorkspaceId }
        if (-not $workspace) {
            Write-Error "Could not find Log Analytics workspace with ID: $WorkspaceId"
            return
        }
        Write-Verbose "Found workspace: $($workspace.Name)"
    }
    catch {
        Write-Error "Error checking workspace: $_"
        return
    }

    # Connect to Log Analytics
    $startDate = (Get-Date).AddDays(-$DaysToAnalyze)
    $endDate = Get-Date

    # Query to get unique daily users with enhanced connection details
    $dailyQuery = @"
// First calculate session durations
let SessionDurations = WVDConnections
| where TimeGenerated between (datetime('$($startDate.ToString("yyyy-MM-dd"))') .. datetime('$($endDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| summarize StartTime = min(iff(State == 'Connected', TimeGenerated, datetime(null))), 
            EndTime = max(iff(State == 'Completed', TimeGenerated, datetime(null))) 
            by CorrelationId
| extend SessionDuration = EndTime - StartTime
| where SessionDuration > 0s;  // Filter out invalid durations
// Main query with all metrics
WVDConnections
| where TimeGenerated between (datetime('$($startDate.ToString("yyyy-MM-dd"))') .. datetime('$($endDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| extend Date = format_datetime(TimeGenerated, 'yyyy-MM-dd')
| summarize 
    DailyUsers = dcount(UserName),
    ActiveSessions = countif(State == "Connected"),
    CompletedSessions = countif(State == "Completed"),
    TotalSessions = count(),
    UniqueClients = dcount(ClientSideIPAddress),
    UniqueHosts = dcount(SessionHostName),
    ClientOSs = make_set(ClientOS),
    ClientTypes = make_set(strcat(ClientType, " (", ClientVersion, ")")),
    TransportTypes = make_set(TransportType),
    GatewayRegions = make_set(GatewayRegion)
    by Date
| join kind=leftouter (
    SessionDurations
    | extend Date = format_datetime(StartTime, 'yyyy-MM-dd')
    | summarize AvgSessionDuration = avg(SessionDuration) by Date
) on Date
| sort by Date asc
"@

    # Query for weekly metrics
    $weeklyQuery = @"
// First calculate session durations
let SessionDurations = WVDConnections
| where TimeGenerated between (datetime('$($startDate.ToString("yyyy-MM-dd"))') .. datetime('$($endDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| summarize StartTime = min(iff(State == 'Connected', TimeGenerated, datetime(null))), 
            EndTime = max(iff(State == 'Completed', TimeGenerated, datetime(null))) 
            by CorrelationId
| extend SessionDuration = EndTime - StartTime
| where SessionDuration > 0s;  // Filter out invalid durations
// Main query with all metrics
WVDConnections
| where TimeGenerated between (datetime('$($startDate.ToString("yyyy-MM-dd"))') .. datetime('$($endDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| extend WeekNumber = week_of_year(TimeGenerated)
| extend Week = strcat(format_datetime(TimeGenerated, 'yyyy'), '-W', iff(WeekNumber < 10, strcat('0', WeekNumber), tostring(WeekNumber)))
| summarize 
    WeeklyUsers = dcount(UserName),
    ActiveSessions = countif(State == "Connected"),
    CompletedSessions = countif(State == "Completed"),
    TotalSessions = count(),
    UniqueHosts = dcount(SessionHostName),
    ClientOSs = make_set(ClientOS),
    ClientTypes = make_set(strcat(ClientType, " (", ClientVersion, ")")),
    TransportTypes = make_set(TransportType),
    GatewayRegions = make_set(GatewayRegion)
    by Week
| join kind=leftouter (
    SessionDurations
    | extend WeekNumber = week_of_year(StartTime)
    | extend Week = strcat(format_datetime(StartTime, 'yyyy'), '-W', iff(WeekNumber < 10, strcat('0', WeekNumber), tostring(WeekNumber)))
    | summarize AvgSessionDuration = avg(SessionDuration) by Week
) on Week
| sort by Week asc
"@

    # Query for monthly metrics
    $monthlyQuery = @"
// First calculate session durations
let SessionDurations = WVDConnections
| where TimeGenerated between (datetime('$($startDate.ToString("yyyy-MM-dd"))') .. datetime('$($endDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| summarize StartTime = min(iff(State == 'Connected', TimeGenerated, datetime(null))), 
            EndTime = max(iff(State == 'Completed', TimeGenerated, datetime(null))) 
            by CorrelationId
| extend SessionDuration = EndTime - StartTime
| where SessionDuration > 0s;  // Filter out invalid durations
// Main query with all metrics
WVDConnections
| where TimeGenerated between (datetime('$($startDate.ToString("yyyy-MM-dd"))') .. datetime('$($endDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| extend Month = format_datetime(TimeGenerated, 'yyyy-MM')
| summarize 
    MonthlyUsers = dcount(UserName),
    ActiveSessions = countif(State == "Connected"),
    CompletedSessions = countif(State == "Completed"),
    TotalSessions = count(),
    UniqueClients = dcount(ClientSideIPAddress),
    UniqueHosts = dcount(SessionHostName),
    ClientOSs = make_set(ClientOS),
    ClientTypes = make_set(strcat(ClientType, " (", ClientVersion, ")")),
    TransportTypes = make_set(TransportType),
    GatewayRegions = make_set(GatewayRegion)
    by Month
| join kind=leftouter (
    SessionDurations
    | extend Month = format_datetime(StartTime, 'yyyy-MM')
    | summarize AvgSessionDuration = avg(SessionDuration) by Month
) on Month
| sort by Month asc
"@

    # Execute queries with error handling
    try {
        Write-Verbose "Executing daily query..."
        $dailyStats = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $dailyQuery -ErrorAction Stop
        $dailyResultsArray = [System.Linq.Enumerable]::ToArray($dailyStats.Results)

        if (-not $dailyStats -or -not $dailyStats.Results) {
            Write-Warning "Daily query returned no results"
        }
        else {
            Write-Verbose "Daily query returned $($dailyStats.Results.Count) results"
        }

        Write-Verbose "Executing weekly query..."
        $weeklyStats = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $weeklyQuery -ErrorAction Stop
        $weeklyResultsArray = [System.Linq.Enumerable]::ToArray($weeklyStats.Results)
        if (-not $weeklyStats -or -not $weeklyStats.Results) {
            Write-Warning "Weekly query returned no results"
        }
        else {
            Write-Verbose "Weekly query returned $($weeklyStats.Results.Count) results"
        }

        Write-Verbose "Executing monthly query..."
        $monthlyStats = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $monthlyQuery -ErrorAction Stop
        $monthlyResultsArray = [System.Linq.Enumerable]::ToArray($monthlyStats.Results)
        if (-not $monthlyStats -or -not $monthlyStats.Results) {
            Write-Warning "Monthly query returned no results"
        }
        else {
            Write-Verbose "Monthly query returned $($monthlyStats.Results.Count) results"
        }
    }
    catch {
        Write-Error "Error executing queries: $_"
        Write-Verbose "Full error details: $($_.Exception.Message)"
        return
    }

    # Calculate additional metrics
    $results = @{
        HostPoolName   = $HostPoolName
        TimeRange      = "$($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))"
    
        DailyMetrics   = @{
            Stats             = $dailyStats.Results
            AverageDailyUsers = ($dailyStats.Results | Measure-Object -Property DailyUsers -Average).Average
            PeakDailyUsers    = ($dailyStats.Results | Measure-Object -Property DailyUsers -Maximum).Maximum
            TrendAnalysis     = $dailyStats.Results | Sort-Object Date | Select-Object -Last 7
        }
    
        WeeklyMetrics  = @{
            Stats              = $weeklyStats.Results
            AverageWeeklyUsers = ($weeklyStats.Results | Measure-Object -Property WeeklyUsers -Average).Average
            PeakWeeklySessions = ($weeklyStats.Results | Measure-Object -Property PeakConcurrentSessions -Maximum).Maximum
        }
    
        MonthlyMetrics = @{
            Stats               = $monthlyStats.Results
            AverageMonthlyUsers = ($monthlyStats.Results | Measure-Object -Property MonthlyUsers -Average).Average
            PerformanceMetrics  = @{
                AvgFrameRate      = ($monthlyStats.Results | Measure-Object -Property AvgFrameRate -Average).Average
                AvgNetworkLatency = ($monthlyStats.Results | Measure-Object -Property AvgNetworkLatency -Average).Average
                AvgBandwidth      = ($monthlyStats.Results | Measure-Object -Property AvgBandwidth -Average).Average
            }
        }
    }

    # Save results
    $reportName = "AVDUsageReport_$(Get-Date -Format 'yyyyMMdd')"
    
    $htmlReport = ConvertTo-StyledHTMLReport -ReportData $results -Title $reportName -Description "Overview of system usage for the current month"
    $htmlReport | Out-File -FilePath "$reportName.html"

    # Export detailed data for further analysis
    $results | ConvertTo-Json -Depth 10 | Out-File "AVDUsageData_$(Get-Date -Format 'yyyyMMdd').json"

    return $results
}

$WorkspaceId = '177678ee-d784-44b9-bebc-0e144b4db4fd'
$HostPoolName = 'nerdio desktop win10'
$DaysToAnalyze = 30

GetMAU -WorkspaceId $WorkspaceId -HostPoolName $HostPoolName -DaysToAnalyze $DaysToAnalyze -Verbose
