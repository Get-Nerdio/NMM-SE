<#
This script is used to update QuickBooks to the latest version.
It downloads the QuickBooks update tool from a specified URL, runs the update,
and then cleans up any temporary files created during the process.

IMPORTANT:
This script does not automatically find the latest available update due to how Intuit structures their update URLs.
Instead, it uses a predefined mapping of QuickBooks versions to their corresponding update URLs. 
You will need to ensure that the mapping is up-to-date with the latest QuickBooks releases.  You can find a list of available updates on
Intuit's website: https://quickbooks.intuit.com/learn-support/en-us/help-article/update-quickbooks-desktop/00/2024

Locate your QuickBooks version and edition, and ensure that the corresponding URL in the script is correct.  The URL can be found
by right-clicking on the "Get lastest updates" link for your version of QuickBooks on the Intuit website, and copying the link address.
If a new version of QuickBooks is released, you will need to update the script with the new URL for that version.

Note that this script will only work for Premier and Enterprise editions of Quickbooks.

This script is designed to be run manually in an elevated PowerShell session on a Desktop image VM as part of regular maintenance.

#> 

Function Get-QuickBooksUpdateURL {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$QBYear,
        [Parameter(Mandatory = $true)]
        [string]$QBEdition
    )

    If ($QBYear.Length -eq 2) {
        $QBYear = "20$QBYear"
    }
    Else {
        # Year is already in 4 digit format, do nothing.
    }

    If ($QBEdition -eq "Enterprise") {
        $QBFileName = "en_qbwebpatch.exe"
    }
    Else {
        $QBFileName = "qbwebpatch.exe"
    }
    
    <# Map QuickBooks year to the corresponding update URL.  Paste the URL for each version of QuickBooks in the switch statement below.
    You can find the URL by right-clicking on the "Get lastest updates" link for your version of QuickBooks on the Intuit website,
    and copying the link address.  Do not include the file name or the trailing "/".  You can add additional years to the
    switch statement as needed when new versions of QuickBooks are released.  The URL structure is generally the same for each version,
    but the specific release identifier may differ.
    #>
    switch ($QBYear) {
        "2024" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2024/rnkpzeq9nUS_R19/Webpatch" }
        "2023" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2023/nctqf0a84US_R18/Webpatch" }
        "2022" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2022/dmknzyq5nUS_R19/Webpatch" }
        "2021" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2021/eo2bf393iUS_R17/Webpatch" }
        "2020" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2020/cveofqqkrsUS_R17/Webpatch" }
        "2019" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2019/szxlidxcipUS_R17/Webpatch" }
        "2018" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2018/qaammbxfvrUS_R17/Webpatch" }
        "2017" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2017/ucnoamocyvUS_R16/Webpatch" }
        "2016" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2016/IFRvyzFmpQUS_R17/WebPatch" }
        "2015" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2015/m734bnderqUS_R17/WebPatch" }
        "2014" { $QBUpdateURL = "https://http-download.intuit.com/http.intuit/Downloads/2014/4covjyl0euUS_R16/WebPatch" }
        default { throw "Unsupported QuickBooks year: $QBYear. Supported years are 2014-2024." }
    }
    $qbUpdaterDownloadlink = $QBUpdateURL, $QBFileName -join "/"

    return $qbUpdaterDownloadlink
}

Function Update-QuickBooks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$QBYear,
        [Parameter(Mandatory = $true)]
        [string]$QBEdition
    )
    
    $QBUpdateFile = "C:\windows\temp\QuickbooksUpdate.exe"
    if(Test-Path -Path $QBUpdateFile){
        Remove-Item $QBUpdateFile -Recurse -Force -ErrorAction Ignore
    }
    $qbUpdaterDownloadlink = Get-QuickBooksUpdateURL -QBYear $QBYear -QBEdition $QBEdition

    try {
        Start-BitsTransfer -Source $qbUpdaterDownloadlink -Destination $QBUpdateFile
    }
    catch {
        throw "Failed to download update for QuickBooks", $QBEdition, $QBYear
    }
    

    $arguments = "/silent", "/a"
    Unblock-File $QBUpdateFile
    try {
        Start-Process $QBUpdateFile -Wait -ArgumentList $arguments -Verb RunAs
    }
    catch {
        throw "Failed to update Quickbooks", $QBEdition, $QBYear
    }
    finally {
        if(Test-Path -Path $QBUpdateFile){
            Remove-Item $QBUpdateFile -Force -ErrorAction Ignore
        }
    }
    

    
}

Function Get-QuickBooksVersions {
    # Get installed QuickBooks versions from registry
    $qbPaths = @(
        "HKLM:\SOFTWARE\Intuit\QuickBooks",
        "HKLM:\SOFTWARE\WOW6432Node\Intuit\QuickBooks"
    )


    $results = foreach ($path in $qbPaths) {
        if (Test-Path $path) {
            $installedproducts = Get-ChildItem $path -Recurse | Where-Object {$_.Property -eq "Product"}
            $installedproducts | ForEach-Object {
                $product = ($_ | Get-ItemProperty -Name "Product").Product
                $path = ($_ | Get-ItemProperty -Name "Path").Path
                [PSCustomObject]@{
                    Edition = If ($product -like "*Enterprise*"){"Enterprise"} Else {"Premier"}
                    Year = If ($product -match "(.{2})\.") {$matches[1]} Else {$product.Substring($product.Length -2)}
                    Path = $path
                }
            }
        }
    }

    return $results

}

Function Start-Quickbooks {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Start-Process $Path -Verb RunAs
    Start-Sleep -Seconds 20
    If (Get-Process qbw32 -ErrorAction SilentlyContinue) {
        Stop-Process qbw32 -Force
    }
    ElseIf (Get-Process qbw -ErrorAction SilentlyContinue) {
        Stop-Process qbw -Force
    }
    Else {
        Write-Host "No running QuickBooks processes found.  Please close any instances of Quickbooks manually before continuing."
        Pause
    }
}

$qbVersions = Get-QuickBooksVersions
If ($qbVersions.Count -eq 0) {
    Write-Host "No QuickBooks installations found."
}
Else {
    Foreach ($qbVersion in $qbVersions) {
        Write-Host "Updating QuickBooks", $qbVersion.Edition, $qbVersion.Year
        Update-QuickBooks -QBYear $qbVersion.Year -QBEdition $qbVersion.Edition
        Start-Quickbooks -Path $qbVersion.Path
    }
}