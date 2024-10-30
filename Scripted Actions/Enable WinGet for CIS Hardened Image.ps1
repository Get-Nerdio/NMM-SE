#description: Enable Winget for CIS images (UAM) on session host VMs
#execution mode: IndividualWithRestart
#tags: Nerdio
<#
Notes:
This script enables app installers by updating EnableAppInstaller policy in Registry.pol file.

IMPORTANT NOTE: This script is designed to offer a simple method to enabled Winget functionality on a CIS based image or other secure image. 
Please ensure that running this script and enabling Winget does not conflict with your company security policies. If in doubt, DO NOT USE this script. 
Please speak with your security team to establish if this exception may be allowed in your environment.
#>

Enum RegType {
    REG_NONE                       = 0
    REG_SZ                         = 1
    REG_EXPAND_SZ                  = 2
    REG_BINARY                     = 3
    REG_DWORD                      = 4
    REG_DWORD_LITTLE_ENDIAN        = 4
    REG_DWORD_BIG_ENDIAN           = 5
    REG_LINK                       = 6
    REG_MULTI_SZ                   = 7
    REG_RESOURCE_LIST              = 8
    REG_FULL_RESOURCE_DESCRIPTOR   = 9
    REG_RESOURCE_REQUIREMENTS_LIST = 10
    REG_QWORD                      = 11
    REG_QWORD_LITTLE_ENDIAN        = 11
}

Class GPRegistryPolicy
{
    [string]  $KeyName
    [string]  $ValueName
    [RegType] $ValueType
    [string]  $ValueLength
    [object]  $ValueData
    [int] $ValueFirstIndex

    GPRegistryPolicy()
    {
        $this.KeyName     = $Null
        $this.ValueName   = $Null
        $this.ValueType   = [RegType]::REG_NONE
        $this.ValueLength = 0
        $this.ValueData   = $Null
        $this.ValueFirstIndex = 0
    }

    GPRegistryPolicy(
            [string]  $KeyName,
            [string]  $ValueName,
            [RegType] $ValueType,
            [string]  $ValueLength,
            [object]  $ValueData,
            [int] $ValueFirstIndex
        )
    {
        $this.KeyName     = $KeyName
        $this.ValueName   = $ValueName
        $this.ValueType   = $ValueType
        $this.ValueLength = $ValueLength
        $this.ValueData   = $ValueData
        $this.ValueFirstIndex = $ValueFirstIndex
    }
}

Function Convert-StringToInt
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Object[]]
        $ValueString
    )
  
    if ($ValueString.Length -le 4)
    {
        [int32] $result = 0
    }
    elseif ($ValueString.Length -le 8)
    {
        [int64] $result = 0
    }
    else
    {
        Fail -ErrorMessage $LocalizedData.InvalidIntegerSize
    }

    for ($i = $ValueString.Length - 1 ; $i -ge 0 ; $i -= 1)
    {
        $result = $result -shl 8
        $result = $result + ([int][char]$ValueString[$i])
    }

    return $result
}

$Path = "C:\windows\system32\GroupPolicy\Machine\Registry.pol"
if (-not (Test-Path $Path)) {
    Write-Host "Registry.pol file of machine configuration not found"
    throw
}

$CurrentDate = Get-Date -Format "dd-MMM-yyyy"
$BackupFile = "C:\windows\system32\GroupPolicy\Machine\Registry_Backup_$CurrentDate.pol"

Copy-Item $Path -Destination $BackupFile
Write-Host "Backup file: $BackupFile"

[string] $policyContents = Get-Content $Path -Raw
[byte[]] $policyContentInBytes = Get-Content $Path -Raw -Encoding Byte

[Array] $RegistryPolicies = @()
$index = 0

$signature = [System.Text.Encoding]::ASCII.GetString($policyContents[0..3])
$index += 4

$version = [System.BitConverter]::ToInt32($policyContentInBytes, 4)
$index += 4

while($index -lt $policyContents.Length - 2)
{
    [string]$keyName = $null
    [string]$valueName = $null
    [int]$valueType = $null
    [int]$valueLength = $null
    [object]$value = $null
    [int]$valueFirstIndex = $null

    $leftbracket = [System.BitConverter]::ToChar($policyContentInBytes, $index)
    $index+=2

    $semicolon = $policyContents.IndexOf(";", $index)
    $keyName = [System.Text.Encoding]::UNICODE.GetString($policyContents[($index)..($semicolon-3)])
    $index = $semicolon + 2

    $semicolon = $policyContents.IndexOf(";", $index)
    $valueName = [System.Text.Encoding]::UNICODE.GetString($policyContents[($index)..($semicolon-3)])
    $index = $semicolon + 2

    $semicolon = $index + 4
    $valueType = [System.BitConverter]::ToInt32($policyContentInBytes, $index)
    $index=$semicolon + 2

    $semicolon = $index + 4
    $valueLength = Convert-StringToInt -ValueString $policyContentInBytes[$index..($index+3)]
    $index=$semicolon + 2

    if ($valueLength -gt 0)
    {
        if($valueType -eq [RegType]::REG_SZ)
        {
            [string] $value = [System.Text.Encoding]::UNICODE.GetString($policyContents[($index)..($index+$valueLength-3)])
            $valueFirstIndex = $index
            $index += $valueLength
        }

        if($valueType -eq [RegType]::REG_EXPAND_SZ)
        {
            [string] $value = [System.Text.Encoding]::UNICODE.GetString($policyContents[($index)..($index+$valueLength-3)])
            $valueFirstIndex = $index
            $index += $valueLength
        }

        if($valueType -eq [RegType]::REG_MULTI_SZ)
        {
            [string] $value = [System.Text.Encoding]::UNICODE.GetString($policyContents[($index)..($index+$valueLength-3)])
            $valueFirstIndex = $index
            $index += $valueLength
        }

        if($valueType -eq [RegType]::REG_BINARY)
        {
            [byte[]] $value = $policyContentInBytes[($index)..($index+$valueLength-1)]
            $valueFirstIndex = $index
            $index += $valueLength
        }
    }

    if($valueType -eq [RegType]::REG_DWORD)
    {
        $value = Convert-StringToInt -ValueString $policyContentInBytes[$index..($index+3)]
        $valueFirstIndex = $index
        $index += 4
    }

    if($valueType -eq [RegType]::REG_QWORD)
    {
        $value = Convert-StringToInt -ValueString $policyContentInBytes[$index..($index+7)]
        $valueFirstIndex = $index
        $index += 8
    }

    $rightbracket = $policyContents.IndexOf("]", $index)
    $index = $rightbracket + 2

    $entry = [GPRegistryPolicy]::new($keyName, $valueName, $valueType, $valueLength, $value, $valueFirstIndex)

    $RegistryPolicies += $entry
}

$EnableAppInstallerPolicy = $RegistryPolicies | Where-Object ValueName -eq "EnableAppInstaller"

if ($EnableAppInstallerPolicy -eq $null) {
    Write-Host "EnableAppInstaller policy not found in Registry.pol"
    throw
}

if ($EnableAppInstallerPolicy.ValueData -eq 1) {
    Write-Host "EnableAppInstaller policy already enabled"
    throw
}

if (-not ($EnableAppInstallerPolicy.ValueLength -eq 4)) {
    Write-Host "unknown EnableAppInstaller policy configuration"
    throw
}

([byte[]](1,0,0,0)).CopyTo($policyContentInBytes, $EnableAppInstallerPolicy.ValueFirstIndex)
Set-Content -Path $Path -Value $policyContentInBytes -Encoding Byte
gpupdate /target:computer /force