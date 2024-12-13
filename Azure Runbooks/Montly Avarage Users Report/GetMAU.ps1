function Get-AggregatedData {
    param (
        [Parameter(Mandatory = $true)]
        [Object[]]$Data,
        [string]$TimeRange = 'Monthly'
    )

    # Helper function to process arrays and count occurrences
    function Process-ArrayData {
        param (
            [Object[]]$Items,
            [string]$JsonProperty
        )
        
        $allItems = @{}
        foreach ($item in $Items) {
            $values = $item.$JsonProperty | ConvertFrom-Json
            $sessionsPerItem = [int]($item.TotalSessions / ($values | Measure-Object).Count)
            foreach ($value in $values) {
                if ($value -eq "<>" -or [string]::IsNullOrWhiteSpace($value)) { continue }
                if ($allItems.ContainsKey($value)) {
                    $allItems[$value] += $sessionsPerItem
                }
                else {
                    $allItems[$value] = $sessionsPerItem
                }
            }
        }

        # Sort by usage count descending and take top 10
        $sortedItems = $allItems.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
        $result = [ordered]@{}
        foreach ($item in $sortedItems) {
            # Truncate long names to improve readability
            $key = $item.Key
            if ($key.Length -gt 50) {
                $key = $key.Substring(0, 47) + "..."
            }
            $result[$key] = $item.Value
        }
        return $result
    }

    # Get the appropriate data based on time range
    $relevantData = switch ($TimeRange) {
        'Daily' { $Data | Sort-Object Date | Select-Object -Last 7 }  # Last 7 days
        'Weekly' { $Data | Sort-Object Week | Select-Object -Last 4 }  # Last 4 weeks
        'Monthly' { $Data | Sort-Object Month | Select-Object -Last 3 }  # Last 3 months
        default { $Data | Sort-Object Month | Select-Object -Last 3 }
    }

    # Process each type of data
    $gatewayRegions = Process-ArrayData -Items $relevantData -JsonProperty 'GatewayRegions'
    $transportTypes = Process-ArrayData -Items $relevantData -JsonProperty 'TransportTypes'
    $clientTypes = Process-ArrayData -Items $relevantData -JsonProperty 'ClientTypes'
    $clientOSs = Process-ArrayData -Items $relevantData -JsonProperty 'ClientOSs'

    # Calculate time range description
    $timeDesc = switch ($TimeRange) {
        'Daily' { 
            $start = ($relevantData | Select-Object -First 1).Date
            $end = ($relevantData | Select-Object -Last 1).Date
            "Daily view ($start to $end)" 
        }
        'Weekly' { 
            $start = ($relevantData | Select-Object -First 1).Week
            $end = ($relevantData | Select-Object -Last 1).Week
            "Weekly view ($start to $end)" 
        }
        'Monthly' { 
            $start = ($relevantData | Select-Object -First 1).Month
            $end = ($relevantData | Select-Object -Last 1).Month
            "Monthly view ($start to $end)" 
        }
    }

    return @{
        GatewayRegions = $gatewayRegions
        TransportTypes = $transportTypes
        ClientTypes = $clientTypes
        ClientOSs = $clientOSs
        TimeRange = $timeDesc
    }
}

