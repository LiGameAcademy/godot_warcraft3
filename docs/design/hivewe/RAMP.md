# HiveWE 的斜坡（Ramp）

> `update_ramp` 完整算法、3-corner valid、L-corner center 补、对角线斜坡。**这是老李当前 `feature/ramp-rebuild` 工作的直接参考**。

## 1. 入口

**`[terrain_operators.cpp:331-369]`**：

```cpp
PathingRect CliffOperator::apply_ramps(const TerrainRect& area, double frame_delta) {
    auto& terrain = map->terrain;
    const int width = terrain.width;
    const int height = terrain.height;
    const glm::ivec2 pos = brush->get_unclipped_pos();
    const glm::vec3 mouse_pos = input_handler.mouse_world;

    TerrainRect modified_area = area;

    for (i, j) in area:
        if (!brush->contains(...)) continue;

        // create new ramps if possible
        int horizontal = (mouse_pos.x > i) - (mouse_pos.x < i);  // -1, 0, 1
        int vertical = (mouse_pos.y > j) - (mouse_pos.y < j);
        update_ramp(i, j, horizontal, vertical, modified_area);
    }

    TerrainRect viewport_area = modified_area.adjusted(-1, -1, 1, 1).intersected({0, 0, width - 1, height - 1});
    terrain.update_cliff_meshes(viewport_area);
    terrain.update_ground_textures(viewport_area);
    terrain.update_ground_heights(viewport_area);

    return modified_area.to_pathing().adjusted(-4, -4, 0, 0);
}

PathingRect CliffOperator::apply(...) {
    if (cliff_operation_type == cliff_operation::ramp) {
        return apply_ramps(area, frame_delta);
    } else {
        return apply_cliffs(area, frame_delta);
    }
}
```

**关键**：
- 鼠标位置决定斜坡方向（`horizontal`/`vertical` = -1/0/1）
- `mouse_pos.x > i` → `+1`（往右）；`<` → `-1`（往左）
- **调用一次 `update_ramp` 处理 1 个 corner 周围的斜坡**

## 2. `update_ramp` 完整算法（**最关键**）

**`[terrain_operators.cpp:406-544]`**——这是 vibecoding 的核心参照：

