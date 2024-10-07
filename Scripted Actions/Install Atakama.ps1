# Copyright (c) 2024 Atakama Inc.
# All rights reserved.

# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#     - Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#     - Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer 
#       in the documentation and other materials provided with the distribution.
#     - Neither the name of Atakama nor the names of its contributors may be used to endorse or promote products derived from this software 
#       without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, 
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL ATAKAMA BE LIABLE FOR ANY DIRECT, 
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, 
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Authors: Oleh Katrych, Chris Higley, Ilya Ayzenberg

$currentTime = Get-Date -Format "yyyyMMdd_HHmmss"
$installerName = "AtakamaSetup-$currentTime.exe"
$installerPath = Join-Path $env:TEMP $installerName
$endpointService = "AtakamaEndpoint"

function DownloadFile ($fileUrl, $filePath) {
    $webClient = New-Object System.Net.WebClient

    try {
        $webClient.DownloadFile($fileUrl, $filePath)
    } catch {
        Write-Host "Failed to download a file from '$fileUrl': $_.Exception.Message"
    } finally {
        $webClient.Dispose()
    }

    return Test-Path $filePath
}

function DownloadInstaller {
    Write-Host "Downloading AtakamaSetup.exe ..."

    $installerUrl = "https://www.atakama.com/dl/browser/update/release/gen1/AtakamaSetup.exe"
    $downloadInstallerResult = DownloadFile $installerUrl $installerPath

    # Verify that the installer was downloaded successfully
    if (! $downloadInstallerResult) {
        throw "Failed to download AtakamaSetup.exe: File not found at '$installerPath'."
    }

    Write-Host "AtakamaSetup.exe downloaded successfully"
}

function InstallAtakama {
    Write-Host "Installing Atakama..."

    # Perform silent installation
    Start-Process -FilePath "$installerPath" -ArgumentList "/silent /install" -Wait
}

function VerifyServiceExists {
    $serviceInfo = Get-Service $endpointService -ErrorAction SilentlyContinue
    return [bool]$serviceInfo
}

function VerifyServiceIsRunning {
    try {
        $serviceInfo = Get-Service $endpointService
        $serviceStatus = $serviceInfo.Status.ToString()
        return ($serviceStatus.ToLower() -eq 'running')
    } catch {
        return $false
    }
}

function WaitWrapper ($Callback) {
    $maxTimeout = 60
    $elapsedTime = 0

    # Loop until the callback result is true or the timeout is reached
    for (;;) {
        $result = & $Callback
        if ($result) {
            Write-Host "Callback '$Callback' returned true. Exiting wait loop."
            return $true
        }

        $elapsedTime++

        if ($elapsedTime -ge $maxTimeout) {
            Write-Host "Timeout reached while running '$Callback' callback. Exiting wait loop."
            return $false
        }

        Start-Sleep -Seconds 1
    }
}

function VerifyInstallation {
    $serviceExists = WaitWrapper VerifyServiceExists
    if (! $serviceExists) {
        throw "Atakama installation failed: Service does not exist."
    }

    $serviceRunning = WaitWrapper VerifyServiceIsRunning
    if (! $serviceRunning) {
        throw "Atakama installation failed: Service is not running."
    }
    Write-Host "Atakama installation completed"
}

function DeleteFile ($filePath) {
    if (Test-Path $filePath) {
        Remove-Item -Path $filePath -Force
    }
}

function VerifyAdministratorPermissions {  
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    if (! $isAdmin) {
        throw "Error: This script must be run with administrative privileges."
    }
}

# ==================== MAIN ====================
function main {
    try {
        VerifyAdministratorPermissions
        DownloadInstaller
        InstallAtakama
        VerifyInstallation
    } catch {
        throw $_
    } finally {
        DeleteFile $installerPath
    }
}

# ================== END MAIN ==================

main

