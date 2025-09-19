# MAUReport PowerShell Module

Monthly Average Users Report Generator for Azure Virtual Desktop

## Overview

This PowerShell module generates detailed usage reports for Azure Virtual Desktop (AVD) environments. It provides insights into user activity, session metrics, and client analytics across daily, weekly, and monthly time ranges.

## Requirements

- PowerShell 7.0 or later
- Azure PowerShell modules:
  - Az.Accounts (2.0.0 or later)
  - Az.OperationalInsights (3.0.0 or later)
- Azure subscription with access to:
  - AVD host pools
  - Log Analytics workspace

## Installation

1. Clone or download the module to your preferred location
2. Import the module:
```powershell
Import-Module ./MAUReport/MAUReport.psd1
```

## Usage

### Basic Report Generation

```powershell
Get-MAUReport -WorkspaceId '<workspace-id>' -HostPoolName '<hostpool-name>'
```

### Optional Parameters

- `DaysToAnalyze`: Number of days to analyze (default: 30)
- `ReportName`: Custom name for the report (default: AVDUsageReport_YYYYMMDD)

```powershell
Get-MAUReport -WorkspaceId '<workspace-id>' -HostPoolName '<hostpool-name>' -DaysToAnalyze 60 -ReportName 'CustomReport'
```

### Configuration Management

Set default values:
```powershell
Set-MAUReportConfigValue -Key 'DefaultWorkspaceId' -Value '<workspace-id>'
Set-MAUReportConfigValue -Key 'DefaultHostPoolName' -Value '<hostpool-name>'
```

Get configuration values:
```powershell
Get-MAUReportConfigValue -Key 'DefaultWorkspaceId'
```

## Module Structure

```
MAUReport/
├── Public/
│   └── Get-MAUReport.ps1         # Main report generation function
├── Private/
│   ├── HelperFunctions.ps1       # Utility functions
│   └── ConvertTo-HTMLReport.ps1  # HTML report generation
├── Queries/
│   └── KQLQueries.ps1           # KQL query definitions
├── Config/
│   └── Settings.ps1             # Configuration management
├── Static/
│   └── NerrdioMSPLogo.png       # Static assets
├── MAUReport.psd1               # Module manifest
├── MAUReport.psm1               # Module loader
└── template.html                # HTML report template
```

## Generated Reports

The module generates two types of files:
1. HTML Report (AVDUsageReport_YYYYMMDD.html)
   - Interactive visualizations
   - Detailed analytics
   - Usage statistics tables
2. JSON Data (AVDUsageData_YYYYMMDD.json)
   - Raw data export
   - Suitable for further analysis

### Report Sections

1. Summary Metrics
   - Average Monthly Users
   - Average Weekly Users
   - Average Daily Users
   - Peak Daily Users

2. Detailed Analytics
   - Transport Types Distribution
   - Gateway Regions Distribution
   - Client Types Distribution
   - Client OS Distribution

3. Usage Statistics
   - Monthly Statistics
   - Weekly Statistics
   - Daily Statistics (Last 7 Days)

## Best Practices

1. Always verify Azure connection before running reports:
```powershell
Connect-AzAccount
```

2. Use appropriate time ranges for analysis:
   - 30 days for regular monitoring
   - 60-90 days for trend analysis
   - Custom ranges for specific reporting periods

3. Store reports in a consistent location:
```powershell
Set-MAUReportConfigValue -Key 'ReportPath' -Value 'path/to/reports'
```

## Troubleshooting

Common issues and solutions:

1. Module Import Errors
   - Verify PowerShell version
   - Check module dependencies
   - Ensure proper file permissions

2. Azure Connection Issues
   - Verify Azure PowerShell modules
   - Check Azure credentials
   - Confirm workspace access

3. Report Generation Issues
   - Verify KQL query permissions
   - Check workspace data retention
   - Ensure sufficient memory for data processing

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
