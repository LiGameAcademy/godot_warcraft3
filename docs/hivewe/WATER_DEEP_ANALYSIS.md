# HiveWE 水体实现深度分析（浅水/深水/斜坡/Shader）

> **角色**：补 [WATER.md](WATER.md) 缺的 4 部分——浅水 vs 深水（CliffOperator
> 水操作）/ 水体与斜坡交互 / Water shader 完整对照 / 岸浪 PE2。
> **目标读者**：Claude Code vibecoding 时的领域参考。
> **对照源码**：`D:\GameMaker\HiveWE` —— `terrain_operators.cpp` + `terrain.ixx`
> + `data/shaders/water.{vert,frag}`。
> 最后更新：2026-07-31

---

## 1. HivEWE 水体的双层架构

HivEWE 水体操作分**两层**（互补，不重叠）：

| 维度 | CliffOperator（cliff 升降路径）| CellOperator（cell 标记路径）|
|------|------------------------------|-----------------------------|
| 入口 | `CliffOperator::apply` 8 档 operation | `CellOperator::apply` 6 档 operation |
| 浅水/深水 | ✅ **cliff_operation::shallow_water / deep_water**（line 210-227）| ❌ 无（只 add/remove water）|
| add_water / remove_water | ❌ 无 | ✅ cell_operation::add_water / remove_water |
| add_boundary / remove_boundary | ❌ 无 | ✅ cell_operation::add_boundary / remove_boundary |
| 触发场景 | 笔刷放在**高台 / 低地**（升降意图）| 笔刷放在**水面/地面**（toggle 意图）|
| 写 corner_water | ✅ 在 apply 循环里 | ✅ 在 apply 循环里 |
| 写 corner_water_height | ✅ `corner_layer_height[idx] - 1` / `corner_layer_height[idx]` | ✅ 用 `water_height`（已算好）|
| 重算 | `update_water(area)` + **可能 `upload_water_heights()`**（水操作立即）| `update_water(area)`（仅重建）|

**关键**：浅水/深水**只**在 CliffOperator 路径里——`apply_begin` 智能判定（看当前是否水），`apply` 主体写 flag + height。

---

## 2. CliffOperator 浅水/深水（HivEWE line 209-285）

### 2.1 `apply_begin` 智能定 layer_height

**`[terrain_operators.cpp:209-227]`**：

```cpp
switch (cliff_operation_type) {
    case shallow_water:
        if (!corner_water[center_idx]) {
            layer_height -= 1;          // 干地 → 浅水 = 降 1
        } else if (corner_final_water_height(center_x, center_y)
                   > corner_final_ground_height(center_x, center_y) + 1) {
            layer_height += 1;          // 深水 → 浅水 = 抬 1
        }
        break;
    case lower1:  layer_height -= 1;  break;
    case lower2:  layer_height -= 2;  break;
    case deep_water:
        if (!corner_water[center_idx]) {
            layer_height -= 2;          // 干地 → 深水 = 降 2
        } else if (corner_final_water_height(center_x, center_y)
                   < corner_final_ground_height(center_x, center_y) + 1) {
            layer_height -= 1;          // 浅水 → 深水 = 降 1
        }
        break;
    case ramp: case level: break;
}
layer_height = clamp(layer_height, 0, 15);
```

**含义**：
- **干地刷浅水** = 降 1（地形沉到浅水）
- **深水刷浅水** = 抬 1（地形上升到浅水）
- **干地刷深水** = 降 2（地形沉到深水）
- **浅水刷深水** = 降 1（再沉 1 到深水）

**`corner_final_water_height` / `corner_final_ground_height`** —— **HivEWE `terrain.ixx` 计算函数**：
```cpp
float corner_final_water_height(int x, int y) {
    return corner_water[x, y]
        ? corner_water_height[x, y] + corner_layer_height[x, y] - 2
        : corner_height[x, y] + corner_layer_height[x, y] - 2;
}
```

注意：corner_layer_height 在浅水/深水路径里**没改**（case ramp / level 跳过）—— water 高度 = water_height + 0（layer 不变）。

### 2.2 `apply` 主体水路径

**`[terrain_operators.cpp:267-285]`**：

```cpp
switch (cliff_operation_type) {
    case lower1/lower2/level/raise1/raise2:
        if (corner_water[idx] && brush->enforce_water_height_limits
            && corner_final_water_height(i, j) < corner_final_ground_height(i, j)) {
            corner_water[idx] = false;  // 水降到比地低 → 强制变干
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
```

