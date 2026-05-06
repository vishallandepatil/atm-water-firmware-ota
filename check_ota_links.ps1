param(
    [string]$ManifestUrl = "https://raw.githubusercontent.com/vishallandepatil/atm-water-firmware-ota/main/ota/manifest.json"
)

$ErrorActionPreference = "Stop"

function Write-Result {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Details
    )

    $status = if ($Pass) { "PASS" } else { "FAIL" }
    Write-Host "[$status] $Name - $Details"
}

try {
    Write-Host "Checking manifest URL: $ManifestUrl"

    $manifestHead = Invoke-WebRequest -Uri $ManifestUrl -Method Head -MaximumRedirection 5
    Write-Result -Name "Manifest HEAD status" -Pass ($manifestHead.StatusCode -eq 200) -Details "HTTP $($manifestHead.StatusCode)"

    $manifestText = Invoke-WebRequest -Uri $ManifestUrl -MaximumRedirection 5 | Select-Object -ExpandProperty Content
    $manifest = $manifestText | ConvertFrom-Json

    $hasVersion = -not [string]::IsNullOrWhiteSpace($manifest.version)
    $hasFirmwareUrl = -not [string]::IsNullOrWhiteSpace($manifest.firmware_url)

    Write-Result -Name "Manifest has version" -Pass $hasVersion -Details "version=$($manifest.version)"
    Write-Result -Name "Manifest has firmware_url" -Pass $hasFirmwareUrl -Details "firmware_url=$($manifest.firmware_url)"

    if (-not $hasFirmwareUrl) {
        throw "firmware_url missing in manifest"
    }

    $firmwareUrl = [string]$manifest.firmware_url
    Write-Host "Checking firmware URL: $firmwareUrl"

    $firmwareHead = Invoke-WebRequest -Uri $firmwareUrl -Method Head -MaximumRedirection 10
    $firmwareOk = $firmwareHead.StatusCode -eq 200
    Write-Result -Name "Firmware HEAD status" -Pass $firmwareOk -Details "HTTP $($firmwareHead.StatusCode)"

    $contentType = [string]$firmwareHead.Headers["Content-Type"]
    $contentLengthRaw = [string]$firmwareHead.Headers["Content-Length"]
    [long]$contentLength = 0
    [void][long]::TryParse($contentLengthRaw, [ref]$contentLength)

    Write-Result -Name "Firmware content type present" -Pass (-not [string]::IsNullOrWhiteSpace($contentType)) -Details "Content-Type=$contentType"

    $firmwareSizePass = $false
    $firmwareSizeDetails = ""

    if ($contentLength -gt 0) {
        $firmwareSizePass = $true
        $firmwareSizeDetails = "Content-Length=$contentLengthRaw"
    }
    else {
        $tmpFile = Join-Path $env:TEMP "ota_firmware_check.bin"
        Invoke-WebRequest -Uri $firmwareUrl -OutFile $tmpFile -MaximumRedirection 10
        $downloadedSize = (Get-Item $tmpFile).Length
        Remove-Item $tmpFile -Force

        $firmwareSizePass = $downloadedSize -gt 0
        $firmwareSizeDetails = "Downloaded bytes=$downloadedSize"
    }

    Write-Result -Name "Firmware size > 0" -Pass $firmwareSizePass -Details $firmwareSizeDetails

    $isRawHost = $firmwareUrl -like "https://raw.githubusercontent.com/*"
    Write-Result -Name "Firmware URL is raw.githubusercontent.com" -Pass $isRawHost -Details "Recommended for OTA stability"

    if ($firmwareOk -and $firmwareSizePass) {
        Write-Host "\nOverall: OTA links are reachable and firmware has non-zero size."
        exit 0
    }

    Write-Host "\nOverall: OTA link checks failed."
    exit 1
}
catch {
    Write-Result -Name "Script exception" -Pass $false -Details $_.Exception.Message
    Write-Host "\nOverall: OTA link checks failed due to exception."
    exit 1
}
