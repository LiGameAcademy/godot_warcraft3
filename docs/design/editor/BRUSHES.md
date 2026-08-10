# 笔刷（Brushes）

> 编辑器笔刷：地表/悬崖/坡笔刷的架构、与 Logic API 边界、加新笔刷流程。
>
> 实现：[`editor/scripts/tools/terrain_brush.gd`](../../../editor/scripts/tools/terrain_brush.gd)
> 配合：[`editor/scripts/commands/`](../../../editor/scripts/commands/)（命令模式/撤销）
> 配合：[`editor/scripts/map_document.gd`](../../../editor/scripts/map_document.gd)（Document）

## 1. 总览

```text
编辑器输入
  ↓
TerrainBrush (Node3D)            ← editor/scripts/tools/terrain_brush.gd
  ├─ 悬停拾取（吸附 tilepoint）
  ├─ 形状/尺寸（1/2/3/5/8，圆/方）
  ├─ 笔刷期间采集
  │   ↓
  │   PaintStrokeRecorder        ← editor/scripts/commands/paint_stroke_recorder.gd
  │   ├─ begin(doc)              ← 笔划开始
  │   ├─ capture_before_at       ← 绘制前快照
  │   ├─ capture_after_at        ← 绘制后快照（仅变化）
  │   └─ finish() → PaintStrokeCommand
  │
  ├─ 改数据
  │   ↓
  │   MapDocument (RefCounted)   ← editor/scripts/map_document.gd
  │   ├─ bind_heightfield(hf)
  │   ├─ paint_texture / paint_cliff / paint_ramp ...
  │   └─ mark_dirty()
  │
  └─ 重建（节流 80ms）
      ↓
      MapEditor._on_brush_rebuild  →  rebuild_terrain_only / rebuild_terrain_cliffs_water
```

**核心契约**（[LAYERED_ARCHITECTURE.md §"分层门禁"](../../architecture/LAYERED_ARCHITECTURE.md)）：
- 笔刷只调 **Logic API**（`Wc3TerrainLogic` / `Wc3CliffLogic` / `Wc3Ramp*Logic`）
- 笔刷**不**直写 Heightfield 私有字段
- 笔刷**不**绕 Command（撤销靠 `EditorCommandHistory`）

## 2. `terrain_brush.gd` 关键 API

| 字段 | 类型 | 含义 |
|------|------|------|
| `document` | `MapDocument` | 编辑器状态权威（preload 实例） |
| `camera` | `Camera3D` | 拾取相机 |
| `space` | `World3D` | 拾取世界空间 |
| `history` | `EditorCommandHistory` | 命令历史；为空则不记撤销 |
| `brush_size` | `int` | 笔刷半径档：`[1, 2, 3, 5, 8]`（`set_brush_settings` 会 sanitize） |
| `brush_shape` | `int` | `0` 圆 / `1` 方 |
| `apply_texture` | `bool` | 是否刷地表贴图 |
| `apply_cliff` | `bool` | 是否刷悬崖 |
| `cliff_tool_id` | `String` | WorldEditData 悬崖工具 id（`"0".."4"` / `ShallowWater` / `DeepWater` / `Ramp`） |
| `cliff_type_index` | `int` | 悬崖类型索引（自动 `ensure_cliff_type_valid`） |
| `cliff_dirty` | `bool` | 本笔划是否改过悬崖数据（决定重建是否含悬崖/水面） |

| 信号 | 含义 |
|------|------|
| `tile_hovered(tile: Vector2i)` | 悬停 tilepoint (ix, iy) |
| `painted` | 一次完整笔划结束 |
| `rebuild_requested` | 笔刷请求重建（节流 80ms 内合并） |
| `ramp_feedback(message: String)` | 斜坡相关状态消息（给状态栏） |

| 常量 | 值 | 含义 |
|------|-----|------|
| `REBUILD_INTERVAL_MS` | `80` | 重建节流，避免刷太快 |
| `HOVER_LIFT` | `0.015` | 悬停绿框抬高（避免 z-fight） |
| `HOVER_COLOR` / `HOVER_EDGE` | `RGBA` | 绿框颜色 |
| `INVALID_VERT` | `Vector2i(-99999, -99999)` | 哨兵值 |

## 3. 笔划生命周期

