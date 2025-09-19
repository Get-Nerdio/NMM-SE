function Get-MAUReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
    
        [Parameter(Mandatory = $true)]
        [string]$HostPoolName,
    
        [Parameter(Mandatory = $false)]
        [int]$DaysToAnalyze = 30,

        [Parameter(Mandatory = $false)]
        [string]$ReportName = "AVDUsageReport_$(Get-Date -Format 'yyyyMMdd')"
    )

    Write-Verbose "Starting Get-MAUReport"
    Write-Verbose "Parameters:"
    Write-Verbose "  WorkspaceId: $WorkspaceId"
    Write-Verbose "  HostPoolName: $HostPoolName"
    Write-Verbose "  DaysToAnalyze: $DaysToAnalyze"
    Write-Verbose "  ReportName: $ReportName"

    # Verify module dependencies
    Write-Verbose "Verifying module dependencies..."
    $requiredModules = @('Az.Accounts', 'Az.OperationalInsights')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Write-Error "Required module '$module' is not installed. Please install it using: Install-Module -Name $module"
            return
        }
    }

    try {
        # Verify prerequisites
        Write-Verbose "Verifying Azure connection..."
        if (-not (Test-AzureConnection)) { 
            throw "Azure connection verification failed"
        }
        
        Write-Verbose "Verifying workspace..."
        if (-not (Test-WorkspaceExists -WorkspaceId $WorkspaceId)) { 
            throw "Workspace verification failed"
        }

        # Get workspace details
        $workspace = Get-AzOperationalInsightsWorkspace | Where-Object { $_.CustomerId -eq $WorkspaceId }
        if (-not $workspace) {
            throw "Could not find workspace details"
        }
        Write-Verbose "Using workspace: $($workspace.Name)"
        Write-Verbose "Resource ID: $($workspace.ResourceId)"

        # Calculate date range
        $endDate = Get-Date
        $startDate = $endDate.AddDays(-$DaysToAnalyze)
        Write-Verbose "Analyzing data from $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))"

        # Get queries
        Write-Verbose "Preparing KQL queries..."
        $dailyQuery = Get-DailyUsageQuery -HostPoolName $HostPoolName -StartDate $startDate -EndDate $endDate
        $weeklyQuery = Get-WeeklyUsageQuery -HostPoolName $HostPoolName -StartDate $startDate -EndDate $endDate
        $monthlyQuery = Get-MonthlyUsageQuery -HostPoolName $HostPoolName -StartDate $startDate -EndDate $endDate

        Write-Verbose "Daily Query:"
        Write-Verbose $dailyQuery

        # Execute queries with error handling
        Write-Verbose "Executing daily query..."
        try {
            # Try to get workspace ID in correct format
            $queryWorkspaceId = $workspace.CustomerId
            if ($queryWorkspaceId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                Write-Verbose "Converting workspace ID to GUID format"
                $queryWorkspaceId = [Guid]::Parse($WorkspaceId).ToString()
            }
            Write-Verbose "Using workspace ID for query: $queryWorkspaceId"

            $dailyStats = Invoke-AzOperationalInsightsQuery -WorkspaceId $queryWorkspaceId -Query $dailyQuery -ErrorAction Stop
            Write-Verbose "Daily query response: $($dailyStats | ConvertTo-Json -Depth 2)"
            
            if (-not $dailyStats -or -not $dailyStats.Results) {
                Write-Warning "Daily query returned no results"
                $dailyStats = @{ Results = @() }
            }
            else {
                Write-Verbose "Daily query returned $($dailyStats.Results.Count) results"
                Write-Verbose "Sample result: $($dailyStats.Results[0] | ConvertTo-Json)"
            }
        }
        catch {
            Write-Error "Error executing daily query: $_"
            Write-Verbose "Full error details: $($_.Exception.Message)"
            Write-Verbose "Error response: $($_.ErrorDetails.Message)"
            throw
        }

        Write-Verbose "Executing weekly query..."
        try {
            $weeklyStats = Invoke-AzOperationalInsightsQuery -WorkspaceId $queryWorkspaceId -Query $weeklyQuery -ErrorAction Stop
            Write-Verbose "Weekly query response: $($weeklyStats | ConvertTo-Json -Depth 2)"
            
            if (-not $weeklyStats -or -not $weeklyStats.Results) {
                Write-Warning "Weekly query returned no results"
                $weeklyStats = @{ Results = @() }
            }
            else {
                Write-Verbose "Weekly query returned $($weeklyStats.Results.Count) results"
                Write-Verbose "Sample result: $($weeklyStats.Results[0] | ConvertTo-Json)"
            }
        }
        catch {
            Write-Error "Error executing weekly query: $_"
            Write-Verbose "Full error details: $($_.Exception.Message)"
            Write-Verbose "Error response: $($_.ErrorDetails.Message)"
            throw
        }

        Write-Verbose "Executing monthly query..."
        try {
            $monthlyStats = Invoke-AzOperationalInsightsQuery -WorkspaceId $queryWorkspaceId -Query $monthlyQuery -ErrorAction Stop
            Write-Verbose "Monthly query response: $($monthlyStats | ConvertTo-Json -Depth 2)"
            
            if (-not $monthlyStats -or -not $monthlyStats.Results) {
                Write-Warning "Monthly query returned no results"
                $monthlyStats = @{ Results = @() }
            }
            else {
                Write-Verbose "Monthly query returned $($monthlyStats.Results.Count) results"
                Write-Verbose "Sample result: $($monthlyStats.Results[0] | ConvertTo-Json)"
            }
        }
        catch {
            Write-Error "Error executing monthly query: $_"
            Write-Verbose "Full error details: $($_.Exception.Message)"
            Write-Verbose "Error response: $($_.ErrorDetails.Message)"
            throw
        }

        # Calculate metrics
        Write-Verbose "Calculating metrics..."
        $results = @{
            HostPoolName   = $HostPoolName
            TimeRange      = "$($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))"
        
            DailyMetrics   = @{
                Stats             = @($dailyStats.Results)
                AverageDailyUsers = ($dailyStats.Results | Measure-Object -Property DailyUsers -Average).Average
                PeakDailyUsers    = ($dailyStats.Results | Measure-Object -Property DailyUsers -Maximum).Maximum
                TrendAnalysis     = @($dailyStats.Results | Sort-Object Date | Select-Object -Last 7)
            }
        
            WeeklyMetrics  = @{
                Stats              = @($weeklyStats.Results)
                AverageWeeklyUsers = ($weeklyStats.Results | Measure-Object -Property WeeklyUsers -Average).Average
                PeakWeeklySessions = ($weeklyStats.Results | Measure-Object -Property TotalSessions -Maximum).Maximum
            }
        
            MonthlyMetrics = @{
                Stats               = @($monthlyStats.Results)
                AverageMonthlyUsers = ($monthlyStats.Results | Measure-Object -Property MonthlyUsers -Average).Average
                PerformanceMetrics  = @{
                    AvgFrameRate      = ($monthlyStats.Results | Measure-Object -Property AvgFrameRate -Average).Average
                    AvgNetworkLatency = ($monthlyStats.Results | Measure-Object -Property AvgNetworkLatency -Average).Average
                    AvgBandwidth      = ($monthlyStats.Results | Measure-Object -Property AvgBandwidth -Average).Average
                }
            }
        }

        # Generate HTML report
        Write-Verbose "Generating HTML report..."
        try {
            $htmlReport = ConvertTo-HTMLReport -ReportData $results -Title $ReportName
            $htmlReportPath = Join-Path $script:ReportsPath "$ReportName.html"
            $htmlReport | Out-File -FilePath $htmlReportPath -Encoding UTF8
            Write-Verbose "HTML report saved to: $htmlReportPath"
        }
        catch {
            Write-Error "Failed to generate HTML report: $_"
            Write-Verbose "Full error details: $($_.Exception.Message)"
            Write-Verbose "Stack trace: $($_.ScriptStackTrace)"
        }

        # Export detailed data for further analysis
        try {
            $jsonPath = Join-Path $script:ReportsPath "AVDUsageData_$(Get-Date -Format 'yyyyMMdd').json"
            $results | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8
            Write-Verbose "JSON data exported to: $jsonPath"
        }
        catch {
            Write-Error "Failed to export JSON data: $_"
            Write-Verbose "Full error details: $($_.Exception.Message)"
            Write-Verbose "Stack trace: $($_.ScriptStackTrace)"
        }

        Write-Verbose "Report generation completed successfully"
        return $results
    }
    catch {
        Write-Error "Error generating report: $_"
        Write-Verbose "Full error details: $($_.Exception.Message)"
        Write-Verbose "Stack trace: $($_.ScriptStackTrace)"
        return
    }
}
