# HiveWE 的 TerrainOperator 策略模式

> 最关键的一个文档——HiveWE 把笔刷的所有操作拆成 4 个 `TerrainOperator`（高度/纹理/悬崖/格），每个 Operator 都有 `apply_begin/apply/apply_end` 三段式。**这种"策略模式 + 三段式"是 vibecoding 加新功能最值得借鉴的架构**。

## 1. 类结构

```text
Brush（基类）
  └─ TerrainBrush : Brush
       ├─ cliff_operator:    CliffOperator
       ├─ height_operator:   HeightOperator
       ├─ texture_operator:  TextureOperator
       ├─ cell_operator:     CellOperator
       └─ terrain_operators: std::array<reference_wrapper<TerrainOperator>, 4>
```

**`[brush/terrain_brush.h:48-51, 79]`**

```cpp
CliffOperator cliff_operator;
HeightOperator height_operator;
TextureOperator texture_operator;
CellOperator cell_operator;

std::array<std::reference_wrapper<TerrainOperator>, 4> terrain_operators;
```

每个 Operator 通过构造时拿 TerrainBrush 引用，激活/停用通过 `activate_operator` / `deactivate_operator`：

```cpp
// terrain_brush.cpp:28
void TerrainBrush::activate_operator(TerrainOperator& target) {
    target.is_active = true;
    brush_type = target.brush_type;
    for (TerrainOperator& op : terrain_operators) {
        if (&op != &target && !can_combine(target, op)) {
            op.is_active = false;
        }
    }
}
```

**互斥表**（哪些 Operator 可同时开）：

```cpp
// terrain_brush.cpp:49
static const std::array compatible = {
    Pair {typeid(TextureOperator), typeid(CliffOperator)},
};
// 仅 Texture + Cliff 可同时（刷地表贴图 + 改悬崖类型）；其余互斥
```

## 2. `TerrainOperator` 基类

**`[brush/terrain_operators.h:10]`**

```cpp
class TerrainOperator {
  public:
    TerrainOperator(TerrainBrush& brush, Brush::Type type) : brush(&brush) {
        set_brush_type(type);
    }

    /// 按下鼠标（笔划开始）
    virtual void apply_begin(const TerrainRect& area, int center_x, int center_y) = 0;
    /// 每帧拖动；返回本次影响的 pathing 矩形
    virtual PathingRect apply(const TerrainRect& area, double frame_delta) = 0;
    /// 抬起鼠标（笔划结束，写 undo）
    virtual void apply_end(WorldEditContext& ctx, const PathingRect& area) = 0;

  protected:
    TerrainBrush* brush;
  private:
    bool is_active = false;
    Brush::Type brush_type;  // corner | cell
};
```

**三段式职责清晰**：

| 阶段 | 职责 |
|------|------|
| `apply_begin` | 采状态（按下瞬间的目标高度/水位/索引）；不改数据 |
| `apply` | 改数据 + 重算 + 改 marker；**返回 affected pathing 矩形** |
| `apply_end` | 写 undo（`add_terrain_undo(ctx, area, type)`） |

## 3. 4 个 Operator 概览

### 3.1 `HeightOperator`

**5 种 deformation**（`[terrain_operators.h:40-46]`）：

```cpp
enum class deformation {
    raise,    // 抬升（按距离衰减，frame_delta 控制速度）
    lower,    // 下降（同上）
    plateau,  // 整平到按下瞬间的目标高度
    ripple,   // 涟漪（TODO 未实现）
    smooth    // 平滑：3×3 卷积，每帧 0.03 * neighbor / 0.97 * self
};
```

**关键**：`apply_begin` 记下按下瞬间的 `corner_height[center_idx]`（`deformation_height_ground`），plateau 用这个值整平。

**smooth 公式**（`[terrain_operators.cpp:78-96]`）：

```cpp
smooth_height = 0.97 * current + 0.03 * (sum_neighbors / 8)
```

⚠️ 关键：3×3 邻域（`TerrainRect(i-1, j-1, 3, 3)`），8 个邻居 + 自己 9 个 cell；用同 area 的 heights 数组（已 snapshot 完整个 area 的高度），避免同时修改影响卷积。

**返回**：`area.to_pathing().adjusted(-2, -2, 2, 2)`（pathing 分辨率，外扩 2 用于 pathing 联动）。

### 3.2 `TextureOperator`

**`[terrain_operators.h:60-73]`**

```cpp
class TextureOperator : public TerrainOperator {
    std::string tile_id;
    int tile_index;  // apply_begin 时从 tile_id 解析
};
```

**apply 关键**（`[terrain_operators.cpp:153-197]`）：

