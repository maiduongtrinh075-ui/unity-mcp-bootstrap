# Setup

## Install Into Codex

Copy this repository into your local Codex skills directory:

```text
C:\Users\<you>\.codex\skills\unity-mcp-bootstrap
```

Minimum required files:

- `SKILL.md`
- `agents/openai.yaml`

Recommended full install:

- `README.md`
- `README_CN.md`
- `SETUP.md`
- `EXAMPLES.md`
- `CHANGELOG.md`
- `references/`
- `scripts/`

## Expected Environment

This skill assumes a Windows workflow similar to:

- local Unity project under `D:\Workspace`
- Codex running on the same machine
- `mcp-for-unity.exe` available locally
- Unity may be installed outside the default Unity Hub path

## Required Local Checks

Before relying on the skill, confirm:

1. `mcp-for-unity.exe` exists
2. Unity can open the target project
3. local HTTP on `127.0.0.1:8080` is reachable when started
4. Codex can read the Unity Editor log

## Recommended Companion Skill

Use this together with `unity-mcp-validator`:

- `unity-mcp-bootstrap`: start or recover the bridge
- `unity-mcp-validator`: inspect, capture, and validate once the bridge is live

## Common Local Paths

- MCP executable: `C:\Users\X\.local\bin\mcp-for-unity.exe`
- Codex skill install dir: `C:\Users\X\.codex\skills\unity-mcp-bootstrap`
- Unity editor log: `%LOCALAPPDATA%\Unity\Editor\Editor.log`

## First Verification

After install, a simple first check is:

```powershell
Get-Process | Where-Object { $_.ProcessName -like '*mcp*' -or $_.ProcessName -like 'Unity*' }
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -Method Get
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/instances' -Method Get
```

## Script-Backed Verification

Prefer these packaged helpers when you want a repeatable local workflow:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\unity_mcp_bootstrap.ps1 -ProjectPath D:\Workspace\UnitySimpleDemo
powershell -ExecutionPolicy Bypass -File .\scripts\start_unity_mcp_http.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\wait_for_unity_instance.ps1 -TimeoutSeconds 120
```

If execution policy is annoying on this machine, use:

```bat
scripts\unity_mcp_bootstrap.cmd -ProjectPath D:\Workspace\UnitySimpleDemo
scripts\start_unity_mcp_http.cmd
scripts\wait_for_unity_instance.cmd
```

The one-command bootstrap is preferred for vibe-coding loops because it returns a single JSON result and can be used before `unity-mcp-validator` without manual probing.
