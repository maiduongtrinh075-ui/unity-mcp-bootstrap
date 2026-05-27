param(
    [string]$ApiBase = 'http://127.0.0.1:8080',
    [string]$McpExePath = 'C:\Users\X\.local\bin\mcp-for-unity.exe',
    [string]$ProjectPath = '',
    [string]$Project = '',
    [string]$Hash = '',
    [string]$UnityExePath = '',
    [string[]]$UnityArgs = @(),
    [int]$HttpWaitSeconds = 8,
    [int]$TimeoutSeconds = 180,
    [switch]$NoLaunchUnity
)

$ErrorActionPreference = 'Stop'

function New-Result(
    [bool]$Ok,
    [string]$Message,
    [object]$Health,
    [object]$Instances,
    [object]$MatchedInstances,
    [bool]$StartedHttp,
    [Nullable[int]]$HttpProcessId,
    [bool]$LaunchedUnity,
    [Nullable[int]]$UnityProcessId,
    [string]$ResolvedUnityExe,
    [object]$Errors,
    [object]$Diagnostics = $null
) {
    [pscustomobject]@{
        ok = $Ok
        message = $Message
        api_base = $ApiBase
        project_path = $ProjectPath
        project = $Project
        hash = $Hash
        started_http = $StartedHttp
        http_process_id = $HttpProcessId
        launched_unity = $LaunchedUnity
        unity_process_id = $UnityProcessId
        unity_exe = $ResolvedUnityExe
        health = $Health
        instances = $Instances
        matched_instances = @($MatchedInstances)
        errors = @($Errors)
        diagnostics = $Diagnostics
    }
}

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

function Get-ProjectNameFromPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }
    return Split-Path -Leaf (Resolve-Path -LiteralPath $Path)
}

function Get-UnityVersionFromProject([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }
    $versionFile = Join-Path $Path 'ProjectSettings\ProjectVersion.txt'
    if (!(Test-Path -LiteralPath $versionFile)) {
        return ''
    }
    $line = Get-Content -LiteralPath $versionFile | Where-Object { $_ -match '^m_EditorVersion:\s*(.+)$' } | Select-Object -First 1
    if ($line -match '^m_EditorVersion:\s*(.+)$') {
        return $Matches[1].Trim()
    }
    return ''
}

function Resolve-UnityExe([string]$RequestedPath, [string]$Path) {
    if ($RequestedPath) {
        if (!(Test-Path -LiteralPath $RequestedPath)) {
            throw "Unity.exe not found at $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $version = Get-UnityVersionFromProject $Path
    $roots = @(
        'D:\Program Files',
        'C:\Program Files\Unity\Hub\Editor',
        'C:\Program Files'
    )

    $candidates = @()
    foreach ($root in $roots) {
        if (!(Test-Path -LiteralPath $root)) {
            continue
        }
        $candidates += @(Get-ChildItem -LiteralPath $root -Recurse -Filter Unity.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\Editor\\Unity\.exe$' })
    }

    if ($version) {
        $matched = @($candidates | Where-Object { $_.FullName -like "*$version*" } | Select-Object -First 1)
        if ($matched.Count -gt 0) {
            return $matched[0].FullName
        }
    }

    $fallback = @($candidates | Sort-Object FullName -Descending | Select-Object -First 1)
    if ($fallback.Count -gt 0) {
        return $fallback[0].FullName
    }

    throw 'Unity.exe could not be discovered. Pass -UnityExePath explicitly.'
}

function Select-MatchingInstances([object]$InstancesPayload, [string]$ProjectFilter, [string]$HashFilter) {
    if (-not $InstancesPayload -or -not $InstancesPayload.instances) {
        return @()
    }
    $matches = @($InstancesPayload.instances)
    if ($ProjectFilter) {
        $matches = @($matches | Where-Object { ([string]$_.project) -eq $ProjectFilter.Trim() })
    }
    if ($HashFilter) {
        $matches = @($matches | Where-Object { ([string]$_.hash) -eq $HashFilter.Trim() })
    }
    return $matches
}

function Get-ProcessSnapshot {
    return @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -eq 'Unity' -or $_.ProcessName -eq 'mcp-for-unity' } |
        ForEach-Object {
            [pscustomobject]@{
                process_id = $_.Id
                name = $_.ProcessName + '.exe'
                path = [string]$_.Path
                transport = ''
                has_exited = $false
            }
        })
}

function Get-EditorLogSignals {
    $path = Join-Path $env:LOCALAPPDATA 'Unity\Editor\Editor.log'
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            exists = $false
            path = $path
            signals = @()
            tail = @()
        }
    }

    $tail = @(Get-Content -LiteralPath $path -Tail 260 -ErrorAction SilentlyContinue)
    $patterns = [ordered]@{
        mcp_auto_start = 'UNITY MCP AUTO START|VIBE MCP AUTO BRIDGE|MCP.*auto'
        connection_failed = 'Connection failed|connect.*failed|Unable to connect'
        disconnected = 'disconnected|1005|session superseded'
        compile_error = 'error CS\d+|Compilation failed|Scripts have compiler errors'
        missing_script = 'referenced script.*Unknown|Missing.*script'
        shader_or_material = 'Shader.*error|material.*missing|pink|magenta'
        unity_hub_launch_shape = 'Launching Unity Hub|Exiting without the bug reporter'
        unity_exit = 'Cleanup mono|return code|Quitting'
    }
    $signals = New-Object System.Collections.Generic.List[object]
    foreach ($key in $patterns.Keys) {
        $matches = @($tail | Where-Object { $_ -match $patterns[$key] } | Select-Object -Last 6)
        if ($matches.Count -gt 0) {
            $signals.Add([pscustomobject]@{
                name = $key
                count = $matches.Count
                samples = @($matches | ForEach-Object {
                    $line = [string]$_
                    if ($line.Length -gt 320) { $line.Substring(0, 320) + '...' } else { $line }
                })
            })
        }
    }

    return [pscustomobject]@{
        exists = $true
        path = (Resolve-Path -LiteralPath $path).Path
        signals = @($signals.ToArray())
        tail = @($tail | Select-Object -Last 16)
    }
}

