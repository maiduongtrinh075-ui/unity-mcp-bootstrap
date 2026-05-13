---
name: unity-mcp-bootstrap
description: Start or recover a local Unity-MCP bridge for a Unity project on Windows. Use when Codex needs to launch Unity, detect whether `mcp-for-unity` is only running in `stdio` mode, bring up the local HTTP bridge on `127.0.0.1:8080`, confirm Unity has registered under `/api/instances`, and unblock runtime inspection or validation.
---

# Unity MCP Bootstrap

## Overview

Use this skill when Unity runtime inspection is blocked because the editor is closed, the MCP server is only running in `stdio`, `/health` is up but `/api/instances` is empty, or PlayMode/domain reload dropped the bridge.

This skill is specifically tuned for the local Windows workflow used in `D:\Workspace`, where Codex can reach Unity-MCP through local HTTP routes even when dedicated Unity tools are not exposed in the current session.

## Workflow

### 1. Preflight the local bridge

Check the three separate moving pieces:

- `mcp-for-unity` process exists
- HTTP transport is actually listening on `127.0.0.1:8080`
- Unity editor has registered an instance

Use:

```powershell
Get-Process | Where-Object { $_.ProcessName -like '*unity*' -or $_.ProcessName -like '*mcp*' }
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -Method Get
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/instances' -Method Get
```

Interpretation:

- `/health` fails: HTTP server is not running
- `/health` passes but `instances` is empty: Unity editor is closed or Unity-side bridge is not connected yet
- an `mcp-for-unity` process with command line `--transport stdio` does not satisfy the local HTTP workflow by itself

### 2. If needed, start the HTTP server explicitly

On this machine, Codex often already owns a `stdio` MCP server. Do not kill it just because you need HTTP. Start a second process for local HTTP:

```powershell
Start-Process -FilePath 'C:\Users\X\.local\bin\mcp-for-unity.exe' `
  -ArgumentList '--transport','http','--http-url','http://127.0.0.1:8080' `
  -WindowStyle Hidden
```

Then verify:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -Method Get
```

Local HTTP does not need the user's external proxy. Do not route `127.0.0.1` traffic through the proxy.

### 3. Make sure Unity is actually running

If `/api/instances` is empty, confirm whether Unity is open:

```powershell
Get-Process | Where-Object { $_.ProcessName -like 'Unity*' -or $_.MainWindowTitle -like '*Unity*' }
```

If Unity is not running, launch the project with the matching editor version.

Important Windows pitfall:

- `uloop` from PowerShell can fail because `uloop.ps1` is blocked by execution policy
- prefer `cmd /c uloop launch <project>` or `uloop.cmd`

Example:

```powershell
cmd /c uloop launch "D:\Workspace\UnitySimpleDemo"
```

If `uloop` says the Hub default path does not contain the target version, search common install roots or launch the discovered `Unity.exe` directly.

On this machine, Unity `6000.3.12f1` was discovered at:

- `D:\Program Files\Unity 6000.3.12f1\Editor\Unity.exe`

So when `uloop` hardcodes `C:\Program Files\Unity\Hub\Editor\<version>\Editor\Unity.exe`, use the real editor path directly instead of treating that as a mystery failure.

### 4. Keep the Unity-side bootstrap script in the project

For local projects that should auto-reconnect, keep an editor bootstrap like:

- `Assets/Editor/UnityMcpAutoBridgeBootstrap.cs`

The working pattern is:

- `EditorConfigurationCache.Instance.SetUseHttpTransport(true);`
- `await MCPServiceLocator.Bridge.StartAsync();`
- `await MCPServiceLocator.Bridge.VerifyAsync();`

This avoids depending on the editor UI being manually configured every session.

Do not make the bootstrap one-shot only. After script recompiles or PlayMode transitions, the bridge can drop and must be retried. Prefer an editor update loop with:

- a short retry interval
- a guard so only one bridge attempt runs at a time
- resets on `EnteredEditMode` and `EnteredPlayMode`

Before adding your own bootstrap, inspect the package cache for built-in handlers such as:

- `Editor/Services/HttpAutoStartHandler.cs`
- `Editor/Services/HttpBridgeReloadHandler.cs`

If the package already ships auto-start and reload-resume logic, treat your custom bootstrap as a thin supplement only. Do not blindly layer a second full reconnect system on top without checking how `Bridge.StartAsync()` stops or switches transports, or you can end up debugging interactions between two competing reconnect policies.

### 5. Read the editor log when registration is missing

Use the latest Unity editor log tail when `/api/instances` stays empty:

```powershell
Get-Content -Path "$env:LOCALAPPDATA\Unity\Editor\Editor.log" -Tail 200
```

What to look for:

- `UNITY MCP AUTO START started=True success=True`
- HTTP or websocket connection success
- repeated `Connection failed` lines, which usually mean Unity tried to connect before the local HTTP server was up
- `The referenced script (Unknown) on this Behaviour is missing!` can appear during scene reloads or imported prefab cleanup; treat it as a possible visual-content issue, not as proof the bridge itself failed

Do not confuse old log noise with the current state. Use the newest tail, not a historical error from an earlier session.

### 6. Wait for instance registration before sending runtime commands

Do not send `/api/command` work until Unity is registered:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/instances' -Method Get
```

