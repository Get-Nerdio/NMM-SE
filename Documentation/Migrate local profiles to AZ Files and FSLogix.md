![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# (Draft) Migrate local profiles to AZ Files and FSLogix

<span style="color:red">*Note: This document is not yet finished and is still in draft.*</span>


## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Scenarios](#scenarios)
4. [Workarounds](#workarounds)
5. [Best Practices](#best-practices)
6. [Tools and Scripts](#tools-and-scripts)
7. [Common Issues and Troubleshooting](#common-issues-and-troubleshooting)
8. [Conclusion](#conclusion)

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

When migrateting profiles you could typically think of these kind of scenario's  

- Scenario 1: Migration of Local Machine Profiles to Azure Files with FSLogix  

- Scenario 2: Migration of Profiles from an On-Premises File Server to Azure Files with FSLogix  

- Scenario 3: Migrate UPD from a RDSH environment to FSLogix  

### Workarounds

**Using the FSLogix Commandline Utilities:**    

For smaller-scale migrations, such as when you have only a handful of profiles, and if you're less familiar with PowerShell, the FSLogix command-line utility frx copy-profile offers a straightforward alternative. Ensure you have FSLogix software installed on the machine where the command will be executed. For guidance on installing FSLogix on non-NMM managed machines, see [Microsoft Docs: How to download and install FSLogix manually on not NMM managed machines](https://learn.microsoft.com/en-us/fslogix/how-to-install-fslogix)

- Steps to Migrate a User Profile:

    - Open a PowerShell terminal as Administrator.
    - Navigate to the FSLogix Apps directory:

```
cd 'C:\Program Files\FSLogix\Apps'
```
- Execute the following command to copy and configure the profile:

```
frx copy-profile -filename C:\Profile.vhdx -username CONTOSO\msmith -size-mbs 30000 -dynamic 1 -verbose
```
This command does the following:

- Saves the FSLogix profile container to C:\Profile.vhdx.
- Converts the domain profile for user CONTOSO\msmith.
- Sets the VHDX file to dynamic, allowing the disk to resize automatically up to a maximum of 30GB.

Note: For profiles that are not domain-joined, specify the username without the domain prefix, e.g., -username msmith.

**Using the FSLogix Migration Powershell Module:** 

For detailed documentation and troubleshooting guides, refer to the [FSLogixMigration repository on GitHub](https://github.com/gregdod/FSLogixMigration). This migration approach is typically favored in somewhat larger environments due to its automation capabilities, which reduce the likelihood of human error and increase efficiency.

**Main Functions:**

- Convert-RoamingProfile – Converts a roaming profile to an FSLogix Profile Container

- Convert-UPDProfile – Converts a user profile disk to an FSLogix Profile Container

- Convert-UPMProfile - Converts a UPM Profile to an FSLogix Profile Container. UPM Conversion has had minimal testing in small environments.

**Syntax and Examples:**

- **Convert-RoamingProfile (Bulk e.g. all users in C:\Users)**

*Syntax:*

```powershell
Convert-RoamingProfile -ParentPath <String> -Target <String> -VHDMaxSizeGB <UInt64> -VHDLogicalSectorSize <String> [-VHD] [-IncludeRobocopyDetail] [-LogPath <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

*Example:*

```powershell
Convert-RoamingProfile -ParentPath "C:\Users\" -Target "\\Server\FSLogixProfiles$" -MaxVHDSize 20 -VHDLogicalSectorSize 512 -IncludeRobocopyDetails -LogPath C:\temp\Log.txt
```

- **Convert-RoamingProfile (Single User Profile)**

*Syntax:*

```powershell
Convert-RoamingProfile -ProfilePath <String> -Target <String> -VHDMaxSizeGB <UInt64> -VHDLogicalSectorSize <String> [-VHD] [-IncludeRobocopyDetail] [-LogPath <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

*Example:*

```powershell
Convert-RoamingProfile -ProfilePath "C:\Users\User1" -Target "\\Server\FSLogixProfiles$" -MaxVHDSize 20 -VHDLogicalSectorSize 512 -VHD -IncludeRobocopyDetails -LogPath C:\temp\Log.txt
```

For more information on what Syntax switches are support check the [Github Repository](https://github.com/gregdod/FSLogixMigration)


##### Global Workarounds:

- When migrating user profiles to Azure Virtual Desktop (AVD), considerations vary based on the number of users and the specific data involved. In some cases, it may be advantageous to start with a fresh profile, especially when setting up a new AVD environment. This approach is often favored by many MSPs and IT companies.  

    - **File Migration to OneDrive:**
For user data such as documents, pictures, and desktop files, migrating to OneDrive is efficient. Utilize migration tools to transfer this data in the background. Perform a final delta sync on the migration day so that when users log into their new AVD desktop, all their files are readily accessible.  
    - **Browser Settings Migration:**
Automate the backup and migration of browser settings. Common practice involves setting Microsoft Edge as the default browser, transferring settings from the previous browser, and enforcing Entra SSO sign-in. This ensures that browser settings are synchronized with the user’s profile. Enable Enterprise State Roaming in the Entra portal to support this process.  
    - **Email Signatures:**
Transition from manual email signatures to a managed solution like Exclaimer Cloud to simplify signature management. Alternatively, guide users on setting up their signatures in Outlook web, which allows signatures to roam with their Microsoft 365 profile.   

**Considerations:**
These migration strategies are best suited for environments where the design is straightforward and a full profile migration is unnecessary. This approach minimizes complexity and enhances user transition to the AVD setup.

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

- [FSLogix Migration Powershell Module](https://github.com/gregdod/FSLogixMigration) -> Currently a good supported and maintained Powershell module to convert the user profiles and UPD disks to FSLogix containers. ***"This is a fork of the Microsoft Migration Private Preview Module linked below."***  

- [Microsoft FSLogix Migration Private Preview Module](https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE4k26R) -> This is a script maintained by Microsoft Engineers, when downloading the module from the follow the steps in the Readme doc.  

### Common Issues and Troubleshooting

TBA

### Conclusion

In conclusion, migrating local profiles to Azure Files and managing them with FSLogix offers a robust solution for enhancing the scalability, reliability, and performance of user profile management in cloud environments. This guide outlines several strategies and tools designed to facilitate this process across various scenarios, whether dealing with small-scale migrations or larger, more complex environments.

Through careful planning, leveraging automation, and employing best practices, organizations can ensure a smooth transition that minimizes downtime and enhances user experience. It is critical to consider the specific needs and infrastructure of your organization to choose the most effective migration approach.

As cloud technologies evolve, continuing to update your migration strategies and troubleshooting methodologies will be crucial in maintaining efficiency and addressing new challenges. By following the guidelines in this document and staying informed about new tools and best practices, your organization can effectively manage its digital workspace transformation, ensuring that user data remains secure, accessible, and efficiently managed.


