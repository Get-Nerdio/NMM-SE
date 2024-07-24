function GetLockedAdAccount {
    param (
        [string]$ComputerName,
        [int]$Minutes = -30
    )
    
    try {
        Get-WinEvent -FilterHashtable @{ LogName = 'Security' ; Id = 4740 ; StartTime = [datetime]::Now.AddMinutes($Minutes) } -ComputerName $ComputerName | Select-Object timecreated, @{n = 'account'; e = { $_.properties[0].value } }, @{n = 'from'; e = { $_.properties[1].value } }
    }
    catch {
        $_.Exception.Message
    }
}