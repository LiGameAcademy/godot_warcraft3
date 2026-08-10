# HiveWE 的悬崖（Cliff）

> CliffOperator 8 种操作、TAG 选型、跨层 clamp、4 角不等判定、HiveWE-vs-我们的算法对照。

## 1. 8 种操作（`cliff_operation`）

**`[terrain_operators.h:79-89]`**：

```cpp
enum class cliff_operation {
    lower2, lower1, level, raise1, raise2,  // 5 档升降（"-2" 到 "+2"）
    deep_water,                              // 深水
    shallow_water,                           // 浅水
    ramp                                     // 斜坡（独立路径）
};
```

**映射到我们的 `cliff_tool_id`（"0".."4"）**：

| 我们的 `cliff_tool_id` | HiveWE enum |
|------------------------|-------------|
| `"0"` | `lower2` |
| `"1"` | `lower1` |
| `"2"` | `level` |
| `"3"` | `raise1` |
| `"4"` | `raise2` |
| `ShallowWater` | `shallow_water` |
| `DeepWater` | `deep_water` |
| `Ramp` | `ramp` |

✅ 1:1 对应

## 2. `apply_begin` 智能定 target layer_height

**`[terrain_operators.cpp:209-241]`**：

```cpp
void CliffOperator::apply_begin(...) {
    const size_t center_idx = ci(center_x, center_y);
    layer_height = corner_layer_height[center_idx];  // 当前层
    cliff_index = cliff_type_to_id(cliff_id);          // 当前 cliff 类型

    switch (cliff_operation_type) {
        case shallow_water:
            if (!corner_water[center_idx]) {
                layer_height -= 1;                     // 干地 → 浅水 = 降 1
            } else if (corner_final_water_height > corner_final_ground_height + 1) {
                layer_height += 1;                     // 已经是深水 → 抬 1
            }
            break;
        case lower1:  layer_height -= 1;  break;
        case lower2:  layer_height -= 2;  break;
        case deep_water:
            if (!corner_water[center_idx]) {
                layer_height -= 2;                     // 干地 → 深水 = 降 2
            } else if (corner_final_water_height < corner_final_ground_height + 1) {
                layer_height -= 1;                     // 浅水 → 深水 = 降 1
            }
            break;
        case raise1:  layer_height += 1;  break;
        case raise2:  layer_height += 2;  break;
        case ramp: case level: break;                  // ramp/level 不动
    }
    layer_height = clamp(layer_height, 0, 15);         // 注意 max=15
}
```

**关键**：
- **水操作** 智能看当前是否水、干地 → 浅水 vs 深水自动算 target
- **`level` 不改 layer_height**（level 是"把周围都拉到当前高度"）
- **ramp 不改 layer_height**（ramp 在 `apply_ramps` 单独处理）

## 3. `apply_cliffs` 主体

**`[terrain_operators.cpp:244-329]`**：

```cpp
PathingRect CliffOperator::apply_cliffs(const TerrainRect& area, double frame_delta) {
    auto& terrain = map->terrain;
    const int width = terrain.width;
    const int height = terrain.height;
    const glm::ivec2 pos = brush->get_unclipped_pos();

    // 1. expanded_area = area + 1 tile 外扩（用于 4 角 cliff 判定）
    TerrainRect expanded_area = TerrainRect(area.x() - 1, area.y() - 1, area.width() + 1, area.height() + 1)
        .intersected({0, 0, width - 1, height - 1});

    for (i, j) in area:
        if (!brush->contains(...)) continue;

        const size_t idx = ci(i, j);
        corner_ramp[idx] = false;                     // 重置 ramp 标志
        corner_layer_height[idx] = layer_height;       // 写目标层高

        // 2. 水操作特殊处理
        switch (cliff_operation_type) {
            case lower1/lower2/level/raise1/raise2:
                if (corner_water[idx] && brush->enforce_water_height_limits
                    && corner_final_water_height(i, j) < corner_final_ground_height(i, j)) {
                    corner_water[idx] = false;         // 水降到比地低 → 强制变干
                }
                break;
            case shallow_water:
                corner_water[idx] = true;
                corner_water_height[idx] = corner_layer_height[idx] - 1;
                break;
            case deep_water:
                corner_water[idx] = true;
                corner_water_height[idx] = corner_layer_height[idx];
                break;
        }

        // 3. 邻接 clamp（递归）
        check_nearby(pos.x, pos.y, i, j, expanded_area);
    }

    // 4. 重算 cliff 标志
    expanded_area = expanded_area.intersected({0, 0, width - 1, height - 1});
    for (i, j) in expanded_area:
        const size_t bl = ci(i, j);
        const size_t br = ci(i + 1, j);
        const size_t tl = ci(i, j + 1);
        const size_t tr = ci(i + 1, j + 1);

        corner_cliff[bl] = (corner_layer_height[bl] != corner_layer_height[br])
                        || (corner_layer_height[bl] != corner_layer_height[tl])
                        || (corner_layer_height[bl] != corner_layer_height[tr]);

        // 5. 放 cliff 自动清 blight（4 角）
        if (corner_cliff[bl]) {
            corner_blight[bl] = corner_blight[br] = corner_blight[tl] = corner_blight[tr] = false;
        }
    }

    // 6. 重算
    TerrainRect tile_area = expanded_area.adjusted(-1, -1, 1, 1).intersected({0, 0, width - 1, height - 1});
    terrain.update_cliff_meshes(tile_area);
    terrain.update_ground_textures(expanded_area);
    terrain.update_ground_heights(expanded_area.adjusted(0, 0, 1, 1));
    terrain.update_water(tile_area.adjusted(0, 0, 1, 1));

    if (shallow_water || deep_water) {
        terrain.upload_water_heights();  // 立即上传 GPU（水操作立即生效）
    }

    return expanded_area.to_pathing();
}
```

