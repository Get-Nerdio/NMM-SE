<#
.SYNOPSIS
    Adds NMM Tags to NME-created Image Resources

.DESCRIPTION
    Cycles through all subscriptions to detect NME-created Image Resources and add corresponding NMM Tags to them.
    Requires appropriate permissions in Azure to modify resources

.NOTES
    AUTHOR:       Tom Biscardi (@tbisque)
    COMPANY:      C3 Integrated Solutions
#>


Foreach ($sub in Get-AzSubscription){
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    Write-Output "Processing subscription: $($sub.Name) ($($sub.Id))"

    $nmeImgRsrcs = (Get-AzResource | ?{ if($_.Tags){($_.Tags["NMW_OBJECT_TYPE"] -eq "DESKTOP_IMAGE") -or ($_.Tags["NMW_OBJECT_TYPE"] -eq "DESKTOP_IMAGE_VM")} })
    $nmeRsrcs = @(); $nmeRsrcs += $nmeImgRsrcs
    $nmeRsrcs.Tags."NMW_JOB_GUID" | Sort-Object -Unique | % {
        $nic = Get-AzResource -ResourceType Microsoft.Network/networkInterfaces -TagName "NMW_JOB_GUID" -TagValue $_ 
        if ($nic.ResourceId -notin $nmeRsrcs.ResourceId){ $nmeRsrcs += $nic }
    }
    if ($nmeRsrcs.Count -eq 0){
        Write-Output "`tNo NME resources found, skipping subscription."
        Continue
    }
    Foreach ($rsc in $nmeRsrcs){
        Write-Output "Processing resource: $($rsc.Name) ($($rsc.ResourceType))"
        #Duplicate tags with NMW_ prefix adding WAP_ prefix
        $oldTagsHT = $rsc.Tags
        $oldTags = $rsc.Tags.Keys | Where-Object {$_.StartsWith("NMW_")}
        Foreach ($tag in $oldTags){
            $newName = $tag.Replace("NMW_","WAP_")
            $oldTagsHT += @{$newName = $rsc.Tags.$tag}
            Write-Output "`t`tAdding tag: $newName = $($rsc.Tags.$tag)"
        }
        Write-Output "`tUpdating resource tags..."
        Set-AzResource -ResourceId $rsc.ResourceId -Tag $oldTagsHT -Force #| Out-Null
    }
    $nmeRsrcs = @();
}