**关键**：
- **浅水**：`corner_water_height = layer - 1`（水面在 ground 下方 1 层 ≈ -0.5 实际位置 + WATER_GROUND_ZERO 偏移）
- **深水**：`corner_water_height = layer`（水面在 ground 同高，但 layer 多 1 → 深）
- **enforce_water_height_limits** — `lower1/2/level/raise1/2` 路径下，水位低于地 → 强制变干（防止 z-fight）

### 2.3 老李现状

| 维度 | 老李 | 评价 |
|------|------|------|
| CliffOperator 浅水/深水路径 | ❌ 没拆 CliffOperator | 浅水/深水笔刷**未实现**（按 CLIFF.md §11 v2 项）|
| `Wc3CellOperator` 拆 | ❌ 没拆（合并在 `MapDocument.paint_water`）| v2 项 |
| `apply_begin` 智能 layer 判定 | ❌ 不可用（climb 不拆）| v2 项 |
| `corner_water_height = layer - 1` / `layer` 公式 | ❌ 未用 | CellOperator 路径用 `water_height`（已算好）|

**短期建议**（WATER.md §10 + 本文 §10）：**不实现** CliffOperator 水操作——老李只走 CellOperator 路径（`add_water / remove_water`），等用户明确要"升降 + 水"才做。

---

## 3. CellOperator 水操作（HivEWE line 546-636）

WATER.md §1-§4 已详细写。这里补**关键常量**和**判定函数**。

### 3.1 关键常量

**`[terrain_operators.h:131-135]`**：

```cpp
static constexpr float WATER_GROUND_ZERO = 0.7f;  // 水面到地表基准偏移
static constexpr float WATER_HEIGHT = 0.25f;      // 默认 add_water 水位
```

**含义**：
- `WATER_GROUND_ZERO` = 0.7：水面渲染层在地表上方 0.7 单位（防 z-fight 经验值）—— **整个 0.7 是"渲染层"概念**
- `WATER_HEIGHT` = 0.25：默认 `add_water` 把水位抬到 `ground + WATER_GROUND_ZERO + WATER_HEIGHT`（即地表上方 0.95）

**`water_above_ground` 判定**（`[terrain_operators.cpp:632-636]`）：
```cpp
bool water_above_ground(int corner_id) const {
    return corner_water_height[corner_id]
        > corner_layer_height[corner_id] - 2
        + corner_height[corner_id]
        + WATER_GROUND_ZERO;
}
```

**含义**：`water_height > ground_top + 0.7` 才算"可见水"（即水面真的渲染出来）—— 地下有水（`corner_water=true` 但 height 不够）不算。

### 3.2 `add_water` 双层水位（HivEWE L116-125）

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

**关键概念**：
- `corner_water[id] = true` 是"这块地是水域"（存盘标志）
- `corner_water_height[id]` 是"水面高度"（存盘值）
- "分层水位"：地下有水（flag=true, height<top+0.7）也算水域；新 `add_water` 抬到可见层

**对应 W3E 文件**：`corner_water` 标志 + `corner_water_height` 数组。

### 3.3 老李现状（按 WATER.md §9 表格）

| 维度 | 老李 | 评价 |
|------|------|------|
| `corner_water` flag | ✅ `Wc3Coords.FLAG_WATER = 1` | 1:1 |
| `corner_water_height` | ✅ `Wc3Heightfield.water_heights[]`（合并）| 拆得更省（HivEWE corner_water + corner_water_height，老李共用一个 `flags_packed` bit + 单独 water_heights 数组）|
| `WATER_GROUND_ZERO` / `WATER_HEIGHT` 常量 | ❌ 缺 | **WATER.md §10.1 建议加 `Wc3Coords`** |
| `water_above_ground` 判定 | ❌ 缺 | 同上 |
| `enforce_water_height_limits` | ⚠️ 在 `MapLoader` | ✅ |
| `apply_begin` 智能水判定 | ❌ 不可用 | CellOperator 拆出来才能用 |

---

## 4. 水体与斜坡交互

### 4.1 HivEWE `update_ground_heights` L912-946 入口 +0.5

**`[terrain.ixx:912-946]`**：

