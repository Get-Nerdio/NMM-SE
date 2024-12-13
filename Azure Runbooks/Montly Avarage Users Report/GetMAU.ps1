function ConvertTo-StyledHTMLReport {
    param (
        [Parameter(Mandatory = $true)]
        [Object]$ReportData,
        [string]$Title = "Report",
        [string]$Description = "",
        [string]$LogoUrl = "https://raw.githubusercontent.com/Get-Nerdio/NMM-SE/main/Azure%20Runbooks/Montly%20Avarage%20Users%20Report/Static/NerrdioMSPLogo.png"
    )

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Title</title>
    <style>
        :root {
            --nerdio-blue: #1B9CB9;
            --nerdio-dark-blue: #1D3557;
            --nerdio-yellow: #D7DF23;
            --nerdio-green: #13BA7C;
            --nerdio-white: #FFFFFF;
            --nerdio-black: #151515;
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }

        body {
            background-color: #f5f5f5;
            color: var(--nerdio-black);
            line-height: 1.6;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }

        .header {
            background-color: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .logo {
            height: 50px;
            width: auto;
        }

        .title-section {
            text-align: right;
        }

        h1, h2 {
            color: var(--nerdio-dark-blue);
            margin-bottom: 10px;
        }

        .description {
            color: #666;
            margin-bottom: 20px;
        }

        .metrics-summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .metric-card {
            background-color: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        .metric-title {
            color: var(--nerdio-blue);
            font-size: 1.1em;
            margin-bottom: 10px;
        }

        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: var(--nerdio-dark-blue);
        }

        .section {
            background-color: white;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 30px;
            padding: 20px;
        }

        .section-title {
            color: var(--nerdio-dark-blue);
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid var(--nerdio-blue);
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin: 0;
        }

        th {
            background-color: var(--nerdio-blue);
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 600;
        }

        td {
            padding: 12px 15px;
            border-bottom: 1px solid #eee;
        }

        tr:hover {
            background-color: #f8f9fa;
        }

        .details-button {
            background-color: var(--nerdio-blue);
            color: white;
            border: none;
            padding: 5px 10px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 0.9em;
        }

        .details-content {
            display: none;
            padding: 15px;
            background-color: #f8f9fa;
            border-radius: 5px;
            margin-top: 10px;
        }

        .details-list {
            list-style: none;
            margin: 0;
            padding: 0;
        }

        .details-list li {
            padding: 5px 0;
            border-bottom: 1px solid #eee;
        }

        @media (max-width: 768px) {
            .header {
                flex-direction: column;
                text-align: center;
            }

            .logo {
                margin-bottom: 15px;
            }

            .title-section {
                text-align: center;
            }

            .metrics-summary {
                grid-template-columns: 1fr;
            }
        }
    </style>
    <script>
        function toggleDetails(buttonId) {
            const content = document.getElementById('content-' + buttonId);
            const button = document.getElementById('button-' + buttonId);
            if (content.style.display === 'none' || content.style.display === '') {
                content.style.display = 'block';
                button.textContent = 'Hide Details';
            } else {
                content.style.display = 'none';
                button.textContent = 'View Details';
            }
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="$LogoUrl" alt="Nerdio Logo" class="logo">
            <div class="title-section">
                <h1>$Title</h1>
                <p class="description">$($ReportData.TimeRange)</p>
                <p class="description">Host Pool: $($ReportData.HostPoolName)</p>
            </div>
        </div>

        <!-- Summary Metrics -->
        <div class="metrics-summary">
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
        </div>

        <!-- Monthly Stats -->
        <div class="section">
            <h2 class="section-title">Monthly Statistics</h2>
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
                        <th>Details</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($stat in $ReportData.MonthlyMetrics.Stats) {
        $detailId = "monthly-$($stat.Month)"
        $html += @"
                    <tr>
                        <td>$($stat.Month)</td>
                        <td>$($stat.MonthlyUsers)</td>
                        <td>$($stat.ActiveSessions)</td>
                        <td>$($stat.CompletedSessions)</td>
                        <td>$($stat.TotalSessions)</td>
                        <td>$($stat.UniqueClients)</td>
                        <td>$($stat.UniqueHosts)</td>
                        <td>
                            <button id="button-$detailId" class="details-button" onclick="toggleDetails('$detailId')">View Details</button>
                            <div id="content-$detailId" class="details-content">
                                <h4>Average Session Duration: $($stat.AvgSessionDuration)</h4>
                                <h4>Client Operating Systems:</h4>
                                <ul class="details-list">
                                    $(($stat.ClientOSs | ConvertFrom-Json | ForEach-Object { "<li>$_</li>" }) -join '')
                                </ul>
                            </div>
                        </td>
                    </tr>
"@
    }

    $html += @"
                </tbody>
            </table>
        </div>

        <!-- Weekly Stats -->
        <div class="section">
            <h2 class="section-title">Weekly Statistics</h2>
            <table>
                <thead>
                    <tr>
                        <th>Week</th>
                        <th>Users</th>
                        <th>Active Sessions</th>
                        <th>Completed Sessions</th>
                        <th>Total Sessions</th>
                        <th>Unique Hosts</th>
                        <th>Details</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($stat in $ReportData.WeeklyMetrics.Stats) {
        $detailId = "weekly-$($stat.Week)"
        $html += @"
                    <tr>
                        <td>$($stat.Week)</td>
                        <td>$($stat.WeeklyUsers)</td>
                        <td>$($stat.ActiveSessions)</td>
                        <td>$($stat.CompletedSessions)</td>
                        <td>$($stat.TotalSessions)</td>
                        <td>$($stat.UniqueHosts)</td>
                        <td>
                            <button id="button-$detailId" class="details-button" onclick="toggleDetails('$detailId')">View Details</button>
                            <div id="content-$detailId" class="details-content">
                                <h4>Average Session Duration: $($stat.AvgSessionDuration)</h4>
                                <h4>Transport Types:</h4>
                                <ul class="details-list">
                                    $(($stat.TransportTypes | ConvertFrom-Json | ForEach-Object { "<li>$_</li>" }) -join '')
                                </ul>
                            </div>
                        </td>
                    </tr>
"@
    }

    $html += @"
                </tbody>
            </table>
        </div>

        <!-- Daily Stats -->
        <div class="section">
            <h2 class="section-title">Daily Statistics (Last 7 Days)</h2>
            <table>
                <thead>
                    <tr>
                        <th>Date</th>
                        <th>Users</th>
                        <th>Active Sessions</th>
                        <th>Completed Sessions</th>
                        <th>Total Sessions</th>
                        <th>Unique Clients</th>
                        <th>Details</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($stat in $ReportData.DailyMetrics.TrendAnalysis) {
        $detailId = "daily-$($stat.Date)"
        $html += @"
                    <tr>
                        <td>$($stat.Date)</td>
                        <td>$($stat.DailyUsers)</td>
                        <td>$($stat.ActiveSessions)</td>
                        <td>$($stat.CompletedSessions)</td>
                        <td>$($stat.TotalSessions)</td>
                        <td>$($stat.UniqueClients)</td>
                        <td>
                            <button id="button-$detailId" class="details-button" onclick="toggleDetails('$detailId')">View Details</button>
                            <div id="content-$detailId" class="details-content">
                                <h4>Average Session Duration: $($stat.AvgSessionDuration)</h4>
                                <h4>Gateway Regions:</h4>
                                <ul class="details-list">
                                    $(($stat.GatewayRegions | ConvertFrom-Json | ForEach-Object { "<li>$_</li>" }) -join '')
                                </ul>
                            </div>
                        </td>
                    </tr>
"@
    }

    $html += @"
                </tbody>
            </table>
        </div>
    </div>
</body>
</html>
"@

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
