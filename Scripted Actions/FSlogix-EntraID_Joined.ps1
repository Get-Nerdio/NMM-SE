###Prerequisites###
<#
This script requires the following Secure Variables to be created at the Account Level of Nerdio Manager for MSPs.
FSlgxStorageAccount
    -This should be just the the name of the Storage Account
    Example:
        Correct: avdstorage1024620
        Incorrect: \\avdstorage1024620\file.core.windows.net

FSLgxSecret
    -This should be the Access Key for the Storage Account


###Script Source###

This script is based on the NMM Community Post by Tony Cai (https://nmmhelp.getnerdio.com/hc/en-us/community/posts/15704855452045-How-to-Use-Azure-Files-with-AADJ-Method-for-AVD) that covers how to do this process with clear-text info.
Please review the Prerequisites BEFORE running this script.

**NOTE: This script is only designed to work with one FSLogix Storage Account per Customer Account.
If you have Multiple FSLogix Storage Accounts, you will need to clone this script and modify it with different Secure Variables ***.


###Deploy the script###
When Deploying the script to the Host Pool, you want to put the script as an 'On VM Create' task so the registry keys apply correctly.
#>


##########################################################################################################
#Script

#Variables
$storageAccount="$($SecureVars.FSlgxStorageAccount)"
$fileserver="$storageAccount.file.core.windows.net"
$secret = "$($SecureVars.FSLgxSecret)" | ConvertTo-SecureString -AsPlainText -Force


#Create the local credentails for the storage account
cmdkey.exe /add:$fileServer /user:localhost\$storageAccount /pass:$secret

# Check if the key exists

if (-not(Test-Path "HKLM:\Software\Policies\Microsoft\AzureADAccount")) {
# Create the key if it doesn't exist
    New-Item -Path "HKLM:\Software\Policies\Microsoft\AzureADAccount" -Force
    }

# Add or modify the property

New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\AzureADAccount" -Name "LoadCredKeyFromProfile" -Value 1 -Type DWord -Force

#Disable Credential Guard
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LsaCfgFlags" -Value 0 -force