```cpp
// For each ramp entrance tile overlapping the area, set base + 0.5 for corners at the base level.
// Uses assignment so corners shared by multiple ramp tiles are written idempotently.
const TerrainRect tile_area = area.adjusted(-1, -1, 0, 0).intersected({0, 0, width - 1, height - 1});
for (int j = tile_area.y(); j < tile_area.y() + tile_area.height(); j++) {
    for (int i = tile_area.x(); i < tile_area.x() + tile_area.width(); i++) {
        const size_t bl = ci(i, j);
        const size_t br = bl + 1;
        const size_t tl = bl + width;
        const size_t tr = bl + width + 1;

        if (!(corner_ramp[bl] && corner_ramp[tl] && corner_ramp[br] && corner_ramp[tr])) continue;
        if (corner_layer_height[bl] == corner_layer_height[tr] && corner_layer_height[tl] == corner_layer_height[br]) continue;

        const int base = std::min({corner_layer_height[bl], corner_layer_height[br],
                                   corner_layer_height[tl], corner_layer_height[tr]});
        if (corner_layer_height[bl] == base) gpu_final_ground_heights[bl] += 0.5f;
        // ... 同样 br/tl/tr ...
    }
}
```

**关键**：
- **入口判定**：4 角都 `corner_ramp` + 对角层差不平（≠ 对角等高）
- **boost 范围**：层高 = 4 角 min 的角（低角）—— 半层抬高 `+= 0.5`
- **幂等**：多次写同一 idx，结果相同（用 assignment 不是 `+=`）
- **水无关**：**没看 corner_water**——水上的入口也 +0.5

**含义**：水下的入口格（ramp entrance + corner_water）也 boost——水面+0.5 与 ground+0.5 在水面 mesh 下方。

### 4.2 老李 `plan_entrance_height_boost`（已实现 L 凹陷/外角扩展）

**`wc3_ramp_collect.gd:587-629`**：扫所有 `is_entrance` + `_is_outer_corner_ramp_tile` + `_is_l_recess_entrance` 的格，对低角 +0.5。

**与 HivEWE 差异**：
- HivEWE 只认 4 旗齐经典入口
- 老李扩展 L 凹陷 + 外角未齐四旗

**HivEWE 不看 water**——老李也**没看**（`plan_entrance_height_boost` 没用 `flags_packed` 检查 FLAG_WATER）。**保持一致**。

### 4.3 `Wc3WaterMesh` "含斜坡格"语义

**`wc3_water_mesh.gd:40-44`**：

```gdscript
for iy in range(tp_h - 1):
    for ix in range(tp_w - 1):
        # HiveWE：不因 ramp 跳过；斜坡/崖下也要有水面，避免岸边直角硬切
        if not has_water_flag(flags, tp_w, ix, iy):
            continue
        cell_count += 1
        # ...
```

**含义**：
- 水面 mesh **不**跳过 ramp corner
- 斜坡/崖下也有水面 mesh（4 角任一 FLAG_WATER）
- z-order：水 < 坡 < 崖 —— 水面在坡 mesh 下方（depth test 控制）

**这与 HivEWE `water.vert` L43-46 一致**：
```glsl
bool is_water = water_exists[quad_pos.y * map_size.x + quad_pos.x] > 0u
             || water_exists[quad_pos.y * map_size.x + quad_pos.x + 1] > 0u
             || water_exists[(quad_pos.y + 1) * map_size.x + quad_pos.x] > 0u
             || water_exists[(quad_pos.y + 1) * map_size.x + quad_pos.x + 1] > 0u;
gl_Position = is_water ? MVP * vec4(pos, water_height, 1) : vec4(2,0,0,1);
```

老李 vs HivEWE 1:1 对照。

### 4.4 深度色（`Wc3WaterParams.depth_color` vs HivEWE `water.vert` L54-61）

**老李**（GDScript，CPU 算）：
```gdscript
static func depth_color(depth_tiles, smin, smax, dmin, dmax) -> Color:
    var value := clampf(depth_tiles, 0.0, 1.0)
    if value <= DEEP_LEVEL:           # DEEP_LEVEL = 64/128
        var t := maxf(0.0, value - MIN_DEPTH) / (DEEP_LEVEL - MIN_DEPTH)  # MIN_DEPTH = 10/128
        return smin.lerp(smax, t)
    var t2 := clampf(value - DEEP_LEVEL, 0.0, MAX_DEPTH - DEEP_LEVEL) / (MAX_DEPTH - DEEP_LEVEL)  # MAX_DEPTH = 72/128
    return dmin.lerp(dmax, t2)
```