function New-Diagnostics {
    param(
        [object]$UnityProcess,
        [object]$LastInstancesProbe
    )

    $processes = @(Get-ProcessSnapshot)
    $unityExited = $false
    if ($UnityProcess) {
        try {
            $UnityProcess.Refresh()
            $unityExited = [bool]$UnityProcess.HasExited
        } catch {
            $unityExited = $true
        }
    }

    $recommendations = New-Object System.Collections.Generic.List[string]
    $log = Get-EditorLogSignals
    $signalNames = @($log.signals | ForEach-Object { $_.name })
    if ($signalNames -contains 'compile_error') {
        $recommendations.Add('Editor.log contains compile-error signals. Fix C# first; bridge restart will not make Unity register reliably.')
    }
    if ($signalNames -contains 'unity_hub_launch_shape') {
        $recommendations.Add('Editor.log shows Unity Hub launch/clean exit signals. Verify Unity was launched with -projectPath and did not receive the project path as a bare positional argument.')
    }
    if ($signalNames -contains 'connection_failed') {
        $recommendations.Add('Unity appears to have connection failures. Confirm HTTP server is healthy before launching Unity, then wait for /api/instances.')
    }
    if ($UnityProcess -and $unityExited) {
        $recommendations.Add('The Unity process launched by bootstrap has already exited. Inspect Editor.log for launch-shape, licensing, or compile problems.')
    }
    if ($recommendations.Count -eq 0) {
        $recommendations.Add('HTTP is healthy but no matching Unity instance registered. Keep Unity open, inspect the MCP package state in the Editor, and retry /api/instances.')
    }

    return [pscustomobject]@{
        processes = [object[]]$processes
        launched_unity_exited = $unityExited
        editor_log = $log
        last_instances_probe_ok = if ($LastInstancesProbe) { [bool]$LastInstancesProbe.ok } else { $false }
        last_instances_error = if ($LastInstancesProbe) { [string]$LastInstancesProbe.error } else { '' }
        recommendations = [object[]]@($recommendations.ToArray())
    }
}

