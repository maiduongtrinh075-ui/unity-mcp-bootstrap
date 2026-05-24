# Unity MCP Bootstrap 中文说明

这是一个独立的 Codex skill 仓库，用来把本地 Unity-MCP 桥接恢复流程固定下来。

它解决的不是“Unity 项目怎么写”的问题，而是更底层、更常见的阻塞点：Unity 编辑器开没开、`mcp-for-unity` 是否真的提供 HTTP、`/api/instances` 里有没有当前项目、PlayMode 或脚本重载后实例有没有掉线。

## 它能做什么

- 检查本地 `http://127.0.0.1:8080/health`
- 检查 `/api/instances` 是否有 Unity 项目实例
- 在 HTTP 不可用时启动 `mcp-for-unity.exe --transport http`
- 在传入 `-ProjectPath` 且没有匹配实例时，用 `Unity.exe -projectPath` 启动项目
- 等待 Unity 重新注册实例
- 输出 JSON，方便后续 `unity-mcp-validator` 或其他脚本继续使用
- 在诊断结果里给出下一步建议，例如先修 C# 编译错误、等待 reconnect、检查 shader/material/render pipeline

## 推荐用法

优先使用一键脚本：

```bat
scripts\unity_mcp_bootstrap.cmd -ProjectPath D:\Workspace\UnitySimpleDemo
```

或者 PowerShell 形式：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\unity_mcp_bootstrap.ps1 -ProjectPath D:\Workspace\UnitySimpleDemo
```

成功时会返回 `ok: true`，并包含：

- 是否新启动了 HTTP bridge
- 是否启动了 Unity
- 使用的 Unity.exe 路径
- 匹配到的 Unity 实例

失败时会返回 `ok: false`，并用非零退出码结束，方便自动化流程直接拦截。

## 和 validator 的关系

这两个仓库建议成对使用：

- `unity-mcp-bootstrap`：负责把 Unity-MCP 拉起来
- `unity-mcp-validator`：负责进入 PlayMode、截图、扫 console、做视觉验收

完整 vibe coding 验收现在建议从 validator 的集成入口启动：

```powershell
powershell -ExecutionPolicy Bypass -File D:\Workspace\unity-mcp-validator\scripts\unity_vibe_accept.ps1 `
  -ProjectPath D:\Workspace\UnitySimpleDemo `
  -Project UnitySimpleDemo `
  -Config D:\Workspace\unity-mcp-validator\validation-config.yaml
```

这个命令会先调用本仓库的 bootstrap 脚本，再继续执行 smoke 和视觉验收。

典型 vibe coding 流程：

1. 修改 Unity 代码、Prefab、场景或资源
2. 运行 `unity_mcp_bootstrap.cmd -ProjectPath <项目路径>`
3. 运行 `unity_vibe_accept.cmd -ProjectPath <项目路径>`
4. 根据截图、console 和报告继续迭代

## 仓库结构

- [SKILL.md](SKILL.md)：Codex skill 主说明
- [agents/openai.yaml](agents/openai.yaml)：skill 元信息
- [README.md](README.md)：英文说明
- [README_CN.md](README_CN.md)：中文说明
- [SETUP.md](SETUP.md)：安装与接线说明
- [EXAMPLES.md](EXAMPLES.md)：常见恢复示例
- [CHANGELOG.md](CHANGELOG.md)：变更记录
- [references/manual-http-probe.md](references/manual-http-probe.md)：原始 HTTP 探针示例
- [references/troubleshooting.md](references/troubleshooting.md)：故障分类
- `scripts/`：可执行脚本

## 脚本列表

- `scripts/unity_mcp_bootstrap.ps1`：推荐的一键入口
- `scripts/unity_mcp_bootstrap.cmd`：Windows cmd 包装
- `scripts/unity_mcp_diagnose.ps1`：诊断 bridge、进程、实例和 Editor.log 状态
- `scripts/unity_mcp_diagnose.cmd`：对应 cmd 包装
- `scripts/start_unity_mcp_http.ps1`：只启动并验证 HTTP bridge
- `scripts/start_unity_mcp_http.cmd`：对应 cmd 包装
- `scripts/wait_for_unity_instance.ps1`：只等待 Unity 实例注册
- `scripts/wait_for_unity_instance.cmd`：对应 cmd 包装

## 注意事项

- 本地 `127.0.0.1` 不需要走外部代理
- 只有 `stdio` 模式的 `mcp-for-unity` 进程，不等于 HTTP 自动化可用
- `/health` 正常但 `instances` 为空，通常是 Unity 侧还没注册回来
- 直接启动 `Unity.exe` 时必须显式使用 `-projectPath`
- PlayMode、脚本重编译、domain reload 后短暂掉线是正常现象，应先轮询等待实例恢复

## 当前版本

当前打包版本：`1.5.0`
