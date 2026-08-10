# 地图编辑器架构

> 入口：`editor/scenes/editor_main.tscn`（F6 运行当前场景；**不**改 `project.godot` 主场景）  
> 分层总纲：[LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md)。MapRoot：[MAP_ARCHITECTURE.md](../../architecture/MAP_ARCHITECTURE.md)。  
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

编辑器整体属于 **Editor 层**。它 **消费** Presentation（`MapRoot`），**不**实现 Catalog/Logic。目录约定见 [LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) §4.2。

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

### 3.1 场景树（已落地）

```text
EditorMain (Node3D)                     ← editor_shell.gd（薄壳）
├── Editor (Node)                       ← editor.gd / MapEditor
│                                         @export 注入；Document + CommandHistory
├── WorldEnvironment / Sun
├── MapRoot (MapLoader)
├── EditorCamera
├── TerrainBrush                        ← 笔划录制 → History.record
├── NewMapDialog
└── UI …
运行时：ToolPaletteWindow × N（挂在 Editor 下）
```

| 约定 | 说明 |
|------|------|
| `Editor` 为直接子节点 | `@export` 注入；缺省按 `../MapRoot` 等回退 |
| 命令模式 | `editor/scripts/commands/`；Ctrl+Z/Y、菜单 `edit_undo`/`edit_redo` |

### 3.2 迁移说明

~~根节点 `editor_app.gd`~~ 已废弃；勿再挂。

---

## 4. 模块职责

### 4.1 编辑层

| 路径 | 职责 |
|------|------|
| `scripts/editor_shell.gd` | 场景壳 |
| `scripts/editor.gd`（`MapEditor`） | 总管：Document、History、菜单、重建 |
| `scripts/map_document.gd` | 会话文档（`Wc3Heightfield`） |
| `scripts/commands/*` | Command / History / PaintStroke / Snapshot |
| `scripts/tools/terrain_brush.gd` | 拾取、绘制、笔划录制 |
| `scripts/editor_camera.gd` | 相机 |
| `scripts/ui/*` | 菜单、工具条、浮窗、i18n |
| `scripts/editor_settings_store.gd` | 用户设置 |

### 4.2 运行时装配（编辑器复用，属 Presentation）

| 路径（现 / 目标） | 职责 |
|------|------|
| `scripts/map/presentation/map_loader.gd` | `reload_from_hf` / 分路径重建；外部 hf 优先 |
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
            → TerrainBrush.setup(doc, camera, world, history)
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

专项文档：[CLIFF.md](../cliff/CLIFF.md)。悬崖回归见 `tests/cliff/selftest_cliff_*.gd`。斜坡待重做。

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

导出 w3e/w3x、装饰/单位编辑、EditorPlugin。撤销栈已接入（笔划级）；菜单其它编辑项仍为桩。

---

## 9. 建议后续（服从 ROADMAP）

1. ~~落地 `MapEditor` 总管~~ ✅  
2. 笔刷全走 Logic；脏区局部重建  
3. 高度笔刷命令、合并细碎笔划、撤销上限与 UI 灰显  
4. 装饰/单位、导出  

完整顺序见 [ROADMAP.md](../../roadmap/ROADMAP.md)。

---

## 10. 相关文档

| 文档 | 内容 |
|------|------|
| [LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) | 五层总纲 + 目录拆分 |
| [MAP_ARCHITECTURE.md](../../architecture/MAP_ARCHITECTURE.md) | MapRoot 节点树 |
| [ROADMAP.md](../../roadmap/ROADMAP.md) | 开发路线 |
| [editor/README.md](README.md) | 如何 F6 运行 |
