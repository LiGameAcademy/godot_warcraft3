# packages/ — 共享源码（单一来源）

D4 起由 `tools/workspace/Sync-Packages.ps1` 复制到各应用的 `packages/<name>/`（`res://packages/...`）。
这不是 Godot AssetLib addon；`addons/` 仅留给第三方插件（GAS/Panku 等）。
**只在本目录编辑**；生成副本禁止手改。

| 包 | 职责 |
|----|------|
| `foundation/` | 跨包小工具与类型 |
| `content/` | 定义 schema、快照、加载契约（现暂部分在 `scripts/content/`） |
| `map/` | 地图数据/查询/地形表现（现 `scripts/map/`） |
| `gameplay/` | 对局运行库（现 `game/match|entities|features`） |

迁移完成前，主工程仍直接使用仓库内路径；双应用通过同步副本启动验证。
