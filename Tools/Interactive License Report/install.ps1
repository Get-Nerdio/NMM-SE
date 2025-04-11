# Define the GitHub repository URL
$repoUrl = "https://github.com/Get-Nerdio/NMM-SE"
$zipUrl = "$repoUrl/archive/refs/heads/main.zip"

# Current directory where the script is run
$currentDir = Get-Location

# Path for the downloaded ZIP file
$zipPath = Join-Path $currentDir "NMM-SE.zip"

# Destination folder for extraction
$extractPath = Join-Path $currentDir "Interactive-License-Report"
$tempExtractPath = Join-Path $currentDir "NMM-SE-main"
$sourcePath = Join-Path $tempExtractPath "Tools\Interactive License Report"

try {
    Write-Output "Downloading repository from $zipUrl..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -ErrorAction Stop

    Write-Output "Download complete. Extracting contents..."
    Expand-Archive -Path $zipPath -DestinationPath $currentDir -Force

    # Move contents from NMM-SE-main/Tools/Interactive License Report to Interactive-License-Report
    if (Test-Path $sourcePath) {
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force
        }
        
        # Create the destination directory
        New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
        
        # Copy all items from the source to the destination
        Copy-Item -Path "$sourcePath\*" -Destination $extractPath -Recurse -Force
        
        Write-Output "Extraction complete. The Interactive License Report tool is now available in the '$extractPath' folder."
    } else {
        throw "Expected folder '$sourcePath' not found after extraction"
    }
}
catch {
    Write-Output "An error occurred: $($_.Exception.Message)"
    return
}

try {
    # Clean up: Remove the ZIP file and temporary extraction directory
    Remove-Item $zipPath -Force
    Remove-Item $tempExtractPath -Recurse -Force
    Write-Output "Temporary files removed."
    
    # Change to the tool directory
    Set-Location $extractPath
    Write-Output "Changed directory to $extractPath"
    Write-Output "You can now run the License Report tool using: .\LicenseReport.ps1"
}
catch {
    Write-Output "Cleanup error: $($_.Exception.Message)"
}