**HivEWE**（GLSL，GPU 算）：
```glsl
float value = clamp(water_height - ground_height, 0.f, 1.f);
if (value <= deeplevel) {            // deeplevel = 64/128
    value = max(0.f, value - min_depth) / (deeplevel - min_depth);  // min_depth = 10/128
    Color = shallow_color_min * (1.f - value) + shallow_color_max * value;
} else {
    value = clamp(value - deeplevel, 0.f, maxdepth - deeplevel) / (maxdepth - deeplevel);  // maxdepth = 72/128
    Color = deep_color_min * (1.f - value) + deep_color_max * value;
}
```

**完全等价**。**关键常量**：
- `MIN_DEPTH = 10/128`（≈ 0.078）—— 浅水起点
- `DEEP_LEVEL = 64/128`（= 0.5）—— 浅→深切换点
- `MAX_DEPTH = 72/128`（≈ 0.563）—— 深水饱和

老李 1:1 翻译 HivEWE GLSL 到 GDScript（CPU 算），传到顶点色，shader 不再算。

---

## 5. Water shader 完整对照

### 5.1 HivEWE `water.vert` / `water.frag`

**`[data/shaders/water.vert:39-64]`**：
```glsl
void main() {
    ivec2 quad_pos = ivec2(gl_InstanceID % map_size.x, gl_InstanceID / map_size.x);
    
    bool is_water = (water_exists[自己 + 3 邻]) 任一 > 0;
    UV = vec2(position[gl_VertexID].x, 1.f - position[gl_VertexID].y);
    
    ivec2 height_pos = position[gl_VertexID] + quad_pos;
    float water_height = water_heights[height_pos] + water_offset;
    float ground_height = cliff_levels[height_pos];
    
    // 深度色（浅/深）
    float value = clamp(water_height - ground_height, 0.f, 1.f);
    if (value <= deeplevel) { ... } else { ... }
    
    gl_Position = is_water ? MVP * vec4(pos, water_height, 1) : vec4(2, 0, 0, 1);
}
```

**`[data/shaders/water.frag:12-14]`**：
```glsl
void main() {
    outColor = texture(water_textures, vec3(UV, current_texture)) * Color;
}
```

**关键**：
- **CPU 切帧**：`current_texture` uniform，每帧 CPU 改（不在 shader 内 `TIME * tex_rate`）
- **几何**：6 顶点 quad（triangle strip × 2 triangle），instanced by `gl_InstanceID`
- **is_water 丢弃**：`vec4(2,0,0,1)` 投到 viewport 外（>= 1.0 NDC）

### 5.2 老李 `wc3_water.gdshader`（26 行）

```glsl
shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, fog_disabled;

uniform sampler2DArray water_frames : source_color, filter_linear_mipmap, repeat_enable;
uniform int frame_count = 1;
uniform float tex_rate = 15.0;

varying vec4 v_depth_color;

void vertex() {
    v_depth_color = COLOR;  // 顶点色（CPU 算好的深度色）
}

void fragment() {
    float frames = max(float(frame_count), 1.0);
    float idx = floor(mod(TIME * tex_rate, frames));  // GPU 切帧
    vec4 tex = texture(water_frames, vec3(UV, idx));
    vec4 c = tex * v_depth_color;
    ALBEDO = c.rgb;
    ALPHA = c.a;
}
```

**关键差异**：

| 维度 | HivEWE | 老李 |
|------|--------|------|
| 切帧 | CPU uniform `current_texture` | **GPU `TIME * tex_rate`** |
| 几何 | 6 顶点 quad，instanced | ArrayMesh（`Wc3WaterMesh.build`）|
| 深度色 | GLSL 内算 | CPU 顶点色 |
| 渲染模式 | 默认 GLSL | `unshaded, blend_mix` |
| 顶点 UV | 手动算 | 引擎 `UV`（多 mesh 拼接）|
| 废弃 cell | `vec4(2,0,0,1)` 投到外 | **跳过 `continue`**（不 emit 顶点）|
| 0.04 抬升防 z-fight | ❌ | ❌（靠 shader blend）|

