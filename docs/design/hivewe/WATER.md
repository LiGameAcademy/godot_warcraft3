# HiveWE 的水体（Water）

> CellOperator 4 种操作、水位公式、water_above_ground 判定、shore 留作 v2。

## 1. CellOperator 5 种 operation

**`[terrain_operators.h:112-121]`**：

```cpp
enum class cell_operation {
    add_water,        // 加水（cell 级别，自动算 height）
    remove_water,     // 移除水
    add_boundary,     // 标记边界（深水不可建）
    remove_boundary,  // 移除边界
    add_hole,         // 挖洞（future work）
    remove_hole       // 挖洞（future work）
};
```

**前 4 种已实现**，后 2 种标"future work"。

**`add_water` / `remove_water`**：水面存在性（`corner_water[i]`）和高度（`corner_water_height[i]`）
**`add_boundary` / `remove_boundary`**：边界标志（`corner_boundary[i]`，深水不可建）

## 2. brush_type 自动切换

**`[terrain_operators.cpp:638-645]`**：

```cpp
void CellOperator::set_operation_type(cell_operation operation) {
    cell_operation_type = operation;
    if (operation == add_boundary || operation == remove_boundary) {
        set_brush_type(Brush::Type::cell);    // 边界用 cell
    } else {
        set_brush_type(Brush::Type::corner);  // 水用 corner
    }
}
```

**为什么**：
- 水面 = corner 级别（每个 corner 单独有 water_height）
- 边界 = cell 级别（一个 cell 一个 boundary 标志）

**这跟我们的设计差异**：
- 我们目前没拆 Cell 层（`MapDocument` 直接管水）
- 我们的 `MapWaterLayer` 走 corner 级别（与 HivEWE 水一致）

## 3. `apply_begin` 智能定 water_height

**`[terrain_operators.cpp:546-557]`**：

```cpp
void CellOperator::apply_begin(const TerrainRect& area, int center_x, int center_y) {
    auto& terrain = map->terrain;
    const size_t center_idx = ci(center_x, center_y);

    if (water_above_ground(center_idx)) {
        // 已经在水面 → 保留当前水位
        water_height = corner_water_height[center_idx];
    } else {
        // 不在水面 → 算默认水位
        int layer_height = corner_layer_height[center_idx];
        float terrain_height = layer_height - 2 + corner_height[center_idx];
        water_height = terrain_height + WATER_GROUND_ZERO + WATER_HEIGHT;
        //                  ^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^
        //                  layer 内偏移     水面到地表       默认 add 高度
    }
}
```

**关键常量**（`[terrain_operators.h:131-135]`）：

```cpp
static constexpr float WATER_GROUND_ZERO = 0.7f;  // 水面到地表基准偏移
static constexpr float WATER_HEIGHT = 0.25f;      // 默认 add_water 水位
```

**`water_above_ground` 判定**（`[terrain_operators.cpp:632-636]`）：

```cpp
bool CellOperator::water_above_ground(int corner_id) const {
    return corner_water_height[corner_id]
        > corner_layer_height[corner_id] - 2 + corner_height[corner_id] + WATER_GROUND_ZERO;
}
```

**含义**：水位 > 地表 + 0.7 才算"可见水"

**这个值 0.7 是哪儿来的**？
- WC3 经典 WE 的水面渲染层叠顺序：水面在地表上方 0.7 单位（防止 z-fight）
- 这是经验值——可以调

## 4. `apply` 主体

**`[terrain_operators.cpp:559-618]`**：

```cpp
PathingRect CellOperator::apply(const TerrainRect& area, double frame_delta) {
    auto& terrain = map->terrain;
    const int width = terrain.width;
    const int height = terrain.height;
    const glm::ivec2 pos = brush->get_unclipped_pos();

    bool edits_water = cell_operation_type == remove_water || cell_operation_type == add_water;

    // cell operator brush targets cells, not corners
    for (i = area.x(); i < area.x() + area.width(); i++) {
        for (j = area.y(); j < area.y() + area.height(); j++) {
            if (!brush->contains(...)) continue;

            // bounds check
            if (i >= width || j >= width || i < 0 || j < 0) continue;

            const size_t id = ci(i, j);

            if (cell_operation_type == add_water) {
                if (!corner_water[id]) {
                    corner_water[id] = true;
                    corner_water_height[id] = water_height;
                } else {
                    // 已经是水，但不在可见层 → 抬到目标
                    if (!water_above_ground(id)) {
                        corner_water_height[id] = water_height;
                    }
                }
            } else if (remove_water) {
                corner_water[id] = false;
                corner_water_height[id] = 0;
            } else if (add_boundary) {
                corner_boundary[id] = true;
            } else if (remove_boundary) {
                corner_boundary[id] = false;
            }
        }
    }

    // 水操作才重算
    if (edits_water) {
        terrain.update_water(area.adjusted(0, 0, 1, 1).intersected({0, 0, width, height}));
    }

    // 返回 affected area
    if (brush->brush_type == Brush::Type::corner) {
        return area.to_pathing().adjusted(-2, -2, -2, -2);
    } else {
        return area.to_pathing();
    }
}
```