## 4. `check_nearby` 跨层 clamp（**关键算法**）

**`[terrain_operators.cpp:376-404]`**：

```cpp
void CliffOperator::check_nearby(const int begx, const int begy, const int i, const int j, TerrainRect& area) const {
    TerrainRect bounds = TerrainRect(i - 1, j - 1, 3, 3).intersected({0, 0, terrain.width, terrain.height});

    for (l) for (k) in bounds:
        // 给 3×3 邻域所有 corner 写 cliff_texture
        corner_cliff_texture[ci(k, l)] = cliff_index;

        if (k == 0 && l == 0) continue;  // 跳过自己

        // 跨层检测：差 > 2 就 clamp 到 ±2
        int difference = corner_layer_height[ci(i, j)] - corner_layer_height[ci(k, l)];
        if (std::abs(difference) > 2 && !brush->contains(glm::ivec2(begx + (k - i), begy + (l - k)))) {
            corner_layer_height[ci(k, l)] = corner_layer_height[ci(i, j)] - std::clamp(difference, -2, 2);
            corner_ramp[ci(k, l)] = false;
            area.setX(std::min(area.x(), k - 1));
            area.setY(std::min(area.y(), l - 1));
            area.setRight(std::max(area.right(), k));
            area.setBottom(std::max(area.bottom(), l));

            check_nearby(begx, begy, k, l, area);  // 递归
        }
    }
}
```

**关键**：
- **3×3 邻域自动 clamp**——如果邻居层高差 > 2，把它拉回到 ±2 范围
- **递归传播**——一次拉低可能让邻居的邻居也超 2，递归处理
- **区域累积**——`area` 记录所有受影响的 corner，扩展 expanded_area
- **`!brush->contains(...)`** 跳过笔刷范围外（不污染）
- **HivEWE 比 0.3 旧版激进了**：0.3 旧版只标 4 角不等（更接近"自然"）
- **新版是为了"避免过陡"**：clamp 到 2 层是经典 WE 的可视安全范围

⚠️ **关键决策点**：是否 clamp 到 ±2？我们目前 `MAX_CLIFF_ADJ_DELTA=2`（[CLIFF.md §2.4](../cliff/CLIFF.md)），但只在"传播"时用，**`is_cliff_tile` 判断不等即 cliff**。HiveWE 新版直接在写 corner 时 clamp 邻居，更激进。

## 5. 4 角不等判定（**核心**）

**`[terrain_operators.cpp:302-304]`**：

```cpp
const size_t bl = ci(i, j);
const size_t br = ci(i + 1, j);
const size_t tl = ci(i, j + 1);
const size_t tr = ci(i + 1, j + 1);

corner_cliff[bl] = (corner_layer_height[bl] != corner_layer_height[br])
                || (corner_layer_height[bl] != corner_layer_height[tl])
                || (corner_layer_height[bl] != corner_layer_height[tr]);
```

