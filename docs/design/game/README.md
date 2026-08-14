# 游戏场景（Gameplay）

> 与地图编辑器（`editor/`）对称的**运行时**入口：加载已解析地图、跑对战规则、将来接 WE 触发器。  
> 默认开发地图：**Echo Isles**（`res://assets/map-parsed/echoisles`）  
> 最后更新：2026-08-14  
> **当前主线：F2 建造**（F0 命令 + F1 采集已落地）；HUD 中栏契约见 [HUD.md](HUD.md)

## 文档

| 文档 | 内容 |
|------|------|
| [ROADMAP.md](ROADMAP.md) | **先读**：对战地图阶段 A→F→E；现阶段**不**急着实现完整触发器 VM |
| [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) | **当前主线**：人族游玩竖切；进度 F0✅ F1✅ → **F2 建造** |
| [BUILD_SYSTEM.md](BUILD_SYSTEM.md) | **建造系统设计**：四族非对称 · Profile/Strategy · 数据钩子（F2 契约） |
| [TREE_INTERACT.md](TREE_INTERACT.md) | **可交互树**：MultiMesh promote、扣血统一入口、防闪烁 |
| [SELECTION_RINGS.md](SELECTION_RINGS.md) | **选中环**：己方绿 / 中立目标黄（金矿·树） |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 游戏层架构、与 Editor/Map 分层关系、触发器远期设计 |
| [PATHFINDING_CHOICE.md](../pathfinding/CHOICE.md) | **寻路选型**：网格 A\* vs NavMesh+RVO（主推网格） |
| [ENVIRONMENT.md](ENVIRONMENT.md) | 天空 / 天气 / 光照 / 阴影复刻方案（WC3→Godot） |
| [HUD.md](HUD.md) | **游戏 HUD**：三分栏、中栏三种形态、肖像、主选/Tab、命令卡二级建造 |

## 与编辑器的关系

```text
editor/          改地图（MapDocument + 笔刷）
scripts/map/     地图 Data/Catalog/Logic/Present（两边共用）
game/            玩地图（GameDirector + Session + 将来 Trigger）
```

- 游戏场景**不**依赖 `MapDocument` / 笔刷 / 撤销。
- 表现继续复用 `scenes/map/map_root.tscn`（`MapLoader`）。
- 开发期默认打开：**最小栅格（32）** + **路径-地面** overlay。

## 入口（目标）

| 场景 | 用途 |
|------|------|
| `game/scenes/game_main.tscn` | 游戏壳（阶段 A）；**F6 运行当前场景**做玩法开发（勿改工程主场景，编辑器仍 F5） |
| `editor/scenes/editor_main.tscn` | 地图编辑器（现主场景） |
| `scenes/main.tscn` | 旧 Lost Temple 静态预览（可保留） |