**GPU 切帧踩坑**：`TIME * tex_rate` 直接用秒，老李注释 "不要再 /60"——**之前**可能是"按帧累加"写法（viewer 每帧 +=texRate/60）—— 老李**确认** GDScript 端是 GPU 切秒。

**评价**：老李实现**完全合理**——HivEWE CPU 切是"engine 不支持自动切帧"的老做法；Godot 4 shader 端用 `TIME * tex_rate` 更简洁。

### 5.3 老李 `wc3_shore_foam.gdshader`（PE2 岸浪）

**`[assets/shaders/wc3_shore_foam.gdshader]`**：

```glsl
shader_type spatial;
render_mode cull_disabled, unshaded, blend_add, depth_draw_never, fog_disabled;

uniform sampler2D foam_albedo : source_color, filter_linear, repeat_disable;
uniform float life_span = 4.5;
uniform float speed_mps = 0.30;
uniform vec3 scale_mps = vec3(0.30, 0.80, 0.70);
uniform vec3 alpha_seg = vec3(0.0, 1.0, 0.0);
uniform float time_middle = 0.5;
uniform float keep_tint = 0.35;

varying float v_alpha;
varying float v_life_t;

void vertex() {
    float phase = INSTANCE_CUSTOM.x;
    float speed_mul = INSTANCE_CUSTOM.y > 0.01 ? INSTANCE_CUSTOM.y : 1.0;
    float scale_mul = INSTANCE_CUSTOM.z > 0.01 ? INSTANCE_CUSTOM.z : 1.0;
    
    float t = fract(TIME / max(life_span, 0.001) + phase);
    float age = t * life_span;
    v_life_t = t;
    
    float sc, a;
    if (t < time_middle) {
        float f = t / max(time_middle, 0.001);
        sc = mix(scale_mps.x, scale_mps.y, f);
        a = mix(alpha_seg.x, alpha_seg.y, f);
    } else {
        float f = (t - time_middle) / max(1.0 - time_middle, 0.001);
        sc = mix(scale_mps.y, scale_mps.z, f);
        a = mix(alpha_seg.y, alpha_seg.z, f);
    }
    sc *= scale_mul;
    v_alpha = a;
    
    VERTEX.x *= sc;
    VERTEX.z *= sc;
    VERTEX.z += speed_mps * speed_mul * age;  // 岸浪向岸推进
    VERTEX.y += 0.04;  // 防 z-fight
}

void fragment() {
    vec4 tex = texture(foam_albedo, UV);
    float mask = tex.a;
    if (mask * v_alpha < 0.004) discard;
    float lum = max(tex.r, max(tex.g, tex.b));
    vec3 rgb = mix(vec3(lum), tex.rgb, keep_tint);
    // Additive: src.rgb * src.a + dst → 预乘 + blend_add(ONE, ONE)
    float a = mask * v_alpha;
    ALBEDO = rgb * a;
    ALPHA = 1.0;
}
```

**关键**：
- **`blend_add, depth_draw_never`** —— Additive 混合 + 不写 depth（避免粒子互相遮挡）
- **`INSTANCE_CUSTOM`** —— per-instance phase + speed + scale（HivEWE ParticleEmitter2 equivalent）
- **生命周期**：`TIME / life_span + phase` → 0..1 → `alpha_seg` 三段（start/middle/end，PE2 默认 0,1,0）
- **scale_mps** —— 三段 XZ 缩放（start/middle/end）
- **0.04 抬升** —— 防止 z-fight 经验值
- **预乘 + blend_add(ONE,ONE)** —— `ALBEDO = rgb * a; ALPHA = 1.0` 等价于 HivEWE `glBlendFunc(SRC_ALPHA, ONE)`

### 5.4 HivEWE ParticleEmitter2 等价

HivEWE 没有单独的 `shore.gdshader`——岸浪用 ParticleEmitter2 模型（PE2）。**老李的 `Wc3ShorelineBuilder.collect_foam_placements` + `wc3_shore_foam.gdshader` + MultiMesh** 是 GDScript 端的 PE2 等价实现。