function New-LightDiagnostics {
    param([object]$UnityProcess)

    $unityExited = $false
    if ($UnityProcess) {
        try {
            $UnityProcess.Refresh()
            $unityExited = [bool]$UnityProcess.HasExited
        } catch {
            $unityExited = $true
        }
    }

    $processes = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -eq 'Unity' -or $_.ProcessName -eq 'mcp-for-unity' } |
        ForEach-Object {
            [pscustomobject]@{
                process_id = $_.Id
                name = $_.ProcessName + '.exe'
                path = [string]$_.Path
            }
        })

    $recommendations = New-Object System.Collections.Generic.List[string]
    if (@($processes | Where-Object { $_.name -eq 'mcp-for-unity.exe' }).Count -eq 0) {
        $recommendations.Add('No mcp-for-unity process is visible. Start the HTTP bridge first.')
    }
    if ($UnityProcess -and $unityExited) {
        $recommendations.Add('The Unity process launched by bootstrap has already exited. Run unity_mcp_diagnose.ps1 for Editor.log details.')
    }
    if ($recommendations.Count -eq 0) {
        $recommendations.Add('Run unity_mcp_diagnose.ps1 for detailed Editor.log and transport diagnosis, then retry bootstrap.')
    }

    return [pscustomobject]@{
        lightweight = $true
        processes = [object[]]$processes
        launched_unity_exited = $unityExited
        recommendations = [object[]]@($recommendations.ToArray())
    }
}

if (!$Project -and $ProjectPath) {
    $Project = Get-ProjectNameFromPath $ProjectPath
}

$errors = @()
$startedHttp = $false
$httpProcessId = $null
$launchedUnity = $false
$unityProcessId = $null
$unityProcess = $null
$resolvedUnityExe = ''

$healthProbe = Invoke-LocalGet '/health'
if (-not $healthProbe.ok) {
    if (!(Test-Path -LiteralPath $McpExePath)) {
        $errors += "mcp-for-unity.exe not found at $McpExePath"
    } else {
        $proc = Start-Process -FilePath $McpExePath -ArgumentList '--transport','http','--http-url',$ApiBase -WindowStyle Hidden -PassThru
        $startedHttp = $true
        $httpProcessId = $proc.Id

        $deadline = (Get-Date).AddSeconds($HttpWaitSeconds)
        do {
            Start-Sleep -Milliseconds 500
            $healthProbe = Invoke-LocalGet '/health'
        } while (-not $healthProbe.ok -and (Get-Date) -lt $deadline)
    }
}

if (-not $healthProbe.ok) {
    $diagnostics = New-LightDiagnostics -UnityProcess $null
    $result = New-Result $false 'Unity-MCP HTTP bridge is not healthy.' $healthProbe.value $null @() $startedHttp $httpProcessId $false $null $resolvedUnityExe ($errors + @($healthProbe.error)) $diagnostics
    $result | ConvertTo-Json -Depth 10
    exit 1
}

$instancesProbe = Invoke-LocalGet '/api/instances'
$matches = Select-MatchingInstances $instancesProbe.value $Project $Hash

if (@($matches).Count -eq 0 -and $ProjectPath -and -not $NoLaunchUnity) {
    if (!(Test-Path -LiteralPath $ProjectPath)) {
        $errors += "ProjectPath not found at $ProjectPath"
    } else {
        $resolvedUnityExe = Resolve-UnityExe $UnityExePath $ProjectPath
        $launchArgs = @('-projectPath', $ProjectPath) + @($UnityArgs)
        $unity = Start-Process -FilePath $resolvedUnityExe -ArgumentList $launchArgs -PassThru
        $unityProcess = $unity
        $launchedUnity = $true
        $unityProcessId = $unity.Id
    }
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$pollCount = 0
$maxPolls = [Math]::Max(1, [Math]::Ceiling($TimeoutSeconds / 2.0) + 1)
do {
    $pollCount++
    $instancesProbe = Invoke-LocalGet '/api/instances'
    if ($instancesProbe.ok) {
        $matches = Select-MatchingInstances $instancesProbe.value $Project $Hash
        if (@($matches).Count -gt 0) {
            $result = New-Result $true 'Unity-MCP bridge is ready.' $healthProbe.value $instancesProbe.value $matches $startedHttp $httpProcessId $launchedUnity $unityProcessId $resolvedUnityExe $errors
            $result | ConvertTo-Json -Depth 10
            exit 0
        }
    } else {
        $errors += $instancesProbe.error
    }
    if ($pollCount -ge $maxPolls) {
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

$diagnostics = New-LightDiagnostics -UnityProcess $unityProcess
$result = New-Result $false 'No matching Unity instance registered before timeout.' $healthProbe.value $instancesProbe.value @() $startedHttp $httpProcessId $launchedUnity $unityProcessId $resolvedUnityExe $errors $diagnostics
$result | ConvertTo-Json -Depth 10
exit 1