**注意**：
- `corner_cliff[bl]` 用 `bl` 索引，但代表**整个 cell**（i, j）
- 任意一对不等就标 cliff
- bl 不必是 4 角中最低的——任意 4 角为索引都行（用 bl 是约定）

**这跟我们的 `Wc3CliffLogic.is_cliff_tile` 一致** ✅

## 6. 跨 cell 的层高比较

**关键问题**：判断 cliff 时只看**单 cell 内 4 角**。**跨 cell 的层高差怎么处理**？

**答案**：
- cliff 标志 = 4 角不等（cell 内）
- 跨 cell 层高差由 **mesh 渲染时** 处理（cliff 模型自动显示层差）
- 3×3 clamp 是限制**写**层高时的传播（不让单笔刷产生悬崖层差 > 2 的硬伤）

**渲染逻辑**（`update_cliff_meshes`，推测）：每个 cell 选一个 cliff GLB，instance 化到 4 角围成的位置；跨 cell 的层高差由邻接 cell 的 cliff GLB 自然过渡。

## 7. Cliff TAG 选型（**关键问题**）

⚠️ **HiveWE 新版源码没看到 `Terrain.cpp` 的 cliff 选型代码**（0.3 旧版的 `Terrain.cpp` 不可访问）

**推测的选型逻辑**（基于 `CliffTypes.slk` 字段 + 行为）：

```cpp
// 推测 [base/map/terrain.ixx] 中的 update_cliff_meshes
void update_cliff_meshes(TerrainRect area) {
    for (cell in area) {
        int bl = ci(cell.i, cell.j);
        // 1. 判断哪 4 角低，哪 4 角高
        bool hL = (layer_height[bl] > layer_height[br]);  // 左高
        bool hR = (layer_height[bl] < layer_height[br]);  // 右高
        // ... 4 角
        // 2. TAG 字符串拼 4 角状态（A=平, B=高, C=低）
        string tag = "CL" + string(bl_state) + string(br_state) + string(tl_state) + string(tr_state);
        // 3. 从 catalog 找 Cliffs{TAG}{var}.glb
        auto glb = catalog.resolve(cliff_id, tag, variation);
        // 4. instance 化
    }
}
```

**HiveWE 0.3 旧版的 TAG 字符串规则**（来自老李 docs/CLIFF.md 和 .cursor rule）：

| 字符 | 含义 |
|------|------|
| `A` | 平（与对侧同高） |
| `B` | 高（上升） |
| `C` | 低（下降） |
| `H` | 悬崖（hard cliff） |
| `L` | 斜坡（ramp） |
| `X` | 不可达（边界） |

**4 角顺序**（HiveWE 0.3）：`BL, TL, TR, BR`（从左下逆时针）

**注意**：`CliffTransCatalog` 角序是 `TL, TR, BR, BL`（与直崖 Cliffs 不同）—— 见 [data/PIPELINE.md §5](../../data/PIPELINE.md)

## 8. 跨层 cliff 叠段（`slices`）

老李的 `Wc3CliffLogic.cliff_slices_at`：

```gdscript
# 跨层 cliff 切多段
# 跨度 <= 2 → 单片
# 跨度 > 2 → 按 +2 叠段
```

**HiveWE 的对应**：**新版没有显式 "slice"**——它靠 `update_cliff_meshes` 自己处理（推测：用 layer 差自动选多段 GLB）

**0.3 旧版**：`slices` 是显式的（每段 +2 layer）；老李照搬了 0.3 的策略。

## 9. 异种崖策略 B

**老李的策略 B**（[CLIFF.md §2.4](../cliff/CLIFF.md)）：触及直崖格整格同化当前类型；远处隔离。

**HiveWE 新版的对应**：**没有这个概念**——`check_nearby` 3×3 clamp 是"邻接平滑"，不是"整格同化"。

⚠️ 策略 B 可能是老李 0.3 旧版的扩展，**不是**新版的标准行为。

## 10. 重要：`max_ground_height = 15` vs 我们 `LAYER_MAX = 14`

**HiveWE**：`clamp(0, 15)` 允许 15（HiveWE 笔刷端）
**我们**：`Wc3TerrainLogic.LAYER_MAX = 14`

**哪个对**？查 WC3 经典：

- W3E 文件 layer 字段是 u8（0-255），但实际只用 0-14
- 经典 WE 工具也 clamp 到 14
- 15 可能是 HivEWE 笔刷的"安全值"

