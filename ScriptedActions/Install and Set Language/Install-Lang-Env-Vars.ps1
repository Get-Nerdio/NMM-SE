# Inspiration: Microsoft AVD Github
# Modified by: Jan Scholte
# Company: Nerdio

$SaveVerbosePreference = $VerbosePreference
$VerbosePreference = 'continue'
$folderPath = "$env:TEMP\NerdioManagerLogs"
$LognameTXT = "Install-languagePack.txt"

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

function Install-LanguagePack {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [ValidateSet("Arabic (Saudi Arabia)", "Bulgarian (Bulgaria)", "Chinese (Simplified, China)", "Chinese (Traditional, Taiwan)", "Croatian (Croatia)", "Czech (Czech Republic)", "Danish (Denmark)", "Dutch (Netherlands)", "English (United Kingdom)", "Estonian (Estonia)", "Finnish (Finland)", "French (Canada)", "French (France)", "German (Germany)", "Greek (Greece)", "Hebrew (Israel)", "Hungarian (Hungary)", "Italian (Italy)", "Japanese (Japan)", "Korean (Korea)", "Latvian (Latvia)", "Lithuanian (Lithuania)", "Norwegian, Bokmål (Norway)", "Polish (Poland)", "Portuguese (Brazil)", "Portuguese (Portugal)", "Romanian (Romania)", "Russian (Russia)", "Serbian (Latin, Serbia)", "Slovak (Slovakia)", "Slovenian (Slovenia)", "Spanish (Mexico)", "Spanish (Spain)", "Swedish (Sweden)", "Thai (Thailand)", "Turkish (Turkey)", "Ukrainian (Ukraine)", "English (Australia)", "English (United States)")]
        [string[]]$LanguageList
    )

    BEGIN {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Output "Starting AVD AIB Customization: Install Language packs: $((Get-Date).ToUniversalTime())"

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

        Disable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\Installation"
        Disable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"
    }

    PROCESS {
        foreach ($Language in $LanguageList) {
            $LanguageCode = $LanguagesDictionary[$Language]
            if (-not $LanguageCode) {
                Write-Output "Language code for $Language not found."
                continue
            }

            $i = 1
            while ($i -le 5) {
                try {
                    Write-Output "Install language packs - Attempt: $i"
                    Install-Language -Language $LanguageCode -ErrorAction Stop
                    Write-Output "Install language packs - Installed language $LanguageCode"
                    break
                }
                catch {
                    Write-Output "Install language packs - Exception occurred"
                    Write-Output $_.Exception.Message
                }
                $i++
            }
        }
    }

    END {
        
        Enable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\Installation"
        Enable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"

        $stopwatch.Stop()
        $elapsedTime = $stopwatch.Elapsed
        Write-Output "Install language packs - Exit Code: $LASTEXITCODE"
        Write-Output "Ending: Install language packs - Time taken: $elapsedTime"
    }
}

$stringArray = $InheritedVars.LanguagePacks.Trim('"').Split(',')

Install-LanguagePack -LanguageList $stringArray

Stop-Transcript
$VerbosePreference = $SaveVerbosePreference
