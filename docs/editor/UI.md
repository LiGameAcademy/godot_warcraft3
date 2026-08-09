# UI 组件

> 编辑器 UI 组件目录：menu_bar / toolbar / tool_palette / new_map_dialog / tile_palette。
>
> 全部位于 [`editor/scripts/ui/`](../../../editor/scripts/ui/)。
> 国际化：[I18N.md](I18N.md)。

## 1. 总览

```text
editor_main.tscn
├── MenuBar (menu_bar.tscn)              ← 顶栏菜单（文件/编辑/查看…）
├── Toolbar (toolbar.tscn)               ← 工具栏（撤销/重做/视图…）
├── ToolPaletteWindow (tool_palette_window.tscn)  ← 浮窗：地表/悬崖/笔刷
├── NewMapDialog (new_map_dialog.tscn)   ← 浮窗：新建地图
├── TilePalette (tile_palette.tscn)      ← 浮窗：地表贴图调色板
├── WorldEditData                        ← WorldEditData.txt 解析
├── WorldEditStrings                     ← WorldEditStrings.txt 解析
└── EditorI18n (Autoload)                ← i18n 门面
```

## 2. 文件清单

| 文件 | 职责 |
|------|------|
| `menu_bar.gd` + `menu_bar.tscn` | 顶栏菜单（File/Edit/View/Window…） |
| `toolbar.gd` + `toolbar.tscn` | 工具栏按钮 |
| `tool_palette_window.gd` + `tool_palette_window.tscn` | 工具面板浮窗（地表/悬崖/坡/笔刷尺寸形状） |
| `new_map_dialog.gd` + `new_map_dialog.tscn` | 新建地图对话框 |
| `tile_palette.gd` + `tile_palette.tscn` | 地表贴图调色板 |
| `world_edit_data.gd` | `WorldEditData.txt` 解析（cliffType 列表等） |
| `world_edit_strings.gd` | `WorldEditStrings.txt` 解析（i18n 覆盖） |
| `editor_i18n.gd` | i18n 门面（Autoload `EditorI18n`） |

## 3. `MenuBar`（顶栏菜单）

**布局**：[`menu_bar.tscn`](../../../editor/scripts/ui/menu_bar.tscn)

**经典 World Editor 顶栏**（File / Edit / View / Window）。

| 字段 | 含义 |
|------|------|
| `ID_TO_ACTION` | PopupMenu item id → action（与 `.tscn` 中 `item_*/id` 对齐） |
| `action_triggered(action_id: StringName)` | 信号：菜单项点击（用 id 不依赖 metadata 反序列化） |

**ID → action 示例**（来自 `menu_bar.gd`）：

| id | action |
|----|--------|
| 1 | `file_new` |
| 2 | `file_open` |
| 5 | `file_save` |
| 6 | `file_save_as` |
| 19 | `file_exit` |
| 20 | `edit_undo` |
| 21 | `edit_redo` |
| 30-58 | view_* (textured/wireframe/grid/...) |

**翻译模式**：

```gdscript
menu.set_item_text(idx, EditorI18n.t("EDITOR_FILE_NEW"))

func _on_locale_changed(_locale: String) -> void:
    # 重设所有 item text
```

**Action 路由**：`MapEditor` 监听 `action_triggered`，分派到 `MapDocument` / `MapLoader` / `EditorApp` 等。

## 4. `Toolbar`（工具栏）

**布局**：[`toolbar.tscn`](../../../editor/scripts/ui/toolbar.tscn)

快捷按钮（撤销/重做/视图切换等）。较小，功能可由 `MenuBar` 替代。

## 5. `ToolPaletteWindow`（工具面板浮窗）

**布局**：[`tool_palette_window.tscn`](../../../editor/scripts/ui/tool_palette_window.tscn)（最大 UI 组件，~24K 字节）

**职责**：
- 地表贴图选择（按 tileset 分组）
- 悬崖工具选择（`"0".."4"` / `ShallowWater` / `DeepWater` / `Ramp`）
- 悬崖类型选择（按 `WorldEditData.cliffTypes`）
- 笔刷尺寸（`1/2/3/5/8`）
- 笔刷形状（圆/方）
- "应用到地表" / "应用到悬崖" 复选框

**关键 API**：

```gdscript
# 设置笔刷
func set_brush_size(size: int) -> void: ...
func set_brush_shape(shape: int) -> void: ...
func set_apply_texture(b: bool) -> void: ...
func set_apply_cliff(b: bool) -> void: ...

# 悬崖
func set_cliff_tool(tool_id: String) -> void: ...
func set_cliff_type_index(idx: int) -> void: ...
```

