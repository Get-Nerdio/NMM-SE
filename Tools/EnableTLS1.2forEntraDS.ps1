<#
This is a script from Microsoft (https://learn.microsoft.com/en-us/entra/identity/domain-services/reference-domain-services-tls-enforcement?tabs=powershell) that quickly enables TLS 1.2 for existing Entra DS installs
#>

# Check if Az.ADDomainServices module is installed, install if not
if (-not (Get-Module -ListAvailable -Name Az.ADDomainServices)) {
    Write-Output "Az.ADDomainServices module not found. Installing..."
    Install-Module -Name Az.ADDomainServices -Scope CurrentUser -Force
} else {
    Write-Output "Az.ADDomainServices module is already installed."
}

# Import the module
Import-Module Az.ADDomainServices -Force

# Connect interactively (with built-in tenant & subscription prompt)
Write-Output "Please sign in to your Azure account."
Connect-AzAccount

# Use the subscription selected during login
$context = Get-AzContext
Write-Output "Using subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"

Set-AzContext -SubscriptionId $context.Subscription.Id

# Get domain service and update TLS setting
$domainService = Get-AzADDomainService
if ($null -eq $domainService) {
    Write-Error "No Azure AD Domain Service found in the selected subscription."
    exit
}

Write-Output "Disabling TLS v1 for domain service '$($domainService.Name)'. This may take about 10 minutes..."
Update-AzADDomainService -Name $domainService.Name -ResourceGroupName $domainService.ResourceGroupName -DomainSecuritySettingTlsV1 Disabled

Write-Output "Update command submitted. This command may take about 10 minutes to complete as domain security updates are enforced. Please check the Azure portal or run status checks to confirm completion."
