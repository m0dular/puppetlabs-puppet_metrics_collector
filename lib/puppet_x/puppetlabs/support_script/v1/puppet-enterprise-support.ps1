################################################################################
# Parameters
################################################################################

Param (
  [int]$logAge = 14
 )

$script_version = '2.9.1'

################################################################################
Write-Host
Write-Host ('Puppet Enterprise Windows Support Script v' + $script_version)
Write-Host
################################################################################

################################################################################
# PowerShell Version Check
################################################################################

if ($PSVersionTable.PSVersion.Major -lt 3) {
  Write-Host 'Error: This script requires PowerShell Version 3 or newer.'
  Write-Host
  exit 1
}

Write-Host 'Note: This script may take a few minutes to execute.'
Write-Host

################################################################################
# Functions
################################################################################

Function Test-CommandExists {
 Param ($command)
 $eap = $ErrorActionPreference
 $ErrorActionPreference = 'stop'
 $exists = $FALSE
 Try {
    if (Get-Command $command){
      $exists = $TRUE
    }
  } Catch {
    "$command does not exist"
  }
  Finally {
    $ErrorActionPreference = $eap
  }
  return $exists
}

################################################################################
# Support Script Variables
################################################################################

$run_date_time = (Get-Date -Format 'yyyyMMddHHmmss')
$hostname = $env:computername.ToLower()
$time_zone = [System.TimeZone]::CurrentTimeZone
$eventlog_date = (Get-Date).AddDays(-$logAge)

if (Test-CommandExists ('puppet.bat')) {
  $puppet_conf               = [string](puppet.bat config print config)
  $puppet_server             = [string](puppet.bat config print server)
  $puppet_logdir             = [string](puppet.bat config print logdir)
  $puppet_statedir           = [string](puppet.bat config print statedir)
} else {
  $puppet_conf     = ''
  $puppet_server   = ''
  $puppet_logdir   = [string](Get-Location)
  $puppet_statedir = ''
}

if (Test-CommandExists ('facter.bat')) {
  $puppet_pxp_logdir         = [string](facter.bat -p common_appdata) + "\PuppetLabs\pxp-agent\var\log"
  $puppet_mcollective_logdir = [string](facter.bat -p common_appdata) + "\PuppetLabs\mcollective\var\log"
} else {
  $puppet_pxp_logdir         = ''
  $puppet_mcollective_logdir = ''
}

$output_directory = $puppet_logdir    + '/puppet_enterprise_support_' + $hostname + '_' + $run_date_time
$output_file      = $output_directory + '/support_script.log'
$output_archive   = $puppet_logdir    + '/puppet_enterprise_support_' + $hostname + '_' + $run_date_time + '.zip'

################################################################################
# PowerShell Variables
################################################################################

$global:progressPreference = 'SilentlyContinue'

################################################################################
# Output Validation
################################################################################

$(New-Item -Path $output_directory -ItemType directory) | Out-Null

@{version = $script_version; timestamp = $run_date_time; osfamily = 'windows'} | ConvertTo-Json | Out-File -FilePath ($output_directory + '/metadata.json')

if (! (Test-Path $output_directory)) {
  Write-Host 'Error: could not create output directory:'
  Write-Host $output_directory
  Exit
}

# For more information about redirection, see:
# https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection
# Using *>> requires PowerShell 3.0 just to compile, but captures streams 3-6 (Warning, Verbose, Debug, Information).

'Puppet Enterprise Windows Support Script' > $output_file

if (! (Test-Path $output_file)) {
  Write-Host 'Error: could not write to output file:'
  Write-Host $output_file
  Exit
}

################################################################################
Write-Host 'Collecting Puppet Diagnostic Information ...'
################################################################################

'Hostname'              | Out-File -Append -FilePath $output_file
(hostname)              | Out-File -Append -FilePath $output_file

'Date, Time, Time Zone' | Out-File -Append -FilePath $output_file
$run_date_time          | Out-File -Append -FilePath $output_file
$time_zone.StandardName | Out-File -Append -FilePath $output_file

'Environment Path'      | Out-File -Append -FilePath $output_file
$env:path               | Out-File -Append -FilePath $output_file

'Get-Command puppet'    | Out-File -Append -FilePath $output_file
Get-Command puppet      | Out-File -Append -FilePath $output_file

'Get-Command facter'    | Out-File -Append -FilePath $output_file
Get-Command facter      | Out-File -Append -FilePath $output_file

