$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = 'continue'
$folderPath = "$env:TEMP\NerdioManagerLogs"
$LognameTXT = "Detection-CleanupPublicDestop.txt"

if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory $folderPath -Force
    Write-Output "$folderPath has been created."
}
else {
    Write-Output "$folderPath already exists, continue script"
}

Start-Transcript -Path (Join-Path $folderPath -ChildPath $LognameTXT) -Append -IncludeInvocationHeader

Write-Output "################# New Script Run #################"
Write-Output "Current time (UTC-0): $((Get-Date).ToUniversalTime())"


#Script content goes here


Stop-Transcript
$VerbosePreference = $SaveVerbosePreference