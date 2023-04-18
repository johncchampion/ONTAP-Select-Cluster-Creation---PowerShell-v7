#requires -version 7

##################################################################################
# A configuration file is REQUIRED by this script to process settings
# See [Notes] section in sample .ini files for description of variables
# Examples
# --------
# PS C:\Scripts> .\otsclustercreate.ps1 -Config singlenode
# PS C:\Scripts> .\otsclustercreate.ps1 -Config ./multinode.ini
#
##################################################################################

[cmdletbinding()]
Param (
    [Parameter(Mandatory = $True)][string]$Configfile
)

# -------------------------------------------------------------------------------
# Functions
# -------------------------------------------------------------------------------
function Get-ConfigSettings ($file) {
	$ini = @{ }
	$section = "NO_SECTION"
	$ini[$section] = @{ }
	
	switch -regex -file $file {
		"^\[(.+)\]$" {
			$section = $matches[1].Trim()
			$ini[$section] = @{ }
		}
		"^\s*([^#].+?)\s*=\s*(.*)" {
			$name, $value = $matches[1 .. 2]
			if (!($name.StartsWith(";")))
			{
				$ini[$section][$name] = $value.Trim()
			}
		}
	}
	return $ini
}
function Valid-IP ($ip) {
	if ($ip -as [IPAddress] -ne $null)
	{
		$address = $ip.split(".")
		if ($address.Count -eq 4)
		{
			return $true
		}
	}
	
	return $false
}
function Valid-Netmask ($mask) {
	$SubnetMaskList = @()
	foreach ($Length in 1 .. 32)
	{
		$MaskBinary = ('1' * $Length).PadRight(32, '0')
		$DottedMaskBinary = $MaskBinary -replace '(.{8}(?!\z))', '${1}.'
		$SubnetMaskList += ($DottedMaskBinary.Split('.') | foreach { [Convert]::ToInt32($_, 2) }) -join '.'
	}
	if ($SubnetMaskList -contains $mask)
	{
		return $true
	}
	return $false
}
function Stop-Script { 
[CmdletBinding()]
    param
    (
    [Parameter(Mandatory = $true)]
    [int]$flag
    $enddatetime = Get-Date -UFormat "%Y-%m-%d %T"
    Write-Host -ForegroundColor Gray " -------------------------------------------------------------------------"
    Write-Host -ForegroundColor Magenta " End: " -NoNewline
    Write-Host -ForegroundColor White $enddatetime -NoNewline
    Write-Host -ForegroundColor Blue "                                             v$v"
    Write-Host -ForegroundColor Gray " -------------------------------------------------------------------------"
    Write-Host
    $ProgressPreference = $OriginalPref
    EXIT $flag
}

# -------------------------------------------------------------------------------
# Variables
# -------------------------------------------------------------------------------
$v = "1.0"                                              # script version
$inc = 0                                                # line number
$valid_count = (1,2,4,6,8)                              # Valid # of nodes
$types = @("small","medium","large")                    # valid instance types
$startdatetime = Get-Date -UFormat "%Y-%m-%d %T"        # script start time

# -------------------------------------------------------------------------------
# Process configuration file
# -------------------------------------------------------------------------------
# If missing .ini extension, add to filename
if ( $Configfile.IndexOf(".ini") -eq -1 ) {
    $Configfile = $Configfile + ".ini"
}
# If filename not foud, EXIT
if (!( Test-Path -Path "$configfile" )) {
    Write-Host -ForegroundColor Yellow   "`n Missing Configuration File [$configfile] `n"
    exit
}

# -------------------------------------------------------------------------------
# Retrieve settings from .ini file
# -------------------------------------------------------------------------------
# Process .INI file
$config = Get-ConfigSettings $Configfile
# Deploy settings
$deploy_ip       = ($config["DEPLOY"]).deploy_ip
$deploy_password = ($config["DEPLOY"]).deploy_password
# vCenter Settings
$vcenter_login    = ($config["VCENTER"]).vcenter_login
$vcenter_password = ($config["VCENTER"]).vcenter_password
$vcenter_name     = ($config["VCENTER"]).vcenter_name
# Cluster settings
$cluster_name     = ($config["CLUSTER"]).cluster_name
$cluster_ip       = ($config["CLUSTER"]).cluster_ip
$cluster_password = ($config["CLUSTER"]).cluster_password
$cluster_netmask  = ($config["CLUSTER"]).cluster_netmask
$cluster_gateway  = ($config["CLUSTER"]).cluster_gateway
$dns_domain_names = ($config["CLUSTER"]).dns_domain_names
$dns_ip_addresses = ($config["CLUSTER"]).dns_ip_addresses
$ntp_servers      = ($config["CLUSTER"]).ntp_servers
$image_version    = ($config["CLUSTER"]).image_version
# Node Settings
$node_names     = ($config["NODE"]).node_names
$node_ips       = ($config["NODE"]).node_ips
$storage_pools  = ($config["NODE"]).storage_pools
$esxi_hosts     = ($config["NODE"]).esxi_hosts
$capacityTB    = ($config["NODE"]).capacityTB
$instance_type = ($config["NODE"]).instance_type
# Convert node related comma separated variable into arrays (lists)
# - Position related across lists (itemA[0] ~ itemB[0])
$node_names_list = @()
$node_ips_list = @()
$storage_pools_list = @()
$esxi_hosts_list = @()
$node_names_list = $node_names.Split(",")
$node_ips_list = $node_ips.Split(",")
$storage_pools_list = $storage_pools.Split(",")
$esxi_hosts_list = $esxi_hosts.Split(",")
# Network Settings
$mgmt_network = ($config["NETWORKS"]).mgmt_network
$data_network = ($config["NETWORKS"]).data_network
$internal_network = ($config["NETWORKS"]).internal_network

# -------------------------------------------------------------------------------
# Verify Settings
# -------------------------------------------------------------------------------
$error_msgs = @()
# IP Addresses
if (!( Valid-IP $deploy_ip ))       { $error_msgs += " Invalid Deploy IP Address [$deploy_ip]" }
if (!( Valid-IP $cluster_ip ))      { $error_msgs += " Invalid Cluster IP Address [$cluster_ip]" }
foreach ( $ip IN $node_ip_list ) {
    if (!( Valid-IP $ip )) { 
        $error_msgs += " Invalid Node IP Address [$ip]" 
    }
}
if (!( Valid-IP $cluster_gateway )) { $error_msgs += " Invalid Gateway IP Address [$cluster_gateway]" }
# Netmask
if (!( Valid-Netmask $cluster_netmask )) { $error_msgs += " Invalid Cluster Netmask [$cluster_netmask]" }
# Instance Type
if ( $types -notcontains $instance_type ) { $error_msgs += " Invalid Instance Type [$instance_type] - small, medium, large" }
# Empty Variables
if ( $vcenter_login.Length -lt 1 ) { $error_msgs += " vcenter_login is REQUIRED"}
if ( $vcenter_name.Length -lt 1 )  { $error_msgs += " vcenter_name is REQUIRED" }
if ( $cluster_name.Length -lt 1 )  { $error_msgs += " cluster_name is REQUIRED" }
foreach ( $nn IN $node_names_list ) {
    if ( $nn -lt 1 ) { 
        $error_msgs += " node_name is REQUIRED"
    }
}
foreach ( $sp IN $storage_pools_list ) {
    If ( $sp.Length -lt 1 ) { 
        $error_msgs += " storage_pool is REQUIRED" 
    }
}
foreach ( $esx IN $esxi_hosts_list ) {
    if ( $esx.Length -lt 1 ) { 
        $error_msgs += " host_name is REQUIRED"
    }
}
if ( $capacityTB.Length -lt 1 )    { $error_msgs += " capacityTB is REQUIRED"   }
if ( $mgmt_network.Length -lt 1 )  { $error_msgs += " mgmt_network is REQUIRED" }
if ( $data_network.Length -lt 1 )  { $error_msgs += " data_network is REQUIRED" }
# Node Count Tests
$nbr_nodes = $node_names_list.Count
$nbr_node_ips = $node_ips_list.Count
$nbr_pools = $storage_pools_list.Count
$nbr_esxis = $esxi_hosts_list.Count
if ( $valid_count -notcontains $nbr_nodes ) { 
    $error_msgs += " Invalid Node Count ($nbr_nodes) - Must be 1,2,4,6 or 8" 
}
if ( $nbr_nodes -ne $nbr_node_ips ) {
    $error_msgs += " Node Name Count ($nbr_nodes) does not match Node IPs count ($nbr_node_ips)"
}
if ( $nbr_nodes -ne $nbr_pools ) {
    $error_msgs += " Node Name Count ($nbr_nodes) does not match Storage Pool Count ($nbr_pools)"
}
if ( $nbr_nodes -ne $nbr_esxis ) {
    $error_msgs += " Node Name Count ($nbr_nodes) does not match ESXi Host Count ($nbr_esxis)"
}
if ( $nbr_nodes -gt 1 ) {
    if ( $internal_network.Length -lt 1 ) { 
        $error_msgs += " internal_network is REQUIRED" 
    }
}
# Verify Deploy Utility is running
if (!( Test-Connection -TargetName $deploy_ip -Count 2 -Quiet )) { 
    $error_msgs += " Deploy Utility [$deploy_ip] did not respond to ping" 
}
# Verify vCenter is running
if (!( Test-Connection -TargetName $vcenter_name -Count 2 -Quiet )) { $error_msgs += " vCenter [$vcenter_name] did not respond to ping" }
# Verify ESXi hosts are running
foreach ( $esx IN $esxi_hosts_list ) {
    if (!( Test-Connection -TargetName $esx -Count 2 -Quiet )) { 
        $error_msgs += " ESXi Server [$esx] did not respond to ping" 
    }
}
# Display error messages
if ( $error_msgs ) {
    Write-Host
    Write-Host -ForegroundColor Gray " -------------------------------------------------------------------------"
    Write-Host -ForegroundColor Cyan " ConfigFile : " -NoNewline
    Write-Host -ForegroundColor White $ConfigFile
    Write-Host -ForegroundColor Gray " -------------------------------------------------------------------------"
    foreach ( $msg IN $error_msgs ) {
        Write-Host -ForegroundColor Red " ERROR :" -NoNewline
        Write-Host -ForegroundColor Yellow $msg
    }
    Stop-Script 1
}

# -------------------------------------------------------------------------------
# Prompt for Deploy password if not in config file
# -------------------------------------------------------------------------------
if ( $deploy_password -eq "" ) {
    Write-Host
    $pword = Read-Host " Enter Deploy Password" -AsSecureString
    $deploy_password = ConvertFrom-SecureString $pword -AsPlainText
}

# -------------------------------------------------------------------------------
# Prompt for vCenter password if not in config file
# -------------------------------------------------------------------------------
if ( $vcenter_password -eq "" ) {
    Write-Host
    $pword = Read-Host " Enter vCenter Password" -AsSecureString
    $vcenter_password = ConvertFrom-SecureString $pword -AsPlainText
}

# -------------------------------------------------------------------------------
# Prompt for ONTAP cluster password if not in config file
# -------------------------------------------------------------------------------
if ( $cluster_password -eq "" ) {
    Write-Host
    $pword = Read-Host " Enter ONTAP Cluster Password" -AsSecureString
    $cluster_password = ConvertFrom-SecureString $pword -AsPlainText
}

# -------------------------------------------------------------------------------
# START
# -------------------------------------------------------------------------------
$spaces = 39 - $cluster_name.Length
$blanks = " " * $spaces
if ( ($MyInvocation.PSCommandPath).Length -eq 0 ) { Clear-Host}
Write-Host -ForegroundColor Gray    " -------------------------------------------------------------------------"
Write-Host -ForegroundColor Yellow  " CREATE CLUSTER "
Write-Host -ForegroundColor Gray    " -------------------------------------------------------------------------"
Write-Host -ForegroundColor Magenta " Start: " -NoNewline
Write-Host -ForegroundColor White   $startdatetime -NoNewline
Write-Host -ForegroundColor White   $blanks -NoNewline
Write-Host -ForegroundColor Cyan    "Cluster " -NoNewline
Write-Host -ForegroundColor White   $cluster_name
Write-Host -ForegroundColor Gray    " -------------------------------------------------------------------------"

# -------------------------------------------------------------------------------
# Configuration Settings
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Configuration Settings `t" -NoNewline
Write-Host -ForegroundColor White $Configfile

# -------------------------------------------------------------------------------
# Generate the Basic Authentication Account/Password for REST API Calls
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Generate Credential `t" -NoNewline
Write-Host -ForegroundColor White "Deploy Admin"
$pw = ConvertTo-SecureString -String "$deploy_password" -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "admin", $pw

# -------------------------------------------------------------------------------
# Build Deploy REST API URL string
# -------------------------------------------------------------------------------
$deploy_url = "https://" + $deploy_ip + "/api/v3"

# -------------------------------------------------------------------------------
# Test for Existing Cluster
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Test if Cluster Exists "
$url = $deploy_url + "/clusters?name=$cluster_name"
try {
    $result = Invoke-RestMethod -Method 'GET' -Uri $url -Credential $cred -SkipCertificateCheck -ErrorAction Stop
} catch {
    Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
    Stop-Script -flag 1
}
if ( $result.num_records -ne 0 ) {
    Write-Host -ForegroundColor Yellow "`n Cluster [$cluster_name] EXISTS in Deploy `n"
    Stop-Script -flag 1
}

# -------------------------------------------------------------------------------
# Add vCenter Credential
# -------------------------------------------------------------------------------

$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Add vCenter Credential `t" -NoNewline
Write-Host -ForegroundColor White $vcenter_login

$url = $deploy_url + "/security/credentials?username=$vcenter_login" + "&" + "hostname=$vcenter_name"

try {
    $result = Invoke-RestMethod -Method 'GET' -Uri $url -Credential $cred -SkipCertificateCheck -ErrorAction Stop
} catch {
    Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
    Stop-Script -flag 1
}

if ( $result.num_records -eq 0 ) {
    $body = @{
        hostname = "$vcenter_name"
        password = "$vcenter_password"
        type = "vcenter"
        username = "$vcenter_login"
    }
    $body = ConvertTo-Json $body
    $url = $deploy_url + "/security/credentials"
    try {
        $result = Invoke-RestMethod -Method 'POST' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
        Stop-Script -flag 1
    }
}

# -------------------------------------------------------------------------------
# Register ESXi Hosts
# -------------------------------------------------------------------------------

foreach ( $esxi_host In $esxi_hosts_list ) {
    $inc++
    if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
    Write-Host -ForegroundColor Gray " $inc. " -NoNewline
    Write-Host -ForegroundColor Cyan "Register ESXi Host `t" -NoNewline
    Write-Host -ForegroundColor White $esxi_host
    $hosturl = $deploy_url + "/hosts?name=$esxi_host"
    try {
        $hostresult = Invoke-RestMethod -Method 'GET' -Uri $hosturl -Credential $cred -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Stop-Script -flag 1 -errormsg $_.Exception.Message
    }
    if ( $hostresult.num_records -eq 0 ) {
        $body = "{`"hosts`": [{`"hypervisor_type`": `"ESX`",`"management_server`": `"$vcenter_name`", `"name`": `"$esxi_host`"}]}"
        $url = $deploy_url + "/hosts"
        try {
            $result = Invoke-RestMethod -Method 'POST' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
        } catch {
            Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
            Stop-Script -flag 1
        }
        Start-Sleep -Seconds 10
    }
}

# -------------------------------------------------------------------------------
# Get ESXi Host IDs
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Get ESXi Host IDs `t`t" -NoNewline
Write-Host -ForegroundColor White $esxi_hosts
$host_ids_list = @()
foreach ( $esxi IN $esxi_hosts_list) {
    $url = $deploy_url + "/hosts?name=$esxi"
    try {
        $result = Invoke-RestMethod -Method 'GET' -Uri $url -Credential $cred -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
        Stop-Script -flag 1
    }
    $host_ids_list += $result.records[0].id
}

# -------------------------------------------------------------------------------
# Create Cluster
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Create Cluster `t`t" -NoNewline
Write-Host -ForegroundColor White "$cluster_name [$cluster_ip]" -NoNewline
if ( $image_version ) { Write-Host -ForegroundColor White "[$image_version] " -NoNewline }
Write-Host
$body = @{
    name = "$cluster_name"
    gateway = "$cluster_gateway"
    ip = "$cluster_ip"
    netmask = "$cluster_netmask"
}
if (( $dns_domain_names ) -and ( $dns_ip_addresses )) {
    $dns_names = @()
    $dns_ips = @()
    $dns_names += $dns_domain_names.Split(",")
    $dns_ips   += $dns_ip_addresses.Split(",")
    $cluster_dns_info = @{
        domains = $dns_names
        dns_ips = $dns_ips
    }
    $body.Add("dns_info",$cluster_dns_info)
}
if ( $ntp_servers ) {
    $ntps = $ntp_servers.Split(",")
    $body.Add("ntp_servers", $ntps)
}
if ( $image_version ) {
    $body.Add("ontap_image_version", "$image_version")
}
$body = ConvertTo-Json $body
$url = $deploy_url + "/clusters?node_count=$nbr_nodes"
try {
    $result = Invoke-RestMethod -Method 'POST' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
} catch {
    Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
    Stop-Script -flag 1
}

# -------------------------------------------------------------------------------
# Get Cluster ID
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Get Cluster ID `t`t" -NoNewline
$url = $deploy_url + "/clusters?name=$cluster_name"
try {
    $result = Invoke-RestMethod -Method 'GET' -Uri $url -Credential $cred -SkipCertificateCheck -ErrorAction Stop
} catch {
    Stop-Script -flag 1 -errormsg $_.Exception.Message
}
Start-Sleep -Seconds 2
if ( $result.num_records -gt 0 ) {
    $cluster_id = $result.records[0].id
} else {
    Write-Host -ForegroundColor Yellow "`n Cluster $cluster_name does not exist in Deploy  `n"
    Stop-Script -flag 1
}
Write-Host -ForegroundColor White $cluster_id

# -------------------------------------------------------------------------------
# Check Cluster State
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Check Cluster State `t" -NoNewline
$url = $deploy_url + "/clusters/" + $cluster_id + "?fields=*"
try {
    $result = Invoke-RestMethod -Method 'GET' -Uri $url -Credential $cred -SkipCertificateCheck -ErrorAction Stop
} catch {
    Stop-Script 1 ( Get-ErrorMessageFromJson $Error[0] )
}
if (!( $result )) {
    Write-Host -ForegroundColor Yellow "`n Cluster creation did not start `n"
    Stop-Script 1
}

Write-Host -ForegroundColor Green "READY TO CONFIGURE"

# -------------------------------------------------------------------------------
# Get Node IDs
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Get Node IDs `t`t" -NoNewline
Write-Host -ForegroundColor White $node_names
$url = $deploy_url + "/clusters/$cluster_id/nodes?order_by=name asc"
try {
    $result = Invoke-RestMethod -Method 'GET' -Uri $url -Credential $cred -SkipCertificateCheck -ErrorAction Stop
} catch {
    Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
    Stop-Script 1
}
if ( $result.num_records -gt 0 ) {
    $node_ids_list = @()
    For ($i=0; $i -lt $result.num_records; $i++ ) {
        $node_ids_list += $result.records[$i].id
    }
}

# -------------------------------------------------------------------------------
# Configure Nodes
# -------------------------------------------------------------------------------
for ( $i=0; $i -lt $nbr_nodes; $i++ ) {
    $n_id = $node_ids_list[$i]
    $n_name = $node_names_list[$i]
    $n_ip = $node_ips_list[$i]
    $h_id = $host_ids_list[$i]
    $h_name = $esxi_hosts_list[$i]
    $inc++
    if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
    Write-Host -ForegroundColor Gray " $inc. " -NoNewline
    Write-Host -ForegroundColor Cyan "Configure Node `t`t" -NoNewline
    Write-Host -ForegroundColor White "$n_name [$n_ip][$h_name]"
    $body = @{
        instance_type = "$instance_type"
        passthrough_disks = $false
        ip = "$n_ip"
        name = "$n_name"
    }
    $hostinfo = @{
        id = $h_id
    }
    $body.Add("host", $hostinfo)
    $body = ConvertTo-Json $body
    $url = $deploy_url + "/clusters/$cluster_id/nodes/$n_id"
    try {
        $result = Invoke-RestMethod -Method 'PATCH' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
        Stop-Script 1
    }
}

# -------------------------------------------------------------------------------
# Get Network IDs
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Get Network IDs `t`t" -NoNewline
Write-Host -ForegroundColor White $node_names
$mgmt_network_ids_list = @()
$data_network_ids_list = @()
$internal_network_ids_list = @()
for ( $i=0; $i -lt $nbr_nodes; $i++ ) {
    $n_id = $node_ids_list[$i]
    $n_name = $node_names_list[$i]
    $url = $deploy_url + "/clusters/$cluster_id/nodes/$n_id/networks"
    try {
        $result = Invoke-RestMethod -Method 'GET' -Uri $url -Credential $cred -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
        Stop-Script 1
    }
    $mgmt_network_ids_list += $result.records[0].id
    $data_network_ids_list += $result.records[1].id
    If ( $nbr_nodes -gt 1 ) {
        $internal_network_ids_list += $result.records[2].id
    }
}

# -------------------------------------------------------------------------------
# Configure Networks
# -------------------------------------------------------------------------------
for ( $i=0; $i -lt $nbr_nodes; $i++ ) {
    $n_name = $node_names_list[$i]
    $n_id = $node_ids_list[$i]
    $inc++
    if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
    Write-Host -ForegroundColor Gray " $inc. " -NoNewline
    Write-Host -ForegroundColor Cyan "Configure Network `t`t" -NoNewline
    Write-Host -ForegroundColor White $n_name
    # Management Network
    Write-Host -ForegroundColor Cyan  "     - Management Network `t" -NoNewline
    Write-Host -ForegroundColor White $mgmt_network
    $mgmt_network_id = $mgmt_network_ids_list[$i]
    $body = @{
        name = "$mgmt_network"
    }
    $body = ConvertTo-Json $body
    $url = $deploy_url + "/clusters/$cluster_id/nodes/$n_id/networks/$mgmt_network_id"
    try {
        $result = Invoke-RestMethod -Method 'PATCH' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
        Stop-Script 1
    }
    # Data Network
    Write-Host -ForegroundColor Cyan "     - Data Network `t`t" -NoNewline
    Write-Host -ForegroundColor White $data_network
    $data_network_id = $data_network_ids_list[$i]
    $body = @{
        name = "$data_network"
    }
    $body = ConvertTo-Json $body
    $url = $deploy_url + "/clusters/$cluster_id/nodes/$n_id/networks/$data_network_id"
    try {
        $result = Invoke-RestMethod -Method 'PATCH' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
        Stop-Script 1
    }
    # Internal Network
    if ( $nbr_nodes -gt 1 ) {
        Write-Host -ForegroundColor Cyan "     - Internal Network `t" -NoNewline
        Write-Host -ForegroundColor White $internal_network
        $internal_network_id = $internal_network_ids_list[$i]
        $body = @{
            name = "$internal_network"
        }
        $body = ConvertTo-Json $body
        $url = $deploy_url + "/clusters/$cluster_id/nodes/$n_id/networks/$internal_network_id"
        try {
            $result = Invoke-RestMethod -Method 'PATCH' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
        } catch {
            Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
            Stop-Script 1
        }
    }
}

# -------------------------------------------------------------------------------
# Configure Storage Pools
# -------------------------------------------------------------------------------
For ( $i=0; $i -lt $nbr_nodes; $i++ ) {
    $n_name = $node_names_list[$i]
    $n_id = $node_ids_list[$i]
    $storage_pool = $storage_pools_list[$i]
    $inc++
    if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
    Write-Host -ForegroundColor Gray " $inc. " -NoNewline
    Write-Host -ForegroundColor Cyan "Configure Storage Pool `t" -NoNewline
    Write-Host -ForegroundColor White "$n_name [$storage_pool][$capacityTB TB]"
    $size = [int64]$capacityTB * 1TB
    $body = "{`"pool_array`": [{`"capacity`": $size,`"name`": `"$storage_pool`"}]}"
    $url = $deploy_url + "/clusters/$cluster_id/nodes/$n_id/storage/pools"
    try {
        $result = Invoke-RestMethod -Method 'POST' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
        Stop-Script 1
    }
}

# -------------------------------------------------------------------------------
# Deploy Cluster
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Deploy Cluster `t`t" -NoNewline
Write-Host -ForegroundColor White $cluster_name
$credinfo = @{
    password = "$cluster_password"
}
$body = @{}
$body.Add("ontap_credential", $credinfo)
$body = ConvertTo-Json $body
$url = $deploy_url + "/clusters/$cluster_id/deploy?inhibit_rollback=false"
try {
    $result = Invoke-RestMethod -Method 'POST' -Uri $url -Credential $cred -Body $body -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
} catch {
    Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
    Stop-Script 1
}
$job_id = $result.job.id

# -------------------------------------------------------------------------------
# Monitor Cluster Creation Job
# -------------------------------------------------------------------------------
$inc++
if ( $inc -lt 10 ) { Write-Host " " -NoNewline }
Write-Host -ForegroundColor Gray " $inc. " -NoNewline
Write-Host -ForegroundColor Cyan "Monitor Job ID `t`t" -NoNewline
Write-Host -ForegroundColor White $job_id
$old_state = ""
$old_msg = ""
$checkJob = $true
$url = $deploy_url + "/jobs/" + $job_id + "?fields=*"
While ( $checkJob ) {
    try {
        $job = Invoke-RestMethod -Method GET -Uri $url -Credential $cred -ContentType 'application/json' -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "`n $($_.Exception.Response)`n"
        Stop-Script -flag 1
    }
    $current_state = $job.record.state
    $current_msg = $job.record.message
    if (( $current_state -eq "failure" ) -or ( $current_state -eq "success" )) {
        $checkJob = $false
    }
    if ( $current_state -ne $old_state ) {
        Write-Host -ForegroundColor Cyan "     - State  : " -NoNewline
        if ( $current_state -eq "success" ) {
            $state_color = "Green"
        } elseif ( $current_state -eq "running" ) {
            $state_color = "Yellow"
        } elseif ( $current_state -eq "failure" ) {
            $state_color = "Red"
        } else {
            $state_color = "White"
        }
        Write-Host -ForegroundColor $state_color $current_state.ToUpper()
        $old_state = $current_state 
    }
    if ( $current_msg -ne $old_msg ) {
        if ( $current_msg -notlike "*loading cache*" ) {
            Write-Host -ForegroundColor Gray "       > " -NoNewline
            Write-Host -ForegroundColor Yellow $current_msg
        }
        $old_msg = $current_msg
    }
    Start-Sleep -Seconds 5
}

# END
Stop-Script
