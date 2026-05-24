param(
    [string]$ApiBase = 'http://127.0.0.1:8080',
    [string]$McpExePath = 'C:\Users\X\.local\bin\mcp-for-unity.exe',
    [string]$ProjectPath = '',
    [string]$Project = '',
    [string]$Hash = '',
    [string]$UnityExePath = '',
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
    [object]$Errors
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

if (!$Project -and $ProjectPath) {
    $Project = Get-ProjectNameFromPath $ProjectPath
}

$errors = @()
$startedHttp = $false
$httpProcessId = $null
$launchedUnity = $false
$unityProcessId = $null
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
    $result = New-Result $false 'Unity-MCP HTTP bridge is not healthy.' $healthProbe.value $null @() $startedHttp $httpProcessId $false $null $resolvedUnityExe ($errors + @($healthProbe.error))
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
        $unity = Start-Process -FilePath $resolvedUnityExe -ArgumentList '-projectPath',$ProjectPath -PassThru
        $launchedUnity = $true
        $unityProcessId = $unity.Id
    }
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
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
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

$result = New-Result $false 'No matching Unity instance registered before timeout.' $healthProbe.value $instancesProbe.value @() $startedHttp $httpProcessId $launchedUnity $unityProcessId $resolvedUnityExe $errors
$result | ConvertTo-Json -Depth 10
exit 1
