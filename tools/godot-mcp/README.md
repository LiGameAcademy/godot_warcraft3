# Godot MCP（godot-warcraft3）

面向本仓库 **headless 测试** 的 MCP 服务，供 Cursor / Claude Desktop 等通过 stdio 调用。

不依赖 Godot 编辑器插件；复用 `tools/lib/godot-cli.mjs` 定位 Godot 与项目根目录。

## 工具一览

| 工具 | 用途 |
|------|------|
| `godot_status` | 检查 `GODOT` 路径与项目根 |
| `godot_warmup` | `--quit-after 1`，刷新 `class_name` 全局缓存 |
| `godot_list_selftests` | 列出 `tests/**/selftest_*.gd` |
| `godot_run_selftest` | 跑单个 selftest |
| `godot_run_selftests` | 批量跑（可先 warmup） |
| `godot_run_main_scene` | headless 进局若干秒，抓启动报错 |
| `godot_run_script` | `-s res://...` 工具脚本 |
| `godot_analyze_log` | 分析 `%APPDATA%/Godot/.../godot.log` 尾部 |

## 安装

```bash
cd tools/godot-mcp
npm install
```

或在仓库根目录（workspace 已加入 `tools/godot-mcp`）：

```bash
npm install
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `GODOT` | **推荐**：指向 Godot **console** 版 exe，如 `Godot_v4.6.1-stable_win64_console.exe` |

未设置时按 `tools/lib/godot-cli.mjs` 的候选路径自动查找（桌面 / PATH）。

## Cursor 配置

项目已包含 [`.cursor/mcp.json`](../../.cursor/mcp.json)。在 Cursor **Settings → MCP** 中启用 `godot-warcraft3`。

若需指定 Godot 路径，在 MCP 配置的 `env.GODOT` 中填写（勿提交个人绝对路径时可只用系统环境变量）。

## 本地调试（不走 MCP）

```bash
# 状态
node -e "import('./src/godot-runner.mjs').then(m=>console.log(m.resolveEnv()))" 
# 需在 tools/godot-mcp 目录

# 跑单个 selftest
npm run start   # MCP stdio；或直接：
node --input-type=module -e "
  import { runSelftest, summarizeOutput } from './tools/godot-mcp/src/godot-runner.mjs';
  const r = runSelftest('res://tests/unit/selftest_ability_blizzard.gd');
  console.log(summarizeOutput(r.combined), r.exitCode);
"
```

## 典型工作流

1. 新建 `class_name` 脚本 → `godot_warmup`
2. 改能力/战斗逻辑 → `godot_run_selftest`（如 `ability_blizzard`）
3. F6 报错排查 → `godot_run_main_scene` + `godot_analyze_log`

## 与第三方 godot-mcp 的区别

- **本服务**：CLI/selftest/日志，适合 CI 式验收与 Agent 自动回归。
- **[bradypp/godot-mcp](https://github.com/bradypp/godot-mcp)** 等：编辑器 WebSocket，适合场景/节点编辑。

两者可并存；本仓库默认只配置 headless 测试 MCP。
