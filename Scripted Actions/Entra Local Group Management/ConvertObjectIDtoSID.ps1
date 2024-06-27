function Convert-ObjectIdToSid {
    param([String] $ObjectId)

    $d = [UInt32[]]::new(4); [Buffer]::BlockCopy([Guid]::Parse($ObjectId).ToByteArray(), 0, $d, 0, 16); "S-1-12-1-$d".Replace(' ', '-')
}

Convert-ObjectIdToSid -ObjectId "dc79cac5-a4b3-4d41-80ca-019d04bf813b"





# Define the SID and the local group name
$SID = 'S-1-12-1-3698969285-1296147635-2634140288-998358788'  # Example SID
$LocalGroupName = 'AzFiles-RW'  # Change to the desired local group

# Add the SID to the local group
try {
    Add-LocalGroupMember -Group $LocalGroupName -Member $SID
    Write-Output "Successfully added SID $SID to the group $LocalGroupName."
} catch {
    Write-Error "Failed to add SID $SID to the group $LocalGroupName: $_"
}