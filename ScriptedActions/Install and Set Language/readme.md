![image](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/5c8dd05e-84a7-49f9-8218-64412fdaffaf)

# Install and Set Language Scripted Action

## Getting Started

We utilize the Nerdio $InheritedVars.LanguagePacks variable from the InheritedVars ability within Nerdio Manager for MSP to set the language of the user's session. This script will install the language pack and set the language for the user. This way you only have to set these values in the NMM Account environment and reuse the script over all your managed Accounts.

How to setup these InheritedVars can be found in these articles: 

- [NMM Documentation MSP Global Inherited Vars](https://nmmhelp.getnerdio.com/hc/en-us/articles/25498222400269-Scripted-Actions-MSP-Level-Variables).

- [NMM Documentation Account Inherited Vars](https://nmmhelp.getnerdio.com/hc/en-us/articles/25498291119629-Scripted-Actions-Account-Level-Variables).

Keep in mind for the **$InheritedVars.LanguagePacks** variable you have to set the content thise way:
```text
Dutch (Netherlands),English (United Kingdom)
```
Also for the **$InheritedVars.SetDefaultLanguage** you have to set the content this way, currently setting one default language is supported:
```text
Dutch (Netherlands)
```
Don't put any "" around the values and separate them with a comma without a whitespace between languages.

![NMM-ScreenShotInheritedVars](https://github.com/Get-Nerdio/NMM-SE/assets/52416805/34880301-b384-44e3-82b4-351eab5ee87d)


## Language Packs Syntax

As you can see in the example above, the language packs are separated by a comma. The language packs are in the format of "Language (Country)". Ignore the acronym country codes, as they are not used in the script. The script will automatically convert the language packs to the correct format.

```powershell
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
```