**建议**：我们改 `LAYER_MAX = 14` 是对的，**但 HivEWE 的 15 是"边界外 1 格"，给 clamp 算法留余量**。可以学：在 `clamp` 时用 `clamp(0, 15)` 然后渲染时再 `if layer >= 15 layer = 14`。

或者更简单：保持 `LAYER_MAX=14`，笔刷不写到 15。

## 11. 对应到 godot_warcraft3

| HiveWE | godot_warcraft3 | 评价 |
|--------|----------------|------|
| 8 种 `cliff_operation` | `cliff_tool_id` 8 字符串 | ✅ 1:1 |
| `corner_cliff[bl]` 4 角不等 | `Wc3CliffLogic.is_cliff_tile` | ✅ 1:1 |
| `corner_cliff_texture[]` | `Wc3Heightfield.cliff_textures[]` | ✅ 1:1 |
| `corner_cliff_variation[]` | `Wc3Heightfield.cliff_variations[]` | ✅ 1:1 |
| `check_nearby` 3×3 clamp ±2 | `_propagate_cliff_adjacency` (`MAX_CLIFF_ADJ_DELTA=2`) | ✅ 思路同 |
| `corner_cliff[bl] != corner_cliff[br/tl/tr]` 仅 bl | `is_cliff_tile` 单 cell | ✅ |
| 跨 cell 层高差自动渲染 | `MapCliffLayer` 消费 `placements` | ✅ 拆得对 |
| 跨 cell `slices` (0.3) | `cliff_slices_at` (跨度>2 叠段) | ✅ 0.3 沿用 |
| 异种崖策略 B | `_sync_cliff_corner_textures` (策略 B) | ⚠️ 0.3 扩展 |
| `cliff_operation::ramp` 独立路径 | `Wc3CliffLogic` + `Wc3Ramp*Logic` 分开 | ✅ 我们拆得对 |
| 放 cliff 后清 4 角 blight | **未实现** | ❌ 缺 |
| `apply_begin` 智能水判定 | **未实现** | ❌ 缺 |
| `apply_end` 写 `TerrainUndoType::cliff` | `PaintStrokeCommand.affects_cliffs_water` | ✅ 1:1 |
| `clamp(0, 15)` | `clamp(0, 14)` | ⚠️ 不一样 |

## 12. vibecoding 指导

### 12.1 改 `Wc3CliffLogic.check_nearby` 学 HiveWE

**当前**：
```gdscript
# _propagate_cliff_adjacency：正交邻接差 ≤2；升则抬低邻到 high−2
# 仅 4 正交，不递归
```

**建议**（学 HiveWE）：
```gdscript
# 3×3 全邻域；递归
# 差 > 2 → clamp 到 ±2（不是 high-2）
# 累加 expanded_area（脏矩形）
```

**改动量**：~50 行（gdscript 比 cpp 短）+ 单测

### 12.2 加 `apply_begin` 智能水判定

**当前**：`cliff_tool_id` 直接走 paint
**建议**：
```gdscript
# Wc3CliffLogic.apply_begin(ix, iy, tool_id)
# tool_id == ShallowWater / DeepWater 时：
#   if !is_water(ix, iy): target_layer = current - 2/-1
#   elif is_deep(ix, iy): target_layer = current + 1
#   else: target_layer = current - 1
```

### 12.3 放 cliff 后清 4 角 blight

**步骤**：
1. `Wc3Heightfield` 加 `FLAG_BLIGHT = 2`
2. `Wc3CliffLogic.paint_cliff_corner` 写完 layer 后，调 `flags_packed[bl/br/tl/tr] &= ~FLAG_BLIGHT`

### 12.4 `clamp(0, 14)` vs `clamp(0, 15)`

**决策点**——老李你的看法：
- 方案 A：保持 14（跟 W3E 实际值）
- 方案 B：改 15（跟 HiveWE 笔刷一致），渲染时再 14
- 方案 C：`clamp(0, 14)` 但 `is_cliff_tile` 用 `<= 14` 不等

**个人建议**：A（最简单）。HivEWE 15 是历史包袱。

### 12.5 CliffOperator 拆 RampOperator（[OPERATORS.md §6.1](OPERATORS.md)）

**当前**：`Wc3CliffLogic` 同时管 cliff + ramp
**建议**：拆 `Wc3RampOperator`，cliff 不再走 ramp 路径

**改动量**：~200 行（`update_ramp` 整个搬走 + 新增 `Wc3RampOperator` 包装）
