# Inspiration: Microsoft AVD Github
# Modified by: Jan Scholte
# Company: Nerdio

$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = 'continue'
$folderPath = "$env:TEMP\NerdioManagerLogs"
$LognameTXT = "Set-DefaultLanguagePack.txt"

if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory -Path $folderPath -Force
    Write-Output "$folderPath has been created."
}
else {
    Write-Output "$folderPath already exists, continue script"
}

Start-Transcript -Path (Join-Path $folderPath -ChildPath $LognameTXT) -Append -IncludeInvocationHeader

Write-Output "################# New Script Run #################"
Write-Output "Current time (UTC-0): $((Get-Date).ToUniversalTime())"

function SetDefaultLanguage {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [ValidateSet("Arabic (Saudi Arabia)", "Bulgarian (Bulgaria)", "Chinese (Simplified, China)", "Chinese (Traditional, Taiwan)", "Croatian (Croatia)", "Czech (Czech Republic)", "Danish (Denmark)", "Dutch (Netherlands)", "English (United Kingdom)", "Estonian (Estonia)", "Finnish (Finland)", "French (Canada)", "French (France)", "German (Germany)", "Greek (Greece)", "Hebrew (Israel)", "Hungarian (Hungary)", "Italian (Italy)", "Japanese (Japan)", "Korean (Korea)", "Latvian (Latvia)", "Lithuanian (Lithuania)", "Norwegian, Bokmål (Norway)", "Polish (Poland)", "Portuguese (Brazil)", "Portuguese (Portugal)", "Romanian (Romania)", "Russian (Russia)", "Serbian (Latin, Serbia)", "Slovak (Slovakia)", "Slovenian (Slovenia)", "Spanish (Mexico)", "Spanish (Spain)", "Swedish (Sweden)", "Thai (Thailand)", "Turkish (Turkey)", "Ukrainian (Ukraine)", "English (Australia)", "English (United States)")]
        [string]$Language
    )

    function Get-RegionInfo($Name = '*') {
        try {
            $cultures = [System.Globalization.CultureInfo]::GetCultures('InstalledWin32Cultures')

            foreach ($culture in $cultures) {        
                if ($culture.DisplayName -eq $Name) {
                    return @($culture.Name, [System.Globalization.RegionInfo]$culture.Name).GeoId
                }
            }
        }
        catch {
            Write-Output "Exception occurred while getting region information"
            Write-Output $_.Exception.Message
        }
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Output "Set default Language"

    $LanguagesDictionary = @{
        "Arabic (Saudi Arabia)"         = "ar-SA"
        "Bulgarian (Bulgaria)"          = "bg-BG"
        "Chinese (Simplified, China)"   = "zh-CN"
        "Chinese (Traditional, Taiwan)" = "zh-TW"
        "Croatian (Croatia)"            = "hr-HR"
        "Czech (Czech Republic)"        = "cs-CZ"
        "Danish (Denmark)"              = "da-DK"
        "Dutch (Netherlands)"           = "nl-NL"
        "English (United States)"       = "en-US"
        "English (United Kingdom)"      = "en-GB"
        "Estonian (Estonia)"            = "et-EE"
        "Finnish (Finland)"             = "fi-FI"
        "French (Canada)"               = "fr-CA"
        "French (France)"               = "fr-FR"
        "German (Germany)"              = "de-DE"
        "Greek (Greece)"                = "el-GR"
        "Hebrew (Israel)"               = "he-IL"
        "Hungarian (Hungary)"           = "hu-HU"
        "Indonesian (Indonesia)"        = "id-ID"
        "Italian (Italy)"               = "it-IT"
        "Japanese (Japan)"              = "ja-JP"
        "Korean (Korea)"                = "ko-KR"
        "Latvian (Latvia)"              = "lv-LV"
        "Lithuanian (Lithuania)"        = "lt-LT"
        "Norwegian, Bokmål (Norway)"    = "nb-NO"
        "Polish (Poland)"               = "pl-PL"
        "Portuguese (Brazil)"           = "pt-BR"
        "Portuguese (Portugal)"         = "pt-PT"
        "Romanian (Romania)"            = "ro-RO"
        "Russian (Russia)"              = "ru-RU"
        "Serbian (Latin, Serbia)"       = "sr-Latn-RS"
        "Slovak (Slovakia)"             = "sk-SK"
        "Slovenian (Slovenia)"          = "sl-SI"
        "Spanish (Mexico)"              = "es-MX"
        "Spanish (Spain)"               = "es-ES"
        "Swedish (Sweden)"              = "sv-SE"
        "Thai (Thailand)"               = "th-TH"
        "Turkish (Turkey)"              = "tr-TR"
        "Ukrainian (Ukraine)"           = "uk-UA"
        "English (Australia)"           = "en-AU"
    }

    try {
        Disable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\Installation"
        Disable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"

        $languageDetails = Get-RegionInfo -Name $Language

        $LanguageTag = $LanguagesDictionary[$Language]
        if ($null -eq $LanguageTag) {
            throw "Language code for $Language not found."
        }

        $GeoID = if ($languageDetails) { $languageDetails[1] } else { $null }

        $foundLanguage = $false

        try {
            $installedLanguages = Get-InstalledLanguage
            foreach ($languagePack in $installedLanguages) {
                if ($languagePack.LanguageId -eq $LanguageTag) {
                    $foundLanguage = $true
                    break
                }
            }
        }
        catch {
            Write-Output "Set default Language - Exception occurred while checking installed languages"
            Write-Output $_.Exception.Message
        }

        if (-not $foundLanguage) {
            $i = 1
            while ($i -le 5) {
                try {
                    Write-Output "Set default language - Install language packs - Attempt: $i"
                    Install-Language -Language $LanguageTag -ErrorAction Stop
                    Write-Output "Set default language - Installed language $LanguageTag"
                    break
                }
                catch {
                    Write-Output "Set default language - Install language packs - Exception occurred"
                    Write-Output $_.Exception.Message
                }
                $i++
            }
        }
        else {
            Write-Output "Set default language - Language pack for $LanguageTag is already installed"
        }

        Set-SystemPreferredUILanguage -Language $LanguageTag
        Set-WinSystemLocale -SystemLocale $LanguageTag
        Set-Culture -CultureInfo $LanguageTag
        Set-WinUILanguageOverride -Language $LanguageTag

        $userLanguageList = New-WinUserLanguageList -Language $LanguageTag
        $installedUserLanguagesList = Get-WinUserLanguageList

        foreach ($language in $installedUserLanguagesList) {
            $userLanguageList.Add($language.LanguageTag)
        }

        Set-WinUserLanguageList -LanguageList $userLanguageList -Force

        Write-Output "Set default Language - $Language with $LanguageTag has been set as the default System Preferred UI Language"

        if ($GeoID) {
            Set-WinHomeLocation -GeoID $GeoID
            Write-Output "Set default Language - $Language with $LanguageTag has been set as the default region"
        }
    }
    catch {
        Write-Output "*** AVD AIB CUSTOMIZER PHASE: Set default Language - Exception occurred***"
        Write-Output $_.Exception.Message
    }

    Enable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\Installation"
    Enable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"

    $stopwatch.Stop()
    $elapsedTime = $stopwatch.Elapsed
    Write-Output "Set default Language - Exit Code: $LASTEXITCODE"
    Write-Output "Set default Language - Time taken: $elapsedTime"
}

SetDefaultLanguage -Language $InheritedVars.SetDefaultLanguage

Stop-Transcript
$VerbosePreference = $SaveVerbosePreference


