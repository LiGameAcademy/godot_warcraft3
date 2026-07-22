# 地图编辑器（HiveWE 式，Godot 竖切）

> 分支：`feature/map-editor`  
> 入口场景：`editor/scenes/editor_main.tscn`（F6 运行；**不**改 `project.godot` 主场景）

## 目标

在 Godot 内逐步复刻经典「世界编辑器 / HiveWE」能力：可打开/新建地图、编辑 heightfield，预览复用现有地图运行时（`MapRoot` / Domain `Wc3*`）。

## 首期范围（已实现）

| 能力 | 说明 |
|------|------|
| 顶栏菜单 | 场景 `menu_bar.tscn` + `EditorI18n`（窗口菜单可切换中文/English） |
| 创建新地图 | 弹窗 `new_map_dialog.tscn`；文案 key 见 `editor/locale/editor_strings.csv` |
| 多语言 | Autoload `EditorI18n`：CSV（zh_CN/en）+ 可选 `UI/WorldEditStrings.txt` 覆盖中文 |
| 编辑器数据 | `world_edit_data.gd` 读逻辑路径 `UI/WorldEditData.txt`（优先 `assets/asset-converted/`，可用 `node tools/sync-editor-assets.mjs` 从 `.cache` 同步） |
| 打开 | 加载 `assets/map-parsed/losttemple` 的 `terrain-heightfield.json` |
| 新建 | 小空白图（默认 33×33 tilepoint → 32×32 格），平坦、Icecrown 地表表 |
| 刷地表 | 左键拖拽，整格四角同贴图；侧栏选贴图 |
| 保存 | 写出 JSON 到 `user://editor_maps/`（**不是** `.w3x`） |

## 明确未做

- 导出 `war3map.w3e` / `.w3x`
- 高度 / 水 / 悬崖 / 斜坡 / 装饰 / 单位笔刷
- 撤销栈
- Godot EditorPlugin（当前是独立运行场景）

## 与 HiveWE 对照

| HiveWE | 本仓库首期 |
|--------|------------|
| 原生 C++/OpenGL 视口 | Godot 场景 + 现有 `MapTerrainLayer` |
| 直接改 w3e | 改内存 heightfield（与 `map-parse` JSON 同形） |
| 全工具栏 | 仅地表纹理笔刷 |

## 架构

```text
editor/          Presentation（编辑器 UI / 笔刷 / 文档）
scripts/map/     运行时装配与 Domain（尽量复用，少分叉）
```

脏数据流：`TerrainBrush` → `MapDocument.hf` → `MapLoader.reload_from_hf` → `Terrain.build`。

## 后续路线（建议）

1. P1：撤销 / 重做；笔刷半径；地形局部重建
2. P1：高度笔刷、水面标志
3. P2：悬崖层编辑、pathing 预览
4. P2：装饰/单位放置（复用 doodad/unit 层）
5. P3：写出 `.w3e` / 打包 `.w3x`
