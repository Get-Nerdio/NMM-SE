<#
.SYNOPSIS
    Caches latest Notion installer and sets up per-user installation at logon via startup launcher.

.DESCRIPTION
    This script downloads the latest Notion installer to a stable cache path
    (C:\Installs\Notion) and creates a startup launcher in the All Users Startup
    folder. When a user logs on, the launcher automatically runs a lightweight
    script that checks if Notion is present for that user (in %LOCALAPPDATA%\Programs\Notion)
    and silently installs it from the cached installer if missing.

    High level steps:
    1. Create C:\Installs\Notion directory with proper permissions
    2. Download the latest NotionSetup.exe to the cache location
    3. Write per-user installer script to C:\Installs\Notion
    4. Create a batch file launcher in All Users Startup folder for automatic execution

.EXECUTION MODE NMM
    Individual

.TAGS
    Nerdio, Apps install, Notion

.NOTES
    - Main script logs are saved to: %WINDIR%\Temp\NerdioManagerLogs\Install-Notion.txt
    - Per-user installer logs are saved to: %TEMP%\NerdioManagerLogs\Install-Notion-PerUser.txt
    - Run with administrative privileges to create the cache directory and startup launcher
    - The startup launcher runs automatically for each user at logon in their own context
    - Installation is completely silent with no visible windows to the user

#>

# Define script variables
$NotionDownloadUrl = "https://www.notion.so/desktop/windows/download"
$CacheRoot = "C:\Installs\Notion"
$InstallerFile = "NotionSetup.exe"
$CachedInstallerPath = Join-Path $CacheRoot $InstallerFile
$PerUserScriptPath = Join-Path $CacheRoot "Install-Notion-PerUser.ps1"
$ScheduledTaskName = "Notion-PerUser-Install"
$LogFilePath = "$Env:WinDir\Temp\NerdioManagerLogs"
$LogFile = "Install-Notion.txt"


function NMMLogOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [string]$LogFilePath = $LogFilePath,
        [string]$LogName = $LogFile,
        [bool]$throw = $false,
        [bool]$return = $false,
        [bool]$exit = $false,
        [bool]$FirstLogInnput = $false
    )
    
    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType Directory -Path $LogFilePath -Force | Out-Null
        Write-Output "$LogFilePath has been created."
    }
    else {
        if ($FirstLogInnput -eq $true) {
            Add-Content -Path "$($LogFilePath)\$($LogName)" -Value "################# New Script Run #################"
        }
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level]: $Message"
    
    try {
        Add-Content -Path "$($LogFilePath)\$($LogName)" -Value $logEntry

        if ($throw) {
            throw $Message
        }

        if ($return) {
            return $Message
        }

        if ($exit) {
            Write-Output "$($Message)"
            exit 
        }
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

function New-DirectoryIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Start logging
NMMLogOutput -Level 'Information' -Message 'Starting Notion cache and scheduled task setup' -FirstLogInnput $true

# 1) Ensure cache directory exists and set permissions for all users to read
try {
    New-DirectoryIfMissing -Path $CacheRoot
    # Grant Users group read and execute permissions
    $acl = Get-Acl -Path $CacheRoot
    $users = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($users, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $CacheRoot -AclObject $acl
    NMMLogOutput -Level 'Information' -Message "Ensured cache directory: $CacheRoot with Users read access" -return $true
}
catch {
    NMMLogOutput -Level 'Error' -Message "Failed to prepare cache directory ${CacheRoot}: $($_.exception.message)" -throw $true
}

# 2) Download latest installer to cache
try {
    NMMLogOutput -Level 'Information' -Message "Downloading Notion installer from $NotionDownloadUrl to $CachedInstallerPath ..." -return $true
    $tmpDownload = "$CachedInstallerPath.download"
    Invoke-WebRequest -Uri $NotionDownloadUrl -OutFile $tmpDownload -UseBasicParsing -ErrorAction Stop

    if (Test-Path $CachedInstallerPath) {
        Remove-Item $CachedInstallerPath -Force -ErrorAction SilentlyContinue
    }
    # Move the temp file to the final location
    Move-Item -Path $tmpDownload -Destination $CachedInstallerPath -Force
    NMMLogOutput -Level 'Information' -Message "Installer cached: $CachedInstallerPath" -return $true
}
catch {
    NMMLogOutput -Level 'Error' -Message "Failed to download Notion installer: $($_.exception.message)" -throw $true
}

# 3) Write the per-user installer script
try {
    $perUserScript = @'
param(
    [string]$CacheRoot = "C:\\Installs\\Notion",
    [string]$InstallerFile = "NotionSetup.exe"
)

# Use user-accessible temp directory instead of system temp
$LogFilePath = "$env:TEMP\NerdioManagerLogs"
$LogFile = "Install-Notion-PerUser.txt"

function Log {
    param([string]$Message, [string]$Level = 'Information')
    try {
        if (-not (Test-Path $LogFilePath)) { 
            New-Item -ItemType Directory -Path $LogFilePath -Force -ErrorAction Stop | Out-Null 
        }
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path "$LogFilePath\$LogFile" -Value "$timestamp [$Level] ${env:USERNAME}: $Message" -ErrorAction Stop
    }
    catch {
        # If logging fails, try to write to user's local appdata as fallback
        try {
            $fallbackLogPath = Join-Path $env:LOCALAPPDATA "NerdioManagerLogs"
            if (-not (Test-Path $fallbackLogPath)) {
                New-Item -ItemType Directory -Path $fallbackLogPath -Force -ErrorAction Stop | Out-Null
            }
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Add-Content -Path (Join-Path $fallbackLogPath $LogFile) -Value "$timestamp [$Level] ${env:USERNAME}: $Message" -ErrorAction Stop
        }
        catch {
            # Last resort - just output to console if logging completely fails
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Output "$timestamp [$Level] ${env:USERNAME}: $Message"
        }
    }
}

try {
    # When running as SYSTEM, we need to find the logged-on user
    $userProfilePath = $null
    $loggedOnUserName = $null
    
    if ($env:USERNAME -eq "SYSTEM") {
        Log "Running as SYSTEM, detecting logged-on user..."
        
        # Method 1: Get logged-on user from Win32_ComputerSystem
        $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($systemInfo -and $systemInfo.UserName) {
            $loggedOnUserName = $systemInfo.UserName.Split('\')[-1]
            Log "Found logged-on user via Win32_ComputerSystem: $loggedOnUserName"
        }
        
        # Method 2: Get from active console session
        if (-not $loggedOnUserName) {
            $sessions = query session 2>&1
            if ($sessions) {
                foreach ($line in $sessions) {
                    if ($line -match '^\s+(\d+)\s+(\w+)\s+.*Active') {
                        $sessionUser = $matches[2]
                        if ($sessionUser -ne "console" -and $sessionUser -ne "SYSTEM") {
                            $loggedOnUserName = $sessionUser
                            Log "Found logged-on user via query session: $loggedOnUserName"
                break
            }
        }
    }
            }
        }
        
        # Method 3: Get from Win32_UserProfile (most reliable)
        if (-not $loggedOnUserName) {
            $userProfiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { -not $_.Special }
            foreach ($profile in $userProfiles) {
                $profilePath = $profile.LocalPath
                $sid = $profile.SID
                try {
                    $account = New-Object System.Security.Principal.SecurityIdentifier($sid)
                    $userAccount = $account.Translate([System.Security.Principal.NTAccount])
                    $userName = $userAccount.Value.Split('\')[-1]
                    
                    # Check if this user is currently logged on by looking at registry
                    $ntUserPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
                    if (Test-Path $ntUserPath) {
                        $profileState = (Get-ItemProperty -Path $ntUserPath -Name "State" -ErrorAction SilentlyContinue).State
                        if ($profileState -eq 0) {  # 0 = loaded
                            $loggedOnUserName = $userName
                            $userProfilePath = $profilePath
                            Log "Found logged-on user via Win32_UserProfile: $loggedOnUserName (Profile: $profilePath)"
                break
            }
                    }
                } catch {
                    # Skip if we can't translate SID
                }
            }
        }
        
        if (-not $userProfilePath -and $loggedOnUserName) {
            # Get profile path from username
            $allProfiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { -not $_.Special }
            foreach ($profile in $allProfiles) {
                if ($profile.LocalPath -like "*\$loggedOnUserName") {
                    $userProfilePath = $profile.LocalPath
                    Log "Found profile path for ${loggedOnUserName}: $userProfilePath"
                    break
                }
            }
        }
        
        if (-not $userProfilePath) {
            Log "Could not determine logged-on user profile path. Using default check." 'Warning'
        } else {
            $targetExe = Join-Path $userProfilePath "AppData\Local\Programs\Notion\Notion.exe"
            $targetLocalAppData = Join-Path $userProfilePath "AppData\Local"
            
            if (Test-Path $targetExe) {
                Log "Notion already present for user ${loggedOnUserName}. Skipping install. Path: $targetExe"
                exit 0
            }
            
            # Set environment variables for the logged-on user before installing
            $env:LOCALAPPDATA = $targetLocalAppData
            $env:APPDATA = Join-Path $userProfilePath "AppData\Roaming"
            $env:USERPROFILE = $userProfilePath
            Log "Set environment variables for user ${loggedOnUserName}: LOCALAPPDATA=$env:LOCALAPPDATA"
        }
    }
    
    # If running in user context (not SYSTEM) or if we couldn't find the user
    if (-not $userProfilePath) {
        $targetExe = Join-Path $env:LOCALAPPDATA "Programs\Notion\Notion.exe"
    }
    
    if (Test-Path $targetExe) {
        Log "Notion already present. Skipping install. Path: $targetExe"
        exit 0
    }

    $installer = Join-Path $CacheRoot $InstallerFile
    if (-not (Test-Path $installer)) {
        Log "Cached installer missing at $installer" 'Error'
        exit 1
    }

    Log "Launching per-user Notion install from $installer"
    Log "Current context - USERNAME: $env:USERNAME, LOCALAPPDATA: $env:LOCALAPPDATA, USERPROFILE: $env:USERPROFILE"
    
    # Create a ProcessStartInfo object to explicitly set environment variables
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $installer
    $processInfo.Arguments = '/S'
    $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $processInfo.CreateNoWindow = $true
    $processInfo.UseShellExecute = $false
    
    # If we found a user profile, set environment variables for the installer
    if ($userProfilePath) {
        $targetLocalAppData = Join-Path $userProfilePath "AppData\Local"
        $targetRoaming = Join-Path $userProfilePath "AppData\Roaming"
        $processInfo.EnvironmentVariables['LOCALAPPDATA'] = $targetLocalAppData
        $processInfo.EnvironmentVariables['APPDATA'] = $targetRoaming
        $processInfo.EnvironmentVariables['USERPROFILE'] = $userProfilePath
        Log "Set installer environment - LOCALAPPDATA: $targetLocalAppData, APPDATA: $targetRoaming, USERPROFILE: $userProfilePath"
    }
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    Log "Installer exit code: $exitCode"

    # Wait for any child processes to complete (Notion installer may spawn them)
    $waitCount = 0
    $maxWait = 30
    while ($waitCount -lt $maxWait) {
        $notionProcesses = Get-Process -Name "NotionSetup" -ErrorAction SilentlyContinue
        if (-not $notionProcesses) {
            break
        }
        Start-Sleep -Seconds 2
        $waitCount++
    }
    
    if ($waitCount -ge $maxWait) {
        Log "Waited for NotionSetup processes but they may still be running" 'Warning'
    }

    # Re-check the target path (in case it was set earlier)
    if (-not $userProfilePath) {
        $targetExe = Join-Path $env:LOCALAPPDATA "Programs\Notion\Notion.exe"
    }
    
    # Poll for Notion.exe to appear (installer extracts many files, may take time)
    Log "Waiting for Notion installation to complete..."
    $maxWaitTime = 180  # 3 minutes max
    $waitInterval = 5   # Check every 5 seconds
    $elapsedTime = 0
    $notionFound = $false
    
    while ($elapsedTime -lt $maxWaitTime) {
        Start-Sleep -Seconds $waitInterval
        $elapsedTime += $waitInterval
        
        # Check the expected path
        if (Test-Path $targetExe) {
            $fileInfo = Get-Item $targetExe -ErrorAction SilentlyContinue
            if ($fileInfo -and $fileInfo.Length -gt 0) {
                Log "Notion installed successfully at $targetExe (found after $elapsedTime seconds)" 
                $notionFound = $true
                break
            }
        }
        
        # Also check if installation directory exists and has files
        $notionDir = Split-Path $targetExe -Parent
        if (Test-Path $notionDir) {
            $fileCount = (Get-ChildItem -Path $notionDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($fileCount -gt 10) {
                Log "Notion directory exists with $fileCount files, checking for Notion.exe..."
            }
        }
    }
    
    if ($notionFound) {
        exit 0
    } else {
        Log "Notion install did not produce expected path: $targetExe" 'Warning'
        Log "Current USERNAME: $env:USERNAME, LOCALAPPDATA: $env:LOCALAPPDATA" 'Warning'
        Log "Waited $elapsedTime seconds for installation to complete" 'Warning'
        
        # Comprehensive search for Notion installation in all user profiles
        Log "Searching for Notion installation in all user profiles..." 'Warning'
        $foundPath = $null
        
        # Search all user profiles - this is the most reliable method
        try {
            $userProfiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { -not $_.Special } -ErrorAction SilentlyContinue
            if ($userProfiles) {
                foreach ($profile in $userProfiles) {
                    $profilePath = $profile.LocalPath
                    $searchPath = Join-Path $profilePath "AppData\Local\Programs\Notion\Notion.exe"
                    if (Test-Path $searchPath) {
                        try {
                            $fileInfo = Get-Item $searchPath -ErrorAction Stop
                            if ($fileInfo -and $fileInfo.Length -gt 0) {
                                $foundPath = $searchPath
                                Log "Found Notion installed in user profile: $foundPath" 'Warning'
                                break
                            }
                        } catch {
                            # Continue searching
                        }
                    }
                }
            }
        } catch {
            Log "Error searching user profiles: $($_.Exception.Message)" 'Warning'
        }
        
        # Also check the wildcard path as fallback
        if (-not $foundPath) {
            try {
                $wildcardPath = "C:\Users\*\AppData\Local\Programs\Notion\Notion.exe"
                $found = Get-ChildItem -Path $wildcardPath -ErrorAction SilentlyContinue
                if ($found) {
                    foreach ($item in $found) {
                        try {
                            if ($item.Length -gt 0) {
                                $foundPath = $item.FullName
                                Log "Found Notion via wildcard search: $foundPath" 'Warning'
                                break
                            }
                        } catch {
                            # Continue
                        }
                    }
                }
            } catch {
                Log "Wildcard search failed: $($_.Exception.Message)" 'Warning'
            }
        }
        
        # Also check system/localappdata locations that might be used
        if (-not $foundPath) {
            $systemPaths = @(
                "$env:LOCALAPPDATA\Programs\Notion\Notion.exe",
                "C:\Windows\System32\config\systemprofile\AppData\Local\Programs\Notion\Notion.exe"
            )
            foreach ($sysPath in $systemPaths) {
                if (Test-Path $sysPath) {
                    try {
                        $fileInfo = Get-Item $sysPath -ErrorAction Stop
                        if ($fileInfo -and $fileInfo.Length -gt 0) {
                            $foundPath = $sysPath
                            Log "Found Notion in system location: $foundPath" 'Warning'
                            break
                        }
                    } catch {
                        # Continue
                    }
                }
            }
        }
        
        if ($foundPath) {
            # If we found it anywhere, that's still a success - installation worked
            Log "Installation succeeded but at unexpected location: $foundPath" 
            Log "Notion is installed and available at: $foundPath"
            exit 0
        } else {
            Log "Could not locate Notion installation after $elapsedTime seconds. Installation may have failed." 'Error'
            Log "Searched: expected path, all user profiles, system locations, and wildcard paths" 'Error'
            exit 2
        }
    }
}
catch {
    Log "Exception during per-user install: $($_.Exception.Message)" 'Error'
    Log "Stack trace: $($_.Exception.Message)" 'Error'
    exit 3
}
'@

    $perUserScript | Out-File -FilePath $PerUserScriptPath -Encoding UTF8 -Force
    NMMLogOutput -Level 'Information' -Message "Per-user installer script written to $PerUserScriptPath" -return $true
}
catch {
    NMMLogOutput -Level 'Error' -Message "Failed to write per-user script: $($_.exception.message)" -throw $true
}

# 4) Create startup script in All Users Startup folder
# This is simpler and runs automatically for every user at logon in their context
try {
    # Remove existing scheduled task if it exists (cleanup from previous method)
    try {
        $existingTask = Get-ScheduledTask -TaskName $ScheduledTaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            NMMLogOutput -Level 'Information' -Message "Removing old scheduled task '$ScheduledTaskName' (no longer needed)..." -return $true
            Unregister-ScheduledTask -TaskName $ScheduledTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Also try removing via schtasks in case it exists there
        schtasks /Query /TN $ScheduledTaskName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            schtasks /Delete /TN $ScheduledTaskName /F 2>&1 | Out-Null
        }
    }
    catch {
        # Ignore errors during cleanup
    }

    # Use All Users Startup folder - much simpler and runs in user context automatically
    NMMLogOutput -Level 'Information' -Message "Creating startup script in All Users Startup folder..." -return $true
    
    $allUsersStartup = [System.Environment]::GetFolderPath("CommonStartMenu")
    $startupFolder = Join-Path $allUsersStartup "Programs\Startup"
    
    # Ensure Startup folder exists
    if (-not (Test-Path $startupFolder)) {
        New-Item -ItemType Directory -Path $startupFolder -Force | Out-Null
    }
    
    # Create a batch file launcher that runs the PowerShell script silently
    # Batch files auto-execute from Startup folder reliably and avoid VBScript security concerns
    # Using @echo off and WindowStyle Hidden ensures no visible windows to the user
    $batLauncher = Join-Path $startupFolder "Install-Notion-Launcher.cmd"
    $batContent = @"
@echo off
REM Launch Notion installer script silently - no window visible to user
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$PerUserScriptPath"
"@
    
    $batContent | Out-File -FilePath $batLauncher -Encoding ASCII -Force
    NMMLogOutput -Level 'Information' -Message "Created startup launcher at: $batLauncher" -return $true
    NMMLogOutput -Level 'Information' -Message "Using batch file launcher (no VBScript, no execution policy issues) - runs silently" -return $true
    NMMLogOutput -Level 'Information' -Message "Script will run automatically for all users at logon in their context" -return $true
}
catch {
    NMMLogOutput -Level 'Error' -Message "Failed to create startup script: $($_.exception.message)" -throw $true
}

NMMLogOutput -Level 'Information' -Message "Completed Notion cache and startup script setup." -return $true