'Get-Command ruby'      | Out-File -Append -FilePath $output_file
Get-Command ruby        | Out-File -Append -FilePath $output_file

'puppet.bat --version'  | Out-File -Append -FilePath $output_file
(puppet.bat --version)  | Out-File -Append -FilePath $output_file

'facter.bat --version'  | Out-File -Append -FilePath $output_file
(facter.bat --version)  | Out-File -Append -FilePath $output_file

'ruby --version'        | Out-File -Append -FilePath $output_file
(ruby --version)        | Out-File -Append -FilePath $output_file

################################################################################
Write-Host 'Running Facter in Debug Mode ...'
################################################################################

facter.bat --debug --trace 2>&1 | Out-File -Append -FilePath ($output_directory + '/facter.log')

################################################################################
Write-Host 'Testing Puppet Server Connectivity ...'
################################################################################

'Test Port 8140 to Puppet Server ' + $puppet_server  | Out-File -Append -FilePath $output_file
Test-NetConnection $puppet_server -Port 8140         | Out-File -Append -FilePath $output_file

'Test Port 8142 to Puppet Server ' + $puppet_server  | Out-File -Append -FilePath $output_file
Test-NetConnection $puppet_server -Port 8142         | Out-File -Append -FilePath $output_file

'Test Port 61613 to Puppet Server ' + $puppet_server | Out-File -Append -FilePath $output_file
Test-NetConnection $puppet_server -Port 61613        | Out-File -Append -FilePath $output_file

################################################################################
Write-Host 'Querying Puppet Agent Services ...'
################################################################################

'Puppet Agent Services Query: puppet pxp-agent mcollective' | Out-File -Append -FilePath $output_file
Get-WmiObject -Query "SELECT * FROM win32_service where (name = 'puppet' or name = 'pxp-agent' or name = 'mcollective')" | Format-List -Property Name, Pathname, ProcessId, Startmode, State, Status, Startname | Out-File -Append -FilePath $output_file

################################################################################
Write-Host 'Exporting Puppet Agent Services Event Logs ...'
################################################################################

Get-Eventlog -Source puppet    -LogName Application -After $eventlog_date 2> ($output_directory + '/eventlog_application_puppet_errors.txt')    | Format-List Index, Time, EntryType, Message | Out-File -Append -FilePath ($output_directory + '/eventlog_application_puppet.txt')
Get-Eventlog -Source pxp-agent -LogName Application -After $eventlog_date 2> ($output_directory + '/eventlog_application_pxp-agent_errors.txt') | Format-List Index, Time, EntryType, Message | Out-File -Append -FilePath ($output_directory + '/eventlog_application_pxp-agent.txt')

################################################################################
Write-Host 'Copying Puppet Agent Services Configuration Files and State Directory ...'
################################################################################

if (! (Test-Path $puppet_conf)) {
  'Error: puppet config file not found' | Out-File -Append -FilePath $output_file
} else {
  Copy-Item $puppet_conf -Destination $output_directory
}

if (! (Test-Path $puppet_statedir)) {
  'Error: puppet state directory not found' | Out-File -Append -FilePath $output_file
} else {
  Copy-Item $puppet_statedir -Recurse -Destination $output_directory
}

if (! (Test-Path $puppet_pxp_logdir)) {
  'Error: puppet pxp-agent log directory not found' | Out-File -Append -FilePath $output_file
} else {
  Copy-Item $puppet_pxp_logdir -Recurse -Destination ($output_directory + "\pxp-agent")
}

if (! (Test-Path $puppet_mcollective_logdir)) {
  'Error: puppet mcollective directory not found' | Out-File -Append -FilePath $output_file
} else {
  Copy-Item $puppet_mcollective_logdir -Recurse -Destination ($output_directory + "\mcollective")
}

################################################################################
Write-Host 'Compressing Support Script Data ...'
################################################################################

Add-Type -Assembly 'System.IO.Compression.FileSystem' ;
[System.IO.Compression.ZipFile]::CreateFromDirectory($output_directory, $output_archive);
Remove-Item $output_directory -Recurse

################################################################################
Write-Host
Write-Host 'Done.'
Write-Host
Write-Host 'Puppet Enterprise Windows Support Script output is located in:'
Write-Host
Write-Host $output_archive
Write-Host
Write-Host 'Please submit it to Puppet Enterprise Support.'
Write-Host
################################################################################
