param(
    [string]$ApiBase = 'http://127.0.0.1:8080',
    [string]$Project = '',
    [string]$EditorLogPath = "$env:LOCALAPPDATA\Unity\Editor\Editor.log",
    [int]$LogTailLines = 240
)

$ErrorActionPreference = 'Stop'

function Invoke-LocalGet([string]$Path) {
    try {
        return @{
            ok = $true
            value = Invoke-RestMethod -Uri ($ApiBase.TrimEnd('/') + $Path) -Method Get -TimeoutSec 5
            error = $null
        }
    } catch {
        return @{
            ok = $false
            value = $null
            error = $_.Exception.Message
        }
    }
}

function Get-ProcessSnapshot {
    return @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -eq 'Unity' -or $_.ProcessName -eq 'mcp-for-unity' } |
        ForEach-Object {
            [pscustomobject]@{
                process_id = $_.Id
                name = $_.ProcessName + '.exe'
                command_line = ''
                transport = ''
            }
        })
}

function Get-LogSignals {
    if (-not (Test-Path -LiteralPath $EditorLogPath)) {
        return [pscustomobject]@{
            exists = $false
            path = $EditorLogPath
            signals = @()
            tail = @()
        }
    }

    $tail = @(Get-Content -LiteralPath $EditorLogPath -Tail $LogTailLines -ErrorAction SilentlyContinue)
    $patterns = [ordered]@{
        mcp_auto_start = 'UNITY MCP AUTO START|MCP.*auto'
        connection_failed = 'Connection failed|connect.*failed'
        disconnected = 'disconnected|1005|session superseded'
        compile_error = 'error CS\d+|Compilation failed'
        missing_script = 'referenced script.*Unknown|Missing.*script'
        shader_or_material = 'Shader.*error|material.*missing|pink|magenta'
        unity_exit = 'Cleanup mono|return code|Quitting'
    }
    function Limit-Line([string]$Line) {
        if ($null -eq $Line) {
            return ''
        }
        if ($Line.Length -le 300) {
            return $Line
        }
        return $Line.Substring(0, 300) + '...'
    }
    $signals = New-Object System.Collections.Generic.List[object]
    foreach ($key in $patterns.Keys) {
        $matches = @($tail | Where-Object { $_ -match $patterns[$key] } | Select-Object -Last 5)
        if ($matches.Count -gt 0) {
            $signals.Add([pscustomobject]@{
                name = $key
                count = $matches.Count
                samples = @($matches | ForEach-Object { Limit-Line ([string]$_) })
            })
        }
    }

    return [pscustomobject]@{
        exists = $true
        path = (Resolve-Path -LiteralPath $EditorLogPath).Path
        signals = @($signals.ToArray())
        tail_count = $tail.Count
        tail = @($tail | Select-Object -Last 10 | ForEach-Object { Limit-Line ([string]$_) })
    }
}

$health = Invoke-LocalGet '/health'
$instances = Invoke-LocalGet '/api/instances'
$processes = Get-ProcessSnapshot
$log = Get-LogSignals
$instanceList = @()
if ($instances.ok -and $instances.value.instances) {
    $instanceList = @($instances.value.instances)
}
$matched = $instanceList
if ($Project) {
    $matched = @($matched | Where-Object { $_.project -eq $Project })
}

$classification = if (-not $health.ok) {
    'http_bridge_down'
} elseif ($matched.Count -gt 0) {
    'ready'
} elseif ($instanceList.Count -gt 0) {
    'different_unity_instance_registered'
} elseif (@($processes | Where-Object { $_.name -match '^Unity' }).Count -eq 0) {
    'unity_editor_not_running'
} else {
    'unity_instance_not_registered'
}

[pscustomobject]@{
    ok = ($classification -eq 'ready')
    classification = $classification
    api_base = $ApiBase
    project = $Project
    health = [pscustomobject]@{
        ok = $health.ok
        error = $health.error
        status = if ($health.value) { [string]$health.value.status } else { '' }
        version = if ($health.value) { [string]$health.value.version } else { '' }
        message = if ($health.value) { [string]$health.value.message } else { '' }
    }
    instances = [pscustomobject]@{
        ok = $instances.ok
        error = $instances.error
        count = $instanceList.Count
        items = @($instanceList | ForEach-Object {
            [pscustomobject]@{
                session_id = [string]$_.session_id
                project = [string]$_.project
                hash = [string]$_.hash
                unity_version = [string]$_.unity_version
                connected_at = [string]$_.connected_at
            }
        })
    }
    matched_instances = @($matched | ForEach-Object {
        [pscustomobject]@{
            session_id = [string]$_.session_id
            project = [string]$_.project
            hash = [string]$_.hash
            unity_version = [string]$_.unity_version
            connected_at = [string]$_.connected_at
        }
    })
    processes = $processes
    editor_log = $log
} | ConvertTo-Json -Depth 8

if ($classification -ne 'ready') {
    exit 1
}
