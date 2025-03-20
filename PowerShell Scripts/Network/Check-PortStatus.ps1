<#
.SYNOPSIS
 
    Name: Check-PortStatus.ps1
    This PowerShell script reads a list of sites from a text file and checks if port THE_PORT_FOR_TEST is reachable for each site. It outputs the reachability status for each site.
 
    This script performs the following:
 
    1.IThe script sets the path to the text file containing site addresses.
    2. It reads the list of sites from the specified file.
    3. For each site, it attempts to test the connectivity to port THE_PORT_FOR_TEST.
    4. If the connection test is successful, it outputs that the port is reachable; otherwise, it outputs that the port is not reachable.
    5. If an error occurs during the test, it outputs an error message for that site.

 
.NOTES
 
    Release Date: 12/03/2025
    Author: Juana Fan
#>

# Path to the text file containing the list of sites
$sitesFile = "YOUR_TXT_FILE_CONTAINING_THE_IP/HOST_FOR_TEST"
 
# Read the list of sites from the text file
$sites = Get-Content -Path $sitesFile
 
# Loop through each site and test if certain port is reachable
foreach ($site in $sites) {
    try {
        $tcpConnection = Test-NetConnection -ComputerName $site -Port THE_PORT_FOR_TEST
        if ($tcpConnection.TcpTestSucceeded) {
            Write-Output "${site}: Port THE_PORT_FOR_TEST is reachable."
        } else {
            Write-Output "${site}: Port THE_PORT_FOR_TEST is not reachable."
        }
    } catch {
        Write-Output "${site}: Error testing port THE_PORT_FOR_TEST."
    }
}