# 地图编辑器架构

> 入口：`editor/scenes/editor_main.tscn`（F6 运行当前场景；**不**改 `project.godot` 主场景）  
> 分层总纲：[LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md)。MapRoot：[MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md)。  
> 最后更新：2026-07-24

---

## 1. 一句话概览

编辑器是**独立 Godot 场景**，不是 EditorPlugin。由子节点 **`Editor`（`MapEditor`）总管** 编排三件事：

1. **文档** — `MapDocument` 持有 `Wc3Heightfield`（迁移中可暂 `to_dict` 兼容）  
2. **预览** — `@export` 注入的 `MapRoot` / `MapLoader`，把文档刷进各 Layer  
3. **交互** — 菜单 / 工具浮窗 / `TerrainBrush` 改文档，再节流触发重建  

原则：编辑层只改数据与调重建；装配与 WC3 规则在 `scripts/map/`，不分叉。

---

## 2. 与五层的关系

编辑器整体属于 **Editor 层**。它 **消费** Presentation（`MapRoot`），**不**实现 Catalog/Logic。目录约定见 [LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md) §4.2。

| 编辑器内模块 | 职责 |
|--------------|------|
| `Editor` / `MapEditor` | 总管：接线、生命周期、脏区重建入口 |
| `MapDocument` | 会话数据与脏标记 |
| `tools/*` | 拾取与笔划 → Document API |
| `ui/*` | Chrome；不碰 heightfield 数组细节 |
| `camera/*` | 编辑相机 |

禁止：在 Brush / UI 里拼 GLB、算崖 TAG、直接 `SurfaceTool`。

---

## 3. 场景树

### 3.1 目标（契约）

```text
EditorMain (Node3D)                     ← 场景壳；无厚业务脚本
├── WorldEnvironment / Sun
├── Editor (Node)                       ← editor.gd / class_name MapEditor
│                                         @export map_root → MapRoot
│                                         @export 可选：brush / camera / ui 根
├── MapRoot (MapLoader)                 ← 实例 scenes/map/map_root.tscn
│   ├── Terrain / Cliffs / Water / …
├── EditorCamera
├── TerrainBrush
├── NewMapDialog
└── UI (CanvasLayer)
    ├── MenuBarPanel / MenuBar
    ├── ToolStrip / Toolbar
    ├── SideBar / TilePalette
    └── StatusBar

运行时：ToolPaletteWindow × N
```

| 约定 | 说明 |
|------|------|
| `Editor` 是 `editor_main.tscn` 的 **直接子节点** | 与 MapRoot 同级，便于在检查器里拖引用 |
| `extends Node` | 总管不承载 3D 变换；世界在兄弟节点 |
| MapRoot **注入** | `@export var map_root: MapLoader`，不用「根脚本 + `$MapRoot`」作为长期形态 |

### 3.2 现状（迁移前）

```text
EditorMain (editor_app.gd : Node3D)     ← 编排仍在根上
├── MapRoot / EditorCamera / TerrainBrush / …
└── UI …
```

迁徙：把 `editor_app.gd` 职责挪到子节点 `Editor`，根改为薄壳；路径与信号一次性改完并自测新建/笔刷/保存。

---

## 4. 模块职责

### 4.1 编辑层（目标路径）

| 路径 | 职责 |
|------|------|
| `scripts/editor.gd` | **总管 MapEditor**：Document、菜单、面板、笔刷设置、脏状态、`map_root` 重建 |
| `scripts/document/map_document.gd` | 会话文档；目标持有 `Wc3Heightfield` |
| `scripts/tools/terrain_brush.gd` | 拾取 tilepoint、绘制、节流 `rebuild_requested` |
| `scripts/camera/editor_camera.gd` | WASD/QE、旋转、缩放 |
| `scripts/ui/*` | 菜单、工具条、浮窗、对话框、i18n、WorldEditData |
| `scripts/settings/editor_settings_store.gd` | 用户设置 |

现状文件仍可能平铺在 `editor/scripts/`（如 `editor_app.gd`）；新代码按上表落位。

### 4.2 运行时装配（编辑器复用，属 Presentation）

| 路径（现 / 目标） | 职责 |
|------|------|
| `scripts/map/map_loader.gd` → `presentation/` | `reload_from_hf` / 分路径重建；外部 hf 优先 |
| `map_build_context.gd` | 单次构建上下文 |
| `map_*_layer.gd` → `presentation/layers/` | 各层挂树 |

---

## 5. 核心数据流

### 5.1 启动 / 新建

```text
MapEditor._ready()
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
  → MapEditor._on_brush_rebuild()
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
```

专项文档：[CLIFF.md](CLIFF.md)、[RAMP.md](RAMP.md)。悬崖回归见 `tests/cliff/selftest_cliff_*.gd`。

偏好：`EditorSettingsStore` → `user://editor_settings.cfg`；语言 `user://editor_locale.cfg`。

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
| `MenuBar.action_triggered` | 顶栏 | `MapEditor._on_menu_action` |
| `NewMapDialog.confirmed` | 新建对话框 | `_on_new_map_confirmed` |
| `MapDocument.dirty_changed` | 文档 | Toolbar 脏标记 |
| `TerrainBrush.tile_hovered` | 笔刷 | StatusBar 坐标 |
| `TerrainBrush.rebuild_requested` | 笔刷 | `_on_brush_rebuild` |
| `ToolPaletteWindow.tile_selected` | 浮窗 | `doc.brush_tile_index` |
| `ToolPaletteWindow.brush_settings_changed` | 浮窗 | 笔刷尺寸/形状 |
| `ToolPaletteWindow.cliff_settings_changed` | 浮窗 | 悬崖工具/类型 |
| `EditorI18n.locale_changed` | Autoload | 各 UI 刷新文案 |

---

## 7. MapDocument 关键 API

| API | 用途 |
|-----|------|
| `create_from_options(options)` | 新建 |
| `load_from_map_dir(path)` | 读 map-parsed |
| `save_json(path?)` | 写出 `user://editor_maps/*.json` |
| `paint_corner` / `paint_cliff_corner` | 地表 / 悬崖·水·坡 |
| `world_godot_to_tilepoint` / `sample_height_at_xy` | 拾取 |
| `mark_dirty` / `clear_dirty` / `is_dirty` | 脏状态 |

文档不挂场景树；由 `MapEditor` 持有。

---

## 8. 能力现状

### 已实现

启动空白图、新建/打开/保存 JSON、地表与悬崖笔刷、分路径重建、碰撞、栅格、工具浮窗、多语言。

### UI 有、逻辑未接通

高度笔刷、特殊纹理、单位/装饰面板、大量顶栏菜单桩。

### 明确未做

导出 w3e/w3x、撤销、装饰/单位编辑、EditorPlugin。

---

## 9. 建议后续（服从 ROADMAP）

1. 落地 `MapEditor` 总管节点（从 `editor_app.gd` 迁出）  
2. Document 迁 `Wc3Heightfield`；Ground 管线可读可刷  
3. 再谈撤销、高度笔刷、装饰/单位、导出  

完整顺序见 [ROADMAP.md](ROADMAP.md)。

---

## 10. 相关文档

| 文档 | 内容 |
|------|------|
| [LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md) | 五层总纲 + 目录拆分 |
| [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) | MapRoot 节点树 |
| [ROADMAP.md](ROADMAP.md) | 开发路线 |
| [editor/README.md](../editor/README.md) | 如何 F6 运行 |
