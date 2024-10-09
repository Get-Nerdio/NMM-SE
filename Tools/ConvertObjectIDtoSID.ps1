function Convert-AzureAdObjectIdToSid {
    
    param([String] $ObjectId)
    
    $bytes = [Guid]::Parse($ObjectId).ToByteArray()
    $array = New-Object 'UInt32[]' 4
    
    [Buffer]::BlockCopy($bytes, 0, $array, 0, 16)
    $sid = "S-1-12-1-$array".Replace(' ', '-')
    
    return $sid
}
    
$objectId = "73d664e4-0886-4a73-b745-c694da45ddb4"
$sid = Convert-AzureAdObjectIdToSid -ObjectId $objectId
Write-Output $sid
    
