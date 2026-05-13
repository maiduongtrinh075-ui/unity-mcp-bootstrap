# Unity MCP Bootstrap

Bootstrap and recover a local Unity-MCP bridge for Unity projects on Windows.

This repository packages the `unity-mcp-bootstrap` Codex skill as a standalone skill repo. It is meant to solve the practical gap between "Unity-MCP is configured" and "Unity-MCP is actually reachable right now".

Chinese documentation is included by default:
- English: [README.md](README.md)
- 中文: [README_CN.md](README_CN.md)

## What This Skill Does

This skill helps Codex:

- detect whether `mcp-for-unity` is running at all
- distinguish `stdio` transport from the local HTTP workflow
- start a local HTTP bridge on `http://127.0.0.1:8080`
- verify `/health` and `/api/instances`
- relaunch Unity when the editor is closed
- recover from PlayMode or domain-reload disconnects
- classify bridge failures honestly instead of guessing

It is tuned for the Windows workflow used in `D:\Workspace`, but the overall recovery logic is generally useful anywhere Unity-MCP is used locally.

## Repository Layout

- [SKILL.md](SKILL.md): main skill instructions
- [agents/openai.yaml](agents/openai.yaml): skill metadata for Codex/OpenAI agents
- [CHANGELOG.md](CHANGELOG.md): version history
- [README_CN.md](README_CN.md): Chinese documentation
- [SETUP.md](SETUP.md): install and wiring guide
- [EXAMPLES.md](EXAMPLES.md): practical recovery examples
- [references/manual-http-probe.md](references/manual-http-probe.md): raw local HTTP examples

## When To Use It

Use this skill when:

- `/health` fails
- `/api/instances` is empty
- Unity is closed
- Unity-MCP reconnects are flaky after PlayMode
- you need to recover the bridge before using runtime validation skills

This skill pairs naturally with `unity-mcp-validator`:

- `unity-mcp-bootstrap`: make the bridge reachable
- `unity-mcp-validator`: validate runtime behavior once the bridge is alive

## Installation

Copy this folder into your Codex skills directory:

```text
C:\Users\<you>\.codex\skills\unity-mcp-bootstrap
```

Minimum required files:

- `SKILL.md`
- `agents/openai.yaml`

Recommended:

- `README.md`
- `README_CN.md`
- `CHANGELOG.md`

## Core Recovery Flow

1. Probe `http://127.0.0.1:8080/health`
2. Probe `http://127.0.0.1:8080/api/instances`
3. Inspect running `mcp-for-unity` processes
4. If only `stdio` exists, start a second `http` transport process
5. If Unity is not open, launch the project with the matching editor
6. Wait for the Unity instance to re-register
7. Only then run runtime inspection or screenshot validation

## Notes

- Local `127.0.0.1` traffic should not be routed through an external proxy
- PlayMode should be treated as a reconnect boundary
- A healthy server with empty `instances` is usually a Unity-side registration issue, not proof the MCP server is broken
- If `uloop` uses the wrong Unity Hub path, launch the real `Unity.exe` directly

## Version

Current packaged skill version: `1.0.0`
