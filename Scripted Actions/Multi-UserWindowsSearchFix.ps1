<#
This script originally came from this blog post: https://virtualwarlock.net/how-to-install-the-fslogix-apps-agent/
Essentially, it enables a per-user Search Database instead of one Search DB for all the users to share.

Script Execution Mode: Individual with Restart

#>


# Check if registry value exist. 
# If registry value exists configure value data to 0, otherwise create registry value 
If (!(Get-ItemProperty -Path "HKLM:SOFTWARE\Microsoft\Windows Search" -Name "EnablePerUserCatalog" -ErrorAction SilentlyContinue)) 
{ 
    New-ItemProperty -Path "HKLM:SOFTWARE\Microsoft\Windows Search" -Name "EnablePerUserCatalog" -Value 0 -PropertyType "DWORD" -Verbose 
} 
    else 
    { 
        Set-ItemProperty -Path "HKLM:SOFTWARE\Microsoft\Windows Search" -Name "EnablePerUserCatalog" -Value 0 -Verbose 
}
