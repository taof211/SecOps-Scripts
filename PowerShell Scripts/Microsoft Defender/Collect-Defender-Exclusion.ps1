<#
.SYNOPSIS
 
    Name: Collect-Defender-Exclusions.ps1
    This script will remotely collect Defender exclusion information from a target host.
 
.DESCRIPTION
 
    This script performs the following:
 
    1. Prompt for credentials to authenticate against the remote machine and the support server.
    2. Define a support server
    3. Read the hostnames from the CSV file, and loop through each host for the following execution
    4. Connect to the remote machine and retrieve exclusion settings for paths, extensions, and processes from Windows Defender.
    5. Compile the results into a hashtable for easier handling.
    6. Connect to the support server from the target host and save the exclusion data into separate text files.
 
.NOTES
 
    Release Date: 2024-10-04
    Author: Juana Fan
#>
 
# Prompt for credentials
$cred = Get-Credential
# Define the support server
$supportServer = "YOUR_JUMP_BOX"
# Read the hostnames from the CSV file
$csvPath = "YOUR_CSV_FILE"
if (-not (Test-Path -Path $csvPath)) {
   Write-Host "CSV file not found at path: $csvPath"
   exit
}
$hosts = Import-Csv -Path $csvPath
# Print the imported data for verification
Write-Host "Imported Hosts:"
$hosts | Format-Table -AutoSize
foreach ($targetHost in $hosts) {
   $hostname = $targetHost.Name
   # Debugging output to check the hostname value
   Write-Host "Processing hostname: $hostname"
   # Check if the hostname is not null or empty
   if ([string]::IsNullOrEmpty($hostname)) {
       Write-Host "Hostname is null or empty. Skipping..."
       continue
   }
   # Invoke-Command to connect to the first remote machine and run the commands
   Invoke-Command -ComputerName $hostname -Credential $cred -ScriptBlock {
       $exclusionPath = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
       $exclusionExtension = Get-MpPreference | Select-Object -ExpandProperty ExclusionExtension
       $exclusionProcess = Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess
       # Store the results in a hashtable to pass to the support server
       $results = @{
           ExclusionPath = $exclusionPath
           ExclusionExtension = $exclusionExtension
           ExclusionProcess = $exclusionProcess
       }
       # Invoke-Command to connect to the support server and save the results
       Invoke-Command -ComputerName $using:supportServer -Credential $using:cred -ScriptBlock {
           param ($hostname, $results)
           # Create the directory if it doesn't exist
           $directory = "D:\DefenderExclusions\$hostname"
           if (-not (Test-Path -Path $directory)) {
               New-Item -Path $directory -ItemType Directory
           }
           # Save the results to files
           $results.ExclusionPath | Out-File -FilePath "$directory\ExclusionPath.txt"
           $results.ExclusionExtension | Out-File -FilePath "$directory\ExclusionExtension.txt"
           $results.ExclusionProcess | Out-File -FilePath "$directory\ExclusionProcess.txt"
       } -ArgumentList $using:hostname, $results
   }
}