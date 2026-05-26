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
    $commandLines = @{}
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Unity.exe' -or $_.Name -eq 'mcp-for-unity.exe' } |
            ForEach-Object { $commandLines[[int]$_.ProcessId] = [string]$_.CommandLine }
    } catch {
        $commandLines = @{}
    }

    return @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -eq 'Unity' -or $_.ProcessName -eq 'mcp-for-unity' } |
        ForEach-Object {
            $commandLine = if ($commandLines.ContainsKey([int]$_.Id)) { $commandLines[[int]$_.Id] } else { '' }
            $transport = if ($commandLine -match '--transport\s+http') {
                'http'
            } elseif ($commandLine -match '--transport\s+stdio') {
                'stdio'
            } else {
                ''
            }
            [pscustomobject]@{
                process_id = $_.Id
                name = $_.ProcessName + '.exe'
                command_line = $commandLine
                transport = $transport
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

function Has-Signal {
    param(
        [object]$Log,
        [string]$Name
    )
    return @($Log.signals | Where-Object { $_.name -eq $Name }).Count -gt 0
}

function Get-Recommendations {
    param(
        [string]$Classification,
        [object]$Log,
        [object[]]$Processes = @()
    )

    $items = New-Object System.Collections.Generic.List[string]

    if (Has-Signal $Log 'compile_error') {
        $items.Add('Editor.log shows C# compile errors. Fix scripts first; restarting the bridge will not make Unity register reliably until compilation succeeds.')
    }
    if (Has-Signal $Log 'disconnected') {
        $items.Add('Editor.log shows disconnect/session rotation signals such as 1005 or session superseded. Treat this as a reconnect boundary: poll /api/instances, then retry the highest-value command against the fresh instance.')
    }
    if (Has-Signal $Log 'shader_or_material') {
        $items.Add('Editor.log shows shader/material or pink/magenta signals. Inspect render pipeline compatibility, missing shaders, and material assignments before accepting visual output.')
    }
    if (Has-Signal $Log 'missing_script') {
        $items.Add('Editor.log shows missing script references. Inspect imported prefabs and scene objects for broken MonoBehaviour components.')
    }
    if (@($Processes | Where-Object { $_.name -eq 'mcp-for-unity.exe' -and $_.transport -eq 'stdio' }).Count -gt 0 -and
        @($Processes | Where-Object { $_.name -eq 'mcp-for-unity.exe' -and $_.transport -eq 'http' }).Count -eq 0) {
        $items.Add('Only a stdio mcp-for-unity process was detected. This does not satisfy the local HTTP validation workflow; start a separate HTTP transport process.')
    }

    switch ($Classification) {
        'http_bridge_down' {
            $items.Add('HTTP bridge is down. Start mcp-for-unity with --transport http --http-url http://127.0.0.1:8080 before running validation.')
        }
        'unity_editor_not_running' {
            $items.Add('Unity editor is not running. Launch the project with Unity.exe -projectPath <ProjectPath>, then wait for /api/instances.')
        }
        'unity_instance_not_registered' {
            $items.Add('HTTP is healthy but no Unity instance is registered. Check the Unity-side MCP plugin, wait through script reloads, and inspect Editor.log for reconnect or compile errors.')
        }
        'different_unity_instance_registered' {
            $items.Add('A Unity instance is registered, but not the requested project. Pass the correct -Project value or close/open the intended project.')
        }
        'ready' {
            $items.Add('Bridge and requested Unity instance are ready. It is safe to run smoke, visual gates, or runtime commands.')
        }
    }

    return @($items.ToArray())
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

$recommendations = Get-Recommendations -Classification $classification -Log $log -Processes $processes

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
    processes = [object[]]@($processes)
    editor_log = $log
    recommendations = [object[]]@($recommendations)
} | ConvertTo-Json -Depth 8

if ($classification -ne 'ready') {
    exit 1
}
