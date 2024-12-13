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

    # Generate HTML report with enhanced details
    # Generate HTML report with enhanced details
    $htmlReport = @"
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
                th, td { padding: 8px; text-align: left; border: 1px solid #ddd; }
                th { background-color: #f2f2f2; }
                .metric { font-weight: bold; }
                h1, h2, h3 { color: #333; }
                .details { font-size: 0.9em; color: #666; }
                .section { margin-bottom: 30px; }
                .list-container { margin: 10px 0; }
                .list-item { margin: 5px 0; padding: 5px; background-color: #f9f9f9; }
            </style>
        </head>
        <body>
            <h1>AVD Host Pool Usage Report - $($results.HostPoolName)</h1>
            <h2>Time Range: $($results.TimeRange)</h2>
            
            <div class="section">
                <h3>Monthly Summary</h3>
                <table>
                    <tr>
                        <th>Metric</th>
                        <th>Value</th>
                    </tr>
                    $(foreach ($month in $monthlyResultsArray) {
                        @"
                        <tr><td>Monthly Users</td><td>$($month.MonthlyUsers)</td></tr>
                        <tr><td>Active Sessions</td><td>$($month.ActiveSessions)</td></tr>
                        <tr><td>Completed Sessions</td><td>$($month.CompletedSessions)</td></tr>
                        <tr><td>Total Sessions</td><td>$($month.TotalSessions)</td></tr>
                        <tr><td>Unique Clients</td><td>$($month.UniqueClients)</td></tr>
                        <tr><td>Unique Hosts</td><td>$($month.UniqueHosts)</td></tr>
                        <tr><td>Average Session Duration</td><td>$($month.AvgSessionDuration)</td></tr>
"@
                    })
                </table>
            </div>
        
            <div class="section">
                <h3>Weekly Trends</h3>
                <table>
                    <tr>
                        <th>Week</th>
                        <th>Users</th>
                        <th>Active Sessions</th>
                        <th>Completed Sessions</th>
                        <th>Total Sessions</th>
                        <th>Unique Hosts</th>
                        <th>Avg Session Duration</th>
                    </tr>
                    $(foreach ($week in $weeklyResultsArray) {
                        "<tr>
                            <td>$($week.Week)</td>
                            <td>$($week.WeeklyUsers)</td>
                            <td>$($week.ActiveSessions)</td>
                            <td>$($week.CompletedSessions)</td>
                            <td>$($week.TotalSessions)</td>
                            <td>$($week.UniqueHosts)</td>
                            <td>$($week.AvgSessionDuration)</td>
                        </tr>"
                    })
                </table>
            </div>
        
            <div class="section">
                <h3>Recent Daily Activity</h3>
                <table>
                    <tr>
                        <th>Date</th>
                        <th>Users</th>
                        <th>Active Sessions</th>
                        <th>Completed Sessions</th>
                        <th>Total Sessions</th>
                        <th>Unique Clients</th>
                        <th>Unique Hosts</th>
                        <th>Avg Session Duration</th>
                    </tr>
                    $(foreach ($day in ($dailyResultsArray | Select-Object -Last 7)) {
                        "<tr>
                            <td>$($day.Date)</td>
                            <td>$($day.DailyUsers)</td>
                            <td>$($day.ActiveSessions)</td>
                            <td>$($day.CompletedSessions)</td>
                            <td>$($day.TotalSessions)</td>
                            <td>$($day.UniqueClients)</td>
                            <td>$($day.UniqueHosts)</td>
                            <td>$($day.AvgSessionDuration)</td>
                        </tr>"
                    })
                </table>
            </div>
        
            <div class="section">
                <h3>Client Details (Last Month)</h3>
                $(foreach ($month in ($monthlyResultsArray | Select-Object -Last 1)) {
                    $clientOSs = $month.ClientOSs | ConvertFrom-Json
                    $clientTypes = $month.ClientTypes | ConvertFrom-Json
                    $transportTypes = $month.TransportTypes | ConvertFrom-Json
                    $gatewayRegions = $month.GatewayRegions | ConvertFrom-Json
        
                    @"
                    <h4>Operating Systems</h4>
                    <div class="list-container">
                        $(foreach ($os in $clientOSs) {
                            "<div class='list-item'>$os</div>"
                        })
                    </div>
        
                    <h4>Client Types</h4>
                    <div class="list-container">
                        $(foreach ($client in $clientTypes) {
                            "<div class='list-item'>$client</div>"
                        })
                    </div>
        
                    <h4>Transport Types</h4>
                    <div class="list-container">
                        $(foreach ($transport in $transportTypes) {
                            "<div class='list-item'>$transport</div>"
                        })
                    </div>
        
                    <h4>Gateway Regions</h4>
                    <div class="list-container">
                        $(foreach ($region in $gatewayRegions) {
                            "<div class='list-item'>$region</div>"
                        })
                    </div>
"@
                })
            </div>
        </body>
        </html>
"@

    # Save results
    $reportPath = "AVDUsageReport_$(Get-Date -Format 'yyyyMMdd').html"
    $htmlReport | Out-File -FilePath $reportPath

    # Export detailed data for further analysis
    $results | ConvertTo-Json -Depth 10 | Out-File "AVDUsageData_$(Get-Date -Format 'yyyyMMdd').json"

    return $results
}




$WorkspaceId = '177678ee-d784-44b9-bebc-0e144b4db4fd'
$HostPoolName = 'nerdio desktop win10'
$DaysToAnalyze = 30

GetMAU -WorkspaceId $WorkspaceId -HostPoolName $HostPoolName -DaysToAnalyze $DaysToAnalyze -Verbose