**`Wc3ShorelineBuilder` 注释**（line 1-10）：
```
## 官方自动岸浪放置点：直边 (S) / 外角 (OC) / 内角 (IC)
## + WavesDepth 等深线（深→浅），水道中间对向泡沫 ≈ 激流感。
##
## 偏移分流（同一套 Shoreline，不是两套特效）：
##   cliff  — 悬崖岸：统一中等 inset（略偏水面，躲开崖 mesh）
##   ramp   — 斜坡岸：可向岸拉近
##   shore  — 平缓岸：可向岸拉近
##   contour— 等深线：固定 inset，与崖岸无关（水道中间那层）
```

**5 类发射点 + 4 类 inset**——已超过 HivEWE 0.3 旧版的简版（只有 cliff/shore 两类）。

**WAVES_DEPTH_WC3 = 25** —— 等深线检测深度（`waterH - groundH = 25` 单位时放 contour 泡沫）—— **没有** HivEWE 直接对应（HivEWE 0.3 PE2 配置是 SLK 表，源码里看不到硬编码值）。

---

## 6. 关键常量对照（HivEWE ↔ 老李）

| 常量 | HivEWE 值 | 老李位置 | 老李值 | 评价 |
|------|----------|---------|-------|------|
| `WATER_GROUND_ZERO` | 0.7 | `Wc3Coords` | ❌ 缺 | 建议加（[WATER.md §10.1](WATER.md)）|
| `WATER_HEIGHT` | 0.25 | `Wc3Coords` | ❌ 缺 | 同上 |
| `MIN_DEPTH` | 10/128 | `Wc3WaterParams.MIN_DEPTH` | 10/128 | ✅ 1:1 |
| `DEEP_LEVEL` | 64/128 | `Wc3WaterParams.DEEP_LEVEL` | 64/128 | ✅ 1:1 |
| `MAX_DEPTH` | 72/128 | `Wc3WaterParams.MAX_DEPTH` | 72/128 | ✅ 1:1 |
| `max_ground_height` | 15 | `Wc3TerrainLogic.LAYER_MAX` | 14 | ⚠️ 1 差（CLIFF.md §10）|
| `enforce_water_height_limits` | true | `MapLoader` | ⚠️ 推测有 | 待验证 |
| `WAVES_DEPTH_WC3` (老李扩展) | — | `Wc3ShorelineBuilder` | 25 | 老李 v2 扩展 |
| `INSET_*` (老李扩展) | — | `Wc3ShorelineBuilder` | 0.02~0.92 | 老李 v2 扩展 |

**关键**：HivEWE 浅水/深水 8 档 cliff_operation + 6 档 cell_operation，老李**只**实现 cell_operation 的 add/remove_water —— 浅水/深水（cliff_operation）是 v2 项。

---

## 7. minimap 水色（HivEWE L843-871）

**`[terrain.ixx:842-871]`**：

```cpp
if (corner_cliff[ci(i, j)] || (i > 0 && corner_cliff[ci(i - 1, j)]) || (j > 0 && corner_cliff[ci(i, j - 1)])
    || (i > 0 && j > 0 && corner_cliff[ci(i - 1, j - 1)])) {
    color = glm::vec4(128.f, 128.f, 128.f, 255.f);  // 灰 = 崖
} else {
    color = ground_textures[real_tile_texture(i, j)]->minimap_color;  // 普通地表
}

if (corner_water[ci(i, j)] && corner_final_water_height(i, j) > corner_final_ground_height(i, j)) {
    if (corner_final_water_height(i, j) - corner_final_ground_height(i, j) > 0.5f) {
        color *= 0.5625f;
        color += glm::vec4(0, 0, 80, 112);  // 深蓝
    } else {
        color *= 0.75f;
        color += glm::vec4(0, 0, 48, 64);   // 浅蓝
    }
}
```

**关键**：
- 优先崖（128 灰）→ 然后地表 → 然后水
- 水判 `corner_final_water_height > corner_final_ground_height`（即真的可见水）
- **深浅**：水位差 > 0.5 = 深（5625 + 深蓝），否则浅（75% + 浅蓝）

**老李 minimap**：在 `editor/resources/editor_environment.tres` —— 待查（vibecoding 之前补）。

---

## 8. vibecoding 指导

### 8.1 浅水/深水笔刷实现（如需）

如果用户要"升降 + 水"笔刷（一个操作同时改 layer + 加水/去水）：

1. **拆 `Wc3CliffOperator`**（WATER.md §10.2 / CLIFF.md §12.5）
2. 在 `apply_begin` 加 `shallow_water` / `deep_water` case：
   ```gdscript
   case shallow_water:
       if not hf.flags_packed[ci] & FLAG_WATER:
           target_layer -= 1
       elif corner_final_water_height(...) > corner_final_ground_height(...) + 1:
           target_layer += 1
       break
   ```