**与 `TerrainBrush` 通信**：

```gdscript
# tool_palette_window
signal brush_settings_changed(size: int, shape: int)
signal cliff_settings_changed(apply: bool, tool_id: String, type_idx: int)
signal ramp_marking_changed(...)

# TerrainBrush 监听
tool_palette.brush_settings_changed.connect(_on_brush_settings)
tool_palette.cliff_settings_changed.connect(_on_cliff_settings)
```

## 6. `NewMapDialog`（新建地图对话框）

**布局**：[`new_map_dialog.tscn`](../../../editor/scripts/ui/new_map_dialog.tscn)

**字段**：

| 字段 | 含义 |
|------|------|
| 地图尺寸 | tiles × tiles（64/96/128/192/256 等） |
| 主 tileset | 地形集 |
| 初始悬崖类型 | 默认 cliffType |
| 初始地表 ID | 默认 tileID |

**动作**：确认后 `MapDocument.bind_heightfield(Wc3Heightfield.new(width, height, ...))` + `MapLoader.reload_from_hf(...)`。

## 7. `TilePalette`（地表贴图调色板）

**布局**：[`tile_palette.tscn`](../../../editor/scripts/ui/tile_palette.tscn)

按地形集字母分页（`L` Lordaeron / `A` Ashenvale / `N` Northrend / `B` Barrens / `C` Cityscape / `D` Dalaran / `F` Felwood / `G` Icecrown / `I` Sunwell 等）。

每个 tile 显示：
- 贴图缩略图
- tileID（`Ldrt`）
- 显示名（`EditorI18n.tile_display_name`）
- 不可建造时显示后缀

**与 `TerrainBrush` 通信**：

```gdscript
signal tile_selected(tile_id: String)
```

## 8. `WorldEditData`（WE 配置解析）

实现：[`world_edit_data.gd`](../../../editor/scripts/ui/world_edit_data.gd)

**作用**：解析 `WorldEditData.txt`（`assets/slk-exported/UI/`；见 [ASSET_LANES.md](../architecture/ASSET_LANES.md)）。

**关键数据**：

| 字段 | 含义 |
|------|------|
| `cliffTypes` | 悬崖类型列表（按 WE 顺序） |
| `cliffTypeToId` | 类型名 → cliffID |
| `groundTilesets` | 地形集列表 |
| `tilesetToName` | tileset ID → 显示名 |

**与 `CliffTypeDef` 关系**：
- `WorldEditData` 是经典 WE 工具的配置
- `CliffTypeDef` 是 SLK 表的元数据
- 两者 ID 大致对应，但顺序/索引可能不同

## 9. `WorldEditStrings`（WE 字符串解析）

实现：[`world_edit_strings.gd`](../../../editor/scripts/ui/world_edit_strings.gd)

**作用**：解析 `WorldEditStrings.txt`，提供 `WESTRING_*` 翻译覆盖。

详见 [I18N.md §6](I18N.md)。

## 10. 加新 UI 组件流程

1. **新建** `editor/scripts/ui/<name>.gd` + `<name>.tscn`
2. **挂到** `editor/scenes/editor_main.tscn` 或子节点
3. **信号** 用 `signal <event>(...)`，由 `MapEditor` / `MapDocument` 监听
4. **翻译** item text / label 用 `EditorI18n.t(key)`；label 用 `EditorI18n.label(key)`（自动加冒号）
5. **locale 刷新** 监听 `EditorI18n.locale_changed` 重设所有 text
6. **测试** 切换 zh_CN / en 确认

## 11. 何时查哪里

| 想改什么 | 去哪 |
|----------|------|
| 菜单项 / 加速键 | `editor/scripts/ui/menu_bar.gd` + `menu_bar.tscn` |
| 工具栏按钮 | `editor/scripts/ui/toolbar.gd` + `toolbar.tscn` |
| 笔刷 UI | `editor/scripts/ui/tool_palette_window.gd` |
| 新建地图对话框 | `editor/scripts/ui/new_map_dialog.gd` |
| 地表调色板 | `editor/scripts/ui/tile_palette.gd` |
| WE 工具/悬崖数据 | `editor/scripts/ui/world_edit_data.gd` |
| 字符串 / i18n | `editor/scripts/ui/editor_i18n.gd` + `editor/locale/editor_strings.csv` |
| 同步 WE / UnitFunc 数据 | [`tools/sync-data-assets.mjs`](../../../tools/sync-data-assets.mjs) |
