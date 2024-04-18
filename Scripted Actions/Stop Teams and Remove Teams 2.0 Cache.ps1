Write-Host "Closing Teams in order to clear cache"
try{
Get-Process -ProcessName Teams | Stop-Process -Force
Start-Sleep -Seconds 5
Write-Host "Teams is now closed"
}
catch{
echo $_
}
# Now clean temp file locations
try{
Get-ChildItem -Path $env:APPDATA\"Microsoft\teams\application cache\cache" | Remove-Item
Get-ChildItem -Path $env:APPDATA\"Microsoft\teams\blob_storage" | Remove-Item
Get-ChildItem -Path $env:APPDATA\"Microsoft\teams\databases" | Remove-Item
Get-ChildItem -Path $env:APPDATA\"Microsoft\teams\cache" | Remove-Item
Get-ChildItem -Path $env:APPDATA\"Microsoft\teams\gpucache" | Remove-Item
Get-ChildItem -Path $env:APPDATA\"Microsoft\teams\Indexeddb" | Remove-Item
Get-ChildItem -Path $env:APPDATA\"Microsoft\teams\Local Storage" | Remove-Item
Get-ChildItem -Path $env:APPDATA\"Microsoft\teams\tmp" | Remove-Item
 
}
catch{
echo $_
}
 
# Teams cache is now cleaned
write-host "Cleaned up Teams Cache"