```cpp
if (tile_index == terrain.blight_texture) {
    // Blight shouldn't be set when there is a cliff near
    bool cliff_near = false;
    for (k=-1; k<=1; k++) for (l=-1; l<=1; l++) {
        cliff_near = cliff_near || terrain.corner_cliff[ci(i+k, j+l)];
    }
    if (cliff_near) continue;  // 跳过：blight 不能贴 cliff
    corner_blight[idx] = true;
} else {
    corner_blight[idx] = false;
    corner_ground_texture[idx] = tile_index;
    corner_ground_variation[idx] = random_ground_variation();  // 5 bit 加权
}
```

**亮点**：
1. 贴 Blight 前查 3×3 邻域 cliff，避免 blight 贴悬崖（视觉错位）
2. 任何非 blight 笔刷顺手清 blight（写 blight=false）

### 3.3 `CliffOperator`（最复杂）

**8 种 operation**（`[terrain_operators.h:79-89]`）：

```cpp
enum class cliff_operation {
    lower2, lower1, level, raise1, raise2,  // 5 档升降
    deep_water,                              // 深水
    shallow_water,                           // 浅水
    ramp                                     // 斜坡
};
```

**`apply_begin` 智能定 target height**（`[terrain_operators.cpp:209-241]`）：

```cpp
switch (cliff_operation_type) {
    case shallow_water:
        if (!corner_water[center_idx]) layer_height -= 1;        // 干地 → 浅水 = 降 1
        else if (water > ground + 1) layer_height += 1;          // 已经是深水 → 抬 1
        break;
    case deep_water:
        if (!corner_water[center_idx]) layer_height -= 2;        // 干地 → 深水 = 降 2
        else if (water < ground + 1) layer_height -= 1;          // 浅水 → 深水 = 降 1
        break;
    case ramp: case level: break;                                // ramp/level 不动 layer_height
    case lower1/2/raise1/2: layer_height ± 1/2;
}
layer_height = clamp(layer_height, 0, 15);
```

**`apply_cliffs` 关键**（`[terrain_operators.cpp:244-329]`）：

```cpp
// 1. 写 layer_height
corner_ramp[idx] = false;  // 重置 ramp 标志
corner_layer_height[idx] = layer_height;

// 2. 处理特殊操作
if (lower/raise/level) {
    if (corner_water[idx] && water < ground) corner_water[idx] = false;  // 强制水位
}
if (shallow_water) {
    corner_water[idx] = true;
    corner_water_height[idx] = corner_layer_height[idx] - 1;  // 浅水 = layer - 1
}
if (deep_water) {
    corner_water[idx] = true;
    corner_water_height[idx] = corner_layer_height[idx];      // 深水 = layer
}

// 3. check_nearby 3×3 邻域 clamp（见 CLIFF.md）
check_nearby(...);

// 4. 重新计算 cliff 标志
for (i, j) in expanded_area:
    bl=ci(i,j); br=ci(i+1,j); tl=ci(i,j+1); tr=ci(i+1,j+1);
    corner_cliff[bl] = (layer[bl] != layer[br]) || (layer[bl] != layer[tl]) || (layer[bl] != layer[tr]);
    if (corner_cliff[bl]) {
        corner_blight[bl] = corner_blight[br] = corner_blight[tl] = corner_blight[tl] = false;
    }

// 5. 重算
terrain.update_cliff_meshes(tile_area);
terrain.update_ground_textures(expanded_area);
terrain.update_ground_heights(...);
terrain.update_water(...);
if (water 操作) terrain.upload_water_heights();  // 立即上传 GPU
```

**`apply_ramps`** 走单独路径（`update_ramp` 算法，详见 [RAMP.md](RAMP.md)）。

**`apply` 调度**（`[terrain_operators.cpp:363-369]`）：

```cpp
PathingRect CliffOperator::apply(...) {
    if (cliff_operation_type == cliff_operation::ramp) {
        return apply_ramps(area, frame_delta);
    } else {
        return apply_cliffs(area, frame_delta);
    }
}
```

### 3.4 `CellOperator`

**5 种 operation**（`[terrain_operators.h:112-121]`）：

```cpp
enum class cell_operation {
    add_water, remove_water,           // 水面
    add_boundary, remove_boundary,     // 边界（深水不可建）
    add_hole, remove_hole              // 挖洞（future work）
};
```

**`set_operation_type` 智能切 brush type**（`[terrain_operators.cpp:638-645]`）：

```cpp
if (add_boundary || remove_boundary) {
    set_brush_type(Brush::Type::cell);   // 边界用 cell
} else {
    set_brush_type(Brush::Type::corner);  // 水用 corner
}
```

