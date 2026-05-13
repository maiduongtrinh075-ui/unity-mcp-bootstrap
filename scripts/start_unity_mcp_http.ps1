param(
    [string]$ExePath = 'C:\Users\X\.local\bin\mcp-for-unity.exe',
    [string]$HttpUrl = 'http://127.0.0.1:8080',
    [int]$WaitSeconds = 4
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path $ExePath)) {
    throw "mcp-for-unity.exe not found at $ExePath"
}

function Invoke-Health([string]$Url) {
    try {
        return Invoke-RestMethod -Uri ($Url.TrimEnd('/') + '/health') -Method Get
    } catch {
        return $null
    }
}

$before = Invoke-Health $HttpUrl
$started = $false
$processId = $null

if (-not $before) {
    $proc = Start-Process -FilePath $ExePath -ArgumentList '--transport','http','--http-url',$HttpUrl -WindowStyle Hidden -PassThru
    $started = $true
    $processId = $proc.Id
    Start-Sleep -Seconds $WaitSeconds
}

$after = Invoke-Health $HttpUrl

[pscustomobject]@{
    exe_path = $ExePath
    http_url = $HttpUrl
    started_new_process = $started
    process_id = $processId
    health_before = [bool]$before
    health_after = [bool]$after
    health_payload = $after
} | ConvertTo-Json -Depth 6
