# 命令模式（Commands / Undo / Redo）

> 编辑器撤销/重做：`EditorCommand` 基类 + `EditorCommandHistory` 栈 + `EditorVertexSnapshot` 顶点快照 + `PaintStrokeCommand` 笔划。
>
> 实现：[`editor/scripts/commands/`](../../../editor/scripts/commands/)
> 配合：[BRUSHES.md](BRUSHES.md)

## 1. 总览

```text
命令生命周期
  │
  ├─ 新命令（还没落地）
  │    history.execute(cmd)            ← 改 Document
  │    history.record(cmd)             ← 只入栈（笔划已落地）
  │
  ├─ 撤销
  │    cmd.undo(document)              ← Document 回滚到 before
  │    history.command_applied.emit(cmd, is_undo=true, should_rebuild=true)
  │
  └─ 重做
       cmd.execute(document)            ← Document 滚到 after
       history.command_applied.emit(cmd, is_undo=false, should_rebuild=true)
```

**信号**：

```gdscript
signal changed                                            # 栈状态变（用于 UI 灰显）
signal command_applied(cmd, is_undo: bool, should_rebuild: bool)
# `record` 时 should_rebuild=false（笔刷自己已请求重建）
# `execute` / `undo` / `redo` 时 should_rebuild=true
```

## 2. 文件清单

| 文件 | 职责 |
|------|------|
| `editor_command.gd` | `EditorCommand` 基类（execute / undo / get_label / affects_cliffs_water） |
| `editor_command_history.gd` | `EditorCommandHistory` 撤销/重做栈（`DEFAULT_LIMIT=64`） |
| `editor_vertex_snapshot.gd` | `EditorVertexSnapshot` 单 tilepoint 全量快照 |
| `paint_stroke_command.gd` | `PaintStrokeCommand` 一次笔划 before/after |
| `paint_stroke_recorder.gd` | `PaintStrokeRecorder` 笔划期间采集 |

## 3. `EditorCommand`（基类）

```gdscript
class_name EditorCommand
extends RefCounted

func get_label() -> String:
    return "Command"

## 是否影响悬崖/水面（决定 rebuild 路径）
func affects_cliffs_water() -> bool:
    return false

func execute(_document) -> void:
    pass

func undo(_document) -> void:
    pass
```

子类覆写 `execute` / `undo` / `get_label` / `affects_cliffs_water`。

## 4. `EditorCommandHistory`（栈）

```gdscript
class_name EditorCommandHistory
extends RefCounted

const DEFAULT_LIMIT := 64

var undo_stack: Array[EditorCommand] = []
var redo_stack: Array[EditorCommand] = []
var limit: int = DEFAULT_LIMIT
var document = null  # MapDocument

func bind_document(doc) -> void: ...
func clear() -> void: ...            # 清两栈
func can_undo() -> bool: ...
func can_redo() -> bool: ...

## 执行尚未落地的命令
func execute(cmd: EditorCommand) -> void: ...

## 笔划已写入 Document，只入栈（不触发重建）
func record(cmd: EditorCommand) -> void: ...

func undo() -> EditorCommand: ...
func redo() -> EditorCommand: ...
```

**栈规则**：
- `limit=64`（FIFO 超出淘汰最旧）
- 新命令压栈 → 清空 redo_stack
- 笔划走 `record()`（不重复 execute，避免与笔刷 rebuild 打架）
- 其他走 `execute()`（会 `should_rebuild=true`）

## 5. `EditorVertexSnapshot`（顶点快照）

```gdscript
class_name EditorVertexSnapshot
extends RefCounted

var index: int = -1
var height: float = 0.0
var layer: int = 0
var water_height: float = 0.0
var flags: int = 0
var ground_tex: int = 0
var ground_var: int = 0
var cliff_tex: int = 0
var cliff_var: int = 0

static func capture(hf: Wc3Heightfield, ix: int, iy: int) -> EditorVertexSnapshot: ...
func apply(hf: Wc3Heightfield) -> void: ...
func equals_snap(other: EditorVertexSnapshot) -> bool: ...
```

**字段对应** `Wc3Heightfield` SoA：

| 快照字段 | Heightfield 字段 |
|----------|------------------|
| `height` | `heights[i]` |
| `layer` | `layer_heights[i]` |
| `water_height` | `water_heights[i]` |
| `flags` | `flags_packed[i]` |
| `ground_tex` / `ground_var` | `ground_textures[i]` / `ground_variations[i]` |
| `cliff_tex` / `cliff_var` | `cliff_textures[i]` / `cliff_variations[i]` |

