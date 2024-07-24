# Function to get a Group Policy value
function Get-GPValue {
    param (
        [string]$PolicyPath,
        [string]$PropertyName
    )

    try {
        $regKey = Get-ItemProperty -Path $PolicyPath -ErrorAction Stop
        $value = $regKey.$PropertyName
        return $value
    } catch {
        Write-Output "Policy $PolicyPath not found or property $PropertyName not set." -ForegroundColor Yellow
        return $null
    }
}

# Define the registry paths and properties for session time settings
$sessionTimeSettings = @{
    # Set time limit for active but idle Remote Desktop Services sessions
    'MaxIdleTime' = 'HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services';
    # Set time limit for active Remote Desktop Services sessions
    'MaxSessionTime' = 'HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services';
    # Set time limit for disconnected sessions
    'MaxDisconnectionTime' = 'HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services';
}

# Main Loop
foreach ($setting in $sessionTimeSettings.GetEnumerator()) {
    $value = Get-GPValue -PolicyPath $setting.Value -PropertyName $setting.Key
    if ($value -ne $null) {
        $minutes = [math]::Round($value / 60000, 2)
        Write-Output "$($setting.Key): $minutes minutes"
    } else {
        Write-Output "$($setting.Key): not set"
    }
}

