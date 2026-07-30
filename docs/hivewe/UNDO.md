# HiveWE 的撤销（Undo / Redo）

> `WorldUndoManager` + `TerrainUndo` + 笔划期全 heightfield 快照 + undo_group。

## 1. 整体架构

```text
Map
├── world_undo: WorldUndoManager        ← 笔划级别 undo/redo
├── terrain: Terrain                    ← 数据
│   ├── corner_height[] / corner_layer_height[] / corner_water[] ...
│   ├── get_corner(i, j) → Corner       ← 拷贝
│   └── update_* 系列方法                ← 重算
└── pathing_map: PathingMap             ← 寻路
    └── pathing_cells_static[]

TerrainBrush
├── old_corners: vector<Corner>         ← 笔划期全 heightfield 快照
├── old_pathing_cells_static: vector<u8> ← 笔划期 pathing 快照
├── pre_change_doodads: vector<Doodad>  ← 笔划期 doodad 快照
├── post_change_doodads: map<int, Doodad>
└── terrain_operators: 4 个 Operator
```

**关键观察**：
- `Map::world_undo`（`WorldUndoManager`）管全局 undo/redo
- 笔刷在 `apply_begin` **一次性快照整个 heightfield**（不是按 area 局部）
- 4 种 `TerrainUndoType`（height / water / cliff / texture）—— 撤销时按类型分别处理

## 2. `apply_begin` 一次性快照

**`[terrain_brush.cpp:153-162]`**：

```cpp
// setup for undo/redo — snapshot all corners
map->world_undo.new_undo_group();
old_corners_width = width;
old_corners_height = height;
old_corners.resize(width * height);
for (int j = 0; j < height; j++) {
    for (int i = 0; i < width; i++) {
        old_corners[j * width + i] = terrain.get_corner(i, j);
    }
}
old_pathing_cells_static = map->pathing_map.pathing_cells_static;
```

**关键**：
- **`world_undo.new_undo_group()`** —— 包裹一整笔划
- **`old_corners.resize(width * height)`** —— 一次笔划要存整张图
- **`terrain.get_corner(i, j)`** —— 返回 `Corner` 拷贝（推测含 height/layer/water/cliff_texture/...）
- **`old_pathing_cells_static`** —— pathing map 也一起快照

**`get_corner` 返回 Corner 拷贝**（推测）：

```cpp
class Corner {
    float height;
    u8 layer_height;
    bool water;
    float water_height;
    int ground_texture;
    u8 ground_variation;
    int cliff_texture;
    u8 cliff_variation;
    bool ramp;
    bool blight;
    bool boundary;
};
```

**Corner 大小估算**：float(4) + u8(2) + bool×6(6) + int(4) + padding ≈ 24 字节
**64×64 地图**：64K × 24 = 1.5MB / 笔划
**128×128 地图**：256K × 24 = 6MB / 笔划

**这个内存成本不小**——但 HiveWE 仍然这么做，因为：
1. 撤销语义简单（直接覆盖，不用 diff）
2. 不漏快照（即使改了远端——比如 cliff 邻接级联）
3. 一次笔划是一次"操作语义"，整体可重放

## 3. doodad 状态

**`[terrain_brush.h:71-72]`**：

```cpp
std::vector<Doodad> pre_change_doodads;
std::map<int, Doodad> post_change_doodads;
```

**这两个** 是 `change_doodad_heights` 的支撑：
- 笔划开始时 `pre_change_doodads` = updated_area 内所有 doodad
- 笔划期间 doodad 高度变化时同步到 `post_change_doodads`
- 笔划结束把 `(pre, post)` 写入 undo

**`change_doodad_heights = true`**（默认开）—— 改地形自动调 doodad Y

## 4. `add_terrain_undo`

**`[terrain_brush.h:44-45]`**：

```cpp
void add_terrain_undo(WorldEditContext& ctx, const TerrainRect& area, TerrainUndoType type);
```

**4 种 TerrainUndoType**（推测）：

```cpp
enum class TerrainUndoType {
    height,   // 高度变化
    water,    // 水面变化
    cliff,    // 悬崖变化
    texture   // 纹理变化
};
```

**Operator 的 apply_end 调用**：

```cpp
void CliffOperator::apply_end(WorldEditContext& ctx, const PathingRect& area) {
    brush->add_terrain_undo(ctx, area.to_terrain(), TerrainUndoType::cliff);
}
```

**TextureOperator**：

```cpp
void TextureOperator::apply_end(WorldEditContext& ctx, const PathingRect& area) {
    brush->add_terrain_undo(ctx, area.to_terrain(), TerrainUndoType::texture);
}
```

**每个 Operator 知道自己改了啥 type，apply_end 写入对应 undo entry**。

## 5. 笔刷生命周期