## 5. 关键细节

### 5.1 `add_water` 不破坏已有水

```cpp
if (!corner_water[id]) {
    // 干地 → 加水
    corner_water[id] = true;
    corner_water_height[id] = water_height;
} else if (!water_above_ground(id)) {
    // 已经有水标志但不在可见层（"地下水"）→ 抬到目标
    corner_water_height[id] = water_height;
}
```

**这是"分层水位"概念**：
- `corner_water[id] = true` 是"这块地是水域"
- `corner_water_height[id]` 是"水面高度"
- 即使地下有水（`corner_water=true` 但 `water_height < ground + 0.7`），新 `add_water` 也会把水位抬到可见

**对应到 W3E 文件**：`corner_water` 标志 + `corner_water_height` 数组。

### 5.2 cell 级别 vs corner 级别

`add_boundary` 用 cell 索引（`ci(i, j)` = 左下 corner），但实际表示整个 cell 的边界标志。

**疑问**：HivEWE 把 boundary 放在 `corner_boundary[]`（corner SoA 数组），但用 `ci(i, j)` 索引——这是 cell-as-corner 约定（每个 cell 用 BL corner 代表）。

### 5.3 `enforce_water_height_limits`

**`[terrain_brush.h:27]`**：

```cpp
bool enforce_water_height_limits = true;
```

**开启时**（CliffOperator 处理）：

```cpp
if (corner_water[idx] && brush->enforce_water_height_limits
    && corner_final_water_height(i, j) < corner_final_ground_height(i, j)) {
    corner_water[idx] = false;  // 水降到比地低 → 强制变干
}
```

**含义**：防止出现"水在地表下面"的不一致状态。

## 6. update_water / upload_water_heights

**`update_water(area)`**（推测）：重算水面 mesh（包括 4 角插值）

**`upload_water_heights()`**（推测）：立即上传到 GPU（openGL VBO）

**何时调**：
- `CliffOperator` 的水操作（shallow/deep）→ `upload_water_heights()` 立即生效
- `CellOperator` 的水操作 → `update_water(area)` 重建

**区别**：cliff 的水操作影响 layer（地形结构）→ 立即上传；cell 的水操作只动 cell flag → 重建就行。

## 7. Shore / 岸浪（**留作 v2**）

**HiveWE 0.3 旧版** 应该有 shore 粒子（PE2 近似），但**新版源码**没看到相关文件（可能分散在 `main_window/glwidget` 或 `models/shore`）。

**查源码**：
- `glwidget.cpp` 应该有水面/岸浪渲染（但只看菜单不算算法）
- 新版可能用 `update_water` 自带岸浪效果

**我们的现状**：
- ✅ `Wc3WaterMesh`（水面 ArrayMesh）
- ✅ `Wc3ShorelineBuilder`（岸浪发射点）
- ✅ `Wc3ShoreFoam`（岸浪 MultiMesh）
- ⏳ 自动岸浪（PE2 近似）— 已就位但未精调

**对比**：我们岸浪实现已经超过 0.3 旧版（PE2 近似 + Shader + MultiMesh）。

## 8. 关键常量

| HiveWE 常量 | 值 | 我们 | 评价 |
|-------------|----|----|------|
| `WATER_GROUND_ZERO` | `0.7` | **未常量** | ❌ 缺 |
| `WATER_HEIGHT` | `0.25` | **未常量** | ❌ 缺 |
| `max_ground_height` | `15` | `14` | ⚠️ 不一样（见 [CLIFF.md §10](CLIFF.md)） |
| `enforce_water_height_limits` | `true` | `MapLoader` `enforce_water_height_limits`（推测） | ✅ |

## 9. 对应到 godot_warcraft3

