param(
    [string]$ApiBase = 'http://127.0.0.1:8080',
    [int]$TimeoutSeconds = 120,
    [string]$Project = '',
    [string]$Hash = ''
)

$ErrorActionPreference = 'Stop'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$last = $null

function Get-Instances([string]$Base) {
    try {
        return Invoke-RestMethod -Uri ($Base.TrimEnd('/') + '/api/instances') -Method Get
    } catch {
        return $null
    }
}

while ((Get-Date) -lt $deadline) {
    $resp = Get-Instances $ApiBase
    if ($resp -and $resp.instances) {
        $matches = @($resp.instances)
        if ($Project) {
            $matches = @($matches | Where-Object { $_.project -eq $Project })
        }
        if ($Hash) {
            $matches = @($matches | Where-Object { $_.hash -eq $Hash })
        }
        if ($matches.Count -gt 0) {
            [pscustomobject]@{
                ok = $true
                api_base = $ApiBase
                timeout_seconds = $TimeoutSeconds
                matched_instances = $matches
            } | ConvertTo-Json -Depth 8
            exit 0
        }
        $last = $resp
    }
    Start-Sleep -Seconds 2
}

[pscustomobject]@{
    ok = $false
    api_base = $ApiBase
    timeout_seconds = $TimeoutSeconds
    last_response = $last
    message = 'No matching Unity instance registered before timeout.'
} | ConvertTo-Json -Depth 8
exit 1
