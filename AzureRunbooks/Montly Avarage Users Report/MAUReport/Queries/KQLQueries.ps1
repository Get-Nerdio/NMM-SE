# Function to get daily usage query
function Get-DailyUsageQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$HostPoolName,
        
        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,
        
        [Parameter(Mandatory = $true)]
        [datetime]$EndDate
    )
    
    return @"
// First calculate session durations
let SessionDurations = WVDConnections
| where TimeGenerated between (datetime('$($StartDate.ToString("yyyy-MM-dd"))') .. datetime('$($EndDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| summarize StartTime = min(iff(State == 'Connected', TimeGenerated, datetime(null))), 
            EndTime = max(iff(State == 'Completed', TimeGenerated, datetime(null))) 
            by CorrelationId
| extend SessionDuration = EndTime - StartTime
| where SessionDuration > 0s;  // Filter out invalid durations
// Main query with all metrics
WVDConnections
| where TimeGenerated between (datetime('$($StartDate.ToString("yyyy-MM-dd"))') .. datetime('$($EndDate.ToString("yyyy-MM-dd"))'))
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
}

# Function to get weekly usage query
function Get-WeeklyUsageQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$HostPoolName,
        
        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,
        
        [Parameter(Mandatory = $true)]
        [datetime]$EndDate
    )
    
    return @"
// First calculate session durations
let SessionDurations = WVDConnections
| where TimeGenerated between (datetime('$($StartDate.ToString("yyyy-MM-dd"))') .. datetime('$($EndDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| summarize StartTime = min(iff(State == 'Connected', TimeGenerated, datetime(null))), 
            EndTime = max(iff(State == 'Completed', TimeGenerated, datetime(null))) 
            by CorrelationId
| extend SessionDuration = EndTime - StartTime
| where SessionDuration > 0s;  // Filter out invalid durations
// Main query with all metrics
WVDConnections
| where TimeGenerated between (datetime('$($StartDate.ToString("yyyy-MM-dd"))') .. datetime('$($EndDate.ToString("yyyy-MM-dd"))'))
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
}

# Function to get monthly usage query
function Get-MonthlyUsageQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$HostPoolName,
        
        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,
        
        [Parameter(Mandatory = $true)]
        [datetime]$EndDate
    )
    
    return @"
// First calculate session durations
let SessionDurations = WVDConnections
| where TimeGenerated between (datetime('$($StartDate.ToString("yyyy-MM-dd"))') .. datetime('$($EndDate.ToString("yyyy-MM-dd"))'))
| extend HostPool = tolower(split(_ResourceId, '/')[-1])
| where HostPool contains tolower('$HostPoolName')
| summarize StartTime = min(iff(State == 'Connected', TimeGenerated, datetime(null))), 
            EndTime = max(iff(State == 'Completed', TimeGenerated, datetime(null))) 
            by CorrelationId
| extend SessionDuration = EndTime - StartTime
| where SessionDuration > 0s;  // Filter out invalid durations
// Main query with all metrics
WVDConnections
| where TimeGenerated between (datetime('$($StartDate.ToString("yyyy-MM-dd"))') .. datetime('$($EndDate.ToString("yyyy-MM-dd"))'))
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
}
