Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = 'stop'
function EnsureModuleInstalled {
    param (
        [string]$moduleName,
        [Version]$MinVersion
    )
    Write-Output 'Check if' $moduleName 'is installed'

    $AzModule = Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue

    if ($null -eq $AzModule.Name -or [Version]$AzModule.Version -lt $MinVersion) {
        Write-Output 'Install' $moduleName
        Install-Module $moduleName -SkipPublisherCheck -Force
        Write-Output $moduleName 'successfully installed'
        Import-Module -Name $moduleName
        return
    }
    else {
        Write-Output $($AzModule.Name) $($AzModule.Version) 'is installed'
        return
    }
}

function Install-AzFilesHybrid {
    param (
        [string]$repo = "Azure-Samples/azure-files-samples",
        [string]$downloadPath = "C:\Temp\AzFilesHybrid"
    )
    
    # Ensure the download path exists
    if (-not (Test-Path -Path $downloadPath)) {
        New-Item -ItemType Directory -Path $downloadPath -Force
    }

    # Define the GitHub API URL for the latest release
    $apiUrl = "https://api.github.com/repos/$repo/releases/latest"

    # Fetch the latest release information
    $latestRelease = Invoke-RestMethod -Uri $apiUrl

    # Get the URL of the first asset (assumes it's a zip file)
    $assetUrl = $latestRelease.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1 -ExpandProperty browser_download_url

    # Define the path to save the downloaded asset
    $zipFilePath = Join-Path -Path $downloadPath -ChildPath "latest-release.zip"

    # Download the asset
    Invoke-WebRequest -Uri $assetUrl -OutFile $zipFilePath

    # Unzip the file to the specified folder
    Expand-Archive -Path $zipFilePath -DestinationPath $downloadPath -Force

    $psModPath = 'C:\Program Files\WindowsPowerShell\Modules'
    if (!(Test-Path -Path $psModPath)) {
        New-Item -Path $psModPath -ItemType Directory | Out-Null
    }

    $psdFile = Import-PowerShellDataFile -Path "$downloadPath\AzFilesHybrid.psd1"
    $desiredModulePath = "$psModPath\AzFilesHybrid\$($psdFile.ModuleVersion)\"
    if (!(Test-Path -Path $desiredModulePath)) {
        New-Item -Path $desiredModulePath -ItemType Directory | Out-Null
    }

    Copy-Item -Path "$downloadPath\AzFilesHybrid.psd1" -Destination $desiredModulePath -Force
    Copy-Item -Path "$downloadPath\AzFilesHybrid.psm1" -Destination $desiredModulePath -Force

    Import-Module -Name $desiredModulePath\AzFilesHybrid.psm1

    #Cleanup Downloaded Files
    Remove-Item -Path $downloadPath -Recurse -Force
}

function SetACLShare {
    param (
        [string]$Path
    )

    try {
        # Grant full control to "Authenticated Users"
        icacls $Path /grant `"Authenticated Users`":F
        Write-Output "Granted full control to 'Authenticated Users'."

        # Remove read permissions from "Users"
        icacls $Path /remove:g "Users"
        Write-Output "Removed read permissions from 'Users'."

        # Remove full control permissions from "CREATOR OWNER"
        icacls $Path /remove:g "CREATOR OWNER"
        Write-Output "Removed full control permissions from 'CREATOR OWNER'."

        # Grant modify permissions to "Users" (this folder only)
        icacls $Path --% /grant "Users":(NP)(M)
        Write-Output "Granted modify permissions to 'Users' (this folder only)."

        # Grant full control to "CREATOR OWNER" (subfolders and files only)
        icacls $Path --% /grant "CREATOR OWNER":(OI)(CI)(IO)(F)
        Write-Output "Granted full control to 'CREATOR OWNER' (subfolders and files only)."
        
    }
    catch {
        $_.Exception.Message
    }
}
 
function JoinAzFilesToADDS {
    param (
        $SubscriptionId,
        $ResourceGroupName,
        $StorageAccountName,
        $FileShareName,
        $StorageAccountKey,
        $OrganizationUnit,
        $EncryptionType,
        $TenantID,
        $ApplicationSecret #Only needed when using $ServicePrincipal = $true
    )
    
    try {
        # Call the function to install and import the latest AzFilesHybrid module
        Install-AzFilesHybrid

        # Call the function to ensure the Az module is installed
        EnsureModuleInstalled -moduleName 'Az' -MinVersion 2.8.0
    }
    catch {
        $_.Exception.Message
    }



    try {
        #Connect to Azure
        Update-AzConfig -EnableLoginByWam $false
        Connect-AzAccount -UseDeviceAuthentication -TenantID $TenantID -SubscriptionId $SubscriptionId
        Select-AzSubscription -SubscriptionId $SubscriptionId

        if ((Get-AzSubscription).Id -eq $SubscriptionId) {
            Write-Output 'Successfully connected to Azure'
        }
        else {
            $_.Exception.Message
            break
        }
    }
    catch {
        $_.Exception.Message
    }

    try {
        Write-Output 'Create logon account in AD for storage account'

        $joinAzStorageAccountParams = @{
            ResourceGroupName                   = $ResourceGroupName
            StorageAccountName                  = $StorageAccountName
            DomainAccountType                   = 'ComputerAccount'
            OrganizationalUnitDistinguishedName = $OrganizationUnit
        } 

        Join-AzStorageAccount @joinAzStorageAccountParams

        # Update the storage account to use AES256 encryption
        Update-AzStorageAccountAuthForAES256 -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName

        Write-Output 'Get the target storage account'

        $getAzStorageAccountParams = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $StorageAccountName
        }

        $storageaccount = Get-AzStorageAccount @getAzStorageAccountParams

        if ($storageAccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -and $storageAccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties) {
            'Storage account joined to AD'
        }
        else {
            'Something went wrong'
        }

        # Set the Kerberos encryption type to AES256 for the computer account
        Set-ADComputer -Identity $StorageAccountName -Server (Get-ADDomain).DNSRoot -KerberosEncryptionType $EncryptionType
    }
    catch {
        $_.Exception.Message
    }

    try {
        # Construct the network path and connect to the file share
        $netUsePath = "\\$storageAccountName.file.core.windows.net\$fileShareName"
        net use Z: $netUsePath "/user:Azure\$StorageAccountName" $StorageAccountKey

        if ($Debug -eq $True) {

            Debug-AzStorageAccountAuth -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName -Verbose
        }

        #Set ACL on the share
        SetACLShare -Path 'Z:\'

        #Delete Network Drive
        net use Z: /delete
    }
    catch {
        $_.Exception.Message
    }
    try {
        
        
    }
    catch {
        $_.Exception.Message
    }

}

############################################################################################################


#Example how to run the script or just set the params statically
$JoinAzFilesParams = @{
    SubscriptionId     = 'Azure Subscription ID'
    ResourceGroupName  = 'Resource Group Name'
    StorageAccountName = 'Name of Strorage Account'
    FileShareName      = 'Name of File Share in Storage Account'
    StorageAccountKey  = 'Storage Account Key'
    OrganizationUnit   = 'OU=AzFiles,OU=Nerdio Sales,DC=nerdiosales,DC=local' #Example value
    EncryptionType     = 'AES256'
    TenantID           = 'Tenant ID'
    Debug              = $false
}

JoinAzFilesToADDS @JoinAzFilesParams