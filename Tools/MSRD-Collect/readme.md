![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# MSRD-Collect AVD DiagTool

This script is designed to collect information on AVD, RDS, Windows 365 hosts and from the connection client hosts.

## Download and Extract

You can grab the latest version of the script from here: https://aka.ms/avd-collect or grab the zip from this repository.

## Prerequisites

Before running the script, ensure you have the following prerequisites:

- First extract the zip file
- Open a PowerShell prompt and navigate to the root of the extracted folder
- Run the following command to unblock the files in the module:

```powershell
Get-ChildItem -Recurse -Path .\Modules\*.psm1\* | Unblock-File -Confirm:$false
```

- Run the following command to start the Diagnostics Tool:

```powershell
.\MSRD-Collect.ps1
```

- Accept the license and the script open a new window where you can select the options.

![Menu MSRD-Collect Tool](https://github.com/user-attachments/assets/ccfd0b12-1f8e-49a0-9c7b-fc5d36d74849)
