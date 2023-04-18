## ONTAP Select Cluster Creation using Deploy Utility REST API and PowerShell v7
_17 April 2023_

### Description
This is an example PowerShell version 7 script that creates/deploys a single or multinode ONTAP Select cluster using the Deploy Utility REST API. Settings are defined in a separate configuration file in standard .ini format.

The script is idempotent and can be re-executed without any known issues.

### Disclaimer
The script and associated components are provided as-is and are intended to provide an example of utilizing PowerShell version 7 and the Invoke-RestMethod cmdlet. Fully test in a non-production enviornment before implementing. Feel free to utilize/modify any portion of code for your specific needs.

### Requirements
* ONTAP Select 9.8 or later
* PowerShell 7.x
* vSphere 6.5 or later with ESXi hosts managed by vCenter

### NOTES
*None*

### Dev/Test Environment
* Windows 2019 Server (jumpbox used to execute scripts)
* PowerShell version 7.1
* ONTAP Select 9.12.1
* VMware vSphere 6.7 and 7.0

### Usage
* Example: _PS C:\Scripts > ./otsclustercreate.ps1 -Configfile singlenode_
* Implement password security in compliance with the environment and best practices. If passwords are not included in the .ini file, the script will prompt for them.
* Sample configuration files are provided for 1 or 2 node Select clusters

### Workflow Tasks
1. Verify Settings and Environment
2. Prompt for missing passwords (if not in configuration file)
3. Generate Deploy credential
4. Check for Existing cluster
5. Add vCenter Credential
6. Register ESXi Hosts - vCenter
7. Get ESXi Host IDs
8. Create Cluster (Initialize)
9. Get Cluster ID
10. Get Cluster State
11. Get Node IDs
12. Configure Nodes
13. Get Network IDs
14. Configure Networks
15. Configure Storage Pools
16. Deploy Cluster

### Known Issues
*None*
