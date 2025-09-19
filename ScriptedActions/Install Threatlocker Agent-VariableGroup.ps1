#description: Install the Threatlocker agent.
#execution mode: Individual
#tags: Nerdio, Threatlocker

<#
Notes:
The installation script requires an organization name, ThreatLocker Unique Identifier,
and a ThreatLocker Instance.

Unique Identifier can be found in Deployment Center under the RMM and Script Deployment section. 
https://threatlocker.kb.help/getting-your-unique-identifier-from-threatlocker/

The ThreatLocker instance can be found in the ThreatLocker portal URL, under Help. Find
"ThreatLocker Access" will be followed by a letter. This letter is the instance. For example,

ThreatLocker Access (G) - The instance is "g". G is the default instance; if not specified, 
the script will use "g".

You must provide secure variables to this script as seen in the Required Variables section. 
Set these up in Nerdio Manager under Settings->Integrations. 
The variables to create are:
    ThreatlockerOrgName
    ThreatlockerUniqueId
    ThreatlockerInstance

You must also provide the following Inherited Variables to this script as seen in the Inherited Variables section. 
Set these up in Nerdio Manager under Settings->Integrations. 
The variables to create are:
    ThreatlockerGroup
#>

##### Required Variables #####

$ThreatlockerOrgName = $SecureVars.ThreatlockerOrgName;
$ThreatlockerIdentifier = $SecureVars.ThreatlockerUniqueId;
$ThreatlockerInstance = $SecureVars.ThreatlockerInstance;


##### Inherited Variables #####
#Set Group Name 
$ThreatlockerGroupName = $InheritedVars.ThreatlockerGroup; 


#Set Threatlocker Instance
if ([string]::IsNullOrEmpty($ThreatlockerInstance)) {
    $ThreatlockerInstance = "g";
}

##### Script Logic #####

if(($ThreatlockerOrgName -eq $null) -and  ($ThreatlockerIdentifier -eq $null))  {
    Write-Output "ERROR: The secure variables ThreatlockerOrgName or ThreatlockerIdentifier are not provided"
}

try {
    $Url = "https://api.$ThreatlockerInstance`.threatlocker.com/getgroupkey.ashx"; 
    $Headers = @{'Authorization'=$ThreatlockerIdentifier;'OrganizationName'=$ThreatlockerOrgName;'GroupName'=$ThreatlockerGroupName}; 
    
    [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
    $Response = (Invoke-RestMethod -Method 'Post' -uri $Url -Headers $Headers -Body ''); 
    $GroupId = $response.split([Environment]::NewLine)[0].split(':')[1].trim();
}
catch {
    Write-Output "Failed to get GroupId. Check the Notes section for information about setting the ThreatLocker instance.";
    throw $_;
    Exit 1;
}

if ([Environment]::Is64BitOperatingSystem) {
    $DownloadURL = "https://api.threatlocker.com/installers/threatlockerstubx64.exe";
    $InstallerName = "threatlockerstubx64.exe"
}
else {
    $DownloadURL = "https://api.threatlocker.com/installers/threatlockerstubx86.exe";
    $InstallerName = "threatlockerstubx86.exe"
}
$InstallerPath = Join-Path $Env:TMP $InstallerName
Invoke-WebRequest -Uri $DownloadURL -OutFile $InstallerPath;

Start-Process $InstallerPath "InstallKey=$GroupId" -Wait