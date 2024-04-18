# Get all groups that contain "WAP" in the name
$groups = Get-AzADGroup | Where-Object { $_.DisplayName -like "*WAP*" }

# Loop through each group and delete it
foreach ($group in $groups) {
    Remove-AzADGroup -ObjectId $group.Id
}