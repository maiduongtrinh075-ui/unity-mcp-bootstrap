# Examples

## Example 1: HTTP Bridge Missing

Symptoms:

- `/health` fails
- no local HTTP listener on `127.0.0.1:8080`

Response:

1. start `mcp-for-unity.exe` in `http` mode
2. verify `/health`
3. then probe `/api/instances`

## Example 2: Only `stdio` Exists

Symptoms:

- `mcp-for-unity` process exists
- process command line contains `--transport stdio`
- runtime validation skill still cannot use local HTTP routes

Response:

1. keep the existing `stdio` process alive
2. launch a second `mcp-for-unity` process with `--transport http`
3. verify the HTTP route separately

## Example 3: Unity Closed

Symptoms:

- `/health` is healthy
- `/api/instances` is empty
- no active `Unity.exe` editor process

Response:

1. launch the Unity project
2. wait for the editor to finish opening
3. poll `/api/instances` until the project registers

## Example 4: `uloop` Uses the Wrong Unity Path

Symptoms:

- `uloop launch` fails with a missing Unity Hub path
- the project version is actually installed elsewhere

Response:

1. search for the real `Unity.exe`
2. launch it directly with `-projectPath`
3. continue polling `/api/instances`

## Example 5: PlayMode Drop and Reconnect

Symptoms:

- instance disappears right after entering PlayMode
- server is still healthy

Response:

1. do not panic-restart the HTTP server
2. poll `/api/instances`
3. wait for the Unity plugin session to re-register
4. send the highest-value runtime command immediately after reconnect

## Example 6: Full Bootstrap Flow

Goal:

- bring up HTTP transport
- wait for Unity to register
- hand off to `unity-mcp-validator`

Suggested route:

```bat
scripts\unity_mcp_bootstrap.cmd -ProjectPath D:\Workspace\UnitySimpleDemo
```

The command handles:

1. HTTP health probing
2. HTTP bridge startup when missing
3. Unity launch with explicit `-projectPath` when no matching instance is registered
4. polling `/api/instances` until the project is visible
5. JSON output for downstream validation scripts

After this succeeds, run validator preflight and capture from the now-live instance.