**`apply_begin` 智能定 water_height**（`[terrain_operators.cpp:546-557]`）：

```cpp
if (water_above_ground(center_idx)) {
    water_height = corner_water_height[center_idx];  // 已在水面 → 保留
} else {
    int layer = corner_layer_height[center_idx];
    float terrain_h = layer - 2 + corner_height[center_idx];
    water_height = terrain_h + WATER_GROUND_ZERO + WATER_HEIGHT;  // 默认
    // = (layer - 2 + height) + 0.7 + 0.25
}
```

**常量**（`[terrain_operators.h:131-135]`）：

```cpp
static constexpr float WATER_GROUND_ZERO = 0.7f;
static constexpr float WATER_HEIGHT = 0.25f;
```

**`apply` 关键**（`[terrain_operators.cpp:559-618]`）：

```cpp
if (add_water) {
    if (!corner_water[id]) {
        corner_water[id] = true;
        corner_water_height[id] = water_height;
    } else if (!water_above_ground(id)) {
        corner_water_height[id] = water_height;  // 不在水面 → 抬到目标
    }
} else if (remove_water) {
    corner_water[id] = false;
    corner_water_height[id] = 0;
} else if (add_boundary) {
    corner_boundary[id] = true;
} else if (remove_boundary) {
    corner_boundary[id] = false;
}
```

**`water_above_ground` 判定**（`[terrain_operators.cpp:632-636]`）：

```cpp
bool CellOperator::water_above_ground(int corner_id) const {
    return corner_water_height[corner_id] > corner_layer_height[corner_id] - 2 + corner_height[corner_id] + WATER_GROUND_ZERO;
}
```

## 4. 笔刷生命周期（`terrain_brush.cpp`）

```cpp
// 135
void TerrainBrush::apply_begin() {
    if (!has_active_operators()) return;

    const auto& terrain = map->terrain;
    const int width = terrain.width;
    const int height = terrain.height;

    const glm::ivec2 pos = get_unclipped_pos();
    TerrainRect area = TerrainRect(pos.x, pos.y, size.x / 4.f, size.y / 4.f).intersected({0, 0, width, height});
    updated_area = PathingRect();
    const int center_x = area.x() + area.width() * 0.5f;
    const int center_y = area.y() + area.height() * 0.5f;

    // 1. 笔划期一次性全 heightfield 快照
    map->world_undo.new_undo_group();
    old_corners_width = width;
    old_corners_height = height;
    old_corners.resize(width * height);
    for (j, i) old_corners[j * width + i] = terrain.get_corner(i, j);
    old_pathing_cells_static = map->pathing_map.pathing_cells_static;

    // 2. 各 Operator 开始
    for (op) if (op.is_active) op.apply_begin(area, center_x, center_y);
}

void TerrainBrush::apply(double frame_delta) {
    if (!has_active_operators()) return;

    TerrainRect area = ...intersected(...);
    PathingRect affected_area;
    if (area.width() <= 0 || area.height() <= 0) return;

    // 1. 各 Operator apply
    for (op) if (op.is_active) {
        affected_area = affected_area.united(op.apply(area, frame_delta)).intersected(...);
    }
    updated_area = updated_area.united(affected_area);
}

void TerrainBrush::apply_end() {
    for (op) if (op.is_active) op.apply_end(ctx, updated_area);
}
```

**关键观察**：
- **`old_corners` 是全 heightfield 快照**（不是按 area 局部）——一次笔划一次性记下整个地图
- **`world_undo.new_undo_group()`** 包裹一整笔划
- **`updated_area` 累积**：多次 `apply` 调用的 affected 区域 union（脏矩形）
- **`frame_delta` 传入 apply**：speed 是 per-frame 的（动画感）

## 5. 对应到 godot_warcraft3

