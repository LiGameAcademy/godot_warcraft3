# 地图编辑器架构

> 分支：`feature/map-editor`  
> 入口：`editor/scenes/editor_main.tscn`（F6 运行当前场景；**不**改 `project.godot` 主场景）  
> 运行时装配细节见 [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md)；水体见 [WATER.md](WATER.md)。  
> 最后更新：2026-07-23

---

## 1. 一句话概览

编辑器是**独立 Godot 场景**，不是 EditorPlugin。根节点 `EditorApp` 编排三件事：

1. **文档** — `MapDocument` 持有与 `map-parsed/*/terrain-heightfield.json` 同形的内存数据  
2. **预览** — 复用 `MapRoot` / `MapLoader` 与 Domain `Wc3*`，把文档刷进地形/悬崖/水面层  
3. **交互** — 顶栏菜单 + 浮动工具面板 + `TerrainBrush` 改文档，再节流触发局部/全量重建  

原则：**Presentation 在 `editor/`，装配与 WC3 规则在 `scripts/map/`，尽量不分叉。**

---

## 2. 分层

```text
┌─────────────────────────────────────────────────────────┐
│  Presentation（editor/）                                  │
│  EditorApp · MenuBar · ToolPalette · TerrainBrush · Cam │
└───────────────────────────┬─────────────────────────────┘
                            │ MapDocument.hf / signals
┌───────────────────────────▼─────────────────────────────┐
│  Application（scripts/map/）                              │
│  MapLoader · MapBuildContext · Map*Layer                  │
└───────────────────────────┬─────────────────────────────┘
                            │ build(ctx)
┌───────────────────────────▼─────────────────────────────┐
│  Domain（Wc3*，无 Node）                                  │
│  Autotile · CliffBuilder/Tiles · WaterMesh · Coords …   │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  Infrastructure                                          │
│  RuntimeAssets · MapModelCache · AssetProvider           │
└─────────────────────────────────────────────────────────┘
```

| 层 | 典型类型 | 允许做 | 禁止做 |
|----|----------|--------|--------|
| Presentation | `Node` / `Window` | 输入、UI、改 `MapDocument`、调 `MapLoader` 重建 | 直接拼悬崖 GLB / Autotile |
| Application | `MapLoader`、各 `Map*Layer` | 建 Context、调 Domain、挂场景节点 | 业务规则硬编码散落 UI |
| Domain | `RefCounted` `Wc3*` | heightfield → mesh / 实例列表 | 碰场景树 |
| Infrastructure | 加载器 / 缓存 | 读 PNG/GLB、路径解析 | 地图规则 |

---

## 3. 场景树

```text
EditorMain (editor_app.gd)
├── WorldEnvironment / Sun
├── MapRoot (MapLoader)                 ← 实例 scenes/map/map_root.tscn
│   ├── Terrain / Ground
│   ├── Cliffs
│   ├── Water / Surface
│   ├── Doodads / Units / PathingDebug  ← 编辑器关闭放置
├── EditorCamera → Pivot / Camera3D
├── TerrainBrush
├── NewMapDialog
└── UI (CanvasLayer)
    ├── MenuBarPanel / MenuBar
    ├── ToolStrip / Toolbar
    ├── SideBar / TilePalette           ← 默认隐藏（功能由浮窗承担）
    └── StatusBar (Status + Hover)

运行时动态子节点：
  ToolPaletteWindow × N                 ← 可多开，always_on_top
```

---

## 4. 模块职责

### 4.1 Presentation（`editor/`）

| 路径 | 职责 |
|------|------|
| `scripts/editor_app.gd` | **编排根**：启动新建、菜单、面板、笔刷设置、脏状态、调用 `MapLoader` 重建 |
| `scripts/map_document.gd` | **可编辑文档**（无 `class_name`，preload）：`hf`/`info`；新建/打开/保存；`paint_corner` / `paint_cliff_corner`；坐标换算 |
| `scripts/tools/terrain_brush.gd` | 拾取 tilepoint、圆/方偏移、悬停预览、左键绘制、节流 `rebuild_requested` |
| `scripts/editor_camera.gd` | WASD/QE 平移、右键旋转、滚轮缩放；近距默认约 3 大栅格 |
| `scripts/ui/tool_palette_window.*` | 主工具浮窗：地表/悬崖/高度 UI、尺寸形状、贴图格 |
| `scripts/ui/new_map_dialog.*` | 新建地图选项 → `confirmed(options)` |
| `scripts/ui/menu_bar.*` | 经典 WE 顶栏 → `action_triggered` |
| `scripts/ui/toolbar.*` | 当前笔刷名、脏标记 |
| `scripts/ui/world_edit_data.gd` | 解析 `UI/WorldEditData.txt`（地形集、刷子、默认尺寸） |
| `scripts/ui/editor_i18n.gd` | Autoload：CSV + 可选客户端字符串；`locale_changed` |
| `scripts/ui/tile_palette.*` | 侧栏地表列表（保留，默认不可见） |