```cpp
void CliffOperator::update_ramp(const int i, const int j, int horizontal, int vertical, TerrainRect& rect) {
    // note: this function expects that horizontal and vertical are -1, 0 or 1
    auto& terrain = map->terrain;
    const int width = terrain.width;
    const int height = terrain.height;
    const size_t idx = ci(i, j);

    int origin_level = corner_layer_height[idx];
    int target_level = origin_level - 1;                          // 斜坡总是从 high 降到 high-1
    int cliff_tex = corner_cliff_texture[idx];

    bool allow_ramp_horizontal = horizontal != 0;
    bool allow_ramp_vertical = vertical != 0;
    bool allow_ramp_diagonal = allow_ramp_horizontal && allow_ramp_vertical;

    // === 1. valid lambda ===
    // 一个 corner 是 valid：边界内 + 已在 target_level
    auto valid = [&](int x, int y) {
        return x >= 0 && x < width && y >= 0 && y < height
            && corner_layer_height[ci(x, y)] == target_level;
    };

    // === 2. check_ramp_direction lambda ===
    // 检查一个方向（horizontal or vertical）的 3 corner 是不是都 valid
    auto check_ramp_direction = [&](int dir_x, int dir_y) -> bool {
        // bounds check - ramps take 3 corners
        if (i + 2 * dir_x < 0 || i + 2 * dir_x > width
            || j + 2 * dir_y < 0 || j + 2 * dir_y > height) {
            return false;
        }

        // 3 个 corner 都 valid
        for (step = 1; step <= 2; ++step) {
            if (!valid(i + step * dir_x, j + step * dir_y)) return false;
        }

        // perpendicular neighbours 不能更高（防止斜坡变悬崖）
        if (corner_layer_height[ci(i + dir_y, j + dir_x)] > origin_level
         || corner_layer_height[ci(i - dir_y, j - dir_x)] > origin_level) {
            return false;
        }

        // 紧贴反向 ramp 的禁止（避免斜坡穿越）
        for (side : {-1, 1}) {
            if (corner_ramp[ci(i, j + side)]
                && (!corner_ramp[ci(i + dir_x, j + side + dir_y)]
                    || !corner_ramp[ci(i + 2 * dir_x, j + side + 2 * dir_y)])) {
                return false;
            }
            if (corner_ramp[ci(i + side, j)]
                && (!corner_ramp[ci(i + side + dir_x, j + dir_y)]
                    || !corner_ramp[ci(i + side + dir_y, j + 2 * dir_y)])) {  // [疑 typo: j + side + 2*dir_y]
                return false;
            }
        }

        return true;
    };

    // === 3. 检查 3 种方向 ===
    allow_ramp_horizontal = check_ramp_direction(horizontal, 0);
    allow_ramp_vertical = check_ramp_direction(0, vertical);

    // 对角线：3x3 区域都 valid（origin + 8 邻居 in direction）
    for (dx = 0; dx <= 2 && allow_ramp_diagonal; ++dx) {
        for (dy = 0; dy <= 2 && allow_ramp_diagonal; ++dy) {
            if (dx == 0 && dy == 0) continue;
            if (!valid(i + dx * horizontal, j + dy * vertical)) {
                allow_ramp_diagonal = false;
            }
        }
    }

    // === 4. 放 valid 的 ramp ===
    if (allow_ramp_horizontal) {
        for (step = 0; step <= 2; ++step) {
            corner_ramp[ci(i + step * horizontal, j)] = true;
            corner_cliff_texture[ci(i + step * horizontal, j)] = cliff_tex;
        }
    }
    if (allow_ramp_vertical) {
        for (step = 0; step <= 2; ++step) {
            corner_ramp[ci(i, j + step * vertical)] = true;
            corner_cliff_texture[ci(i, j + step * vertical)] = cliff_tex;
        }
    }
    if (allow_ramp_diagonal) {
        for (dx = 0; dx <= 2; ++dx) for (dy = 0; dy <= 2; ++dy) {
            corner_ramp[ci(i + dx * horizontal, j + dy * vertical)] = true;
            corner_cliff_texture[ci(i + dx * horizontal, j + dy * vertical)] = cliff_tex;
        }
    }

    // === 5. 补 L-corner center piece ===
    // (H or D) && 右下角 valid && 自己+H+V 三段都 ramp → 补 center ramp
    if (allow_ramp_horizontal || allow_ramp_diagonal) {
        if (valid(i + horizontal, j + 1) && corner_ramp[ci(i, j)] && corner_ramp[ci(i + 1, j)]
            && corner_ramp[ci(i + 2, j)] && corner_ramp[ci(i, j + 1)]
            && corner_ramp[ci(i, j + 2)]) {
            corner_ramp[ci(i + horizontal, j + 1)] = true;
        }
        // ... 同样 for j - 1
    }
    if (allow_ramp_vertical || allow_ramp_diagonal) {
        // 同样 for i+1 / i-1
    }

    // === 6. 扩 modified_area ===
    rect = rect.adjusted(
        (allow_ramp_horizontal && horizontal < 0 || allow_ramp_diagonal && horizontal < 0) ? -2 : 0,
        ...);
}
```

## 3. 算法拆解

### 3.1 valid lambda 条件

```cpp
auto valid = [&](int x, int y) {
    return x >= 0 && x < width && y >= 0 && y < height
        && corner_layer_height[ci(x, y)] == target_level;
};
```

**含义**：候选 corner 必须已经在 `target_level = origin_level - 1`（即斜坡的"低侧"）

**为什么是 `==`**：斜坡只能在 2 个相邻层高之间放（不能跨 3 层）

### 3.2 check_ramp_direction（横向/纵向）

**3 段 corner**：
- 起点：i, j（已默认在 origin_level）
- 中间：i + dir_x, j + dir_y
- 终点：i + 2*dir_x, j + 2*dir_y

**所有 3 段都必须 valid**（即在 target_level）

**附加检查 1**：垂直方向的两个 corner 不能更高
```cpp
// 防止斜坡在 (i+1, j+1) 和 (i-1, j-1) 比 origin 高
if (corner_layer_height[ci(i + dir_y, j + dir_x)] > origin_level
 || corner_layer_height[ci(i - dir_y, j - dir_x)] > origin_level) return false;
```

**附加检查 2**：不能紧贴"反向 ramp"（同一 i 行 / 列）
```cpp
for (side : {-1, 1}) {
    if (corner_ramp[ci(i, j + side)]  // 同列已有 ramp
        && (!corner_ramp[ci(i + dir_x, j + side + dir_y)]
            || !corner_ramp[ci(i + 2 * dir_x, j + side + 2 * dir_y)])) {
        return false;
    }
}
```