| HiveWE | godot_warcraft3 | 评价 |
|--------|----------------|------|
| `TerrainOperator` 4 类 | **无对应**—— `MapDocument` 是单一类 + 各 `Wc3*Logic` 调用 | ❌ 缺策略层 |
| `apply_begin/apply/apply_end` 三段 | `PaintStrokeRecorder.begin/capture_before/capture_after/finish`（partially） | ⚠️ 部分对应 |
| `HeightOperator` | `Wc3TerrainLogic.set_height` | ✅ 1 个方法 |
| `TextureOperator` | `Wc3TerrainLogic.set_ground_tex` + `Wc3GroundTileCatalog` | ✅ 拆得对 |
| `CliffOperator` | `Wc3CliffLogic` | ✅ 拆得对（但没分 apply_cliffs / apply_ramps） |
| `CellOperator` | **无对应** | ❌ Cell 层缺失 |
| `can_combine` 互斥表 | 笔刷 UI 复选框（`apply_texture` / `apply_cliff`） | ✅ 简化版 |
| `apply_begin` 采目标高度 | `_stroke._cliff_level_anchor` 采 `layer` | ✅ 1:1 |
| `apply_end` 写 undo | `history.record(cmd)` | ✅ 1:1 |
| 全 heightfield 快照 | `CAPTURE_RADIUS=3` 局部快照 | ❌ 不一样 |
| `frame_delta` per-frame | `REBUILD_INTERVAL_MS=80` 节流 | ⚠️ 思路不同 |
| `updated_area` 累积 | `MapDocument.dirty_min/max` | ✅ 等价 |
| `change_doodad_heights` 自动调 doodad Y | **未实现**（ROADMAP §⑩） | ❌ 缺 |
| `doodad_state_undo` | **未实现** | ❌ 缺 |
| `WATER_GROUND_ZERO=0.7` 常量 | **未常量** | ❌ 缺 |

## 6. vibecoding 指导

### 6.1 是否照搬 `TerrainOperator` 模式？

**建议：P1 引入**。当前痛点：
- `MapDocument` 单类承担太多（笔划 + 数据 + 撤销 + 重建触发）
- `Wc3CliffLogic` 没拆 `apply_cliffs` / `apply_ramps`（RAMP.md §"差距"）
- Cell 层（水/边界/污染）完全缺失

**怎么照**（增量改造，不要 big-bang）：

1. **加 `RampOperator`**：从 `Wc3CliffLogic` 拆出，独立类
   ```gdscript
   class_name Wc3RampOperator
   extends RefCounted
   # 把 cliff/wc3_ramp_paint.gd 里的 paint 逻辑收成 apply_begin/apply/apply_end
   ```
2. **加 `CellOperator`**：water/boundary/blight
   ```gdscript
   class_name Wc3CellOperator
   extends RefCounted
   # 水面 + 边界（blight 留给 TextureOperator 内部）
   ```
3. **`MapDocument` 持 `Array[Operator]`**，按 active 状态循环调用
4. **保持 `EditorCommandHistory` 现状**（撤销栈 OK）
5. **`WATER_GROUND_ZERO` / `WATER_HEIGHT` 提到 `Wc3Coords`**（常量集中）

### 6.2 不要照搬的 4 件事

1. **全 heightfield 快照** —— 我们 64×64~128×128 地图不大可以照；**但 256×256 就不行了**（每笔划拷贝 65K 顶点 8 字段 = 0.5MB/笔划）
   - 改：`PaintStrokeRecorder` 保留 CAPTURE_RADIUS 局部即可（更省）
   - 撤销/重做仍要全 heightfield 的话在 `MapDocument` 缓存"上次保存的快照"

2. **CASC/Reforged 资产管线** —— 不适用

3. **Bullet 物理** —— Godot 4.6 用 Jolt

4. **`can_combine` 类型表**（`std::type_index` 模板技巧）—— GDScript 没模板，简化为 4 个 bool 字段即可

### 6.3 笔刷期全 heightfield 快照 vs 局部 CAPTURE_RADIUS

**HiveWE 全 heightfield**：
- ✅ 撤销语义简单（直接覆盖）
- ✅ 不漏快照（即使改了远端）
- ❌ 内存 + 时间都大

**我们的局部**：
- ✅ 省内存
- ❌ **如果笔刷改了笔刷区域外的顶点（cascade、clamp），会漏快照** → 撤销不一致

**建议折中**：根据笔刷类型选策略：
- 高度/纹理笔刷：局部 `CAPTURE_RADIUS=3` 够用
- 悬崖笔刷：**全 heightfield**（因为 cliff 邻接会级联 clamp 整片）
- 斜坡笔刷：全 heightfield + 外扩 2-3（romp 会传播）

### 6.4 `change_doodad_heights`（地形改 → doodad Y 自动调）

**现状**：ROADMAP §⑩ 待实现

**建议路径**：
1. `MapDoodadLayer` 改 `build(ctx)`，吃 Context
2. `MapDocument` 改 terrain 时算 `doodad_affected_rect`（高度差 > 阈值 × 半径）
3. `apply_end` 调 `doodads.apply_height_update(rect)`
4. `doodad_state_undo` 独立 undo（仿 HiveWE 走 `DoodadsUndo` module）

这是 vibecoding 的一个**独立模块**——可以分一两次 PR 做掉。
