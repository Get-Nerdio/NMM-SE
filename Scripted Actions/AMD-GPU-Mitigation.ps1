function Invoke-AmdGpuFix {
    [CmdletBinding()]
    param()

    try {
        # Define paths
        $amdPath = "C:\Program Files\AMD"
        $backupPath = "C:\Program Files\AMD.bak"
        $cimiPath = Join-Path -Path $amdPath -ChildPath "CIMI\BIN64"

        # Create backup of AMD folder if it doesn't exist
        if (-not (Test-Path -Path $backupPath)) {
            Write-Output "Creating backup of AMD folder..."
            Rename-Item -Path $amdPath -NewName $backupPath -ErrorAction Stop
        }

        # Create CIMI\BIN64 directory structure
        if (-not (Test-Path -Path $cimiPath)) {
            Write-Output "Creating CIMI\BIN64 directory..."
            New-Item -Path $cimiPath -ItemType Directory -Force -ErrorAction Stop
        }

        Write-Output "AMD GPU fix completed successfully."
    }
    catch {
        Write-Error "Error during AMD GPU fix: $_"
        return $false
    }

    return $true
}

# Execute the function
Invoke-AmdGpuFix