```cpp
void TerrainBrush::apply_begin() {
    if (!has_active_operators()) return;

    // 1. 笔划期全 heightfield 快照
    map->world_undo.new_undo_group();
    old_corners.resize(width * height);
    for (j, i) old_corners[j * width + i] = terrain.get_corner(i, j);
    old_pathing_cells_static = map->pathing_map.pathing_cells_static;

    // 2. 各 Operator 开始
    for (op in terrain_operators) {
        if (op.is_active) op.apply_begin(area, center_x, center_y);
    }
}

void TerrainBrush::apply(double frame_delta) {
    if (!has_active_operators()) return;

    PathingRect affected_area;
    for (op) if (op.is_active) {
        affected_area = affected_area.united(op.apply(area, frame_delta));
    }
    updated_area = updated_area.united(affected_area);
}

void TerrainBrush::apply_end() {
    for (op) if (op.is_active) {
        op.apply_end(ctx, updated_area);  // ← 这里写 undo
    }
}
```

**3 段分工**：
- `apply_begin`：**一次性** 全 heightfield 快照 + Operator 起步
- `apply`：每帧 Operator 改数据（dirty rect 累积）
- `apply_end`：Operator 写 undo entry

## 6. WorldUndoManager 推测

```cpp
class WorldUndoManager {
  public:
    void new_undo_group();  // 开始一组（一笔划）
    void add_undo_action(std::unique_ptr<UndoAction> action);  // 加 entry

    bool can_undo() const;
    bool can_redo() const;
    void undo();  // 整组撤销
    void redo();  // 整组重做
};
```

**每组（group）包含多个 UndoAction**（一笔划可能改 height + water + cliff + texture 多种 type）：

```cpp
class UndoAction {
    TerrainRect area;
    TerrainUndoType type;
    // before / after 数据
    std::vector<Corner> before;
    std::vector<Corner> after;
};
```

**注意**：HiveWE 的 `UndoAction` **不是按 vertex 拆的**——`before`/`after` 是**整个 area 的 corner 拷贝**。这样**记录的是"整片改了啥"**，不是"哪个 vertex 改了"。

## 7. 撤销语义

**`undo()`** 简化为：把所有 `UndoAction.before` 覆盖回去。

```cpp
void undo() {
    for (group : undo_stack | reversed) {
        for (action : group) {
            apply_undo_action(action);
        }
    }
}
```

**`apply_undo_action` 简化版**：

```cpp
void apply_undo_action(const UndoAction& action) {
    for (idx in action.area) {
        switch (action.type) {
            case height:   corner_height[idx] = action.before[idx].height; ...
            case water:    corner_water[idx] = action.before[idx].water; ...
            case cliff:    corner_layer_height[idx] = action.before[idx].layer_height; ...
            case texture:  corner_ground_texture[idx] = action.before[idx].ground_texture; ...
        }
    }
}
```

## 8. 对应到 godot_warcraft3

| HiveWE | godot_warcraft3 | 评价 |
|--------|----------------|------|
| `WorldUndoManager` | `EditorCommandHistory` | ✅ 等价 |
| `new_undo_group()` 包裹一笔划 | **无显式 group**（每笔划一个 `PaintStrokeCommand`） | ✅ 简化版（每个 command 自带 before/after） |
| `old_corners` 全 heightfield 快照 | `PaintStrokeRecorder._before/_after`（CAPTURE_RADIUS=3） | ❌ **不一样**——见下 |
| `old_pathing_cells_static` 快照 | **未实现**（没 pathing） | ⚠️ 暂不需 |
| `pre_change_doodads` | **未实现**（ROADMAP §⑩） | ❌ 缺 |
| 4 种 `TerrainUndoType` | `PaintStrokeCommand.affects_cliffs_water: bool` | ⚠️ 我们只分 cliff-or-not，2 档 |
| `Corner` 11 字段 SoA | `EditorVertexSnapshot` 8 字段 | ✅ 简化版 |
| `apply_begin` 一次快照 | `PaintStrokeRecorder.begin(doc)` + `capture_before_at` | ✅ 思路同（多次采集） |
| `apply` 改数据 + dirty rect | `Document.paint_*` + `MapDocument.mark_dirty` | ✅ 1:1 |
| `apply_end` 写 undo | `history.record(cmd)` | ✅ 1:1 |
| `record` 不触发重建 | `command_applied.emit(cmd, false, false)` | ✅ 1:1 |
| `DEFAULT_LIMIT=64` 栈 | `DEFAULT_LIMIT=64` | ✅ 完全一致 |
| `undo` 整组覆盖 | `cmd.undo(document)` 走 `_apply_map(before)` | ✅ 等价 |
| `redo` 走 execute | `cmd.execute(document)` 走 `_apply_map(after)` | ✅ 等价 |

## 9. 关键差距：全 heightfield 快照 vs 局部 CAPTURE_RADIUS

**HiveWE 全 heightfield**（`old_corners.resize(width*height)`）：

✅ 优点：
- 撤销语义简单（直接覆盖）
- cliff 邻接级联传播到远处也能 undo
- 不依赖"哪些 vertex 被改了"