3. 在 `apply` 主体加：
   ```gdscript
   case shallow_water:
       flags_packed[ci] |= FLAG_WATER
       water_heights[ci] = layer_heights[ci] - 1
       break
   ```
4. 写 selftest 测"干地刷浅水"= 降 1 + FLAG_WATER + waterH = layer-1
5. **不要**在 CellOperator 里做——层级冲突

### 8.2 `Wc3Coords` 加水常量

```gdscript
const WATER_GROUND_ZERO := 0.7
const WATER_HEIGHT := 0.25
```

下游：
- `Wc3TerrainLogic.water_above_ground(ix, iy)` 用 `WATER_GROUND_ZERO`
- `Wc3WaterParams.default_water_height(ix, iy, hf)` 用 `WATER_GROUND_ZERO + WATER_HEIGHT`
- `wc3_water.gdshader` 加 uniform `water_offset = WATER_GROUND_ZERO + WATER_HEIGHT`（已通过 `height_offset_wc3` 隐式传）

### 8.3 minimap 水色补

如果老李 minimap 还没水色：
1. 跟地表 `real_tile_texture` 走（已对齐 HivEWE）
2. 在 `corner_water` + `water_above_ground` 时叠蓝（0,0,80,112 / 0,0,48,64）
3. **不要**在 `corner_water` flag 阶段叠——要 `water_above_ground`（避免地下水干扰）

### 8.4 水位-地面差异检查

`water_above_ground` 没实现 = CellOperator 智能 layer 判定不可用 + 强制变干不可用。
**临时**：
- `Wc3TerrainLogic.set_water(ix, iy, h)` 调用前自己检查 `h > hf.layer_heights[ci] - 2 + hf.heights[ci] + 0.7`
- 不可见水 → 仍写 flag（地下水域）但 height 不动

**长期**：WATER.md §10.1 加 `WATER_GROUND_ZERO` 常量 → 复用。

### 8.5 shore 调参（95% 美术）

老李 `wc3_shore_foam.gdshader` 已就位，调参顺序：
1. `Wc3ShorelineBuilder.collect_foam_placements` —— 发射点位置（PE2 邻接判定）
2. `Wc3ShorelineBuilder.INSET_*` —— 内缩距离
3. `Wc3ShoreFoam.material` —— 材质参数
4. `wc3_shore_foam.gdshader` `alpha_seg` / `tex_rate` / `keep_tint` —— 视觉调

跑 `selftest_shoreline.gd` 看哪些 case fail → 改对应阶段。

---

## 9. 对应到 godot_warcraft3

| HiveWE | godot_warcraft3 | 评价 |
|--------|----------------|------|
| `CliffOperator::apply_begin` 浅水/深水 | ❌ 未实现 | v2 项 |
| `CliffOperator::apply` 浅水/深水 case | ❌ 未实现 | v2 项 |
| `CellOperator` 4 种 operation | `MapDocument.paint_water` (单方法) | ⚠️ 简化 |
| `corner_water` flag | `Wc3Coords.FLAG_WATER = 1` | ✅ |
| `corner_water_height[]` | `Wc3Heightfield.water_heights[]` | ✅ 合并 `flags_packed` |
| `WATER_GROUND_ZERO = 0.7` | ❌ 缺 | WATER.md §10.1 |
| `WATER_HEIGHT = 0.25` | ❌ 缺 | 同上 |
| `water_above_ground` 判定 | ❌ 缺 | 同上 |
| `apply_begin` 智能 layer 判定 | ❌ | CellOperator 拆后才有 |
| `enforce_water_height_limits` | `MapLoader` (推测) | ✅ |
| `update_ground_heights` ramp entrance +0.5 | `plan_entrance_height_boost` + `apply_ramp_dig` | ✅ |
| `update_ground_heights` **不看 water** | `plan_entrance_height_boost` **不看 water** | ✅ 一致 |
| `Wc3WaterMesh` "含斜坡格" | 注释 + 实现 ✅ | ✅ |
| `depth_color` (HivEWE GLSL) | `Wc3WaterParams.depth_color` (GDScript) | ✅ 1:1 |
| `MIN_DEPTH/DEEP_LEVEL/MAX_DEPTH` | `Wc3WaterParams.MIN_DEPTH/DEEP_LEVEL/MAX_DEPTH` | ✅ 1:1 |
| `water.vert` `is_water` 4 角 OR | `Wc3WaterMesh.has_water_flag` | ✅ 1:1 |
| `water.vert` CPU 切帧 | `wc3_water.gdshader` GPU 切 `TIME * tex_rate` | ⚠️ 差异（实现合理）|
| `water.frag` `texture * Color` | `wc3_water.gdshader` `tex * v_depth_color` | ✅ 等价 |
| `ParticleEmitter2` 岸浪 | `Wc3ShorelineBuilder` + `Wc3ShoreFoam` + shader | ✅ 已超过 0.3 旧版 |
| `minimap_image` 水色 | 待查 | v2 项 |