```gdscript
# 笔划按下（鼠标左键）
terrain_brush.on_press()           # 内部：PaintStrokeRecorder.begin(document)
#   + capture_before_at(ix, iy, CAPTURE_RADIUS=3)  ← 拉外扩邻域

# 笔划拖动（每帧）
terrain_brush.on_drag(vert)
#   if vert != _last_vert:                   ← 防重
#       Document.paint_texture/cliff/ramp(...)
#       _stroke.capture_after_at(...)        ← 仅采集相对 before 变化的
#       if elapsed > 80ms: rebuild_requested

# 笔划抬起
terrain_brush.on_release()
#   var cmd := _stroke.finish("Paint")        ← 输出 PaintStrokeCommand
#   history.record(cmd)                       ← record 不触发重建
```

**关键点**：
- **不要 execute**：笔刷在拖动中已直接改 `MapDocument.heightfield`；抬起时 `history.record(cmd)` 只入栈、不触发重建
- **节流 80ms**：避免笔刷一拖一卡；其余顶点按 `_last_rebuild_ms` 合并
- **`_last_vert` 防重**：避免在同一顶点重复触发
- **`cliff_dirty`**：标志本笔划是否改过悬崖；释放时按 `affects_cliffs_water()` 决定走 `rebuild_terrain_only` 还是 `rebuild_terrain_cliffs_water`

## 4. 笔刷尺寸/形状

```text
size 1  → 单点（圆 = 方）
size 2  → 半径 1 圆 / 1×1 周围
size 3  → 半径 2
size 5  → 半径 4
size 8  → 半径 7
```

`_sanitize_brush_size(p_size)` 把任意输入映射到合法档位（取最近）。

形状 `0=圆 / 1=方` —— 见 `terrain_brush.gd` 内的 `_shape_mask()` / `_square_extent()`。

## 5. 悬崖/水面整合

| `apply_cliff` | `cliff_tool_id` | 含义 |
|---------------|-----------------|------|
| `false` | — | 仅刷地表贴图 |
| `true` | `"0".."4"` | WorldEditData 5 类悬崖工具 |
| `true` | `ShallowWater` | 浅水（`FLAG_WATER=1`） |
| `true` | `DeepWater` | 深水 |
| `true` | `Ramp` | 斜坡（走 `Wc3Ramp*Logic`） |

`set_cliff_settings(p_apply, tool_id, type_idx)` 调 `MapDocument.ensure_cliff_type_valid()` 防止选了不存在的类型。

## 6. 与 `MapDocument` 的关系

`MapDocument`（[`editor/scripts/map_document.gd`](../../../editor/scripts/map_document.gd)）是**编辑器侧的 heightfield 包装**：

- 持有 `Wc3Heightfield` + `Wc3TerrainLogic` + 笔刷上下文
- 提供 `paint_texture(...)` / `paint_cliff(...)` / `paint_ramp(...)` 等高层 API
- `mark_dirty()` 通知编辑器脏区
- `as_build_dict()` 转为 `Wc3ParsedMap` 兼容视图（过渡期）

**禁止**：笔刷绕过 `MapDocument` 直写 `heightfield` 字段；那样会让撤销失效、画脏数据。

## 7. 加新笔刷流程

1. **逻辑层**（如新模块）：
   - Data → Catalog → Logic（按 [LAYERED_ARCHITECTURE.md §"固化模块节奏"](../../architecture/LAYERED_ARCHITECTURE.md)）
   - 输出 `Wc3*Placement` / `Wc3*BuildResult` 等结构
2. **Document API**（`map_document.gd`）：
   - 加 `paint_<new>(ix, iy, ...)` 委托 `Wc3*Logic`
   - 返回值喂给 `_stroke.mark_cliff()`（如影响悬崖/水面）
3. **TerrainBrush**（`terrain_brush.gd`）：
   - 在 `on_press` / `on_drag` / `on_release` 加分支
   - 配套 UI 控件（tool palette / toolbar）
4. **命令模式**：
   - 如新数据不在现有 `EditorVertexSnapshot` 字段内，扩展它
   - 或新增 `EditorCommand` 子类
5. **重建路径**：
   - `MapEditor._on_brush_rebuild` 看 `cliff_dirty` 决定走全量还是 ground-only
6. **测试**：`tests/unit/selftest_editor_commands.gd` + 新逻辑对应 selftest

## 8. 何时查哪里

| 想改什么 | 去哪 |
|----------|------|
| 笔刷输入拾取 | `editor/scripts/tools/terrain_brush.gd` |
| 笔刷数据改写 | `editor/scripts/map_document.gd` |
| 撤销/重做 | [`editor/scripts/commands/`](COMMANDS.md) |
| 重建路径 | `editor/scripts/editor.gd` (`_on_brush_rebuild`) |
| 笔刷 UI（尺寸/形状） | [`editor/ui/tool_palette_window.gd`](UI.md) |
| 笔刷操作手感 | `editor/scripts/editor.gd`（_process / 拾取） |
