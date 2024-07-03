# Description: This script adds the specified Entra groups to the FSLogix Exclude List Group

function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$LogFilePath = "$env:TEMP\NerdioManagerLogs",

        [string]$LogName = "Add_EntraGroupExclusionFSLogix.txt"
    )
    
    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType Directory $LogFilePath -Force
        Write-Output "$LogFilePath has been created."
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level]: $Message"
    
    try {
        Add-Content -Path "$($LogFilePath)\$($LogName)" -Value $logEntry
    }
    catch {
        $_.Exception.Message
    }
}

function Convert-AzureAdObjectIdToSid {
    
    param([String] $ObjectId)
    
    $bytes = [Guid]::Parse($ObjectId).ToByteArray()
    $array = New-Object 'UInt32[]' 4
    
    [Buffer]::BlockCopy($bytes, 0, $array, 0, 16)
    $sid = "S-1-12-1-$array".Replace(' ', '-')
    
    return $sid
}


try {
    $EntraGroupObjectID = @(
        '060b74ef-5655-4e9e-a944-1e9d8162cdf1' # Microsoft Entra Joined Device Local Administrator
        '47a35b71-b3d6-4993-bce3-9bfcbe244b7b' # Global Administrators Group
        '99c33ffc-af06-4f7f-a52c-d0c80dfd841d' # Custom Created Group: FSLogix Exclude Group (Replace the ID with the ID of the group you want to add to the FSLogix Exclude Group)
    )

    $FSLogixExclusionGroup = 'FSLogix Profile Exclude List'



    foreach ($objectId in $EntraGroupObjectID) {
        $sid = Convert-AzureAdObjectIdToSid -ObjectId $objectId
        Write-Output "Adding $sid to $FSLogixExclusionGroup"
        Add-LocalGroupMember -Group $FSLogixExclusionGroup -Member $sid
        NMMLogOutput -Level Information -Message "Added $sid to $FSLogixExclusionGroup"
    }
}
catch {
    NMMLogOutput -Level Error -Message $_.Exception.Message
}
finally {
    NMMLogOutput -Level Information -Message "Script execution completed"
}