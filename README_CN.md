# Unity MCP Bootstrap

这是一个独立的 Codex skill 仓库，用来解决 Unity-MCP 在本地 Windows 工作流里的“启动、恢复、重连”问题。

很多时候并不是“配置没有写”，而是：

- `mcp-for-unity` 只跑在 `stdio`
- 本地 `http://127.0.0.1:8080` 没起来
- Unity 编辑器没开
- 进入 `PlayMode` 或脚本重编后实例掉线
- `/health` 正常但 `/api/instances` 为空

这个 skill 的目的，就是把这条恢复链固定下来，而不是每次临时猜。

默认提供中英文文档：

- 英文：[README.md](README.md)
- 中文：[README_CN.md](README_CN.md)

## 这个 Skill 能做什么

它会指导 Codex：

- 检查 `mcp-for-unity` 进程是否存在
- 区分当前到底是 `stdio` 还是 `http` 传输
- 拉起本地 HTTP bridge：`http://127.0.0.1:8080`
- 验证 `/health` 和 `/api/instances`
- 在 Unity 没打开时重启项目
- 在 `PlayMode` / `domain reload` 后等待实例重连
- 把失败原因分类清楚，而不是一律当成“桥挂了”

## 什么时候用

适合这些场景：

- `Unity-MCP` 没响应
- `/api/instances` 为空
- Unity 编辑器没开
- 进入 `PlayMode` 后桥接掉线
- 想在运行时验收前，先把 MCP 恢复到可用状态

它和 `unity-mcp-validator` 是配套关系：

- `unity-mcp-bootstrap`：先把桥拉起来
- `unity-mcp-validator`：桥起来以后再做运行时验收

## 仓库结构

- [SKILL.md](SKILL.md)：主技能说明
- [agents/openai.yaml](agents/openai.yaml)：Codex/OpenAI skill 元信息
- [CHANGELOG.md](CHANGELOG.md)：版本记录
- [README.md](README.md)：英文说明
- [SETUP.md](SETUP.md)：安装和接线说明
- [EXAMPLES.md](EXAMPLES.md)：常见恢复示例
- [references/manual-http-probe.md](references/manual-http-probe.md)：原始 HTTP 探针示例

## 安装方式

把整个目录复制到你的 Codex skills 目录：

```text
C:\Users\<你自己的用户名>\.codex\skills\unity-mcp-bootstrap
```

最少需要：

- `SKILL.md`
- `agents/openai.yaml`

建议一起带上：

- `README.md`
- `README_CN.md`
- `CHANGELOG.md`

## 固定恢复流程

1. 先探测 `http://127.0.0.1:8080/health`
2. 再探测 `http://127.0.0.1:8080/api/instances`
3. 看 `mcp-for-unity` 当前是不是只跑在 `stdio`
4. 如果没有本地 HTTP，就单独拉起 `http` 模式
5. 如果 Unity 没开，就启动对应版本的 Unity 项目
6. 轮询等待 Unity 实例重新注册
7. 等实例回来以后，再做截图、PlayMode 检查、console 扫描等 runtime 验证

## 经验要点

- 本地 `127.0.0.1` 不应该走外部代理
- `PlayMode` 要当成“重连边界”看待
- `/health` 正常但 `instances` 为空，通常是 Unity 侧还没注册回来
- `uloop` 如果写死了错误的 Unity Hub 路径，不要死磕，直接找真实的 `Unity.exe`

## 当前版本

当前打包版本：`1.0.0`
