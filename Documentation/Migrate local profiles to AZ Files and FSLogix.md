![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# (Draft) Migrate local profiles to AZ Files and FSLogix

<span style="color:red">*Note: This document is not yet finished and is still in draft.*</span>


## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#Prerequisites)
3. [Scenarios](#scenarios)
   - [Scenario 1: Migration of Local Machine Profiles to Azure Files with FSLogix](#scenario-1-migrating-from-local-profiles-on-physical-devices)
   - [Scenario 2: Migration of Profiles from an On-Premises File Server to Azure Files with FSLogix](#scenario-2-migrating-from-on-premises-ad-to-azure-ad-with-fslogix)
   - [Scenario 3: Handling Mixed Environments](#scenario-3-handling-mixed-environments)
4. [Best Practices](#best-practices)
5. [Tools and Scripts](#tools-and-scripts)
6. [Common Issues and Troubleshooting](#common-issues-and-troubleshooting)
7. [Conclusion](#conclusion)

***
### Introduction

This guide provides step-by-step instructions for migrating local user profiles to Azure Files and managing them with FSLogix. This process enhances performance, scalability, and reliability of user profile management in cloud environments.

"Please note that our main policy, as outlined in the [Disclaimer](https://github.com/Get-Nerdio/NMM-SE/blob/main/readme.md#disclaimer), also applies to this document."

### Prerequisites

##### Preperation and Assessment:

- Before proceeding, ensure you have proper **BACKUPS** of your data. It's crucial to have a fallback option in case something goes awry during the migration process.
- Evaluate the current local profiles and determine the requirements for the migration.
- Ensure you have adequate Azure File storage and it's configured correctly to handle the profiles, focusing on aspects such as redundancy and access permissions.

##### Setting Up Azure Files:
- Create an Azure Files share that will be used to store the FSLogix profile containers.
- Configure the Azure Files share with appropriate network access and security settings. -> [Nerdio Help Center: how to manage Azure Files with NMM](https://nmmhelp.getnerdio.com/hc/en-us/articles/26125608596237-Manage-Azure-Files-Shares)
- Make sure that the Azure environment is properly set up for SMB connections, which are required for FSLogix.
- Check our -> [Nerdio Help Center: article for more info about Azure Files](https://nmmhelp.getnerdio.com/hc/en-us/articles/26125588139917-What-Are-Azure-Files-and-FSLogix-Profile-Storage-Options)

##### FSLogix Configuration:

- Install and configure FSLogix on all user systems that will be migrated. This includes setting up the FSLogix agent to redirect user profiles to the Azure Files share.
- Configure FSLogix rules and settings according to the needs of your organization. This may include setting up redirections, managing permissions, and optimizing performance.
- CHeck our -> [Nerdio Help Center: For more info about FSLogix, and how to configure the steps above](https://nmmhelp.getnerdio.com/hc/en-us/articles/26125632741005-FSLogix-Settings-and-Configuration)

### Scenario's

##### Scenario 1: Migration of Local Machine Profiles to Azure Files with FSLogix
Describe scenario...

- Workaround 1:
- Workaround 2:

##### Scenario 2: Migration of Profiles from an On-Premises File Server to Azure Files with FSLogix
Describe scenario...

- Workaround 1:
- Workaround 2:

##### Scenario 3: Migrate UPD from a RDSH environment to FSLogix
Describe scenario...

- Workaround 1:
- Workaround 2:




### Best Practices

Add some text here..



### Tools and Scripts

- [Builtin FSLogix Command Line Utilities](https://learn.microsoft.com/en-us/fslogix/utilities/frx/frx#frx-copy-profile) -> Using the builtin FSLogix Command Line Utilities is a solid solution, but the current docs don't describe bulk actions. So the ```frx copy-profile``` command is within proper scripting a single profile action migration. A good practice when using this tool is to set the **RobocopyLogPath** regkey.
[Microsoft Docs link FSLogix settings](https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings?tabs=logging#robocopylogpath)  
```

Registry Hive: HKEY_LOCAL_MACHINE

Registry Path: SOFTWARE\FSLogix\Logging

Value Name: RobocopyLogPath

Value Type: REG_SZ

Default Value: None

Specifies a log file name and path where the output of the robocopy commands (for example, during mirroring of data in or out of a VHD) are stored. If the value is nonexistent, then the robocopy results aren't logged at all. This setting is recommended for troubleshooting only.
Example Value: C:\NMM\Logs\FSLogixRoboLogs.txt
```  


- [Microsoft FSLogix Migration Private Preview Module](https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE4k26R) -> This is a script maintained by Microsoft Engineers, when downloading the module from the follow the steps in the Readme doc.  

- [FSLogix Migration Powershell Module](https://github.com/gregdod/FSLogixMigration) -> Currently a good supported and maintained tool to convert the user profiles and UPD disks to FSLogix containers. ***"This is a fork of the Microsoft Migration Private Preview Module linked above."***  

### Common Issues and Troubleshooting

Add some text here..

### Conclusion

Add some text here..


