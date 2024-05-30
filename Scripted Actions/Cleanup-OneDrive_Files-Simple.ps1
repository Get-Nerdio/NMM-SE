# Import the GetCompressedFileSize function from kernel32.dll
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Kernel32 {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern uint GetCompressedFileSize(string lpFileName, out uint lpFileSizeHigh);
}
"@

# Function to get the actual size on disk
function Get-ActualSizeOnDisk {
    param (
        [string]$filePath
    )
    
    $highSize = 0
    $lowSize = [Kernel32]::GetCompressedFileSize($filePath, [ref]$highSize)

    if ($lowSize -eq 0xFFFFFFFF) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($errorCode -ne 0) {
            Write-Output "Error getting size for $filePath : $errorCode"
            return 0
        }
    }

    return ($highSize -shl 32) -bor $lowSize
}

function SetOneDriveFilesToCloud {
    param (
        [int]$MaxLocalSizeMB = 5000 # Maximum allowed size on local disk in MB
    )

    # Convert MB to Bytes
    $MaxLocalSizeBytes = $MaxLocalSizeMB * 1MB

    # Function to unpin a file (set to cloud)
    function UnpinOneDriveFile {
        param (
            [string]$FilePath
        )
        # Using attrib command to set file to cloud
        attrib +U -P $FilePath
    }

    # Function to calculate total size of OneDrive files on local disk
    function Get-LocalOneDriveSize {
        param (
            [string]$UserOneDrivePath
        )
        
        # Initialize a list to store file sizes and paths
        $fileDetails = [System.Collections.Generic.List[Object]]::new()
    
        # Get all files in the OneDrive path and add their details to the list
        Get-ChildItem -Path $UserOneDrivePath -Recurse -File | ForEach-Object {
            $actualSize = Get-ActualSizeOnDisk -filePath $_.FullName
            $fileDetails.Add([PSCustomObject]@{Path = $_.FullName; Size = $actualSize}) | Out-Null
        }
    
        # Calculate the total size by summing the elements of the list
        $totalSize = $fileDetails | Measure-Object -Property Size -Sum
        return $totalSize.Sum, $fileDetails
    }

    # Main loop
    while ($true) {
        $oneDrivePath = $env:OneDrive  # Adjust the OneDrive path if necessary
        $localSize, $fileDetails = Get-LocalOneDriveSize -UserOneDrivePath $oneDrivePath

        Write-Output "Initial local size: $($localSize / 1MB) MB"

        if ($localSize -gt $MaxLocalSizeBytes) {
            $files = Get-ChildItem -Path $oneDrivePath -Recurse -File | Sort-Object LastAccessTime
            foreach ($file in $files) {
                if ($localSize -le $MaxLocalSizeBytes) {
                    Write-Output "OneDrive Cleaned Up"
                    break
                }

                Write-Output "Unpinning file: $($file.FullName)"
                UnpinOneDriveFile -FilePath $file.FullName

                $fileDetail = $fileDetails | Where-Object { $_.Path -eq $file.FullName }
                if ($fileDetail) {
                    [void]$fileDetails.Remove($fileDetail)
                }

                $localSize = $fileDetails | Measure-Object -Property Size -Sum
                $localSize = $localSize.Sum
                Write-Output "Updated local size: $localSize bytes"
            }
        }

        if ($localSize -le $MaxLocalSizeBytes) {
            Write-Output "OneDrive Cleaned Up"
            break
        }
    }
}

# Example usage:
SetOneDriveFilesToCloud -MaxLocalSizeMB 3000