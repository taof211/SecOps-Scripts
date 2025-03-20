<#
.SYNOPSIS
 
    Name: Check-UnhealthyMDESensors.ps1
    The script tests various aspects of Microsoft Endpoint Defebder sensor health and connectivity, updating a CSV report with results and suggestions for further actions.
 
    This script performs the following:
 
    1.Import device data from a CSV file and prompt for credentials.
    2. Check each device's reachability and internet connectivity.
    3. Test connectivity to MDE service URLs.
    4. Verify the status of the Diagtrack service and optionally enable it.
    5. Check the Defender antivirus status via registry keys.
    6. Generate a report with suggestions based on the checks and export it to a CSV file.
 
.NOTES
 
    Release Date: 18/10/2024
    Author: Juana Fan
#>
 
# Variables
$cred = Get-Credential
$csvPath = "YOUR_CSV_FILE_EXPORTED_FROM_DEFENDER"
$devices = Import-Csv -Path $csvPath
$urls = @(
   "https://winatp-gw-cus.microsoft.com/commands/test",
   "https://winatp-gw-eus.microsoft.com/commands/test",
   "https://winatp-gw-cus3.microsoft.com/commands/test",
   "https://winatp-gw-eus3.microsoft.com/commands/test",
   "https://us.vortex-win.data.microsoft.com/ping",
   "https://us-v20.events.data.microsoft.com/ping"
)
$currentDate = Get-Date -Format "MM-dd-yyyy"
$reportPath = "YOUR_REPORT_FOLDER\MEDSensorHealthReport_$currentDate.csv"
 
# Functions
function Test-RemoteHostReachable {
    param (
        [pscredential]$cred,
        [array]$devices
    )
    Write-Output "Reachable check beginning..."
    foreach ($device in $devices) {
        $deviceName = $device.'Device Name'
        $osPlatform = $device.'OS Platform'
        # Add the "Internet" and "Reachable" property to the device object
        $device | Add-Member -MemberType NoteProperty -Name Reachable -Value ""
        # Check if the OS Platform starts with "Windows"
        if ($osPlatform -like "Windows*") {
            # Test WinRM connection
            $winrmTest = Test-WSMan -ComputerName $deviceName -ErrorAction SilentlyContinue
            if ($winrmTest) {
                Write-Output "$deviceName is reachable"
                $device.Reachable = "True"
            } else {
                Write-Output "$deviceName is not reachable"
                $device.Reachable = "False"
            }
        } else {
            # Test ping connection
            $pingTest = Test-Connection -ComputerName $deviceName -Count 1 -ErrorAction SilentlyContinue
            if ($pingTest) {
                Write-Output "$deviceName is reachable"
                $device.Reachable = "True"
            } else {
                Write-Output "$deviceName is not reachable"
                $device.Reachable = "False"
            }
        }
    }
    # Export the updated CSV file
    $devices | Export-Csv -Path $csvPath -NoTypeInformation
}
 
function Test-RemoteHostInternetConnectivity {
    param (
        [pscredential]$cred,
        [array]$devices
    )
    Write-Output "Internet connectivity check beginning..."
    foreach ($device in $devices) {
        $deviceName = $device.'Device Name'
        $osPlatform = $device.'OS Platform'
        $reachable = $device.'Reachable'
        # Add the "Internet" property to the device object
        $device | Add-Member -MemberType NoteProperty -Name Internet -Value ""
        # Check if the OS Platform starts with "Windows"
        if ($osPlatform -like "Windows*" -and $reachable -eq "True") {
            # Test Internet connectivity
            try {
                $pingResult = Invoke-Command -ComputerName $deviceName -Credential $cred -ScriptBlock {
                    Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet
                }
                if ($pingResult) {
                    Write-Output "Internet is connected on $deviceName"
                    $device.Internet = "True"
                } else {
                    Write-Output "Internet is not connected on $deviceName"
                    $device.Internet = "False"
                }
            } catch {
                Write-Output "Error testing internet connectivity on $deviceName"
                $device.Internet = "Error"
            }
        } elseif ($reachable -eq "False") {
            Write-Output "$deviceName is not reachable"
        } else {
            Write-Output "$deviceName is not a Windows host, please check its internet connectivity manually"
            $device.Internet = "Unknown"
        }
    }
    # Export the updated CSV file
    $devices | Export-Csv -Path $csvPath -NoTypeInformation
}
 