| HiveWE | godot_warcraft3 | 评价 |
|--------|----------------|------|
| `CellOperator` 4 种 operation | **未拆 CellOperator** | ❌ 缺 |
| `add_water` / `remove_water` | `MapDocument.paint_water` | ⚠️ 单方法 |
| `add_boundary` / `remove_boundary` | **未实现** | ❌ 缺 |
| `add_hole` / `remove_hole` | **未实现** | ❌ 缺（待重做） |
| `corner_water[]` + `corner_water_height[]` | `Wc3Heightfield.water_heights[]`（合并） | ⚠️ 拆得更省 |
| `WATER_GROUND_ZERO=0.7` | **未常量** | ❌ 缺 |
| `WATER_HEIGHT=0.25` | **未常量** | ❌ 缺 |
| `water_above_ground` 判定 | `WATER_GROUND_ZERO` 用法 | ⚠️ 应该提到 `Wc3Coords` |
| `enforce_water_height_limits` | `MapLoader` 开关 | ✅ |
| `terrain.update_water(area)` | `MapWaterLayer.build(ctx)` | ✅ 拆得对 |
| `terrain.upload_water_heights()` | **未实现** | ⚠️ Godot 端不需 |
| `Brush::Type::cell` 用于 boundary | **未实现** | ❌ 缺 cell 笔刷模式 |
| 岸浪 PE2 近似 | `Wc3ShoreFoam` MultiMesh | ✅ 已实现 |

## 10. vibecoding 指导

### 10.1 `Wc3Coords` 加 `WATER_GROUND_ZERO` / `WATER_HEIGHT`

**步骤**：
1. `scripts/map/data/wc3_coords.gd` 加：
   ```gdscript
   const WATER_GROUND_ZERO := 0.7
   const WATER_HEIGHT := 0.25
   ```
2. `Wc3TerrainLogic.water_above_ground(ix, iy)` 用 `Wc3Coords.WATER_GROUND_ZERO`
3. `Wc3CellLogic.default_water_height(ix, iy)` 用 `Wc3Coords` 两个常量
4. 渲染 shader 也用（`wc3_water.gdshader` uniform）

### 10.2 拆 `Wc3CellOperator`（[OPERATORS.md §6.1](OPERATORS.md)）

**当前**：`MapDocument.paint_water` 一个方法
**建议**：
```gdscript
class_name Wc3CellOperator
extends RefCounted

enum cell_operation { ADD_WATER, REMOVE_WATER, ADD_BOUNDARY, REMOVE_BOUNDARY, ADD_HOLE, REMOVE_HOLE }

func apply_begin(ix, iy, op, ctx) -> void
func apply(ix, iy, op, ctx) -> void  # 或 apply_batch(area, op, ctx)
func apply_end(ctx) -> void
```

**调用方**：`MapDocument` 持 `Wc3CellOperator`；笔刷 UI 选 operation 后 dispatch。

### 10.3 `FLAG_BOUNDARY` 加到 `flags_packed`

**步骤**：
1. `Wc3Coords` 加 `FLAG_BOUNDARY = 8`（不与现有 1/2/4 冲突）
2. `Wc3Heightfield` 用 `flags_packed[ci] & FLAG_BOUNDARY` 查
3. `Wc3CellOperator.apply_boundary` 写
4. `MapWaterLayer` 检查边界，渲染特殊（深水标记）

### 10.4 岸浪精调（`selftest_shoreline.gd`）

**当前**：[WATER.md §"已知问题"](../water/WATER.md) 说"泡沫精调暂搁"

**建议路径**：
1. 跑 `selftest_shoreline.gd`，看哪些用例 fail
2. 调 `Wc3ShorelineBuilder.collect_foam_placements`（发射点算法）
3. 调 `Wc3ShoreFoam.material`（alpha / scale / 速度）
4. 调 shader `wc3_shore_foam.gdshader`（Additive 混合）

**测试用图**：Lost Temple（湖岸 + 海边都有）

### 10.5 Cell 模式笔刷（`Brush::Type::cell`）

**我们现状**：所有笔刷都是 corner 模式
**建议**：
1. `MapDocument` 加 `paint_cell(ix, iy, op, value)` 方法
2. `TerrainBrush` 加 `cell_mode: bool` 开关
3. UI 加"按 cell / 按 corner"切换
4. 测试：用 cell 笔刷画 boundary 应该一次过 1 tile

### 10.6 岸浪不算法问题，是美术调参

**如果岸浪"看起来不对"**：
- 95% 是 `wc3_shore_foam.gdshader` 的 `alpha_mode` / `tex_rate` 调参
- 4% 是 `Wc3ShorelineBuilder` 发射点位置（PE2 邻接判定）
- 1% 是 `Wc3WaterMesh` 几何

**vibecoding 时**：先按 [WATER.md](../water/WATER.md) 路线调美术参数；不行再改算法。
