# Changelog

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