### 4.2 运行时装配（编辑器复用）

| 路径 | 职责 |
|------|------|
| `scripts/map/map_loader.gd` | `reload_from_hf` / `rebuild_terrain_only` / `rebuild_terrain_cliffs_water`；`_external_hf` 优先于磁盘 |
| `scripts/map/map_build_context.gd` | 单次构建上下文；`ensure_cliff_topology()` |
| `scripts/map/map_terrain_layer.gd` | 地面 Autotile + debug 栅格 |
| `scripts/map/map_cliff_layer.gd` | 悬崖 GLB MultiMesh + 立面栅格 |
| `scripts/map/map_water_layer.gd` | 水面 + 岸浪 |

---

## 5. 核心数据流

### 5.1 启动 / 新建

```text
EditorApp._ready()
  → MapDocument + WorldEditData.load_default()
  → 配置 MapLoader（无 doodad/unit，开悬崖/水面/碰撞）
  → await _startup_new_map()
       → create_from_options(_default_new_map_options())
       → _apply_document(full_reload=true)
            → 各面板 rebuild_terrain
            → TerrainBrush.setup(doc, camera, world)
            → MapLoader.reload_from_hf → Terrain / Cliffs / Water.build
            → EditorCamera.focus_map_extent()
  → _spawn_tool_palette(TERRAIN)
```

打开示例图：`file_open` → `load_from_map_dir(losttemple)` → `_apply_document(true)`。

### 5.2 刷地表

```text
TerrainBrush 左键拖拽
  → _pick_vertex() → _brush_offsets()（圆/方，尺寸 1/2/3/5/8）
  → MapDocument.paint_corner()
  → 节流 rebuild_requested（约 80ms / 抬键）
  → EditorApp._on_brush_rebuild()
       → MapLoader.rebuild_terrain_only()   # 仅地面 + 碰撞
```

### 5.3 刷悬崖 / 水 / 斜坡

```text
ToolPalette → cliff_settings_changed → TerrainBrush.set_cliff_settings()
绘制：
  → MapDocument.paint_cliff_corner(tool_id, …)
       "0".."4" 升降层 | ShallowWater / DeepWater | Ramp
       → 邻接层差 ≤2 + 单格跨度 ≤2（叠蛋糕外扩，含对角）
  → cliff_dirty = true
重建：
  → MapLoader.rebuild_terrain_cliffs_water()
       → Terrain + Cliffs + Water
       → cliff_slices_at：跨度≤2 单片 TAG（含 AABC）；>2 才 +2 叠段
       → 崖贴图同步只触及「落笔/蛋糕」相关直崖格，不按 AABB 误改邻近另一座崖
```

**悬崖回归：** `tools/selftest_cliff_variants.gd`（变体表/AABC/叠段/笔刷）、`selftest_cliff_level3.gd`、`selftest_cliff_ground_tex.gd`。  
专项文档：[CLIFF.md](CLIFF.md)（策略 B / 层高）、[RAMP.md](RAMP.md)（崖边斜坡 A vs 纯高度 B、M0–M4 路线图）。  
参考实现：`.cursor/rules/hivewe-cliff-reference.mdc`、本机 `D:\GameMaker\HiveWE.0.3`。

偏好：`EditorSettingsStore` → `user://editor_settings.cfg`（默认 **中级栅格**）；语言仍为 `user://editor_locale.cfg`。

### 5.4 保存

```text
file_save → MapDocument.save_json()
  → user://editor_maps/{name}_{timestamp}.json
  → clear_dirty()
```

**不是** `.w3e` / `.w3x`。

### 5.5 重建路径对照

| 触发 | API | 范围 |
|------|-----|------|
| 新建 / 打开 | `reload_from_hf` | Terrain + Cliffs + Water |
| 仅地表 | `rebuild_terrain_only` | Terrain + collision |
| 悬崖 / 水 / 坡 | `rebuild_terrain_cliffs_water` | Terrain + Cliffs + Water + collision |

---

## 6. 关键信号