---

## 10. 源码索引

| 主题 | HivEWE 文件 | HivEWE 符号 | 本仓库符号 |
|------|------------|------------|------------|
| 浅水/深水 apply_begin | `terrain_operators.cpp` | `CliffOperator::apply_begin` L209-227 | ❌ |
| 浅水/深水 apply | `terrain_operators.cpp` | `CliffOperator::apply` L267-285 | ❌ |
| 水关键常量 | `terrain_operators.h` | `WATER_GROUND_ZERO/WATER_HEIGHT` L131-135 | ❌（WATER.md §10.1 待加）|
| `water_above_ground` | `terrain_operators.cpp` | `CellOperator::water_above_ground` L632-636 | ❌ |
| CellOperator add/remove water | `terrain_operators.cpp` | `CellOperator::apply` L559-618 | `MapDocument.paint_water` |
| ramp entrance +0.5 | `terrain.ixx` | `update_ground_heights` L912-946 | `plan_entrance_height_boost` |
| `is_corner_ramp_entrance` | `terrain.ixx` | L819-831 | `_is_classic_entrance` + `_is_l_recess_entrance` |
| 水面 mesh | `terrain.ixx` + `water.vert/frag` | `is_water` 判定 + 深度色 | `Wc3WaterMesh` + `wc3_water.gdshader` |
| 深度色 11 行公式 | `water.vert` L54-61 | `min_depth=10/128, deeplevel=64/128, maxdepth=72/128` | `Wc3WaterParams` 常量 + `depth_color` |
| 岸浪 PE2 | `ParticleEmitter2` (`models/`) | `wc3_shore_foam.gdshader` 仿 | `Wc3ShorelineBuilder` + `Wc3ShoreFoam` |
| minimap 水色 | `terrain.ixx` | `minimap_image` L843-871 | 待查 |
| 本仓库实现 | — | — | `scripts/map/presentation/water/wc3_water_*.gd` |

---

## 11. 与 [WATER.md](WATER.md) 的关系

WATER.md（11.6KB，**已完成**）覆盖：
- §1-2 CellOperator 4 种 operation + brush_type 切换
- §3-4 apply_begin 智能水判定 + apply 主体
- §5 关键细节（add_water 双层水位 / cell vs corner / enforce）
- §6 update_water / upload_water_heights
- §7 Shore / 岸浪（PE2 近似）
- §8 关键常量（缺 WATER_GROUND_ZERO / WATER_HEIGHT）
- §9 对应到 godot_warcraft3
- §10 vibecoding 指导 6 条

**WATER.md 缺**（本文补）：
- 浅水/深水（CliffOperator 水操作 5 档升降的 2 档）— 本文 §2
- 完整 8 档 cliff_operation 双层架构 — 本文 §1
- 水体与斜坡：`update_ground_heights` L912-946 boost — 本文 §4.1
- shader 完整对照（HivEWE GLSL ↔ 老李 GLSL）— 本文 §5
- 关键常量扩展（MIN_DEPTH/DEEP_LEVEL/MAX_DEPTH / WAVES_DEPTH_WC3 / INSET_*）— 本文 §6
- minimap 水色（HivEWE 已有，老李缺）— 本文 §7
- vibecoding 8 条 — 本文 §8

**读本文 vs 读 WATER.md**：
- 浅水/深水 / shader / 水-斜坡 → **读本文**
- CellOperator / update_water / shore 实现 → 读 [WATER.md](WATER.md)
- 常量 / 决策表 → 两边对照