**为什么**：避免 ramp 互相交叉/平行

### 3.3 对角线斜坡（diagonal）

**9 个 corner 全 valid**（origin + 8 个 in-direction corner）：

```cpp
for (dx = 0; dx <= 2; ++dx) {
    for (dy = 0; dy <= 2; ++dy) {
        if (dx == 0 && dy == 0) continue;
        if (!valid(i + dx * horizontal, j + dy * vertical)) {
            allow_ramp_diagonal = false;
        }
    }
}
```

**注意**：3×3 区域是 `(0..2, 0..2)`，不包含 `(0, 0)`（origin 本身）

### 3.4 L-corner center piece（**关键补丁**）

**问题**：水平 ramp 和垂直 ramp 会在 L-corner 出现"空洞"（corner 没标 ramp 但应该标）

**修复**：当特定条件满足时，自动标中间的 corner：

```cpp
if (allow_ramp_horizontal || allow_ramp_diagonal) {
    if (valid(i + horizontal, j + 1)         // 右下角 valid（在 target_level）
        && corner_ramp[ci(i, j)]            // 自己 ramp
        && corner_ramp[ci(i + 1, j)]        // 中间 ramp
        && corner_ramp[ci(i + 2, j)]        // 末尾 ramp
        && corner_ramp[ci(i, j + 1)]        // 垂直方向 1
        && corner_ramp[ci(i, j + 2)]) {     // 垂直方向 2
        corner_ramp[ci(i + horizontal, j + 1)] = true;  // 标 center
    }
    // ... 同样 for (i + horizontal, j - 1)  // 左下角
}
```

**含义**：当 L-corner 的 4 边都有 ramp 时，**自动补中间的 corner**——避免视觉空洞。

## 4. ramp 标志 vs cliff_texture

**`corner_ramp[idx] = true`** 同时 **写 `corner_cliff_texture[idx] = cliff_tex`**

**为什么**：ramp 沿用 cliff 的贴图（同 cliff type 渲染），但 `corner_ramp` 标志告诉渲染器"这是 ramp，不是硬 cliff"。

**对应到我们**：
- `flags_packed[ci] |= FLAG_RAMP` (FLAG_RAMP=4)
- `cliff_textures[ci]` 不变（保持 cliff 贴图）

## 5. 对应到 godot_warcraft3

**`Wc3RampPaint`（`scripts/map/logic/ramp/wc3_ramp_paint.gd`）**——老李当前在做的。

| HiveWE | godot_warcraft3 | 评价 |
|--------|----------------|------|
| `update_ramp(i, j, h, v, rect)` | `Wc3RampPaint.paint(ix, iy, h, v)` | ✅ 思路同 |
| `target_level = origin - 1` | `target = current - 1` | ✅ 1:1 |
| 3 corner 全 valid (h/v) | `Wc3RampLogic._check_ramp_3_points` | ✅ 1:1 |
| 9 corner valid (diagonal) | `Wc3RampLogic._check_ramp_diagonal` | ✅ 1:1 |
| perpendicular neighbours 不高 | `_check_perpendicular_neighbours` | ✅ |
| 紧贴反向 ramp 禁止 | **未实现** | ❌ 缺 |
| L-corner center 自动补 | **未实现** | ❌ 缺 |
| `corner_ramp[idx] = true` | `flags_packed[ci] \|= FLAG_RAMP` | ✅ 1:1（合并到 flags） |
| `corner_cliff_texture` 保留 | `cliff_textures[ci]` 不变 | ✅ 1:1 |
| `update_cliff_meshes(viewport)` | `MapCliffLayer.build(ctx)` | ✅ 拆得对 |
| 修改 `modified_area` 累积 | `MapRampLayer` 重算 | ⚠️ 我们没显式 dirty |
| mouse_pos 决定方向 | `paint_ramp` 参数 `axis: h/v/d` | ✅ 等价 |
| `apply_ramps` → `apply` 调度 | `Wc3CliffLogic` + `Wc3Ramp*Logic` 分开 | ✅ 拆得对 |

## 6. vibecoding 指导

### 6.1 实现 `update_ramp` 的完整算法

