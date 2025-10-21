# Windows 11 Upgrade Detection Script
# This script detects if Windows 11 is already installed or if Windows 10 is ready for upgrade

try {
    $Context.Log("INFO: Starting Windows 11 upgrade detection")
    
    # Get operating system information
    try {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $Context.Log("INFO: Current OS: $($OS.Caption) Version: $($OS.Version)")
    }
    catch {
        $Context.Log("ERROR: Unable to retrieve operating system information: $($_.Exception.Message)")
        exit 1
    }
    
    # Check if already running Windows 11
    if ($OS.Caption -match "Windows 11") {
        $Context.Log("INFO: Windows 11 is already installed")
        exit 0  # Exit code 0 means Windows 11 is detected/installed
    }
    
    # Check if running Windows 10
    if ($OS.Caption -notmatch "Windows 10") {
        $Context.Log("ERROR: This device is not running Windows 10. Current OS: $($OS.Caption)")
        exit 1  # Exit code 1 means not applicable for upgrade
    }
    
    $Context.Log("INFO: Windows 10 detected, checking compatibility")
    
    # Check disk space (minimum 64GB required)
    try {
        $osDrive = Get-Volume -DriveLetter ($env:SystemDrive -replace ":") -ErrorAction Stop
        if (!$osDrive.SizeRemaining) {
            throw "Failed to retrieve remaining size for drive '$env:SystemDrive'"
        }
        
        $freeSpaceGB = [math]::Round(($osDrive.SizeRemaining / 1GB), 2)
        $Context.Log("INFO: Available disk space: $freeSpaceGB GB")
        
        if ($osDrive.SizeRemaining -lt 64GB) {
            $Context.Log("ERROR: Insufficient disk space. Required: 64GB, Available: $freeSpaceGB GB")
            exit 1
        }
    }
    catch {
        $Context.Log("ERROR: Failed to check disk space: $($_.Exception.Message)")
        exit 1
    }
    
    # Check Windows 11 hardware compatibility
    try {
        $Context.Log("INFO: Checking Windows 11 hardware compatibility")
        
        # Run hardware readiness check
        $hardwareReadiness = Get-HardwareReadiness
        
        if ($hardwareReadiness) {
            $result = $hardwareReadiness | ConvertFrom-Json
            $Context.Log("INFO: Hardware compatibility result: $($result.returnResult)")
            
            # Check if system is capable
            if ($result.returnCode -eq 0) {
                $Context.Log("INFO: System is compatible with Windows 11")
            }
            else {
                $Context.Log("ERROR: System is not compatible with Windows 11. Reason: $($result.returnReason)")
                exit 1
            }
        }
        else {
            $Context.Log("WARNING: Could not determine hardware compatibility")
            exit 1
        }
    }
    catch {
        $Context.Log("ERROR: Hardware compatibility check failed: $($_.Exception.Message)")
        exit 1
    }
    
    # Check if upgrade is already in progress
    try {
        $Windows10UpgradeApp = Get-Process -Name "Windows10UpgraderApp" -ErrorAction SilentlyContinue
        if ($Windows10UpgradeApp) {
            $Context.Log("ERROR: Windows 11 upgrade is already in progress")
            exit 1
        }
        else {
            $Context.Log("INFO: No upgrade process currently running")
        }
    }
    catch {
        $Context.Log("WARNING: Could not check for running upgrade process: $($_.Exception.Message)")
    }
    
    # Check if Windows 11 Installation Assistant is already downloaded
    $installAssistantPath = "$env:TEMP\Windows11InstallAssistant\Windows11InstallationAssistant.exe"
    if (Test-Path $installAssistantPath) {
        $Context.Log("INFO: Windows 11 Installation Assistant already downloaded")
        # Verify signature
        try {
            $signature = Get-AuthenticodeSignature $installAssistantPath -ErrorAction Stop
            if ($signature.Status -eq "Valid" -and 
                $signature.SignerCertificate.Subject -eq "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US") {
                $Context.Log("INFO: Installation Assistant signature is valid")
                exit 0  # Already downloaded and ready
            }
            else {
                $Context.Log("WARNING: Installation Assistant signature is invalid, will re-download")
            }
        }
        catch {
            $Context.Log("WARNING: Could not verify Installation Assistant signature: $($_.Exception.Message)")
        }
    }
    
    $Context.Log("INFO: Windows 10 is ready for Windows 11 upgrade")
    exit 1  # Exit code 1 means upgrade is needed
}
catch {
    $Context.Log("ERROR: Detection failed: $($_.Exception.Message)")
    exit 1
}

# Hardware Readiness Function (simplified version from original script)
function Get-HardwareReadiness() {
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
