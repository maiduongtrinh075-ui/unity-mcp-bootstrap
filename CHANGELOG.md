# Changelog

## 1.5.0 - 2026-05-24

- Added diagnosis recommendations to `unity_mcp_diagnose.ps1`
- Recommendations now distinguish compile errors, reconnect boundaries, shader/material problems, missing script references, missing HTTP bridge, closed Unity editor, and missing Unity instance registration

## 1.4.0 - 2026-05-24

- Added `scripts/unity_mcp_diagnose.ps1` and `.cmd`
- The diagnose route classifies common states such as `http_bridge_down`, `unity_editor_not_running`, `unity_instance_not_registered`, `different_unity_instance_registered`, and `ready`
- Included Editor.log signal extraction for reconnect, compile, missing-script, shader/material, and clean-exit clues

## 1.3.1 - 2026-05-24

- Documented the integrated `unity-mcp-validator` acceptance entry that calls bootstrap automatically
- Clarified the recommended full vibe-coding loop: validator entry first, bootstrap as the recovery layer

## 1.3.0 - 2026-05-24

- Added `scripts/unity_mcp_bootstrap.ps1` as the preferred one-command bootstrap entry
- Added `scripts/unity_mcp_bootstrap.cmd` for execution-policy-friendly Windows usage
- The one-command flow can start HTTP, launch Unity with `-projectPath`, wait for matching instance registration, and emit JSON for downstream validators
- Updated setup, examples, skill guidance, and Chinese documentation for vibe-coding workflows

## 1.2.0 - 2026-05-16

- Documented that direct `Unity.exe` relaunches on this machine must use `-projectPath`
- Added failure classification for the case where Unity starts and then exits cleanly without registering an instance
- Rewrote `README_CN.md` into a clean UTF-8 Chinese guide

## 1.1.0 - 2026-05-14

- Added executable bootstrap helpers under `scripts/`
- Added Windows `.cmd` wrappers to bypass local PowerShell execution-policy friction
- Added `references/troubleshooting.md`
- Expanded setup and examples for real recovery workflows
- Promoted the repo from "documented skill" to "documented + script-backed skill"

## 1.0.0 - 2026-05-14

- Initial standalone repository for `unity-mcp-bootstrap`
- Added bilingual documentation (`README.md` and `README_CN.md`)
- Packaged the Windows-focused Unity-MCP recovery workflow into a reusable Codex skill