function Test-MEDClientConnectivity {
    param (
        [pscredential]$cred,
        [array]$devices,
        [array]$urls
    )
    Write-Output "MDE Service URLs connectivity check beginning..."
    foreach ($device in $devices) {
        $deviceName = $device.'Device Name'
        $internet = $device.'Internet'
        # Add the "MED Connectivity" property to the device object if it doesn't already exist
        $device | Add-Member -MemberType NoteProperty -Name "MED Connectivity" -Value ""
        if ($internet -eq "True") {
            $connected = $false
            foreach ($url in $urls) {
                $scriptBlock = {
                    param ($url)
                    Write-Output "Testing URL: $url"  # Debugging output
                    try {
                        # Use Invoke-WebRequest for HTTP GET
                        $winHttpRequest = New-Object -ComObject WinHttp.WinHttpRequest.5.1
                        $winHttpRequest.Open("GET", $url, $false)
                        $winHttpRequest.Send()
                        Write-Output "Status Code: $($winHttpRequest.Status)"  # Debugging output
                        return $winHttpRequest.Status
                    } catch {
                        Write-Output "Failed to connect to $url - Error: $_"
                        return $null
                    }
                }
                try {
                    # Execute the script block on the remote device
                    $statusCode = Invoke-Command -ComputerName $deviceName -Credential $cred -ScriptBlock $scriptBlock -ArgumentList $url
                    if ($statusCode -eq 200) {
                        Write-Output "Successfully connected to $url from $deviceName"
                        $device."MED Connectivity" = "True"
                        $connected = $true
                        break  # Exit the URL loop if successful
                    } else {
                        Write-Output "Failed to connect to $url from $deviceName - Status Code: $statusCode"
                    }
                } catch {
                    Write-Output "Error invoking command on $deviceName - Error: $_"
                }
            }
            if (-not $connected) {
                $device."MED Connectivity" = "False"  # Set to False if no successful connection
            }
        } else {
            Write-Output "Internet connectivity is lost/unknown on $deviceName, skipping..."
            $device."MED Connectivity" = "Unknown"
        }
    }
    # Export the updated CSV file
    $devices | Export-Csv -Path $csvPath -NoTypeInformation
}
 
 
function Enable-DiagtrackService {
    param (
        [pscredential]$cred,
        [array]$devices
    )
    Write-Output "Diagtrack service check beginning..."
    foreach ($device in $devices) {
        $deviceName = $device.'Device Name'
        $MEDConnectivity = $device."MED Connectivity"
 
        # Add the "Diagtrack Service" property to the device object
        $device | Add-Member -MemberType NoteProperty -Name "Diagtrack Service" -Value ""
 
        if ($MEDConnectivity -eq "True") {
            $scriptBlock_check = {
                sc.exe query diagtrack
            }
            try {
                $result = Invoke-Command -ComputerName $deviceName -Credential $cred -ScriptBlock $scriptBlock_check
                if ($result -match "RUNNING") {
                    Write-Output "Diagtrack service is running on $deviceName"
                    $device."Diagtrack Service" = "True"
                } else {
                    Write-Output "Diagtrack service is stopped on $deviceName"
                    $device."Diagtrack Service" = "False"
                }
            } catch {
                Write-Output "Error checking diagtrack service on $deviceName"
                $device."Diagtrack Service" = "Error"
            }
        } else {
            Write-Output "MED connectivity is lost/unknown on $deviceName, skipping..."
            $device."Diagtrack Service" = "Unknown"
        }
 
        $diagtrackService = $device."Diagtrack Service"
 
        if ($diagtrackService -eq "False") {
            $enable = Read-Host "Do you want to enable diagtrack service on the host? (Y/N)"
            switch ($enable.ToUpper()) {
                'Y' {
                    try {
                        $scriptBlock_enable = {
                            net start diagtrack
                        }
                        $return = Invoke-Command -ComputerName $deviceName -Credential $cred -ScriptBlock $scriptBlock_enable -ErrorAction Stop
                        if ($return -match "was started successfully") {
                            Write-Output "Diagtrack service was started successfully on $deviceName"
                            $device."Diagtrack Service" = "True"
                        } else {
                            Write-Output "Failed to start diagtrack service on $deviceName"
                            $device."Diagtrack Service" = "False"
                        }
                    } catch {
                        Write-Output "Error starting diagtrack service on $deviceName"
                        $device."Diagtrack Service" = "Error"
                    }
                }
                'N' {
                    Write-Output "No actions taken on $deviceName"
                    $device."Diagtrack Service" = "False"
 
                }
                Default {
                    Write-Output "Invalid option"
                }
            }
        }
    }
    # Export the updated CSV file
    $devices | Export-Csv -Path $csvPath -NoTypeInformation
}
 