Use the reported `unity_instance` hash in subsequent commands.

Common local routes:

- `GET /api/instances`
- `POST /api/command`

Common command types:

- `manage_scene`
- `manage_editor`
- `find_gameobjects`
- `get_gameobject`
- `get_gameobject_components`
- `execute_code`
- `read_console`
- `manage_camera`

### 7. Expect a brief disconnect on PlayMode or domain reload

Entering PlayMode or recompiling scripts can temporarily drop the bridge. Treat that as normal:

1. send `manage_editor` play
2. poll `/api/instances`
3. wait for Unity to reconnect
4. resume runtime inspection

Do not misclassify the temporary disconnect as a fatal failure unless the instance does not return.

If the plugin reconnects but then the server log shows a fast `disconnected (1005)`, assume you have a narrow command window. In that case:

1. poll `/api/instances`
2. as soon as the instance appears, send the highest-value command immediately
3. prefer one-shot evidence capture such as `manage_camera` screenshot or a single `execute_code` probe
4. do not waste the reconnect window on low-value exploratory commands first

## Recovery Checklist

Use this exact order:

1. Confirm `/health`
2. If missing, start HTTP transport
3. Check `/api/instances`
4. If empty, confirm Unity process exists
5. If Unity is closed, relaunch the project
6. Tail `Editor.log` for Unity-MCP bridge status
7. Only after the instance appears, send `/api/command`

## Failure Classification

Separate the failure into the correct bucket before reacting:

- **Server healthy, editor open, `/api/instances` empty**:
  this is primarily a Unity-side plugin registration or reconnect problem
- **Server log shows `Plugin registered ...` and then fast `disconnected (1005)`**:
  this is primarily plugin session instability across reloads or PlayMode transitions
- **Command reaches Unity but returns parser/compiler errors**:
  this is an interaction-shape problem in the request you sent, not proof the bridge is down

Treat these differently. Do not restart the HTTP server every time a command fails if the real issue is request syntax or a Unity-side reconnect gap.

## Fallback Visual Capture Without Unity-MCP

If Unity is open but `/api/instances` stays empty, you can still capture the live editor window as fallback evidence.

Practical Windows fallback:

1. find the `Unity` process whose `MainWindowTitle` contains the project name
2. restore that window first if it is minimized, then bring it to front
3. capture its screen rect with a small PowerShell script using `System.Drawing` + `user32.dll`

This does not replace PlayMode-aware screenshot capture, but it is still useful to answer questions like:

- is the editor really in Game view?
- is a ranch/shop overlay covering the riding scene?
- are there obviously duplicated props on the rider?

If `uloop focus-window` is unavailable because the project is not set up for Unity CLI Loop, go straight to the native PowerShell window-capture fallback instead of treating that as a blocker.

