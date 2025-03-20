<#
.SYNOPSIS
 
    Name: Defender-MPLog-Review.ps1
    This PowerShell script filters lines from a MP log file to keep only those with percentages greater than 70%, extracts the path and percentage, deduplicates the paths, and writes the results to an output file.
 
    This script performs the following:
 
 
    1. Define File Paths: The script sets the input and output file paths.
    2. Read Input File: It reads all lines from the input file.
    3. Initialize Hash Set: A hash set is initialized to store unique paths.
    4. Filter and Extract: The script filters lines with percentages greater than 70%, extracts the path and percentage, and checks for uniqueness.
    5. Write Output File: Finally, it writes the filtered and deduplicated lines to the output file.
 
.NOTES
 
    Release Date: 15/01/2025
    Author: Juana Fan
#>
 
# Define the input and output file paths
$inputFilePath = "THE_PATH_OF_YOUR_MPLOG"
$outputFilePath = "YOUR_PATH_OF_OUTPUT"
 
# Read all lines from the input file
$lines = Get-Content -Path $inputFilePath
 
# Initialize a hash set to store unique paths
$uniquePaths = @{}
 
# Filter lines with percentage greater than 70% and extract path and percentage
$filteredLines = $lines | ForEach-Object {
    if ($_ -match "\d+(\.\d+)?%") {
        $percentage = [regex]::Match($_, "\d+(\.\d+)?%").Value.TrimEnd('%')
        if ([double]$percentage -gt 70) {
            $pathMatch = [regex]::Match($_, "\\Device\\HarddiskVolume\d+\\[^,]+")
            if ($pathMatch.Success) {
                $path = $pathMatch.Value
                if (-not $uniquePaths.ContainsKey($path)) {
                    $uniquePaths[$path] = $percentage
                    return "$path, $percentage%"
                }
            }
        }
    }
}
 
# Write the filtered lines to the output file
$filteredLines | Out-File -FilePath $outputFilePath -Encoding utf8
Write-Host "Filtered lines have been written to $outputFilePath"