function Check-DefenderAVStatus {
    param (
        [pscredential]$cred,
        [array]$devices
    )
    Write-Output "Defender antivirus status check beginning..."
    foreach ($device in $devices) {
        $deviceName = $device.'Device Name'
        $diagtrackService = $device."Diagtrack Service"
        # Add the "Diagtrack Service" property to the device object
        $device | Add-Member -MemberType NoteProperty -Name "Defender AV Enabled" -Value ""
        if ($diagtrackService -eq "True") {
            $scriptBlock_registry = {
                Get-Item -Path Registry::"HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender"
            }
            try {
                $registryReturn = Invoke-Command -ComputerName $deviceName -Credential $cred -ScriptBlock $scriptBlock_registry
 
                # Check for DisableAntiSpyware and DisableAntiVirus registry keys
                $disableAntiSpyware = $null
                $disableAntiVirus = $null
                if ($registryReturn.PSObject.Properties["DisableAntiSpyware"]) {
                    $disableAntiSpyware = $registryReturn.DisableAntiSpyware
                }
                if ($registryReturn.PSObject.Properties["DisableAntiVirus"]) {
                    $disableAntiVirus = $registryReturn.DisableAntiVirus
                }
 
                if (($disableAntiSpyware -eq 1) -or ($disableAntiVirus -eq 1)) {
                    Write-Output "Defender AV is blocked by policy on $deviceName"
                    $device."Defender AV Enabled" = "False"
                } else {
                    Write-Output "Defender AV is not blocked by policy on $deviceName"
                    $device."Defender AV Enabled" = "True"
                }
            } catch {
                Write-Output "Error checking Defender AV status on $deviceName"
                $device."Defender AV Enabled" = "Error"
            }
        } else {
            Write-Output "Diagtrack service is stopped/unknown on $deviceName, skipping..."
            $device."Defender AV Enabled" = "Unknown"
        }
    }
}
 
function Report-MDESensorHealthCheck {
    param (
        [array]$devices,
        [string]$reportPath
    )
 
    # Create a new array to hold modified devices
    $modifiedDevices = foreach ($device in $devices) {
        # Create a PSObject with selected columns
        $newDevice = New-Object PSObject -Property @{
            "Device Name" = $device.'Device Name'
            "OS Platform" = $device.'OS Platform'
            Reachable  = $device.Reachable
            Internet   = $device.Internet
            "MED Connectivity" = $device."MED Connectivity"
            "Diagtrack Service" = $device."Diagtrack Service"
            "Defender AV Status" = $device."Defender AV Enabled"
        }
        $deviceName = $device.'Device Name'
        if ($device."Defender AV Enabled" -eq "True") {
            $value = "Check if the sensor health on $deviceName is still misconfigured, if so, raise a support ticket with Microsoft if necessary"
        } elseif ($device."Diagtrack Service" -eq "True" -and $device."Defender AV Enabled" -eq "False" ) {
            $value = "Enable the Defender AV on $deviceName"
        } elseif ($device."Diagtrack Service" -eq "True" -and $device."Defender AV Enabled" -eq "Error") {
            $value = "Check the Defender AV status on $deviceName manually"
        } elseif ($device."MED Connectivity" -eq "True" -and $device."Diagtrack Service" -eq "False") {
            $value = "Enable Diagtrack Service on $deviceName"
        } elseif ($device."MED Connectivity" -eq "True" -and $device."Diagtrack Service" -eq "Error") {
            $value = "Check the Diagtrack Service on $deviceName manually"
        } elseif ($device.Internet -eq "True" -and $device."MED Connectivity" -eq "False") {
            $value = "Check the firewall rules for further investigation"
        } elseif ($device.Internet -eq "True" -and $device."MED Connectivity" -eq "Error") {
            $value = "Check the MED Connectivity on $deviceName manually"
        } elseif ($device.Reachable -eq "True" -and $device.Internet -eq "False") {
            $value = "Check the firewall rules for further investigation"
        } elseif ($device.Reachable -eq "True" -and $device.Internet -eq "Error") {
            $value = "Check the Internet connectivity on $deviceName manually"
        } else {
            $value = "Raise a ticket for $deviceName and assign it to system owner for assistance"
        }
        # Define the new column in the report
        $newDevice | Add-Member -MemberType NoteProperty -Name Suggestion -Value $value
        $newDevice | Add-Member -MemberType NoteProperty -Name "Work Comment" -Value ""
        # Output the modified device
        $newDevice
    }
    # Export the modified devices to the new CSV file
    $modifiedDevices | Export-Csv -Path $reportPath -NoTypeInformation
    Write-Host "New CSV file has been created: $reportPath"
}
 
# Execution
Test-RemoteHostReachable -cred $cred -devices $devices
Test-RemoteHostInternetConnectivity -cred $cred -devices $devices
Test-MEDClientConnectivity -cred $cred -devices $devices -urls $urls
Enable-DiagtrackService -cred $cred -devices $devices
Check-DefenderAVStatus -cred $cred -devices $devices
Report-MDESensorHealthCheck -devices $devices -reportPath $reportPath