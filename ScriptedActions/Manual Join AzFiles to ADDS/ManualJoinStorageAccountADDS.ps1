Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser

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

function SetRBACAzFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]$EntraGroupName,

        [Parameter(Mandatory = $true)]
        [string]$EntraGroupDescription,

        [Parameter(Mandatory = $true)]
        [string]$AzureRoleName,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName
    )

    try {
        #Install the Graph module
        EnsureModuleInstalled -moduleName 'Microsoft.Graph.Authentication' -MinVersion 2.19.0

        EnsureModuleInstalled -moduleName 'Microsoft.Graph.Groups' -MinVersion 2.19.0
 
        # Connect to Microsoft Graph
        if ($ServicePrincipal -eq $true) {
            $SecurePassword = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
            $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $SecurePassword
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Credential
        }
        else {
         
            Connect-MgGraph -UseDeviceCode -TenantId $TenantId -Scopes "Group.ReadWrite.All"
        }
    }
    catch {
        $_.Exception.Message
    }

    try {
        # Check if the Entra group exists
        $EntraGroup = Get-MgGroup -Filter "displayName eq '$EntraGroupName'" -ConsistencyLevel eventual -ErrorAction SilentlyContinue

        # If the Entra group does not exist, create it
        if (-not $EntraGroup) {
            $EntraGroup = New-MgGroup -DisplayName $EntraGroupName -MailEnabled:$false -SecurityEnabled -MailNickname $EntraGroupName -Description $EntraGroupDescription
        }

        # Get the storage account
        $StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName

        # Get the role definition
        $RoleDefinition = Get-AzRoleDefinition -Name $AzureRoleName

        #Check if the Role already is assigned to the group
        $RoleAssignment = Get-AzRoleAssignment -Scope $StorageAccount.Id -RoleDefinitionName $AzureRoleName -ObjectId $EntraGroup.id -ErrorAction SilentlyContinue

        # Assign the role to the Entra group
        if (-not $RoleAssignment) {
            New-AzRoleAssignment -ObjectId $EntraGroup.Id -RoleDefinitionId $RoleDefinition.Id -Scope $StorageAccount.Id
            Write-Output "Role assigned to $($EntraGroup.DisplayName) group."
        }

        Write-Output "Role assignment completed successfully."
    }
    catch {
        $_.Exception.Message
    }
}
 
function JoinAzFilesToADDS {
    param (
        $ClientId,
        $ClientSecret,
        $ServicePrincipal,
        $SubscriptionId,
        $ResourceGroupName,
        $StorageAccountName,
        $FileShareName,
        $StorageAccountKey,
        $OrganizationUnit,
        $EncryptionType,
        $SetRBACAzFiles,
        $EntraGroupName,
        $EntraGroupDescription,
        $AzureRoleName,
        $DomainAccountType,
        $TenantID
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
        if ($ServicePrincipal -eq $true) {
            #Connect to Azure with Service Principal
            $SecurePassword = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
            $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $SecurePassword
            Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential -SubscriptionId $SubscriptionId
            Select-AzSubscription -SubscriptionId $SubscriptionId
        }
        else {
            #Connect to Azure with DeviceCode
            Update-AzConfig -EnableLoginByWam $false
            Connect-AzAccount -UseDeviceAuthentication -TenantID $TenantID -SubscriptionId $SubscriptionId
            Select-AzSubscription -SubscriptionId $SubscriptionId
        }

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
            DomainAccountType                   = $DomainAccountType
            OrganizationalUnitDistinguishedName = $OrganizationUnit
        } 

        Join-AzStorageAccount @joinAzStorageAccountParams

        # Update the storage account to use AES256 encryption
        Update-AzStorageAccountAuthForAES256 -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName

        Write-Output "Get the target storage account $($StorageAccountName)"

        $getAzStorageAccountParams = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $StorageAccountName
        }

        $storageaccount = Get-AzStorageAccount @getAzStorageAccountParams

        if ($storageAccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -and $storageAccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties) {
            Write-Output 'Storage account joined to AD'
        }
        else {
            Write-Output 'Something went wrong, storage account not joined to AD'
            $_.Exception.Message
            break
        }

        # Set the Kerberos encryption type to AES256 for the computer account
        Set-ADComputer -Identity $StorageAccountName -Server (Get-ADDomain).DNSRoot -KerberosEncryptionType $EncryptionType

        if ($SetRBACAzFiles -eq $true) {
            SetRBACAzFiles -EntraGroupName $EntraGroupName -EntraGroupDescription $EntraGroupDescription -AzureRoleName $AzureRoleName -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName

        }
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

}

############################################################################################################


#Example how to run the script or just set the params statically
$JoinAzFilesParams = @{
    ServicePrincipal      = $false
    SubscriptionId        = 'Azure Subscription ID'
    ResourceGroupName     = 'Resource Group Name'
    StorageAccountName    = 'Name of Strorage Account'
    FileShareName         = 'Name of File Share in Storage Account'
    StorageAccountKey     = 'Storage Account Key'
    OrganizationUnit      = 'OU=AzFiles,OU=Nerdio Sales,DC=nerdiosales,DC=local' #Example value
    DomainAccountType     = 'ComputerAccount' #ComputerAccount or ServiceLogonAccount default is ComputerAccount
    EncryptionType        = 'AES256'
    TenantID              = 'Tenant ID'
    Debug                 = $false
    ClientSecret          = 'Client Secret'
    ClientId              = 'Client ID'
    SetRBACAzFiles        = $false
    EntraGroupName        = 'AzFiles-TestGroup'
    EntraGroupDescription = 'Test Group for AzFiles'
    AzureRoleName         = 'Storage File Data SMB Share Contributor' #Role needed for assigned Group to have access to the Storage Account
}

JoinAzFilesToADDS @JoinAzFilesParams