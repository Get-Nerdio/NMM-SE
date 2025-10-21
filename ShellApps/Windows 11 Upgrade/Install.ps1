# Windows 11 Upgrade Installation Script
# This script downloads and initiates the Windows 11 upgrade process

[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [string] $InstallAssistantDownloadURL = 'https://go.microsoft.com/fwlink/?linkid=2171764',
    [Parameter()]
    [string] $DownloadDestination = "$env:TEMP\Windows11InstallAssistant\Windows11InstallationAssistant.exe",
    [Parameter()]
    [string] $UpdateLogLocation = "$env:SYSTEMROOT\Logs\Windows11InstallAssistant"
)

try {
    $Context.Log("INFO: Starting Windows 11 upgrade installation")
    
    # Check if running as administrator
    if (!(Test-IsElevated)) {
        $Context.Log("ERROR: This script must be run with Administrator privileges")
        throw "Access Denied. Please run with Administrator privileges."
    }
    
    # Verify Windows 10 compatibility
    try {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $Context.Log("INFO: Current OS: $($OS.Caption) Version: $($OS.Version)")
        
        if ($OS.Caption -notmatch "Windows 10") {
            throw "This device is not currently running Windows 10. It is currently running '$($OS.Caption)'."
        }
    }
    catch {
        $Context.Log("ERROR: OS verification failed: $($_.Exception.Message)")
        throw $_
    }
    
    # Check disk space
    try {
        $osDrive = Get-Volume -DriveLetter ($env:SystemDrive -replace ":") -ErrorAction Stop
        if (!$osDrive.SizeRemaining) {
            throw "Failed to retrieve the remaining size for drive '$env:SystemDrive'."
        }
        
        $freeSpaceGB = [math]::Round(($osDrive.SizeRemaining / 1GB), 2)
        $Context.Log("INFO: Available disk space: $freeSpaceGB GB")
        
        if ($osDrive.SizeRemaining -lt 64GB) {
            throw "The current free space for the system drive '$env:SystemDrive' is $freeSpaceGB GB. There is not enough free space. You must have at least 64GB of free space."
        }
    }
    catch {
        $Context.Log("ERROR: Disk space check failed: $($_.Exception.Message)")
        throw $_
    }
    
    # Verify Windows 11 compatibility
    try {
        $Context.Log("INFO: Verifying Windows 11 compatibility")
        $Result = Get-HardwareReadiness | Select-Object -Unique | ConvertFrom-Json
        $Context.Log("INFO: Hardware compatibility result: $($Result.returnResult)")
        
        if ($Result.returnCode -ne 0) {
            $reason = if ($Result.returnReason) { " - $($Result.returnReason)" } else { "" }
            throw "This device is either incompatible with Windows 11 or its compatibility could not be determined.$reason"
        }
    }
    catch {
        $Context.Log("ERROR: Hardware compatibility check failed: $($_.Exception.Message)")
        throw $_
    }
    
    # Check if upgrade is already in progress
    $Context.Log("INFO: Verifying the upgrade is not already in progress")
    $Windows10UpgradeApp = Get-Process -Name "Windows10UpgraderApp" -ErrorAction SilentlyContinue
    
    if ($Windows10UpgradeApp) {
        $Context.Log("ERROR: The Windows 11 upgrade is already in progress")
        $Context.Log("INFO: Upgrade Process Details:")
        $Context.Log("INFO: PID: $($Windows10UpgradeApp.Id)")
        $Context.Log("INFO: Name: $($Windows10UpgradeApp.ProcessName)")
        $Context.Log("INFO: Path: $($Windows10UpgradeApp.Path)")
        throw "The Windows 11 upgrade is already in progress via process PID $($Windows10UpgradeApp.Id)"
    }
    
    $Context.Log("INFO: No upgrade process currently running")
    
    # Download Windows 11 Installation Assistant
    $Context.Log("INFO: Downloading the Windows 11 Installation Assistant executable")
    try {
        $WindowsInstallAssistant = Invoke-Download -Path $DownloadDestination -URL $InstallAssistantDownloadURL -Overwrite -ErrorAction Stop
        $Context.Log("INFO: Download completed successfully")
    }
    catch {
        $Context.Log("ERROR: Download failed: $($_.Exception.Message)")
        throw "Unable to download the Windows 11 Installation Assistant at '$InstallAssistantDownloadURL'"
    }
    
    # Verify executable signature
    $Context.Log("INFO: Verifying the executable's signature")
    try {
        $InstallationAssistantSignature = Get-AuthenticodeSignature $WindowsInstallAssistant -ErrorAction Stop
        
        if ($InstallationAssistantSignature.Status -ne "Valid") {
            throw "An invalid signature status of '$($InstallationAssistantSignature.Status)' was provided. Perhaps the downloaded file was corrupted in transit?"
        }
        
        if ($InstallationAssistantSignature.SignerCertificate.Subject -ne "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US") {
            throw "An invalid signature subject of '$($InstallationAssistantSignature.SignerCertificate.Subject)' was provided. Expected Microsoft Corporation certificate."
        }
        
        $Context.Log("INFO: The signature is valid and appears to be what was expected")
    }
    catch {
        $Context.Log("ERROR: Signature verification failed: $($_.Exception.Message)")
        throw "Failed to verify the executable signature for the file '$WindowsInstallAssistant'"
    }
    
    # Create log folder
    if (!(Test-Path -Path $UpdateLogLocation -ErrorAction SilentlyContinue)) {
        $Context.Log("INFO: Creating log folder '$UpdateLogLocation'")
        try {
            New-Item -Path $UpdateLogLocation -ItemType Directory -Force | Out-Null
            $Context.Log("INFO: Successfully created the log folder")
        }
        catch {
            $Context.Log("ERROR: Failed to create log folder: $($_.Exception.Message)")
            throw "Failed to create log folder '$UpdateLogLocation'"
        }
    }
    else {
        $Context.Log("INFO: Log folder already exists")
    }
    
    # Define installation arguments
    $InstallAssistantArguments = @(
        "/QuietInstall"
        "/SkipEULA"
        "/NoRestartUI"
        "/Auto Upgrade"
        "/CopyLogs `"$UpdateLogLocation`""
    )
    
    # Set up process parameters
    $InstallAssistantProcessArguments = @{
        FilePath               = $WindowsInstallAssistant
        ArgumentList           = $InstallAssistantArguments
        RedirectStandardOutput = "$UpdateLogLocation\$(New-Guid).stdout.log"
        RedirectStandardError  = "$UpdateLogLocation\$(New-Guid).stderr.log"
        NoNewWindow            = $True
    }
    
    # Start the upgrade process
    $Context.Log("INFO: Initiating Windows 11 upgrade")
    $Context.Log("WARNING: This may take a few hours to complete")
    $Context.Log("INFO: Logs will be available at '$UpdateLogLocation' and '${env:ProgramFiles(x86)}\WindowsInstallationAssistant\Logs'")
    
    try {
        Start-Process @InstallAssistantProcessArguments
        $Context.Log("INFO: Windows 11 upgrade process started")
    }
    catch {
        $Context.Log("ERROR: Failed to start upgrade process: $($_.Exception.Message)")
        throw "Failed to start the Windows 11 upgrade process using the file '$WindowsInstallAssistant'"
    }
    
    # Wait and verify the process started
    Start-Sleep -Seconds 30
    $Windows10UpgradeApp = Get-Process -Name "Windows10UpgraderApp" -ErrorAction SilentlyContinue
    
    if (!$Windows10UpgradeApp) {
        $Context.Log("ERROR: Failed to detect the upgrade process after starting")
        throw "Failed to start the Windows 11 upgrade process"
    }
    else {
        $Context.Log("INFO: Windows 11 Upgrade Process successfully started")
        $Context.Log("INFO: Process Details:")
        $Context.Log("INFO: - PID: $($Windows10UpgradeApp.Id)")
        $Context.Log("INFO: - Name: $($Windows10UpgradeApp.ProcessName)")
        $Context.Log("INFO: - Path: $($Windows10UpgradeApp.Path)")
    }
    
    $Context.Log("INFO: Windows 11 upgrade installation completed successfully")
    $Context.Log("INFO: The upgrade process is now running in the background")
    $Context.Log("INFO: Monitor the logs for progress and any issues")
}
catch {
    $Context.Log("ERROR: Windows 11 upgrade installation failed: $($_.Exception.Message)")
    throw $_
}

# Helper Functions
function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $True)]
        [String]$URL,
        [Parameter(Mandatory = $True)]
        [String]$Path,
        [Parameter()]
        [int]$Attempts = 3,
        [Parameter()]
        [Switch]$SkipSleep,
        [Parameter()]
        [Switch]$Overwrite
    )

    # Set TLS security protocol
    $SupportedTLSversions = [enum]::GetValues('Net.SecurityProtocolType')
    if ( ($SupportedTLSversions -contains 'Tls13') -and ($SupportedTLSversions -contains 'Tls12') ) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol::Tls13 -bor [System.Net.SecurityProtocolType]::Tls12
    }
    elseif ( $SupportedTLSversions -contains 'Tls12' ) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }
    else {
        $Context.Log("WARNING: TLS 1.2 and/or TLS 1.3 are not supported on this system. This download may fail!")
    }

    # Trim whitespace from parameters
    if ($URL) { $URL = $URL.Trim() }
    if ($Path) { $Path = $Path.Trim() }

    # Validate parameters
    if (!$URL) { throw [System.ArgumentNullException]::New("You must provide a URL.") }
    if (!$Path) { throw [System.ArgumentNullException]::New("You must provide a file path.") }

    $Context.Log("INFO: Downloading from URL: $URL")

    # Validate URL format
    if ($URL -notmatch "^http") {
        $URL = "https://$URL"
        $Context.Log("WARNING: URL modified to: $URL")
    }

    # Validate URL characters
    if ($URL -match "[^A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]") {
        throw [System.IO.InvalidDataException]::New("The url '$URL' contains an invalid character according to RFC3986.")
    }

    # Validate path characters
    if ($Path -and ($Path -match '[/*?"<>|]' -or $Path.SubString(3) -match "[:]")) {
        throw [System.IO.InvalidDataException]::New("The file path specified '$Path' contains invalid characters")
    }

    # Check for reserved folder names
    $Path -split '\\' | ForEach-Object {
        $Folder = ($_).Trim()
        if ($Folder -match '^CON$' -or $Folder -match '^PRN$' -or $Folder -match '^AUX$' -or $Folder -match '^NUL$' -or $Folder -match '^LPT\d$' -or $Folder -match '^COM\d+$') {
            throw [System.IO.InvalidDataException]::New("An invalid folder name was given in '$Path'. Reserved folder names: CON, PRN, AUX, NUL, COM1-9, LPT1-9")
        }
    }

    # Temporarily disable progress reporting
    $PreviousProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    # Handle filename extraction if needed
    if (($Path | Split-Path -Leaf) -notmatch "[.]") {
        $Context.Log("INFO: No filename provided, checking URL for suitable filename")
        
        $ProposedFilename = Split-Path $URL -Leaf
        if ($ProposedFilename -and $ProposedFilename -notmatch "[^A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]" -and $ProposedFilename -match "[.]") {
            $Filename = $ProposedFilename
        }
        
        if ($PSVersionTable.PSVersion.Major -lt 4) {
            $ProgressPreference = $PreviousProgressPreference
            throw [System.NotSupportedException]::New("You must provide a filename for systems not running PowerShell 4 or higher.")
        }

        if (!$Filename) {
            $Context.Log("INFO: Attempting to discover filename via Content-Disposition header")
            $Request = 1

            While ($Request -le $Attempts) {
                if (!($SkipSleep)) {
                    $SleepTime = Get-Random -Minimum 3 -Maximum 15
                    $Context.Log("INFO: Waiting for $SleepTime seconds")
                    Start-Sleep -Seconds $SleepTime
                }
        
                if ($Request -ne 1) { $Context.Log("") }
                $Context.Log("INFO: Attempt $Request")

                try {
                    $HeaderRequest = Invoke-WebRequest -Uri $URL -Method "HEAD" -MaximumRedirection 10 -UseBasicParsing -ErrorAction Stop
                }
                catch {
                    $Context.Log("WARNING: Header request failed: $($_.Exception.Message)")
                }

                if (!$HeaderRequest.Headers."Content-Disposition") {
                    $Context.Log("WARNING: No Content-Disposition header provided")
                }
                else {
                    $Content = [System.Net.Mime.ContentDisposition]::new($HeaderRequest.Headers."Content-Disposition")
                    $Filename = $Content.FileName
                }

                if ($Filename) {
                    $Request = $Attempts
                }

                $Request++
            }
        }

        if ($Filename) {
            $Path = "$Path\$Filename"
        }
        else {
            $ProgressPreference = $PreviousProgressPreference
            throw [System.IO.FileNotFoundException]::New("Unable to find a suitable filename from the URL.")
        }
    }

    # Check if file exists and handle overwrite
    if ((Test-Path -Path $Path -ErrorAction SilentlyContinue) -and !$Overwrite) {
        $ProgressPreference = $PreviousProgressPreference
        throw [System.IO.IOException]::New("A file already exists at the path '$Path'.")
    }

    # Ensure destination folder exists
    $DestinationFolder = $Path | Split-Path
    if (!(Test-Path -Path $DestinationFolder -ErrorAction SilentlyContinue)) {
        try {
            $Context.Log("INFO: Creating folder '$DestinationFolder'")
            New-Item -Path $DestinationFolder -ItemType "directory" -ErrorAction Stop | Out-Null
            $Context.Log("INFO: Successfully created the folder")
        }
        catch {
            $ProgressPreference = $PreviousProgressPreference
            throw $_
        }
    }

    $Context.Log("INFO: Downloading the file...")

    # Download with retry logic
    $DownloadAttempt = 1
    While ($DownloadAttempt -le $Attempts) {
        if (!($SkipSleep)) {
            $SleepTime = Get-Random -Minimum 3 -Maximum 15
            $Context.Log("INFO: Waiting for $SleepTime seconds")
            Start-Sleep -Seconds $SleepTime
        }
        
        if ($DownloadAttempt -ne 1) { $Context.Log("") }
        $Context.Log("INFO: Download Attempt $DownloadAttempt")

        try {
            if ($PSVersionTable.PSVersion.Major -lt 4) {
                $WebClient = New-Object System.Net.WebClient
                $WebClient.DownloadFile($URL, $Path)
            }
            else {
                $WebRequestArgs = @{
                    Uri                = $URL
                    OutFile            = $Path
                    MaximumRedirection = 10
                    UseBasicParsing    = $true
                }
                Invoke-WebRequest @WebRequestArgs
            }

            $File = Test-Path -Path $Path -ErrorAction SilentlyContinue
        }
        catch {
            $Context.Log("WARNING: Download attempt failed: $($_.Exception.Message)")

            if (Test-Path -Path $Path -ErrorAction SilentlyContinue) {
                Remove-Item $Path -Force -Confirm:$false -ErrorAction SilentlyContinue
            }

            $File = $False
        }

        if ($File) {
            $DownloadAttempt = $Attempts
        }
        else {
            $Context.Log("WARNING: File failed to download")
        }

        $DownloadAttempt++
    }

    # Restore progress preference
    $ProgressPreference = $PreviousProgressPreference

    # Final verification
    if (!(Test-Path $Path)) {
        throw [System.IO.FileNotFoundException]::New("Failed to download file. Please verify the URL of '$URL'.")
    }
    else {
        $Context.Log("INFO: Download completed successfully")
        return $Path
    }
}

function Get-HardwareReadiness() {
    # Simplified hardware readiness check (same as in Detect.ps1)
    [int]$MinOSDiskSizeGB = 64
    [int]$MinMemoryGB = 4
    [Uint32]$MinClockSpeedMHz = 1000
    [Uint32]$MinLogicalCores = 2
    [Uint16]$RequiredAddressWidth = 64

    $PASS_STRING = "PASS"
    $FAIL_STRING = "FAIL"
    $FAILED_TO_RUN_STRING = "FAILED TO RUN"
    $UNDETERMINED_CAPS_STRING = "UNDETERMINED"
    $UNDETERMINED_STRING = "Undetermined"
    $CAPABLE_STRING = "Capable"
    $NOT_CAPABLE_STRING = "Not capable"
    $CAPABLE_CAPS_STRING = "CAPABLE"
    $NOT_CAPABLE_CAPS_STRING = "NOT CAPABLE"
    $STORAGE_STRING = "Storage"
    $OS_DISK_SIZE_STRING = "OSDiskSize"
    $MEMORY_STRING = "Memory"
    $SYSTEM_MEMORY_STRING = "System_Memory"
    $GB_UNIT_STRING = "GB"
    $TPM_STRING = "TPM"
    $TPM_VERSION_STRING = "TPMVersion"
    $PROCESSOR_STRING = "Processor"
    $SECUREBOOT_STRING = "SecureBoot"

    $logFormat = '{0}: {1}={2}. {3}; '
    $logFormatWithUnit = '{0}: {1}={2}{3}. {4}; '
    $logFormatReturnReason = '{0}, '
    $logFormatException = '{0}; '
    $logFormatWithBlob = '{0}: {1}. {2}; '

    $outObject = @{ returnCode = -2; returnResult = $FAILED_TO_RUN_STRING; returnReason = ""; logging = "" }

    function Private:UpdateReturnCode {
        param([Parameter(Mandatory = $true)][ValidateRange(-2, 1)][int] $ReturnCode)
        Switch ($ReturnCode) {
            0 { if ($outObject.returnCode -eq -2) { $outObject.returnCode = $ReturnCode } }
            1 { $outObject.returnCode = $ReturnCode }
            -1 { if ($outObject.returnCode -ne 1) { $outObject.returnCode = $ReturnCode } }
        }
    }

    # Storage check
    try {
        $osDrive = Get-CimInstance -Class Win32_OperatingSystem | Select-Object -Property SystemDrive
        $osDriveSize = Get-CimInstance -Class Win32_LogicalDisk -Filter "DeviceID='$($osDrive.SystemDrive)'" | Select-Object @{Name = "SizeGB"; Expression = { $_.Size / 1GB -as [int] }}  
        
        if ($null -eq $osDriveSize) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $STORAGE_STRING
            $outObject.logging += $logFormatWithBlob -f $STORAGE_STRING, "Storage is null", $FAIL_STRING
        }
        elseif ($osDriveSize.SizeGB -lt $MinOSDiskSizeGB) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $STORAGE_STRING
            $outObject.logging += $logFormatWithUnit -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, ($osDriveSize.SizeGB), $GB_UNIT_STRING, $FAIL_STRING
        }
        else {
            $outObject.logging += $logFormatWithUnit -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, ($osDriveSize.SizeGB), $GB_UNIT_STRING, $PASS_STRING
            UpdateReturnCode -ReturnCode 0
        }
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormat -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    }

    # Memory check
    try {
        $memory = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum | Select-Object @{Name = "SizeGB"; Expression = { $_.Sum / 1GB -as [int] }}
        
        if ($null -eq $memory) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $MEMORY_STRING
            $outObject.logging += $logFormatWithBlob -f $MEMORY_STRING, "Memory is null", $FAIL_STRING
        }
        elseif ($memory.SizeGB -lt $MinMemoryGB) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $MEMORY_STRING
            $outObject.logging += $logFormatWithUnit -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, ($memory.SizeGB), $GB_UNIT_STRING, $FAIL_STRING
        }
        else {
            $outObject.logging += $logFormatWithUnit -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, ($memory.SizeGB), $GB_UNIT_STRING, $PASS_STRING
            UpdateReturnCode -ReturnCode 0
        }
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormat -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    }

    # TPM check
    try {
        $tpm = Get-Tpm
        
        if ($null -eq $tpm) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
            $outObject.logging += $logFormatWithBlob -f $TPM_STRING, "TPM is null", $FAIL_STRING
        }
        elseif ($tpm.TpmPresent) {
            $tpmVersion = Get-CimInstance -Class Win32_Tpm -Namespace root\CIMV2\Security\MicrosoftTpm | Select-Object -Property SpecVersion
            
            if ($null -eq $tpmVersion.SpecVersion) {
                UpdateReturnCode -ReturnCode 1
                $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, "null", $FAIL_STRING
            }
            
            $majorVersion = $tpmVersion.SpecVersion.Split(",")[0] -as [int]
            if ($majorVersion -lt 2) {
                UpdateReturnCode -ReturnCode 1
                $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpmVersion.SpecVersion), $FAIL_STRING
            }
            else {
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpmVersion.SpecVersion), $PASS_STRING
                UpdateReturnCode -ReturnCode 0
            }
        }
        else {
            if ($tpm.GetType().Name -eq "String") {
                UpdateReturnCode -ReturnCode -1
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
                $outObject.logging += $logFormatException -f $tpm
            }
            else {
                UpdateReturnCode -ReturnCode 1
                $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpm.TpmPresent), $FAIL_STRING
            }
        }
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    }

    # CPU check (simplified)
    try {
        $cpuDetails = @(Get-CimInstance -Class Win32_Processor)[0]
        
        if ($null -eq $cpuDetails) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $PROCESSOR_STRING
            $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, "CpuDetails is null", $FAIL_STRING
        }
        else {
            $processorCheckFailed = $false
            
            # AddressWidth
            if ($null -eq $cpuDetails.AddressWidth -or $cpuDetails.AddressWidth -ne $RequiredAddressWidth) {
                UpdateReturnCode -ReturnCode 1
                $processorCheckFailed = $true
            }
            
            # ClockSpeed
            if ($null -eq $cpuDetails.MaxClockSpeed -or $cpuDetails.MaxClockSpeed -le $MinClockSpeedMHz) {
                UpdateReturnCode -ReturnCode 1
                $processorCheckFailed = $true  
            }
            
            # Number of Logical Cores
            if ($null -eq $cpuDetails.NumberOfLogicalProcessors -or $cpuDetails.NumberOfLogicalProcessors -lt $MinLogicalCores) {
                UpdateReturnCode -ReturnCode 1
                $processorCheckFailed = $true
            }
            
            $cpuDetailsLog = "{AddressWidth=$($cpuDetails.AddressWidth); MaxClockSpeed=$($cpuDetails.MaxClockSpeed); NumberOfLogicalCores=$($cpuDetails.NumberOfLogicalProcessors); Manufacturer=$($cpuDetails.Manufacturer); Caption=$($cpuDetails.Caption)}"
            
            if ($processorCheckFailed) {
                $outObject.returnReason += $logFormatReturnReason -f $PROCESSOR_STRING
                $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, ($cpuDetailsLog), $FAIL_STRING
            }
            else {
                $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, ($cpuDetailsLog), $PASS_STRING
                UpdateReturnCode -ReturnCode 0
            }
        }
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormat -f $PROCESSOR_STRING, $PROCESSOR_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    }

    # SecureBoot check
    try {
        Confirm-SecureBootUEFI | Out-Null
        $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $CAPABLE_STRING, $PASS_STRING
        UpdateReturnCode -ReturnCode 0
    }
    catch [System.PlatformNotSupportedException] {
        UpdateReturnCode -ReturnCode 1
        $outObject.returnReason += $logFormatReturnReason -f $SECUREBOOT_STRING
        $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $NOT_CAPABLE_STRING, $FAIL_STRING 
    }
    catch [System.UnauthorizedAccessException] {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    }

    Switch ($outObject.returnCode) {
        0 { $outObject.returnResult = $CAPABLE_CAPS_STRING }
        1 { $outObject.returnResult = $NOT_CAPABLE_CAPS_STRING }
        -1 { $outObject.returnResult = $UNDETERMINED_CAPS_STRING }
        -2 { $outObject.returnResult = $FAILED_TO_RUN_STRING }
    }

    $outObject | ConvertTo-Json -Compress
}
