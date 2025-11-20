<#
.SYNOPSIS
    Adds NME Tags (NMW_ prefix) to NMM-tagged Image Resources using Azure Resource Graph

.DESCRIPTION
    Uses Azure Resource Graph to efficiently find NMM-tagged Image Resources (with WAP_ prefix tags)
    across all subscriptions and adds corresponding NME tags (NMW_ prefix) to them. 
    Also finds and tags related NICs.
    Requires appropriate permissions in Azure to query Resource Graph and modify resources.

.NOTES
    Requires:
    - Az.ResourceGraph module (pre-installed in Azure Cloud Shell)
    - Az.Resources module (pre-installed in Azure Cloud Shell)
    - Appropriate Azure permissions for Resource Graph queries and resource tag updates
    
    Compatible with Azure Cloud Shell - modules are pre-installed.
    If running locally and modules are missing, install with:
    Install-Module Az.ResourceGraph, Az.Resources -Scope CurrentUser
#>

# Check for required modules
$requiredModules = @('Az.ResourceGraph', 'Az.Resources')
$missingModules = @()

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        $missingModules += $module
    }
}

if ($missingModules.Count -gt 0) {
    Write-Error "Missing required modules: $($missingModules -join ', ')"
    Write-Output "For Azure Cloud Shell: Modules should be pre-installed. If missing, contact support."
    Write-Output "For local execution: Install-Module $($missingModules -join ', ') -Scope CurrentUser"
    exit 1
}

# Import modules
try {
    Import-Module Az.ResourceGraph -ErrorAction Stop
    Import-Module Az.Resources -ErrorAction Stop
}
catch {
    Write-Error "Failed to import required modules: $_"
    exit 1
}

Write-Output "Querying Azure Resource Graph for NMM-tagged resources..."

try {
    # ARG query to find image resources tagged by NMM (WAP_ prefix)
    $imageResourcesQuery = @"
resources
| where type =~ 'microsoft.compute/images'
    or type =~ 'microsoft.compute/virtualmachines'
    or tags["WAP_OBJECT_TYPE"] in~ ('DESKTOP_IMAGE', 'DESKTOP_IMAGE_VM')
| project
    id,
    name,
    type,
    subscriptionId,
    tags,
    jobGuid = tostring(tags['WAP_JOB_GUID'])
"@

    $imageResources = Search-AzGraph -Query $imageResourcesQuery -ErrorAction Stop

    if ($null -eq $imageResources -or $imageResources.Count -eq 0) {
        Write-Output "No NMM-tagged image resources found."
        exit 0
    }

    # Extract unique GUIDs
    $jobGuids = $imageResources.jobGuid | Where-Object { $_ -and $_ -ne '' } | Sort-Object -Unique

    Write-Output "Found $($imageResources.Count) image resources."
    Write-Output "Found $($jobGuids.Count) unique WAP job GUIDs."

    # Query for NICs only if we have job GUIDs
    $nicResources = @()
    if ($jobGuids.Count -gt 0) {
        # ARG query to find NICs with matching job GUID (check both WAP_ and NMW_ prefixes)
        $jobGuidList = $jobGuids -join "','"
        $nicQuery = @"
resources
| where type =~ 'microsoft.network/networkinterfaces'
| where tags['WAP_JOB_GUID'] in~ ('$jobGuidList')
    or tags['NMW_JOB_GUID'] in~ ('$jobGuidList')
| project id, name, type, subscriptionId, tags
"@

        try {
            $nicResources = Search-AzGraph -Query $nicQuery -ErrorAction Stop
            Write-Output "Found $($nicResources.Count) related NICs."
        }
        catch {
            Write-Warning "Failed to query for NICs: $_"
            Write-Output "Continuing with image resources only..."
        }
    }
    else {
        Write-Output "No job GUIDs found, skipping NIC query."
    }

    # Combine images + NICs
    $allResources = @()
    if ($imageResources) {
        $allResources += $imageResources
    }
    if ($nicResources) {
        $allResources += $nicResources
    }

    # Remove duplicates by ID
    $allResources = $allResources | Sort-Object id -Unique

    if ($allResources.Count -eq 0) {
        Write-Output "No resources to tag."
        exit 0
    }

    Write-Output "Total resources to tag: $($allResources.Count)"
    Write-Output ""

    # === Apply new tags ===
    $successCount = 0
    $errorCount = 0

    foreach ($rsc in $allResources) {
        try {
            Write-Output "Processing: $($rsc.name) ($($rsc.type))"

            $oldTags = $rsc.tags
            if ($null -eq $oldTags) {
                Write-Warning "`tResource has no tags, skipping."
                continue
            }

            $newTags = @{}

            # Clone existing tags
            $tagsAdded = $false
            foreach ($key in $oldTags.Keys) {
                $newTags[$key] = $oldTags[$key]

                # Add NMW_ equivalents (reverse of WAP_)
                if ($key.StartsWith("WAP_")) {
                    $newKey = $key.Replace("WAP_", "NMW_")
                    # Only add if it doesn't already exist (don't overwrite existing NMW_ tags)
                    if (-not $newTags.ContainsKey($newKey)) {
                        $newTags[$newKey] = $oldTags[$key]
                        Write-Output "`tAdding tag $newKey = $($oldTags[$key])"
                        $tagsAdded = $true
                    }
                    else {
                        Write-Output "`tTag $newKey already exists, skipping."
                    }
                }
            }

            if (-not $tagsAdded) {
                Write-Output "`tNo WAP_ tags found to duplicate, or all NMW_ equivalents already exist."
                continue
            }

            Write-Output "`tUpdating resource tags..."

            Set-AzResource -ResourceId $rsc.id -Tag $newTags -Force -ErrorAction Stop | Out-Null
            $successCount++
            Write-Output "`t✓ Successfully updated tags."
        }
        catch {
            $errorCount++
            Write-Error "`t✗ Failed to update resource $($rsc.name): $_"
        }
        Write-Output ""
    }

    Write-Output "Tag updates complete."
    Write-Output "Successfully updated: $successCount resources"
    if ($errorCount -gt 0) {
        Write-Warning "Failed to update: $errorCount resources"
    }
}
catch {
    Write-Error "Failed to query Azure Resource Graph: $_"
    exit 1
}

