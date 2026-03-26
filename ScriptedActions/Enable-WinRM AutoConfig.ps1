<#
.SYNOPSIS
  Enables AutoConfig for WinRM Service via local policy (registry) settings

.NOTES
  Script can be run multiple times without adverse effects. It will create the necessary registry keys if they do not exist.
  Script is designed to be run on AVD session hosts which utilize CIS hardened images, where this policy is disabled by default
  for security hardening. Enabling this policy is necessary to allow remote management via WinRM, which is commonly used 
  for administration and monitoring tasks in AVD environments.  Without using this script, AVD session hosts using CIS hardened
  images will fail at the Join ARM AVD task.

.EXECUTION MODE NMM
  IndividualWithRestart
#>

$ErrorActionPreference = 'Stop'

Write-Host "==> Enabling local policy: Allow remote server management through WinRM" -ForegroundColor Cyan

# Policy-backed registry location for WinRM Service policy
# Check if the key exists first to avoid unnecessary creation
$policyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
if (!(Test-Path $policyKey)) {
    New-Item -Path $policyKey -Force | Out-Null
}

# The policy setting maps to AllowAutoConfig:
# 1 = Enabled, 0 = Disabled (policy guidance references this value)

# Check if the property already exists and has the desired value to avoid unnecessary writes
$currentValue = (Get-ItemProperty -Path $policyKey -Name 'AllowAutoConfig' -ErrorAction SilentlyContinue).AllowAutoConfig
if ($currentValue -ne 1) {
    Write-Host "==> Setting AllowAutoConfig to 1 (Enabled)"
    New-ItemProperty -Path $policyKey -Name 'AllowAutoConfig' -PropertyType DWord -Value 1 -Force | Out-Null
} else {
    Write-Host "==> AllowAutoConfig is already set to 1 (Enabled), skipping"
}