function ConvertTo-StyledHTMLReport {
    param (
        [Parameter(Mandatory = $true)]
        [Object]$ReportData,
        [string]$Title = "Report",
        [string]$Description = "",
        [string]$LogoUrl = "https://raw.githubusercontent.com/Get-Nerdio/NMM-SE/main/Azure%20Runbooks/Montly%20Avarage%20Users%20Report/Static/NerrdioMSPLogo.png"
    )

    # Read HTML template
    $template = Get-Content -Path "template.html" -Raw

    # Process data for different time ranges
    $monthlyAnalytics = Get-AggregatedData -Data $ReportData.MonthlyMetrics.Stats -TimeRange 'Monthly'
    $weeklyAnalytics = Get-AggregatedData -Data $ReportData.WeeklyMetrics.Stats -TimeRange 'Weekly'
    $dailyAnalytics = Get-AggregatedData -Data $ReportData.DailyMetrics.Stats -TimeRange 'Daily'

    # Generate summary metrics HTML
    $summaryMetrics = @"
        <div class="metric-card">
            <div class="metric-title">Average Monthly Users</div>
            <div class="metric-value">$([math]::Round($ReportData.MonthlyMetrics.AverageMonthlyUsers, 1))</div>
        </div>
        <div class="metric-card">
            <div class="metric-title">Average Weekly Users</div>
            <div class="metric-value">$([math]::Round($ReportData.WeeklyMetrics.AverageWeeklyUsers, 1))</div>
        </div>
        <div class="metric-card">
            <div class="metric-title">Average Daily Users</div>
            <div class="metric-value">$([math]::Round($ReportData.DailyMetrics.AverageDailyUsers, 1))</div>
        </div>
        <div class="metric-card">
            <div class="metric-title">Peak Daily Users</div>
            <div class="metric-value">$([math]::Round($ReportData.DailyMetrics.PeakDailyUsers, 1))</div>
        </div>
"@

    # Generate monthly stats table
    $monthlyStats = @"
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
            <tbody>
"@
    foreach ($stat in $ReportData.MonthlyMetrics.Stats) {
        $monthlyStats += @"
                <tr>
                    <td>$($stat.Month)</td>
                    <td>$($stat.MonthlyUsers)</td>
                    <td>$($stat.ActiveSessions)</td>
                    <td>$($stat.CompletedSessions)</td>
                    <td>$($stat.TotalSessions)</td>
                    <td>$($stat.UniqueClients)</td>
                    <td>$($stat.UniqueHosts)</td>
                    <td class="session-duration">$($stat.AvgSessionDuration)</td>
                </tr>
"@
    }
    $monthlyStats += @"
            </tbody>
        </table>
"@

    # Generate weekly stats table
    $weeklyStats = @"
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
            <tbody>
"@
    foreach ($stat in $ReportData.WeeklyMetrics.Stats) {
        $weeklyStats += @"
                <tr>
                    <td>$($stat.Week)</td>
                    <td>$($stat.WeeklyUsers)</td>
                    <td>$($stat.ActiveSessions)</td>
                    <td>$($stat.CompletedSessions)</td>
                    <td>$($stat.TotalSessions)</td>
                    <td>$($stat.UniqueHosts)</td>
                    <td class="session-duration">$($stat.AvgSessionDuration)</td>
                </tr>
"@
    }
    $weeklyStats += @"
            </tbody>
        </table>
"@

    # Generate daily stats table
    $dailyStats = @"
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
            <tbody>
"@
    foreach ($stat in $ReportData.DailyMetrics.TrendAnalysis) {
        $dailyStats += @"
                <tr>
                    <td>$($stat.Date)</td>
                    <td>$($stat.DailyUsers)</td>
                    <td>$($stat.ActiveSessions)</td>
                    <td>$($stat.CompletedSessions)</td>
                    <td>$($stat.TotalSessions)</td>
                    <td>$($stat.UniqueClients)</td>
                    <td class="session-duration">$($stat.AvgSessionDuration)</td>
                </tr>
"@
    }
    $dailyStats += @"
            </tbody>
        </table>
"@

    # Generate chart data
    $chartData = @"
        const monthlyData = {
            transportTypes: {
                labels: $($monthlyAnalytics.TransportTypes.Keys | ConvertTo-Json -Compress),
                data: $($monthlyAnalytics.TransportTypes.Values | ConvertTo-Json -Compress)
            },
            gatewayRegions: {
                labels: $($monthlyAnalytics.GatewayRegions.Keys | ConvertTo-Json -Compress),
                data: $($monthlyAnalytics.GatewayRegions.Values | ConvertTo-Json -Compress)
            },
            clientTypes: {
                labels: $($monthlyAnalytics.ClientTypes.Keys | ConvertTo-Json -Compress),
                data: $($monthlyAnalytics.ClientTypes.Values | ConvertTo-Json -Compress)
            },
            clientOSs: {
                labels: $($monthlyAnalytics.ClientOSs.Keys | ConvertTo-Json -Compress),
                data: $($monthlyAnalytics.ClientOSs.Values | ConvertTo-Json -Compress)
            }
        };

        const weeklyData = {
            transportTypes: {
                labels: $($weeklyAnalytics.TransportTypes.Keys | ConvertTo-Json -Compress),
                data: $($weeklyAnalytics.TransportTypes.Values | ConvertTo-Json -Compress)
            },
            gatewayRegions: {
                labels: $($weeklyAnalytics.GatewayRegions.Keys | ConvertTo-Json -Compress),
                data: $($weeklyAnalytics.GatewayRegions.Values | ConvertTo-Json -Compress)
            },
            clientTypes: {
                labels: $($weeklyAnalytics.ClientTypes.Keys | ConvertTo-Json -Compress),
                data: $($weeklyAnalytics.ClientTypes.Values | ConvertTo-Json -Compress)
            },
            clientOSs: {
                labels: $($weeklyAnalytics.ClientOSs.Keys | ConvertTo-Json -Compress),
                data: $($weeklyAnalytics.ClientOSs.Values | ConvertTo-Json -Compress)
            }
        };

        const dailyData = {
            transportTypes: {
                labels: $($dailyAnalytics.TransportTypes.Keys | ConvertTo-Json -Compress),
                data: $($dailyAnalytics.TransportTypes.Values | ConvertTo-Json -Compress)
            },
            gatewayRegions: {
                labels: $($dailyAnalytics.GatewayRegions.Keys | ConvertTo-Json -Compress),
                data: $($dailyAnalytics.GatewayRegions.Values | ConvertTo-Json -Compress)
            },
            clientTypes: {
                labels: $($dailyAnalytics.ClientTypes.Keys | ConvertTo-Json -Compress),
                data: $($dailyAnalytics.ClientTypes.Values | ConvertTo-Json -Compress)
            },
            clientOSs: {
                labels: $($dailyAnalytics.ClientOSs.Keys | ConvertTo-Json -Compress),
                data: $($dailyAnalytics.ClientOSs.Values | ConvertTo-Json -Compress)
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
