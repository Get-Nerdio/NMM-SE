function ConvertTo-HTMLReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$ReportData,
        
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    
    try {
        Write-Verbose "Starting HTML report generation..."
        
        # Read template and scripts
        $templatePath = Join-Path $PSScriptRoot ".." "template.html"
        $chartConfigPath = Join-Path $PSScriptRoot ".." "Scripts" "chartConfig.js"
        $chartFunctionsPath = Join-Path $PSScriptRoot ".." "Scripts" "chartFunctions.js"
        $chartDataPath = Join-Path $PSScriptRoot ".." "Scripts" "chartData.js"
        $configPath = Join-Path $PSScriptRoot ".." "Config" "config.json"

        Write-Verbose "Reading template, scripts, and config..."
        if (-not (Test-Path $templatePath)) { throw "Template file not found at: $templatePath" }
        if (-not (Test-Path $chartConfigPath)) { throw "Chart config file not found at: $chartConfigPath" }
        if (-not (Test-Path $chartFunctionsPath)) { throw "Chart functions file not found at: $chartFunctionsPath" }
        if (-not (Test-Path $chartDataPath)) { throw "Chart data file not found at: $chartDataPath" }
        if (-not (Test-Path $configPath)) { throw "Config file not found at: $configPath" }

        $template = Get-Content -Path $templatePath -Raw
        $chartConfig = Get-Content -Path $chartConfigPath -Raw
        $chartFunctions = Get-Content -Path $chartFunctionsPath -Raw
        $chartDataTemplate = Get-Content -Path $chartDataPath -Raw
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

        # Get logo URL from config
        $logoUrl = if ($config.LogoUrl) { 
            $config.LogoUrl 
        } else {
            Write-Warning "Logo URL not found in config, using default path"
            Join-Path $PSScriptRoot ".." "Static" "NerrdioMSPLogo.png"
        }
        Write-Verbose "Using logo URL: $logoUrl"

        # Process metrics for different time ranges
        Write-Verbose "Processing metrics for charts..."
        $monthlyAnalytics = Process-MetricsForCharts -Stats $ReportData.MonthlyMetrics.Stats
        $weeklyAnalytics = Process-MetricsForCharts -Stats $ReportData.WeeklyMetrics.Stats
        $dailyAnalytics = Process-MetricsForCharts -Stats $ReportData.DailyMetrics.Stats

        # Generate summary metrics HTML
        Write-Verbose "Generating summary metrics..."
        $summaryMetrics = @"
        <div class="metric-card">
            <div class="metric-title">Average Monthly Users</div>
            <div class="metric-value">$([math]::Round($ReportData.MonthlyMetrics.AverageMonthlyUsers))</div>
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
            <div class="metric-value">$([math]::Round($ReportData.DailyMetrics.PeakDailyUsers))</div>
        </div>
"@

        # Generate analytics summaries
        Write-Verbose "Generating analytics summaries..."
        $transportTypesSummary = ($monthlyAnalytics.transportTypes.labels | ForEach-Object -Begin {$i = 0} -Process {
            "<div class='analytics-list-item'>
                <span class='analytics-label'>$_</span>
                <span class='analytics-value'>$($monthlyAnalytics.transportTypes.data[$i].ToString('N1'))%</span>
            </div>"
            $i++
        }) -join "`n"

        $gatewayRegionsSummary = ($monthlyAnalytics.gatewayRegions.labels | ForEach-Object -Begin {$i = 0} -Process {
            "<div class='analytics-list-item'>
                <span class='analytics-label'>$_</span>
                <span class='analytics-value'>$($monthlyAnalytics.gatewayRegions.data[$i].ToString('N1'))%</span>
            </div>"
            $i++
        }) -join "`n"

        $clientTypesSummary = ($monthlyAnalytics.clientTypes.labels | ForEach-Object -Begin {$i = 0} -Process {
            "<div class='analytics-list-item'>
                <span class='analytics-label'>$_</span>
                <span class='analytics-value'>$($monthlyAnalytics.clientTypes.data[$i].ToString('N1'))%</span>
            </div>"
            $i++
        }) -join "`n"

        $clientOSSummary = ($monthlyAnalytics.clientOSs.labels | ForEach-Object -Begin {$i = 0} -Process {
            "<div class='analytics-list-item'>
                <span class='analytics-label'>$_</span>
                <span class='analytics-value'>$($monthlyAnalytics.clientOSs.data[$i].ToString('N1'))%</span>
            </div>"
            $i++
        }) -join "`n"

        # Create monthly statistics table
        Write-Verbose "Generating monthly statistics table..."
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
            $ReportData.MonthlyMetrics.Stats | Sort-Object Month | ForEach-Object {
                "                <tr>
                    <td>$($_.Month)</td>
                    <td>$($_.MonthlyUsers)</td>
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
        Write-Verbose "Generating weekly statistics table..."
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
            $ReportData.WeeklyMetrics.Stats | Sort-Object Week | ForEach-Object {
                "                <tr>
                    <td>$($_.Week)</td>
                    <td>$($_.WeeklyUsers)</td>
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
        Write-Verbose "Generating daily statistics table..."
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
            $ReportData.DailyMetrics.Stats | Sort-Object Date -Descending | Select-Object -First 7 | ForEach-Object {
                "                <tr>
                    <td>$($_.Date)</td>
                    <td>$($_.DailyUsers)</td>
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

        # Create chart data JavaScript
        Write-Verbose "Generating chart data..."
        $chartDataInit = @"
        // Initialize chart data
        monthlyData = {
            transportTypes: {
                labels: $(ConvertTo-Json @($monthlyAnalytics.transportTypes.labels)),
                data: $(ConvertTo-Json @($monthlyAnalytics.transportTypes.data))
            },
            gatewayRegions: {
                labels: $(ConvertTo-Json @($monthlyAnalytics.gatewayRegions.labels)),
                data: $(ConvertTo-Json @($monthlyAnalytics.gatewayRegions.data))
            },
            clientTypes: {
                labels: $(ConvertTo-Json @($monthlyAnalytics.clientTypes.labels)),
                data: $(ConvertTo-Json @($monthlyAnalytics.clientTypes.data))
            },
            clientOSs: {
                labels: $(ConvertTo-Json @($monthlyAnalytics.clientOSs.labels)),
                data: $(ConvertTo-Json @($monthlyAnalytics.clientOSs.data))
            }
        };

        weeklyData = {
            transportTypes: {
                labels: $(ConvertTo-Json @($weeklyAnalytics.transportTypes.labels)),
                data: $(ConvertTo-Json @($weeklyAnalytics.transportTypes.data))
            },
            gatewayRegions: {
                labels: $(ConvertTo-Json @($weeklyAnalytics.gatewayRegions.labels)),
                data: $(ConvertTo-Json @($weeklyAnalytics.gatewayRegions.data))
            },
            clientTypes: {
                labels: $(ConvertTo-Json @($weeklyAnalytics.clientTypes.labels)),
                data: $(ConvertTo-Json @($weeklyAnalytics.clientTypes.data))
            },
            clientOSs: {
                labels: $(ConvertTo-Json @($weeklyAnalytics.clientOSs.labels)),
                data: $(ConvertTo-Json @($weeklyAnalytics.clientOSs.data))
            }
        };

        dailyData = {
            transportTypes: {
                labels: $(ConvertTo-Json @($dailyAnalytics.transportTypes.labels)),
                data: $(ConvertTo-Json @($dailyAnalytics.transportTypes.data))
            },
            gatewayRegions: {
                labels: $(ConvertTo-Json @($dailyAnalytics.gatewayRegions.labels)),
                data: $(ConvertTo-Json @($dailyAnalytics.gatewayRegions.data))
            },
            clientTypes: {
                labels: $(ConvertTo-Json @($dailyAnalytics.clientTypes.labels)),
                data: $(ConvertTo-Json @($dailyAnalytics.clientTypes.data))
            },
            clientOSs: {
                labels: $(ConvertTo-Json @($dailyAnalytics.clientOSs.labels)),
                data: $(ConvertTo-Json @($dailyAnalytics.clientOSs.data))
            }
        };
"@

        # Generate statistics tables
        Write-Verbose "Generating statistics tables..."
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
            <tbody>
                $(($ReportData.MonthlyMetrics.Stats | Sort-Object Month | ForEach-Object {
                    "<tr>
                        <td>$($_.Month)</td>
                        <td>$($_.MonthlyUsers)</td>
                        <td>$($_.ActiveSessions)</td>
                        <td>$($_.CompletedSessions)</td>
                        <td>$($_.TotalSessions)</td>
                        <td>$($_.UniqueClients)</td>
                        <td>$($_.UniqueHosts)</td>
                        <td class='session-duration'>$($_.AvgSessionDuration)</td>
                    </tr>"
                }) -join "`n")
            </tbody>
        </table>
"@

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
            <tbody>
                $(($ReportData.WeeklyMetrics.Stats | Sort-Object Week | ForEach-Object {
                    "<tr>
                        <td>$($_.Week)</td>
                        <td>$($_.WeeklyUsers)</td>
                        <td>$($_.ActiveSessions)</td>
                        <td>$($_.CompletedSessions)</td>
                        <td>$($_.TotalSessions)</td>
                        <td>$($_.UniqueHosts)</td>
                        <td class='session-duration'>$($_.AvgSessionDuration)</td>
                    </tr>"
                }) -join "`n")
            </tbody>
        </table>
"@

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
            <tbody>
                $(($ReportData.DailyMetrics.Stats | Sort-Object Date -Descending | Select-Object -First 7 | ForEach-Object {
                    "<tr>
                        <td>$($_.Date)</td>
                        <td>$($_.DailyUsers)</td>
                        <td>$($_.ActiveSessions)</td>
                        <td>$($_.CompletedSessions)</td>
                        <td>$($_.TotalSessions)</td>
                        <td>$($_.UniqueClients)</td>
                        <td class='session-duration'>$($_.AvgSessionDuration)</td>
                    </tr>"
                }) -join "`n")
            </tbody>
        </table>
"@

        Write-Verbose "Replacing placeholders in template..."
        # Replace placeholders in template
        $html = $template
        $html = $html.Replace('{TITLE}', $Title)
        $html = $html.Replace('{LOGO_URL}', $logoUrl)
        $html = $html.Replace('{TIME_RANGE}', $ReportData.TimeRange)
        $html = $html.Replace('{HOST_POOL}', $ReportData.HostPoolName)
        $html = $html.Replace('{SUMMARY_METRICS}', $summaryMetrics)
        $html = $html.Replace('{MONTHLY_STATS}', $monthlyStatsHtml)
        $html = $html.Replace('{WEEKLY_STATS}', $weeklyStatsHtml)
        $html = $html.Replace('{DAILY_STATS}', $dailyStatsHtml)
        
        # Replace analytics summaries
        $html = $html.Replace('<div id="transportTypesSummary" class="analytics-list"></div>', 
            "<div id='transportTypesSummary' class='analytics-list'>$transportTypesSummary</div>")
        $html = $html.Replace('<div id="gatewayRegionsSummary" class="analytics-list"></div>', 
            "<div id='gatewayRegionsSummary' class='analytics-list'>$gatewayRegionsSummary</div>")
        $html = $html.Replace('<div id="clientTypesSummary" class="analytics-list"></div>', 
            "<div id='clientTypesSummary' class='analytics-list'>$clientTypesSummary</div>")
        $html = $html.Replace('<div id="clientOSSummary" class="analytics-list"></div>', 
            "<div id='clientOSSummary' class='analytics-list'>$clientOSSummary</div>")

        # Replace JavaScript sections
        $html = $html.Replace('{CHART_CONFIG}', $chartConfig)
        $html = $html.Replace('{CHART_DATA}', "$chartDataTemplate`n$chartDataInit")
        $html = $html.Replace('{CHART_FUNCTIONS}', $chartFunctions)

        Write-Verbose "HTML report conversion completed"
        return $html
    }
    catch {
        Write-Error "Error generating HTML report: $_"
        Write-Verbose "Full error details: $($_.Exception.Message)"
        Write-Verbose "Stack trace: $($_.ScriptStackTrace)"
        throw
    }
}