**当前进度**（推测，老李在 `feature/ramp-rebuild` 分支）：
- ✅ Paint 只写 `FLAG_RAMP`
- ✅ 3 corner valid（h/v）
- ✅ 9 corner valid（diagonal）
- ❌ 紧贴反向 ramp 禁止
- ❌ L-corner center 补
- ❌ dirty rect 累积

**建议实现**（按 HiveWE 算法）：

```gdscript
# Wc3RampPaint.paint(ix, iy, axis, var)
# 1. valid(x, y): in_bounds && layer == target
# 2. check_direction(dir_x, dir_y): 3 valid + perpendicular check + 紧贴反向 ramp check
# 3. check_diagonal(): 9 valid
# 4. write: flags_packed[ci] |= FLAG_RAMP
# 5. L-corner 补
# 6. dirty rect 累积
```

### 6.2 紧贴反向 ramp 检查

**逻辑翻译**：

```gdscript
for side in [-1, 1]:
    if flags_packed[ci(ix, iy + side)] & FLAG_RAMP:
        if not (flags_packed[ci(ix + dir_x, iy + side + dir_y)] & FLAG_RAMP) \
        or not (flags_packed[ci(ix + 2*dir_x, iy + side + 2*dir_y)] & FLAG_RAMP):
            return false
```

**注**：HiveWE 代码里有个疑似 typo（`j + side + 2*dir_y` 当 `dy` 是 horizontal 时）—— 实际跑应该用正确的 perpendicular 偏移。

### 6.3 L-corner center 补

**逻辑翻译**：

```gdscript
# allow_h or allow_diagonal, 下侧
if (valid(ix + h, iy + 1)
    and flags_packed[ci(ix, iy)] & FLAG_RAMP
    and flags_packed[ci(ix + 1, iy)] & FLAG_RAMP
    and flags_packed[ci(ix + 2, iy)] & FLAG_RAMP
    and flags_packed[ci(ix, iy + 1)] & FLAG_RAMP
    and flags_packed[ci(ix, iy + 2)] & FLAG_RAMP):
    flags_packed[ci(ix + h, iy + 1)] |= FLAG_RAMP

# 同样 for 上侧 (iy - 1) / 左侧 (ix - 1) / 右侧 (ix + 1)
```

**为什么必须**：不然 L 形转弯处会缺 1 格 ramp，视觉断开。

### 6.4 cliff vs ramp 互斥

**当前 `update_ramp` 不动 `corner_ramp` 之外的标志**——但需要注意：
- 放 ramp 不能与 cliff 冲突（4 角已 = target 不会触发 cliff）
- 但**邻接** 4 角如果层高 > target，可能触发 cliff（应该用 ramp 替代 cliff）

**HiveWE 不处理这个**——`update_cliff_meshes` 自动选 ramp 模型（因为 `corner_ramp=true` 优先）

**我们的 `Wc3CliffLogic.is_cliff_tile` 应该**：`is_ramp(ix, iy) ? false : is_4_corners_unequal(...)`——**ramp 优先于 cliff**

### 6.5 dirty rect（脏区局部重建）

**当前**：`Wc3RampPaint` 写完所有 ramp 后，由 `MapDocument.mark_dirty()` 全 heightfield 重建

**建议**（学 HiveWE）：
```gdscript
# Wc3RampPaint 维护 dirty rect
var dirty_min := Vector2i(INT_MAX, INT.MAX)
var dirty_max := Vector2i(INT.MIN, INT.MIN)
func _expand_dirty(ix, iy):
    dirty_min = Vector2i(min(dirty_min.x, ix), min(dirty_min.y, iy))
    dirty_max = Vector2i(max(dirty_max.x, ix), max(dirty_max.y, iy))
```

**为什么**：斜坡会传播到邻接 cell（romp），重建粒度应该至少 1 cell 外扩。

## 7. 测试覆盖

按 [RAMP_WE.md](../ramp/RAMP_WE.md) 的验收清单 + HiveWE 算法，建议加这些用例：

- [ ] 横/竖斜坡基础
- [ ] 对角线斜坡（3×3 9 corner）
- [ ] 紧贴反向 ramp 禁止
- [ ] L-corner center 自动补
- [ ] perpendicular neighbours 禁止
- [ ] cliff 邻接 ramp 互斥
- [ ] dirty rect 累积（多个 ramp 在不同位置）

可以照 `selftest_ramp_logic.gd` / `selftest_ramp_present.gd` 加新 case。
