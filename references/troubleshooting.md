# Troubleshooting

## `/health` Fails

Meaning:

- local HTTP transport is not currently listening

Check:

1. is `mcp-for-unity.exe` running at all
2. if yes, is it only running with `--transport stdio`
3. if yes, start a second process with `--transport http`

## `/health` Passes But `/api/instances` Is Empty

Meaning:

- the MCP server is alive
- Unity has not registered yet

Check:

1. is Unity actually open
2. is the target project still loading or compiling
3. does the latest Unity editor log show a bridge start or repeated reconnect failures

Do not restart the HTTP server first unless there is evidence it is the problem.

## `uloop launch` Uses The Wrong Unity Path

Meaning:

- the project version may be installed, but not under the path `uloop` assumes

Fix:

1. locate the real `Unity.exe`
2. launch that binary directly with `-projectPath`

## Unity Registers Then Disconnects With `1005`

Meaning:

- the plugin session is rotating or dropping after reload/PlayMode

Fix:

1. keep the HTTP server alive
2. poll `/api/instances`
3. when the instance returns, issue the most valuable command first
4. avoid low-value exploratory calls in the narrow reconnect window

## PowerShell Script Is Blocked

Meaning:

- execution policy is blocking local `.ps1`

Fix:

1. call the bundled `.cmd` wrapper
2. or use `powershell -ExecutionPolicy Bypass -File ...`
