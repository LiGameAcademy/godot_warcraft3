# HiveWE 的地形网格（TerrainMesh）

> 高度场布局、corner/cell 区分、脏矩形、PathingRect 转换。

## 1. 核心数据结构

**`Map::terrain`**（[base/map/map.ixx:67](file:///D:/GameMaker/HiveWE/src/base/map/map.ixx)）

```cpp
class Terrain {
  public:
    int width;        // tilepoint 数（不是 tile 数）
    int height;       // tilepoint 数

    // SoA 平行数组，长度 = width * height
    std::vector<float> corner_height;        // [0, 1] 层内高度
    std::vector<u8>    corner_layer_height;  // [0, 15] 层高（0-14，clamp 15）
    std::vector<bool>  corner_water;         // 是否水面
    std::vector<float> corner_water_height;  // 水面高度
    std::vector<int>   corner_ground_texture;
    std::vector<u8>    corner_ground_variation;  // 0-31 加权变体
    std::vector<bool>  corner_cliff;             // 是否 cliff（4 角不等自动算）
    std::vector<int>   corner_cliff_texture;
    std::vector<u8>    corner_cliff_variation;
    std::vector<bool>  corner_ramp;              // 斜坡标志
    std::vector<bool>  corner_blight;            // 污染（亡灵的）
    std::vector<bool>  corner_boundary;          // 边界（深水不可建）

    // 总览
    static constexpr u8 min_ground_height = 0;
    static constexpr u8 max_ground_height = 15;  // clamp 到 15（HiveWE 笔刷端）
};
```

**关键**：
- `corner_*` 是 **tilepoint（顶点）级别**——不是 tile（格子）
- 一个 `tile` 由 4 个 corner 围成：`bl=ci(i,j), br=ci(i+1,j), tl=ci(i,j+1), tr=ci(i+1,j+1)`
- **重要发现**：`max_ground_height = 15`（不是 14！）—— HivEWE 笔刷 `clamp(0, 15)`，意味着允许中间态，clamp 在 14 是 Godot 端（`Wc3TerrainLogic.LAYER_MAX=14`）
- `corner_height` 是 [0, 1] **层内偏移**；实际渲染高度 = `corner_layer_height[ci] - 2 + corner_height[ci]`

## 2. 角 vs 格

| 概念 | 含义 | 笔刷类型 |
|------|------|----------|
| **Corner（角）** | tilepoint，顶点 = `ci(i, j)` | `Brush::Type::corner`（默认） |
| **Cell（格）** | 4 角围成的 tile = `[i, i+1] × [j, j+1]` | `Brush::Type::cell` |

**HiveWE 的 brush type 切换**（`[terrain_operators.cpp:638-645]`）：

```cpp
void CellOperator::set_operation_type(cell_operation operation) {
    cell_operation_type = operation;
    if (operation == add_boundary || operation == remove_boundary) {
        set_brush_type(Brush::Type::cell);   // 边界用 cell
    } else {
        set_brush_type(Brush::Type::corner);  // 水用 corner
    }
}
```

**索引函数**：

```cpp
// `[terrain.ixx]`（推测）
constexpr size_t ci(int i, int j) const { return j * width + i; }
```

## 3. 脏矩形：TerrainRect vs PathingRect

**两种分辨率**：
- **TerrainRect**：tilepoint 分辨率（与 `Map::terrain.width/height` 一致）
- **PathingRect**：pathing map 分辨率（4×4 tilepoint = 1 pathing cell；推测）

**互相转换**（`[terrain_operators.cpp:133]`）：

```cpp
// Terrain → Pathing（除 4，截断）
PathingRect area.to_pathing().adjusted(-2, -2, 2, 2);  // 高度算子返回
// Pathing → Terrain（乘 4）
TerrainRect area.to_terrain();
```

**每算子返回的 affected area**（pathing 分辨率）：

| 算子 | 返回 | 含义 |
|------|------|------|
| `HeightOperator::apply` | `area.to_pathing().adjusted(-2, -2, 2, 2)` | 上下左右各外扩 2（pathing 分辨率） |
| `TextureOperator::apply` | `area.to_pathing().adjusted(-2, -2, -2, -2)` | 仅左上扩 2（猜测） |
| `CliffOperator::apply_cliffs` | `expanded_area.to_pathing()` | 整个 expanded_area |
| `CliffOperator::apply_ramps` | `modified_area.to_pathing().adjusted(-4, -4, 0, 0)` | 左上扩 4 |
| `CellOperator::apply` | corner 模式 `adjusted(-2, -2, -2, -2)` / cell 模式原样 | 看 brush type |

**外扩的目的**：邻接区域（如 cliff 邻接、texture 接缝）需要重算。

## 4. Cliff 判定（**重要算法**）

**4 角不等就标 cliff**（`[terrain_operators.cpp:302-304]`）：

```cpp
const size_t bl = ci(i, j);
const size_t br = ci(i + 1, j);
const size_t tl = ci(i, j + 1);
const size_t tr = ci(i + 1, j + 1);

corner_cliff[bl] = (layer_height[bl] != layer_height[br])
                || (layer_height[bl] != layer_height[tl])
                || (layer_height[bl] != layer_height[tr]);

if (corner_cliff[bl]) {
    corner_blight[bl] = corner_blight[br] = corner_blight[tl] = corner_blight[tr] = false;
}
```

**注意**：
- `corner_cliff` 用**单个 corner**（`bl`）做 cell 索引——和 ground mesh 的 cell 概念错位
- bl 是 4 角的**左下** corner；如果它跟其他 3 角不等，整个 cell 算 cliff
- 同时**清 4 角的 blight**（亡灵的污染不该跨到 cliff）

## 5. 平滑算法（3×3 卷积）

**`[terrain_operators.cpp:78-96]`**：

```cpp
auto smooth_height = [&](int i, int j, float current_height, auto height_vector, auto get_corner_height) {
    float accumulate = 0;
    TerrainRect acum_area = TerrainRect(i - 1, j - 1, 3, 3).intersected({0, 0, width, height});
    for (k, l) in acum_area:
        if ((k < i || l < j) && 边界检查) {
            accumulate += height_vector[(k - area.x()) * area_h + (l - area.y())];  // 用 area snapshot
        } else {
            accumulate += get_corner_height(k, l);  // 用 terrain 实时值
        }
    accumulate -= current_height;
    return 0.97f * current_height + 0.03f * (accumulate / (acum_area.width() * acum_area.height() - 1));
};
```

**关键**：
- **`0.97 * self + 0.03 * (sum / 8)`**——经典卷积，每帧只动 3%，所以平滑是"软"的（动画感）
- **`height_vector` 是 area 的 snapshot**——同 area 顶点用 snapshot（避免"当前修改影响其他顶点"）
- **其它 area 的顶点用 `get_corner_height` 实时值**——避免跨 area 不一致

**为什么需要 snapshot**：平滑算子"先全部算好再写回"才能保持一致；不 snapshot 就会出现"已经平滑过的又被平滑"的偏置。

## 6. 笔刷生命周期（关键观察）

**`apply_begin` 一次性快照整个 heightfield**（`[terrain_brush.cpp:153-162]`）：

```cpp
map->world_undo.new_undo_group();
old_corners_width = width;
old_corners_height = height;
old_corners.resize(width * height);
for (j = 0; j < height; j++) {
    for (i = 0; i < width; i++) {
        old_corners[j * width + i] = terrain.get_corner(i, j);
    }
}
old_pathing_cells_static = map->pathing_map.pathing_cells_static;
```

**`get_corner` 是 Corner 类的拷贝**（推测包含 height/layer/water/...）

**这意味着**：
- ✅ 一次笔划期间所有修改都能 undo（无论改多广）
- ❌ 内存：`width * height * sizeof(Corner)` —— 64×64 地图约 64K Corner ≈ 0.5MB
- ❌ 时间：每笔划 O(width × height) 拷贝

**新版还加了 doodad 快照**（`[terrain_brush.h:71-72]`）：

```cpp
std::vector<Doodad> pre_change_doodads;
std::map<int, Doodad> post_change_doodads;
```

这是 `change_doodad_heights` 的支撑。

## 7. `change_doodad_heights`（**关键灵感**）

**`[terrain_brush.h:28]`**：

```cpp
bool change_doodad_heights = true;
```

**开启时**（推测 `terrain_brush.cpp` 的 `apply_end`）：

```cpp
if (brush->change_doodad_heights) {
    // 对 updated_area 内的 doodad 重算 Y
    for (doodad) if (in_updated_area(doodad)) {
        doodad.position.z = terrain.interpolated_height(doodad.position.x, doodad.position.y);
        doodad.update();
    }
}
```

**意义**：改地形时，**装饰物自动贴合新地形**——不用手动一个个调。

**对应到 ROADMAP**：§⑩ 应用高度（待实现）。

## 8. 关键常量

| 常量 | 值 | 含义 |
|------|-----|------|
| `Terrain::min_ground_height` | `0` | 最小层高 |
| `Terrain::max_ground_height` | `15` | 最大层高（注意 0-15，Godot 端用 0-14） |
| `CellOperator::WATER_GROUND_ZERO` | `0.7f` | 水面到地表基准偏移 |
| `CellOperator::WATER_HEIGHT` | `0.25f` | 默认 add_water 水位 |
| `Brush::Type` | `corner` / `cell` | 笔刷模式 |

## 9. 对应到 godot_warcraft3

| HiveWE | godot_warcraft3 | 评价 |
|--------|----------------|------|
| `terrain.width/height` | `Wc3Heightfield.width/height` | ✅ 1:1 |
| `corner_height[]` | `Wc3Heightfield.heights[]` | ✅ 1:1（都是 SoA） |
| `corner_layer_height[]` | `Wc3Heightfield.layer_heights[]` | ✅ 1:1 |
| `corner_water[]` + `corner_water_height[]` | `Wc3Heightfield.water_heights[]`（合并为单数组） | ⚠️ 拆分不直观（但更省） |
| `corner_ground_texture[]` | `Wc3Heightfield.ground_textures[]` | ✅ 1:1 |
| `corner_ground_variation[]` | `Wc3Heightfield.ground_variations[]` | ✅ 1:1 |
| `corner_cliff[]` | **未独立存**——`Wc3CliffLogic` 现算 | ⚠️ 4 角不等逻辑应该在数据层 |
| `corner_cliff_texture[]` | `Wc3Heightfield.cliff_textures[]` | ✅ 1:1 |
| `corner_cliff_variation[]` | `Wc3Heightfield.cliff_variations[]` | ✅ 1:1 |
| `corner_ramp[]` | `flags_packed[]` (FLAG_RAMP=4) | ⚠️ 合 flag（不好拆） |
| `corner_blight[]` / `corner_boundary[]` | **未实现** | ❌ 缺 |
| `ci(i, j)` 索引 | `Wc3Heightfield.index_at(ix, iy)` | ✅ 1:1 |
| `corner_height[bl] != corner_height[br] \|\| ...` 4 角不等 | `Wc3CliffLogic.is_cliff_tile` | ✅ 已实现 |
| `TerrainRect` / `PathingRect` | `MapDocument.dirty_min/max` | ⚠️ 简化为 2 个 Vector2i |
| `0.97 * self + 0.03 * neighbor` 平滑 | **未实现** | ❌ 缺（先 plateau） |
| 全 heightfield 快照 | `CAPTURE_RADIUS=3` 局部 | ❌ 不同 |
| `change_doodad_heights` | **未实现**（ROADMAP §⑩） | ❌ 缺 |
| `LAYER_MAX=14` | `LAYER_MAX=14` | ✅ 1:1 |
| **`max_ground_height=15` clamp** | `clamp(layer, 0, 14)` | ⚠️ 不一样——我们应该改 `15` 还是它改 `14`？ |

## 10. vibecoding 指导

### 10.1 cliff 4 角不等的判定应该在 Data 层

**当前**：`Wc3CliffLogic.is_cliff_tile(...)` 在 Logic 层算
**建议**：在 `Wc3Heightfield` 缓存 `corner_cliff[]`（写 layer 时同步），减少重复算

**改动**：
1. `Wc3Heightfield` 加 `cliffs: PackedByteArray`（同 SoA 长度）
2. `Wc3TileVertex.layer` setter 自动重算当前 cell 4 角的 cliff
3. 笔刷读 `cliffs[ci(ix, iy)]` O(1)

### 10.2 加 `corner_blight` / `corner_boundary`（污染 + 边界）

**步骤**：
1. `Wc3Heightfield` 加 `flags_packed` 扩展位（FLAG_BLIGHT / FLAG_BOUNDARY）
2. `Wc3TerrainLogic` 加 `set_blight` / `set_boundary`
3. `MapDocument` 加新笔刷类型

### 10.3 平滑算法（`Wc3TerrainLogic.smooth`）

**实现**：
```gdscript
# Wc3TerrainLogic.smooth(area)
# 3×3 卷积；0.97 self + 0.03 * sum / 8
# 必须先 snapshot area 的 heights 数组
```

**测试**：`selftest_terrain_logic.gd` 加平滑用例

### 10.4 应用高度（`change_doodad_heights`）

**完整路径**（见 [OPERATORS.md §6.4](OPERATORS.md)）：
1. `MapDoodadLayer.build(ctx)` 吃 Context
2. `MapDocument` 改 terrain 时算 `doodad_affected_rect`
3. `apply_end` 调 `doodads.apply_height_update(rect)`（插值高度）
4. `doodad_state_undo` 独立 undo

**预计工作量**：中等（独立模块，可单 PR）

### 10.5 脏矩形：4×4 pathing 分辨率

**我们现状**：`dirty_min/max` 是 tilepoint 级别
**建议**：加 `pathing_dirty_min/max`（用于 pathing 重算联动）

**当前没 pathing map**——可以缓做。