If the capture unexpectedly shows the desktop or a non-Unity window, treat that as a restore/focus problem first. On Windows, calling `ShowWindow(..., 9)` before `SetForegroundWindow(...)` is a useful baseline fix for minimized Unity editors.

### Fallback In-Unity Render Capture

If the OS-level fallback is unreliable on this machine, prefer a screenshot rendered from inside Unity itself instead of trusting desktop capture.

In this project, use:

- `Assets/Editor/HorseArcherCaptureScreenshot.cs`

Available entry points:

- batch/CLI flow: `HorseArcherCaptureScreenshot.Run()` - captures and exits the editor
- interactive editor flow: menu `Tools > Horse Archer > Capture Hero Shot (Keep Editor Open)` - captures and leaves the editor open
- current live view: menu `Tools > Horse Archer > Capture Current Play Camera` - captures the current `Camera.main` view during an already-running PlayMode session

Why this matters here:

- `CopyFromScreen` can capture the desktop instead of Unity
- `PrintWindow` can return the Unity frame while the DX12 client area stays black
- an in-Unity camera render avoids both issues and produces a more honest gameplay image

When you add or maintain this path, keep the capture flow PlayMode-aware:

1. open the gameplay scene
2. enter PlayMode
3. arrange a deterministic hero shot if needed
4. wait until presentation state is ready
5. render from `Camera.main` into a `RenderTexture`
6. save the PNG to a known path

## Pitfalls

- A healthy local server with zero `instances` means Unity is not connected yet, not that the server is useless
- A `stdio`-only `mcp-for-unity` process is not enough for local HTTP automation
- PowerShell execution policy can block `uloop.ps1`; use `cmd /c uloop launch ...`
- `uloop` can also fail even when the project version is correct because it assumes the Hub default install path; search the real drive and launch `Unity.exe` directly when needed
- After a crash, `Temp\\UnityLockfile` can block relaunch; only clean stale lock/temp files after confirming no Unity editor process is active
- Local/LAN bridge traffic does not need the external proxy
- A server log warning like `No Unity plugin reconnected within 20.00s` means the HTTP server is healthy but Unity did not return to the hub in time; treat that as a Unity-side reconnect problem, not a reason to restart the HTTP server first
- When the plugin repeatedly registers and then disconnects with `1005`, optimize for immediate capture on reconnect and keep a local fallback path such as editor-log inspection and direct screenshot files under `Assets/Screenshots`
- For imported weapon rigs, do not promote a grip/helper bone into the whole prop's visual root just because it is convenient for alignment. Use helper bones only for measuring grip/string anchors; keep the actual prefab root as the visual root or the bow/arrow facing can flip and the string side can end up mirrored relative to the rider.
- When replacing a character's built-in weapon with your own imported prop, hide the source character's original weapon renderers first and only then attach the replacement prop. Otherwise you can end up with two bows on the rider and misread the duplicate as a mount-offset bug.
- `uloop focus-window` may not work if the target project does not contain the Unity CLI Loop settings file. That does not mean the editor cannot be captured; fall back to native window capture.
- `execute_code` can fail for interaction-shape reasons even while the bridge is fine. In this environment, top-level `using UnityEngine;` sent to `execute_code` produced a parser error (`Unexpected symbol 'UnityEngine'`). Prefer fully qualified names like `UnityEngine.Object.FindFirstObjectByType<...>()` or switch compiler mode deliberately instead of blaming the bridge first.
- Do not claim Unity-MCP validator input tools such as `simulate-click-ui`, `simulate-click-world`, or `click-button-by-name` are available unless `/api/instances` currently reports a live Unity editor instance and the tool path is actually callable in the session. If the bridge is down or the instance list is empty, remove simulated-click from the proposed validation route and fall back to direct code inspection, editor-log evidence, or native window capture instead.

## References

- [README.md](README.md)
- [README_CN.md](README_CN.md)
- [SETUP.md](SETUP.md)
- [EXAMPLES.md](EXAMPLES.md)
- [references/manual-http-probe.md](references/manual-http-probe.md)