# SIG # Begin signature block
# MIIgNAYJKoZIhvcNAQcCoIIgJTCCICECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCals5uZyAB9o2u
# 8yjaSLucVzOY60ed4BLAtVFAuHg+gKCCDbgwggbRMIIEuaADAgECAhALkzRL7KW6
# jutCzYTdkI1tMA0GCSqGSIb3DQEBCwUAMHsxCzAJBgNVBAYTAlVTMQ4wDAYDVQQI
# DAVUZXhhczEQMA4GA1UEBwwHSG91c3RvbjERMA8GA1UECgwIU1NMIENvcnAxNzA1
# BgNVBAMMLlNTTC5jb20gRVYgQ29kZSBTaWduaW5nIEludGVybWVkaWF0ZSBDQSBS
# U0EgUjMwHhcNMjIwMzE2MjAzOTIwWhcNMjUwMzE1MjAzOTIwWjCBwjELMAkGA1UE
# BhMCVVMxETAPBgNVBAgMCE5ldyBZb3JrMREwDwYDVQQHDAhOZXcgWW9yazEVMBMG
# A1UECgwMQXRha2FtYSBJbmMuMRAwDgYDVQQFEwc1NTAxNTAyMRUwEwYDVQQDDAxB
# dGFrYW1hIEluYy4xHTAbBgNVBA8MFFByaXZhdGUgT3JnYW5pemF0aW9uMRkwFwYL
# KwYBBAGCNzwCAQIMCERlbGF3YXJlMRMwEQYLKwYBBAGCNzwCAQMTAlVTMIIBojAN
# BgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAlhQQpHe1Kjq/l3jmEtN0QL+IUJz+
# 9CTei12VMuzBusfgGEd37oxIPeJw+HduNd35DoLPtI2e93fhNbOQ6Up/hktedtY2
# SChkyeMB7F8vUyFfy00ZAr2Vzk6GBeTDQwHxtlzc8/NIHxEel0kW9BG/IEhY+blF
# IlPcv3/HabMYvwlva0egxS44YxfqSmMX0ZuuHfzztBIBdE1vyDv/yBfPAJy+pqZ+
# 5kWeG19/Pa8HquoJTqJrR+DpusmdMWg3GCm7Xns1JQ/unoVzKFWuvwqxmPh4hdVS
# svJJbIQ+wb3i3l0b0nEIcVMs9i3inHutCtsYT+TeHuJxRMdx2njeLdawcfEfEyVn
# Od9kttKV3pTCCR1B5ciwpnnOry1NOcOYrZGmvPQhXGmYzjrNxqJn6l2KwF0EQolK
# XgMquPqWw9SFB0Kyrd2b+sKA1R0f/935aFTVWzt5txlAjWlt+E13OsZScU4RcmT0
# Na8vpRtHt9mLlwgOSQ2Oyr5DG48Yn8QFqXcnAgMBAAGjggGHMIIBgzAMBgNVHRMB
# Af8EAjAAMB8GA1UdIwQYMBaAFDa9Sf8xLOuvakD+mcAW7br8SN1fMFsGCCsGAQUF
# BwEBBE8wTTBLBggrBgEFBQcwAoY/aHR0cDovL2NlcnQuc3NsLmNvbS9TU0xjb20t
# U3ViQ0EtRVYtQ29kZVNpZ25pbmctUlNBLTQwOTYtUjMuY2VyMF8GA1UdIARYMFYw
# BwYFZ4EMAQMwDQYLKoRoAYb2dwIFAQcwPAYMKwYBBAGCqTABAwMCMCwwKgYIKwYB
# BQUHAgEWHmh0dHBzOi8vd3d3LnNzbC5jb20vcmVwb3NpdG9yeTATBgNVHSUEDDAK
# BggrBgEFBQcDAzBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3Jscy5zc2wuY29t
# L1NTTGNvbS1TdWJDQS1FVi1Db2RlU2lnbmluZy1SU0EtNDA5Ni1SMy5jcmwwHQYD
# VR0OBBYEFGupZLRsOEMOD0rnSqzND9FsgjkDMA4GA1UdDwEB/wQEAwIHgDANBgkq
# hkiG9w0BAQsFAAOCAgEAZKBn1eTmOveGfhOlPxpc7DD7FJwnbQVp+73XPr/PXRzH
# mKokecNnyP10Y98qlfIGccgmwOIPbbse8dq2mlD6iDDY3HlI0pK8EfcjXVi2WswS
# LQZcheW9nFnIIPlwqkTyXTjz5z0uvMkK8UgHdXboXfBqaM1SMrCPqAgPB9bIrsx3
# sel4fSiRL7TfZSdznKiisUQC41rO3152BrTAbA4/Ix35OxsB8nI4cGxYPZ1DW8wX
# bjPSC258OFqK8Z/DHDCFhu4SZ8tn441z00bCPIKnm9mMJVR+NdIl9uqFlUg466gR
# i0BYKp59BNGX8YxMojFivoAh4NkbnCBBchiiwx3bSYb96yCaG8nke+AE1YzTzUuD
# 5Ef1StwwF8h0bWoBkXGHtsX6IdleTEmEe1VM8Upw6Bnxy96L5eOqQgoxjEsjQ3H6
# OVJDGacA4o5T3GhkJm+HRnyILFsU/C1HEr1NRVaW8IoBsach6fCKNQwQ6PEQH1s6
# c+0CctUY5RtEGsZV+2Ogimf1FFs3tNl6PoPlQe3j5JH2SBT3qLe4lDrX6TC97G7e
# MDp+E78qUPsgoOy43dtzDynueUK+R+0RgxsxTZknElvNVBmJA01EU9pVDBU/0t/V
# buOSMWxnPoTuV0m+H2qye8zUsi/vZiTFwNQi1LbH89tHpM3FNteP0+A7u7ROC/Ew
# ggbfMIIEx6ADAgECAhBCS2pTzsdmFBwqY7GlHEEEMA0GCSqGSIb3DQEBCwUAMIGC
# MQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAOBgNVBAcMB0hvdXN0b24x
# GDAWBgNVBAoMD1NTTCBDb3Jwb3JhdGlvbjE3MDUGA1UEAwwuU1NMLmNvbSBFViBS
# b290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IFJTQSBSMjAeFw0xOTAzMjYxNzQ0
# MjNaFw0zNDAzMjIxNzQ0MjNaMHsxCzAJBgNVBAYTAlVTMQ4wDAYDVQQIDAVUZXhh
# czEQMA4GA1UEBwwHSG91c3RvbjERMA8GA1UECgwIU1NMIENvcnAxNzA1BgNVBAMM
# LlNTTC5jb20gRVYgQ29kZSBTaWduaW5nIEludGVybWVkaWF0ZSBDQSBSU0EgUjMw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDwqjf3KyGRIGc6OY4V5SG6
# WhMqjVHQcz29rgGME3vWfvhmY+30eyuS8b5ja/eoN2V2DXw0p1Kx2HjwX+mfd3ph
# PoNm7GbOt6Q9fRqVrx1df8WVSaDY6r0j5pQ/mW4lRjjEVZg4PKn05a552vt1bgAf
# ED+xjwL/Qq6S/PXTWgklUmOI3V/0kSgWFatULpzx3uDb0jJpIWdGbVdfm8rRN3+n
# aScerjtqXrLGCqA9YB58dsUcowJlc4QxZe3+VWibrCHRnYR+6gHP5OdLTBhdZIF3
# NmjHA/jKxDb2nxJs3UQZC+lgfgkr25o8Ns+OoRwB93W19m+HCwNaz5jXyyhQl6Wh
# 8qghHPuxTDXqGFsWx0VcACB5b4jTUG9w98XSQx8Xkn4xlqlBukPyudGNxmiS4JuK
# gNZ51ilf5sCBivLLDk0YNgt1qkk27SPOF85RhynQ2Ayiomb/2+eTE4t8lMlrUY1S
# 1jvvig3kvf44oVpoWdgH57U1sJA4PFstIhCXBzuysjJgYcY4FWywurV+g/k8sioe
# v63NWKePbztsN9+uiCxH3xEdqNcUtGWvT/aiSbJhcAr+2U4XeFdeiSXSxB5K055z
# 6hRoKQIiUf3PFAQu/x7zlJSdc1CsqqkrQ3EhjnYyligQWSvsPyDpLubT42YlETic
# aUPq0ySk/6Il6ggOKFic6QIDAQABo4IBVTCCAVEwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAfBgNVHSMEGDAWgBT5YLvU49U09rj1BoAlp3PbRmmonjB8BggrBgEFBQcBAQRw
# MG4wSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cuc3NsLmNvbS9yZXBvc2l0b3J5L1NT
# TGNvbS1Sb290Q0EtRVYtUlNBLTQwOTYtUjIuY3J0MCAGCCsGAQUFBzABhhRodHRw
# Oi8vb2NzcHMuc3NsLmNvbTARBgNVHSAECjAIMAYGBFUdIAAwEwYDVR0lBAwwCgYI
# KwYBBQUHAwMwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybHMuc3NsLmNvbS9T
# U0xjb20tUm9vdENBLUVWLVJTQS00MDk2LVIyLmNybDAdBgNVHQ4EFgQUNr1J/zEs
# 669qQP6ZwBbtuvxI3V8wDgYDVR0PAQH/BAQDAgGGMA0GCSqGSIb3DQEBCwUAA4IC
# AQByj/qBSIKR4mCDJVt7jy+UD4NYzogk+plCTi1ON4n4n7EernRAefney/f/LCUQ
# UphAj1Q4/13RKqla5rcCu8h/7irT/3/MNjxVKUNdNkmWJl1w5/IrBWdHTJlYGQj2
# scZPYNL8OL4CrCXRiA2lLOHd031Xz2rDGWDSbapde0ToWluD28gbNgp+CvUKUjZ4
# 4pr7E1TMnMlHv2JONa8+4boPyZPu1SC3lrdQdlI1ep2hOyZkNx/OvAN7xGGBUonM
# e/5aBRpHruQSyo5U41qfsMGK8vlfRmi5r8fZPoTRKyUSOD27mgHq38xmqLbFH2qT
# R7DOBpKErUODaoY5XEziAkt4c65LKOak+GFpgMz/NOiwL2QCSQ2NLh9966GGBQ/t
# XnA05RgCAOtjvnUmbacckFcHrpmljjfSp8NYbKX051IiNadbu27rSNuact6qWmJJ
# CZ6QKxIPyDrbr2hzndnjecqY+Wgd6uZYLqkYbM2ZOprNJnBE5maYnCUeGWrH2PPn
# /6Y1d/v1fbuMgsdvfVQyu+qZCznoIFEVL4njKuHFIPN6eE49rxdiklSNJ4yQN9zj
# KehCk7b4OysLmVC45DQGmCPu6t+1VLuu2/Hq3XL5Re2x2kM7gPxvbN/ckW24pdTv
# dc1lTGQsWd8TLgIbS/oEk8C7Nx0fsiDTTzOvFqEcwKqoiDGCEdIwghHOAgEBMIGP
# MHsxCzAJBgNVBAYTAlVTMQ4wDAYDVQQIDAVUZXhhczEQMA4GA1UEBwwHSG91c3Rv
# bjERMA8GA1UECgwIU1NMIENvcnAxNzA1BgNVBAMMLlNTTC5jb20gRVYgQ29kZSBT
# aWduaW5nIEludGVybWVkaWF0ZSBDQSBSU0EgUjMCEAuTNEvspbqO60LNhN2QjW0w
# DQYJYIZIAWUDBAIBBQCgfDAQBgorBgEEAYI3AgEMMQIwADAZBgkqhkiG9w0BCQMx
# DAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkq
# hkiG9w0BCQQxIgQgzKaeLawj3c+rSHzilb+FjSSm9IhXXx/Pq9Eyl7JsK5IwDQYJ
# KoZIhvcNAQEBBQAEggGAlf6X65k4HRg6WX7U2aEy+8c0rtxiBu7W/mL3YB5YOXaT
# IlIm3gkTaw3qLsIpWR9RX8T+9vBMTe84ll1C3R2bblyglPScOw6gIja8nDKwuAo3
# jFLqz8N82cHtK7bl9/7NAkjjYcCOlnk4XR79/YiqdmmSA9Pi0vgk+lBT7uUyFDRV
# 38lSHRqCwqXdHn1wgUbqvRryvxRnChPE2R7Mo/4j8NZKRm/Z6JVefJ5Cp13lWpUS
# lVK5w7UmV1pRIeCvI+hfxLM4Xor2wtoyon2OUFP5ioINO+/Qp9924kHaxpvYSDWW
# i0kB+GFW5PM/eMGPEFIJQzkF6AspD8wU0WdzMmy91PoS2+vT4nB/UBSHT6yRZt7a
# OxbP7VRIc9EyZlMe34BOuA/BMTj3NS9F+E7k6zQvMKPbqwY0iqvIIqS9cAzAJn6N
# mPOIiF7MbWNf7lEpO1oDERFvQ4URK8LKwI9wlFrDD2cRuLuzDsRgT+Ubi1gBqcYX
# s0tayapZSggpYD7qT2UgoYIPFTCCDxEGCisGAQQBgjcDAwExgg8BMIIO/QYJKoZI
# hvcNAQcCoIIO7jCCDuoCAQMxDTALBglghkgBZQMEAgEwdwYLKoZIhvcNAQkQAQSg
# aARmMGQCAQEGDCsGAQQBgqkwAQMGATAxMA0GCWCGSAFlAwQCAQUABCBHzQT/ZSsc
# 6ntpxzTa+5yvIQx52tGu0LPlU/pQHytpcwIITb+ILzgOfeYYDzIwMjQwNDI5MTM1
# MTI2WjADAgEBoIIMADCCBPwwggLkoAMCAQICEFparOgaNW60YoaNV33gPccwDQYJ
# KoZIhvcNAQELBQAwczELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVRleGFzMRAwDgYD
# VQQHDAdIb3VzdG9uMREwDwYDVQQKDAhTU0wgQ29ycDEvMC0GA1UEAwwmU1NMLmNv
# bSBUaW1lc3RhbXBpbmcgSXNzdWluZyBSU0EgQ0EgUjEwHhcNMjQwMjE5MTYxODE5
# WhcNMzQwMjE2MTYxODE4WjBuMQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMx
# EDAOBgNVBAcMB0hvdXN0b24xETAPBgNVBAoMCFNTTCBDb3JwMSowKAYDVQQDDCFT
# U0wuY29tIFRpbWVzdGFtcGluZyBVbml0IDIwMjQgRTEwWTATBgcqhkjOPQIBBggq
# hkjOPQMBBwNCAASnYXL1MOl6xIMUlgVC49zonduUbdkyb0piy2i8t3JlQEwA74cj
# K8g9mRC8GH1cAAVMIr8M2HdZpVgkV1LXBLB8o4IBWjCCAVYwHwYDVR0jBBgwFoAU
# DJ0QJY6apxuZh0PPCH7hvYGQ9M8wUQYIKwYBBQUHAQEERTBDMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2VydC5zc2wuY29tL1NTTC5jb20tdGltZVN0YW1waW5nLUktUlNB
# LVIxLmNlcjBRBgNVHSAESjBIMDwGDCsGAQQBgqkwAQMGATAsMCoGCCsGAQUFBwIB
# Fh5odHRwczovL3d3dy5zc2wuY29tL3JlcG9zaXRvcnkwCAYGZ4EMAQQCMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMEYGA1UdHwQ/MD0wO6A5oDeGNWh0dHA6Ly9jcmxz
# LnNzbC5jb20vU1NMLmNvbS10aW1lU3RhbXBpbmctSS1SU0EtUjEuY3JsMB0GA1Ud
# DgQWBBRQTySs77U+YxMjCZIm7Lo6luRdIjAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZI
# hvcNAQELBQADggIBAJigjwMAkbyrxGRBf0Ih4r+rbCB57lTuwViC6nH2fZSciMog
# pqSzrSeVZ2eIb5vhj9rT7jqWXZn02Fncs4YTrA1QyxJW36yjC4jl5/bsFCaWuXzG
# Xt2Y6Ifp//A3Z0sNTMWTTBobmceM3sqnovdX9ToRFP+29r5yQnPcgRTI2PvrVSqL
# xY9Eyk9/0cviM3W29YBl080ENblRcu3Y8RsfzRtVT/2snuDocRxvRYmd0TPaMgIj
# 2xII651QnPp1hiq9xU0AyovLzbsi5wlR5Ip4i/i8+x+HwYJNety5cYtdWJ7uQP6Y
# aZtW/jNoHp76qNftq/IlSx6xEYBRjFBxHSq2fzhUQ5oBawk2OsZ2j0wOf7q7AqjC
# t6t/+fbmWjrAWYWZGj/RLjltqdFPBpIKqdhjVIxaGgzVhaE/xHKBg4k4DfFZkBYJ
# 9BWuP93Tm+paWBDwXI7Fg3alGsboErWPWlvwMAmpeJUjeKLZY26JPLt9ZWceTVWu
# Iyujerqb5IMmeqLJm5iFq/Qy4YPGyPiolw5w1k9OeO4ErmS2FKvk1ejvw4SWR+S1
# VyWnktY442WaoStxBCCVWZdMWFeB+EpL8uoQNq1MhSt/sIUjUudkyZLIbMVQjj7b
# 6gPXnD6mS8FgWiCAhuM1a/hgA+6o1sJWizHdmcpYDhyNzorf9KVRE6iR7rcmMIIG
# /DCCBOSgAwIBAgIQbVIYcIfoI02FYADQgI+TVjANBgkqhkiG9w0BAQsFADB8MQsw
# CQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAOBgNVBAcMB0hvdXN0b24xGDAW
# BgNVBAoMD1NTTCBDb3Jwb3JhdGlvbjExMC8GA1UEAwwoU1NMLmNvbSBSb290IENl
# cnRpZmljYXRpb24gQXV0aG9yaXR5IFJTQTAeFw0xOTExMTMxODUwMDVaFw0zNDEx
# MTIxODUwMDVaMHMxCzAJBgNVBAYTAlVTMQ4wDAYDVQQIDAVUZXhhczEQMA4GA1UE
# BwwHSG91c3RvbjERMA8GA1UECgwIU1NMIENvcnAxLzAtBgNVBAMMJlNTTC5jb20g
# VGltZXN0YW1waW5nIElzc3VpbmcgUlNBIENBIFIxMIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEArlEQE9L5PCCgIIXeyVAcZMnh/cXpNP8KfzFI6HJaxV6o
# Yf3xh/dRXPu35tDBwhOwPsJjoqgY/Tg6yQGBqt65t94wpx0rAgTVgEGMqGri6vCI
# 6rEtSZVy9vagzTDHcGfFDc0Eu71mTAyeNCUhjaYTBkyANqp9m6IRrYEXOKdd/eRE
# sqVDmhryd7dBTS9wbipm+mHLTHEFBdrKqKDM3fPYdBOro3bwQ6OmcDZ1qMY+2Jn1
# o0l4N9wORrmPcpuEGTOThFYKPHm8/wfoMocgizTYYeDG/+MbwkwjFZjWKwb4hoHT
# 2WK8pvGW/OE0Apkrl9CZSy2ulitWjuqpcCEm2/W1RofOunpCm5Qv10T9tIALtQo7
# 3GHIlIDU6xhYPH/ACYEDzgnNfwgnWiUmMISaUnYXijp0IBEoDZmGT4RTguiCmjAF
# F5OVNbY03BQoBb7wK17SuGswFlDjtWN33ZXSAS+i45My1AmCTZBV6obAVXDzLgdJ
# 1A1ryyXz4prLYyfJReEuhAsVp5VouzhJVcE57dRrUanmPcnb7xi57VPhXnCuw26h
# w1Hd+ulK3jJEgbc3rwHPWqqGT541TI7xaldaWDo85k4lR2bQHPNGwHxXuSy3yczy
# Og57TcqqG6cE3r0KR6jwzfaqjTvN695GsPAPY/h2YksNgF+XBnUD9JBtL4c34AcC
# AwEAAaOCAYEwggF9MBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAU3QQJ
# B6L1en1SUxKSle44gCUNplkwgYMGCCsGAQUFBwEBBHcwdTBRBggrBgEFBQcwAoZF
# aHR0cDovL3d3dy5zc2wuY29tL3JlcG9zaXRvcnkvU1NMY29tUm9vdENlcnRpZmlj
# YXRpb25BdXRob3JpdHlSU0EuY3J0MCAGCCsGAQUFBzABhhRodHRwOi8vb2NzcHMu
# c3NsLmNvbTA/BgNVHSAEODA2MDQGBFUdIAAwLDAqBggrBgEFBQcCARYeaHR0cHM6
# Ly93d3cuc3NsLmNvbS9yZXBvc2l0b3J5MBMGA1UdJQQMMAoGCCsGAQUFBwMIMDsG
# A1UdHwQ0MDIwMKAuoCyGKmh0dHA6Ly9jcmxzLnNzbC5jb20vc3NsLmNvbS1yc2Et
# Um9vdENBLmNybDAdBgNVHQ4EFgQUDJ0QJY6apxuZh0PPCH7hvYGQ9M8wDgYDVR0P
# AQH/BAQDAgGGMA0GCSqGSIb3DQEBCwUAA4ICAQCSGXUNplpCzxkH2fL8lPrAm/AV
# 6USWWi9xM91Q5RN7mZN3D8T7cm1Xy7qmnItFukgdtiUzLbQokDJyFTrF1pyLgGw/
# 2hU3FJEywSN8crPsBGo812lyWFgAg0uOwUYw7WJQ1teICycX/Fug0KB94xwxhsvJ
# BiRTpQyhu/2Kyu1Bnx7QQBA1XupcmfhbQrK5O3Q/yIi//kN0OkhQEiS0NlyPPYoR
# boHWC++wogzV6yNjBbKUBrMFxABqR7mkA0x1Kfy3Ud08qyLC5Z86C7JFBrMBfyhf
# PpKVlIiiTQuKz1rTa8ZW12ERoHRHcfEjI1EwwpZXXK5J5RcW6h7FZq/cZE9kLRZh
# vnRKtb+X7CCtLx2h61ozDJmifYvuKhiUg9LLWH0Or9D3XU+xKRsRnfOuwHWuhWch
# 8G7kEmnTG9CtD9Dgtq+68KgVHtAWjKk2ui1s1iLYAYxnDm13jMZm0KpRM9mLQHBK
# 5Gb4dFgAQwxOFPBslf99hXWgLyYE33vTIi9p0gYqGHv4OZh1ElgGsvyKdUUJkAr5
# hfbDX6pYScJI8v9VNYm1JEyFAV9x4MpskL6kE2Sy8rOqS9rQnVnIyPWLi8N9K4GZ
# vPit/Oy+8nFL6q5kN2SZbox5d69YYFe+rN1sDD4CpNWwBBTI/q0V4pkgvhL99IV2
# XasjHZf4peSrHdL4RjGCAlcwggJTAgEBMIGHMHMxCzAJBgNVBAYTAlVTMQ4wDAYD
# VQQIDAVUZXhhczEQMA4GA1UEBwwHSG91c3RvbjERMA8GA1UECgwIU1NMIENvcnAx
# LzAtBgNVBAMMJlNTTC5jb20gVGltZXN0YW1waW5nIElzc3VpbmcgUlNBIENBIFIx
# AhBaWqzoGjVutGKGjVd94D3HMAsGCWCGSAFlAwQCAaCCAWEwGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yNDA0MjkxMzUxMjZaMCgG
# CSqGSIb3DQEJNDEbMBkwCwYJYIZIAWUDBAIBoQoGCCqGSM49BAMCMC8GCSqGSIb3
# DQEJBDEiBCA6gvFDoyZjZWtGt0nxf4uSFPjdy0p73+kMIfczWjPwSTCByQYLKoZI
# hvcNAQkQAi8xgbkwgbYwgbMwgbAEIJ1xf43CN2Wqzl5KsOH1ddeaF9Qc7tj9r+8D
# /T29iUfnMIGLMHekdTBzMQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAO
# BgNVBAcMB0hvdXN0b24xETAPBgNVBAoMCFNTTCBDb3JwMS8wLQYDVQQDDCZTU0wu
# Y29tIFRpbWVzdGFtcGluZyBJc3N1aW5nIFJTQSBDQSBSMQIQWlqs6Bo1brRiho1X
# feA9xzAKBggqhkjOPQQDAgRGMEQCIBC/6nmu5Al08CqddcVEnnwhak1R6v3VjGXv
# VxVPuaa3AiB81MZtRY1q5u6+i0bAf560x2w+jOXOIhOnPvqGOzyurw==
# SIG # End signature block
