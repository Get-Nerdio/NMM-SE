function Convert-AzureAdSidToObjectId {
   
    param([String] $Sid)
    
    $text = $sid.Replace('S-1-12-1-', '')
    $array = [UInt32[]]$text.Split('-')
    
    $bytes = New-Object 'Byte[]' 16
    [Buffer]::BlockCopy($array, 0, $bytes, 0, 16)
    [Guid]$guid = $bytes
    
    return $guid
}
    
    
$sid = "S-1-12-1-1943430372-1249052806-2496021943-3034400218"
$objectId = Convert-AzureAdSidToObjectId -Sid $sid
Write-Output $objectId
    