| 信号 | 发射 | 处理 |
|------|------|------|
| `MenuBar.action_triggered` | 顶栏 | `EditorApp._on_menu_action` |
| `NewMapDialog.confirmed` | 新建对话框 | `_on_new_map_confirmed` |
| `MapDocument.dirty_changed` | 文档 | Toolbar 脏标记 |
| `TerrainBrush.tile_hovered` | 笔刷 | StatusBar 坐标 |
| `TerrainBrush.rebuild_requested` | 笔刷 | `_on_brush_rebuild` |
| `ToolPaletteWindow.tile_selected` | 浮窗 | `doc.brush_tile_index` |
| `ToolPaletteWindow.brush_settings_changed` | 浮窗 | 笔刷尺寸/形状 + 同步各浮窗 |
| `ToolPaletteWindow.cliff_settings_changed` | 浮窗 | 悬崖工具/类型 |
| `ToolPaletteWindow.apply_texture_changed` | 浮窗 | `brush.apply_texture` |
| `EditorI18n.locale_changed` | Autoload | 各 UI 刷新文案 |

---

## 7. MapDocument 关键 API

| API | 用途 |
|-----|------|
| `create_from_options(options)` | 新建：宽高、地形集、地表/悬崖表、初始层、水位、随机高度 |
| `load_from_map_dir(path)` | 读 `terrain-heightfield.json` + 可选 `info.json` |
| `save_json(path?)` | 写出 `user://editor_maps/*.json` |
| `paint_corner(ix, iy, …)` | 角点地表 |
| `paint_cliff_corner(ix, iy, tool_id, …)` | 悬崖 / 水 / 坡 + 邻接约束 |
| `world_godot_to_tilepoint` / `sample_height_at_xy` | 拾取与悬停高度 |
| `ground_tilesets()` / `cliff_tilesets()` | UI 贴图格 |
| `mark_dirty` / `clear_dirty` / `is_dirty` | 脏状态 |

文档不挂场景树；由 `EditorApp` 持有并 `preload`。

---

## 8. 能力现状

### 已实现

| 能力 | 说明 |
|------|------|
| 启动空白图 | WorldEditData 默认尺寸/地形集（不再自动开 Lost Temple） |
| 新建 / 打开 / 保存 JSON | 对话框 + 示例图 + `user://editor_maps/` |
| 地表笔刷 | 圆/方；尺寸 1/2/3/5/8；欧氏格点圆 |
| 悬崖笔刷 | 升/降 1–2 层、整平、浅/深水、斜坡；层差 ≤2 外扩 |
| 悬崖类型 | `cliffTextures` + 面板类型格 |
| 双通道开关 | `apply_texture` / `apply_cliff` 独立 |
| 分路径重建 | 仅地表 vs 地表+悬崖+水 |
| 地形碰撞 | trimesh 供笔刷 raycast |
| 查看→栅格 | 大/中/小；默认中级；写入 `user://editor_settings.cfg` |
| 多开工具浮窗 | 地形面板为主；置顶、不抢焦点 |
| 多语言 | zh_CN / en |

### UI 有、逻辑未接通

| 项 | 说明 |
|----|------|
| 高度笔刷 | Raise / Lower / Plateau / Noise / Smooth 仅高亮 |
| 特殊纹理 | Blight / Boundary 仅 UI |
| 单位 / 装饰 / 区域 / 相机面板 | Placeholder |
| 大量顶栏菜单 | 状态栏 `EDITOR_STATUS_NOT_IMPLEMENTED` |

### 明确未做

- 导出 `.w3e` / `.w3x`、导入真实地图包  
- 撤销 / 重做  
- 装饰 / 单位放置编辑、Pathing 编辑  
- Godot EditorPlugin 集成  

---

## 9. 与经典 WE / HiveWE

| WE / HiveWE | 本仓库 |
|-------------|--------|
| 直接改 w3e | 改内存 JSON 形 heightfield |
| 原生视口 | Godot + 现有 `Map*Layer` |
| 全工具栏 | 顶栏 shell + 地形浮窗；多数菜单桩 |
| 悬崖 / 水 / 坡 | **已实现**（笔刷 + Domain） |
| 高度雕刻 | UI 有，逻辑无 |
| 撤销 / 导出 w3x | 无 |

---

## 10. 建议后续路线

1. **P1** 撤销/重做；高度笔刷接通 `MapDocument`  
2. **P1** 特殊纹理（Blight / Boundary）  
3. **P2** 装饰/单位放置（复用 doodad/unit 层）  
4. **P2** Pathing 预览与编辑  
5. **P3** 写出 `.w3e` / 打包 `.w3x`  

---

## 11. 相关文档

| 文档 | 内容 |
|------|------|
| [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) | MapRoot 分层、数据/调用流、干预速查、设计评估 |
| [ROADMAP.md](ROADMAP.md) | MapRoot + Editor 开发路线 |
| [WATER.md](WATER.md) | 水体与岸浪 |
| [TODO.md](TODO.md) | 全局待办 |
| [editor/README.md](../editor/README.md) | 如何 F6 运行与基本操作 |