`equals_snap` 用 `is_equal_approx` 比 height/water_height，flags/text 整数比。

## 6. `PaintStrokeCommand`（笔划命令）

```gdscript
class_name PaintStrokeCommand
extends EditorCommand

var before: Dictionary = {}  # int index → EditorVertexSnapshot
var after: Dictionary = {}
var _affects_cliff: bool = false
var _label: String = "Paint"

func get_label() -> String:
    return "%s (%d verts)" % [_label, after.size()]

func affects_cliffs_water() -> bool: ...
func execute(document) -> void: ...   # _apply_map(after)
func undo(document) -> void: ...      # _apply_map(before)
```

**注意**：
- `before` / `after` 是 `Dictionary`，key 是 tilepoint 的 `int index`
- `execute` 实际不被调用（笔划已直接改 `MapDocument`）；但 redo 时会用到
- `undo` 时把 before 全量 apply 回 heightfield，再 `document.mark_dirty()`

## 7. `PaintStrokeRecorder`（笔划采集）

```gdscript
class_name PaintStrokeRecorder
extends RefCounted

const CAPTURE_RADIUS := 3  # 悬崖外扩邻域

func begin(document) -> void: ...
func is_active() -> bool: ...
func mark_cliff() -> void: ...   # 标记本笔划影响悬崖/水面

func capture_before_at(ix, iy, radius = CAPTURE_RADIUS) -> void: ...
func capture_before_points(points: Array[Vector2i]) -> void: ...
func capture_after_points(points: Array[Vector2i]) -> void: ...
func capture_after_at(ix, iy, radius = CAPTURE_RADIUS) -> void: ...

func finish(label := "Paint") -> PaintStrokeCommand: ...
func cancel() -> void: ...
```

**使用流程**（[BRUSHES.md §3](BRUSHES.md)）：

```gdscript
_stroke.begin(document)
_stroke.capture_before_at(ix, iy, CAPTURE_RADIUS)
# ... 笔刷改 Document ...
_stroke.capture_after_at(ix, iy, CAPTURE_RADIUS)
# ... 抬笔 ...
var cmd := _stroke.finish("Paint Texture")
if cmd:
    history.record(cmd)
```

**关键点**：
- `CAPTURE_RADIUS=3`：悬崖笔刷需外扩邻域（影响判定）
- `capture_after_at` 只保留**相对 before 有变化**的顶点
- `finish` 时**只保留真正改过的 before**（剪枝）
- `after` 空时 `finish` 返回 `null`，不入栈

## 8. 与笔刷、Editor 的连接

```text
TerrainBrush._on_press
  └─ _stroke.begin(document)
  └─ _stroke.capture_before_at(vert, CAPTURE_RADIUS)

TerrainBrush._on_drag
  ├─ Document.paint_texture/cliff/ramp(...)
  ├─ _stroke.mark_cliff()         # 如有
  ├─ _stroke.capture_after_at(...)
  └─ rebuild_requested (节流 80ms)

TerrainBrush._on_release
  ├─ _stroke.finish("...")
  ├─ history.record(cmd)          # 不触发重建
  └─ signal "painted"
```

`MapEditor` 监听 `command_applied` 信号：

```gdscript
func _on_command_applied(cmd: EditorCommand, is_undo: bool, should_rebuild: bool) -> void:
    if should_rebuild:
        if cmd.affects_cliffs_water():
            map_loader.rebuild_terrain_cliffs_water()
        else:
            map_loader.rebuild_terrain_only()
    _update_undo_redo_ui()  # 灰显按钮
```

## 9. 加新命令的流程

1. **继承** `EditorCommand`，覆写 `execute` / `undo` / `get_label` / `affects_cliffs_water`
2. **execute**：改 `MapDocument` 状态
3. **undo**：把状态回滚到 execute 之前
4. **rebuild 路径**：覆写 `affects_cliffs_water()` 返回正确值
5. **测试**：`tests/unit/selftest_editor_commands.gd`

## 10. 边界与坑

- **execute 不要重复执行** —— 笔划已在拖动中改了 Document；只走 `record()` 入栈
- **不能直接 `history.undo()` 后立刻 `history.redo()`** —— redo_stack 是空（被 record 清空）
- **snapshot 不能长持有** —— 它只是 transient 视图
- **`MapDocument.mark_dirty()`** —— undo/redo 都要调，触发脏区
- **脏区未做** —— `rebuild_terrain_only` / `rebuild_terrain_cliffs_water` 目前是全量重建；脏区接口已有但 Ground 走全量（见 [HEX_MAP_LESSONS.md](../terrain/HEX_MAP_LESSONS.md)）