❌ 缺点：
- 内存：`width * height * sizeof(Corner)` ≈ 1.5MB/笔划（64×64）
- 时间：每笔划 O(N) 拷贝

**我们的局部**（`CAPTURE_RADIUS=3`）：

✅ 优点：
- 省内存（仅外扩 3×3 = 49 corner/笔划）
- 省时间

❌ 缺点：
- **如果笔刷改了笔刷区域外的 vertex（cascade、clamp），会漏快照**
- 例如：cliff 笔刷的 3×3 clamp 传播到 5-6 格远，那个 5-6 格的 corner 改了但没快照 → 撤销不一致

## 10. vibecoding 指导

### 10.1 悬崖笔刷建议改用全 heightfield 快照

**当前**：`CAPTURE_RADIUS=3` 局部，悬崖笔刷可能漏掉远端 clamp

**建议**：

```gdscript
# Wc3CliffLogic 笔刷专用
# 按 cliff_tool_id 选策略
# 悬崖 / 斜坡 → 全 heightfield 快照
# 高度 / 纹理 → CAPTURE_RADIUS=3 局部

# 实现：TerrainBrush 加 brush_mode: enum { LOCAL, FULL_HEIGHTFIELD }
#   FULL_HEIGHTFIELD: capture_before_at 走全 heightfield（但实现为每点 capture_before_at(0,0,width,height)）
#   LOCAL: 走原 CAPTURE_RADIUS
```

**注意**：全 heightfield 模式要确保 `capture_before_at` 能处理整个 heightfield 不爆。

### 10.2 `WorldUndoManager` 的 `new_undo_group()` 概念

**当前**：我们每个 `PaintStrokeCommand` 是一个"组"（自带 before/after）
**建议**：保持现状，**不要** 引入 group 概念——GDScript 简单即可

**但**：如果想做"组合笔划"（多笔划作为一次撤销），要加 group。当前没必要。

### 10.3 doodad 状态 undo（`pre_change_doodads`）

**当前**：未实现
**建议**（[OPERATORS.md §6.4](OPERATORS.md)）：
1. `Wc3DoodadLogic`（新类）管 doodad Y 计算
2. `MapDocument` 改 terrain 时算 `doodad_affected_rect`
3. `apply_end` 调 `doodads.apply_height_update(rect)`，同时 `pre/post_doodads` 写 undo
4. `DoodadUndoAction`（新类，类似 `TerrainUndoType`）—— 单独 undo 栈

### 10.4 4 种 `TerrainUndoType` vs 我们 1 种

**HiveWE**：4 种独立 undo entry，混合写
**我们**：1 个 `PaintStrokeCommand`，`affects_cliffs_water: bool` 决定重建路径

**评价**：我们**简化得当**——4 种 type 拆开反而复杂（同一笔划可能改 height+cliff，合并更自然）。

**但**：如果要加"选择性 undo"（只撤销 cliff 不撤销 height），需要拆 type。当前**没必要**。

### 10.5 全 heightfield 快照的"懒"实现

**问题**：64×64 快照 ≈ 1.5MB/笔划；用户画 100 笔 = 150MB

**建议**（"懒快照"）：

```gdscript
# 不在 apply_begin 立即快照
# 而在 apply 期间首次改 vertex 时才记 before
# 配合 `_last_snapshot_heightfield: Wc3Heightfield` 缓存

# 优势：用户画"无变化"的笔刷不产生 undo
# 劣势：实现复杂（要"first-write"检测）
```

**或者**更简单：HivEWE 的全 heightfield 快照对 64×64~128×128 够用，**保持现状**即可。256×256+ 才需要优化。

### 10.6 重做逻辑

**HiveWE**：`redo` 走 `apply(after)` —— 重新应用 after 数据
**我们**：`cmd.execute(document)` 走 `_apply_map(after)` —— 等价

**评价**：✅ 1:1。

**注意**：redo 后 redo_stack 不清空（仅 undo 清空），所以"反复 undo/redo"是 OK 的。

## 11. 总结

| 维度 | HiveWE | 我们 | 谁更好 |
|------|--------|------|--------|
| 撤销栈 | `WorldUndoManager` | `EditorCommandHistory` | **平** |
| 笔划期快照 | **全 heightfield** | 局部 CAPTURE_RADIUS=3 | **HiveWE 更稳**（不漏） |
| doodad undo | ✅ 有 | ❌ 无 | **HiveWE 强** |
| 4 种 type | ✅ 独立 | ❌ 混合 | **我们简化得当** |
| redo 语义 | apply after | apply after | **平** |
| DEFAULT_LIMIT | 64 | 64 | **完全一致** |
| `record` 不触发重建 | ✅ | ✅ | **平** |

**对 vibecoding 的核心建议**：
1. 悬崖笔刷改**全 heightfield 快照**（防漏）
2. doodad undo 独立做（[OPERATORS.md §6.4](OPERATORS.md)）
3. 其他保持现状
