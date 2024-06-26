using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

try {
    $HaloAPIURL = "https://test.halopsa.com" # URL of your HaloPSA environment.
    Import-Module -Name HaloAPI
    Connect-HaloAPI -URL $HaloAPIURL -ClientID $env:HaloClientID -ClientSecret $env:HaloSecretID
}
catch {
    $_.Exception.Message
}

try {
    $NMMObj = $Request.body

    $HaloObj = [PSCustomObject]@{
        oppjobtitle   = 'New NMM Alert'
        tickettype_id = '27'
        priority_id   = if ($NMMObj.Job.JobStatus -eq 'Completed') { '4' }else { '2' }
        supplier_name = 'Nerdo Manager MSP'
        summary       = "NMM: $(($NMMObj.Job.JobType -creplace '([A-Z])',' $1').Trim())"
        details       = 'Details of the NMM Alert in Additional Fields'
        customFields  = @(
            @{ id = 178; value = if ($NMMObj.AccountId) { $NMMObj.AccountId } else { "Global MSP" } },
            @{ id = 179; value = $NMMObj.Job.Id },
            @{ id = 180; value = $NMMObj.Job.CreationDateUtc },
            @{ id = 181; value = ($NMMObj.Job.JobType -creplace '([A-Z])', ' $1').Trim() },
            @{ id = 182; value = $NMMObj.Job.JobStatus },
            @{ id = 183; value = $NMMObj.Job.JobRunMode },
            @{ id = 184; value = $NMMObj.ConditionId },
            @{ id = 185; value = $NMMObj.ActionId }
        )
    }

    $HaloResponse = New-HaloTicket -Ticket $HaloObj
}
catch {
    $_.Exception.Message
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $HaloResponse
    })