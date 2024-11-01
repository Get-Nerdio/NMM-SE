function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateSet('String', 'DWORD', 'QWORD', 'Binary', 'MultiString', 'ExpandString')]
        [string]$Type
    )

    try {
        if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set registry value")) {
            # Check if the registry key exists, create it if it doesn't
            if (-not (Test-Path $Path)) {
                Write-Output "The registry key '$Path' does not exist. Creating it..."
                New-Item -Path $Path -Force | Out-Null
            }

            # Set the registry value using the appropriate type
            switch ($Type) {
                'String' {
                    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type String
                }
                'DWORD' {
                    Set-ItemProperty -Path $Path -Name $Name -Value ([Convert]::ToInt32($Value)) -Type DWord
                }
                'QWORD' {
                    Set-ItemProperty -Path $Path -Name $Name -Value ([Convert]::ToInt64($Value)) -Type Qword
                }
                'Binary' {
                    $binaryValue = $Value -split ' ' | ForEach-Object { [Convert]::ToByte($_, 16) }
                    Set-ItemProperty -Path $Path -Name $Name -Value $binaryValue -Type Binary
                }
                'MultiString' {
                    $multiStringValue = $Value -split ';'
                    Set-ItemProperty -Path $Path -Name $Name -Value $multiStringValue -Type MultiString
                }
                'ExpandString' {
                    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type ExpandString
                }
            }

            Write-Output "Successfully set $Name in $Path to $Value as $Type"
        } else {
            Write-Output 'Operation canceled by user.'
        }
    } catch {
        Write-Error "Failed to set $Name in $Path : $_"
    }
}


try {
    
    Set-RegistryValue  -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "DisableDomainCreds" -Value "0" -Type "DWORD"
    
   Write-Output 'Successfully Disabled Do not allow storage of passwords and credentials for network authentication'

}
catch {
    Write-Error $_.Exception.Message
}
