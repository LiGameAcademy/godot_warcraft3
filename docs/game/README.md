# 游戏场景（Gameplay）

> 与地图编辑器（`editor/`）对称的**运行时**入口：加载已解析地图、跑对战规则、将来接 WE 触发器。  
> 当前分支：`feature/game-scene-echoisles`  
> 默认开发地图：**Echo Isles**（`res://assets/map-parsed/echoisles`）  
> 最后更新：2026-08-03

## 文档

| 文档 | 内容 |
|------|------|
| [ROADMAP.md](ROADMAP.md) | **先读**：对战地图开发节奏（阶段 A→E）；现阶段**不**急着实现完整触发器 VM |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 游戏层架构、与 Editor/Map 分层关系、触发器远期设计 |

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
| `game/scenes/game_main.tscn` | 游戏壳（待建）；F5 可切到此场景做玩法开发 |
| `editor/scenes/editor_main.tscn` | 地图编辑器（现主场景） |
| `scenes/main.tscn` | 旧 Lost Temple 静态预览（可保留） |
