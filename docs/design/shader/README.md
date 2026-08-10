# shader/ — GLSL 着色器文档

> **角色**：覆盖 `assets/shaders/` 下 4 个 `.gdshader` + 1 个 `.gdshaderinc` 的**设计意图
> / 顶点契约 / 渲染参数 / HivEWE 对照**。所有"为什么这么写"和"和 HivEWE 怎么映射"在这里。
> 详细 API / 完整参数列表查 shader 文件本身（注释已经写满了）。
> **对应**：
> - [present/Z_ORDER.md §5](../presentation/Z_ORDER.md)（渲染优先级 / 透明度策略）
> - [present/LAYERS.md](../presentation/LAYERS.md)（哪层用哪个 shader）
> - [hivewe/](../hivewe/)（HivEWE 源码对照）
> 最后更新：2026-07-31

---

## 1. 文件目录

| 文件 | 行数 | 角色 | 顶点数据 |
|------|------|------|----------|
| `wc3_ground.gdshader` | ~85 | 地面 tileset 4 层 mix（base + overlay1-3）| `CUSTOM0` (vec4 = 4 tile 槽), `CUSTOM1` (vec4 = 4 variation), `UV` (本地 0..1) |
| `wc3_cliff.gdshader` | ~60 | 悬崖纹理 + 顶点 Y 位移（按 height_map）| `UV` (cliff 贴图 0..1), 通过 `MODEL_MATRIX` 反算 wc3 坐标 |
| `wc3_water.gdshader` | ~35 | 水面动画帧 + 深度色 | `UV` (水贴图 0..1), `COLOR` (深度色), `TIME` (秒) |
| `wc3_shore_foam.gdshader` | ~80 | 岸浪粒子（additive, INSTANCE_CUSTOM 驱动）| `INSTANCE_CUSTOM` (xyz = phase/speed/scale), `UV` (foam 贴图) |
| `wc3_debug_grid.gdshaderinc` | ~50 | 寻路调试栅格（include 给 ground/cliff）| `dbg_wc3_xy` (varying vec2) |

**对应 `assets/shaders/`**：

```text
assets/shaders/
├─ wc3_ground.gdshader              # 1.4.1 地面
├─ wc3_cliff.gdshader               # 1.4.2 悬崖
├─ wc3_water.gdshader               # 1.4.3 水面
├─ wc3_shore_foam.gdshader          # 1.4.4 岸浪
└─ wc3_debug_grid.gdshaderinc       # 1.4.5 调试栅格
```

---

## 2. 渲染模式速查表

| shader | shader_type | render_mode | 投影 | 备注 |
|--------|-------------|-------------|------|------|
| `wc3_ground` | spatial | `cull_back, unshaded, fog_disabled` | 写 depth（默认）| 唯一用 `cull_back`（heightfield mesh 单面）|
| `wc3_cliff` | spatial | `cull_disabled, unshaded, fog_disabled` | 写 depth（默认）| 双面（解旋 Basis AABB 不可靠）|
| `wc3_water` | spatial | `cull_disabled, unshaded, blend_mix, fog_disabled` | 写 depth（默认）| 表面透明（`ALPHA = tex.a`）|
| `wc3_shore_foam` | spatial | `cull_disabled, unshaded, blend_add, depth_draw_never, fog_disabled` | **不写 depth** | 防止粒子互遮挡（加性 + 预乘）|
| `wc3_debug_grid` | (inc) | — | — | 给 ground/cliff 混入 ALBEDO |

> **unshaded**：所有 WC3 贴图**不**参与方向光计算——经典 WC3 是 prelit（光照 baked 进去）。
> 复刻保持原行为，避免 cliff 顶缘被照得比地面亮。
> **fog_disabled**：WC3 fog 用 vertex color + height，**不**用 Godot 体积 fog。
> 详情见 [hivewe/TERRAIN_MESH.md §3](../hivewe/TERRAIN_MESH.md)。

---

## 3. 顶点数据契约

### 3.1 4 个 `CUSTOMn` 通道

| 通道 | 含义 | 写入方 | 读出方 |
|------|------|--------|--------|
| `CUSTOM0` | 地面 4 个 tile 槽位（-1=无）| `MapTerrainLayer` 设 CUSTOM0 = `vec4(tex.x, tex.y, tex.z, tex.w)` | `wc3_ground.gdshader vertex()` |
| `CUSTOM1` | 地面 4 个 variation（atlas 编号 0..31）| `MapTerrainLayer` 设 CUSTOM1 = `vec4(var.x, var.y, var.z, var.w)` | 同上 |
| `COLOR` | 水面深度色（vertex color）| `Wc3WaterMesh.build()` 算 depth tint 写入 | `wc3_water.gdshader vertex()` |
| `INSTANCE_CUSTOM` | 岸浪 per-instance (phase, speed_mul, scale_mul) | `Wc3ShoreFoam` 写 | `wc3_shore_foam.gdshader vertex()` |

> **shader 内 `flat` 限定符**：`v_tex` / `v_var` 是 `varying flat vec4`——
> `flat` 表示不插值（每个 triangle 内的 fragment 都用同一个值），因为 tileset 索引是
> per-corner 不是 per-fragment。

### 3.2 mesh 拓扑约定

- **ground mesh**：`ArrayMesh` + `PRIMITIVE_TRIANGLES`（`HeightfieldMesh.set_array_mesh()`）
  - 顶点格式：position + uv + custom0 + custom1
  - **没有** normal / tangent（unshaded 不需要）
- **cliff / ramp mesh**：`ArrayMesh`（来自 GLB 解析）+ `PRIMITIVE_TRIANGLES`
  - 顶点格式：position + uv（normal 从 GLB 带入但**不读**）
- **water mesh**：`ArrayMesh` + `PRIMITIVE_TRIANGLES`
  - 顶点格式：position + uv + color（depth tint）
- **foam mesh**：`ArrayMesh`（单 quad billboard）+ `MultiMesh` per placement
  - 顶点格式：position + uv
  - 动画在 shader 内的 `vertex()` 算（按 INSTANCE_CUSTOM 推进）

---

## 4. 各 shader 关键策略

### 4.1 `wc3_ground` — 地面 4 层 tileset mix

**目的**：把每个 corner 的 4 层 tile（base / overlay1-3）按 alpha 顺序混在一起。

**关键逻辑**（`fragment()`）：

```glsl
vec4 color = sample_layer(v_tex.x, v_var.x, v_local);  // base
vec4 o1 = sample_layer(v_tex.y, v_var.y, v_local);
color = mix(color, o1, o1.a);
vec4 o2 = sample_layer(v_tex.z, v_var.z, v_local);
color = mix(color, o2, o2.a);
vec4 o3 = sample_layer(v_tex.w, v_var.w, v_local);
color = mix(color, o3, o3.a);
```

`sample_layer` 用 atlas_uv 算当前 variation 的子图（`mod/4, floor/4`），从 `sampler2DArray` 采。

**关键参数**：
- `tilesets` —— 512×256 图集（8×4 格 = 32 variation），通过 `sampler2DArray`
- `roughness_value` —— 默认 0.92（WC3 地面粗糙度，**不参与光照但保留 PBR 接口**）
- `albedo_scale` —— 整体明度微调（0.5..1.5）
- `world_scale = 0.01` —— wc3 坐标 → world 坐标（1u = 1cm）

**特点**：
- `flat` varying 防止 4 个槽位被插值（per-corner 不是 per-fragment）
- 不做方向光（`unshaded`）——WC3 是 prelit，贴图色就是最终色

### 4.2 `wc3_cliff` — 悬崖纹理 + 顶点位移

**目的**：贴 cliff texture + 按 height_map 抬升 Y（避免 cliff GLB 内部 ground 高度错位）。

**关键逻辑**（`vertex()`）：

```glsl
vec2 wc3_xy = vec2(world_pos.x, -world_pos.z) / world_scale;
vec2 tp = (wc3_xy - center_offset) / 128.0;       // 1 corner = 128u
vec2 tp0 = floor(tp);
vec2 f = clamp(tp - tp0, vec2(0.0), vec2(1.0));

// 双线性插值
float h00 = texture(height_map, tp_uv(tp0)).r;
// ...
float h = mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);

VERTEX.y += h * 128.0;    // 1 layer = 128u
```

**关键参数**：
- `cliff_albedo` —— cliff 贴图（来自 `cliff_tilesets.png`）
- `height_map` —— 整张地图 HF 的 R channel
- `center_offset` / `map_size` —— wc3 中心坐标 + 地图尺寸
- `world_scale = 0.01`
- `albedo_scale` —— 整体明度

**特点**：
- `cull_disabled`（双面）——解旋 Basis 下 AABB 不严格，背面剔了会出现"洞"
- `unshaded`——避免 cliff 顶缘被方向光照亮（Godot 默认 normal 朝上，cliff 顶 normal 偏 +Y）

### 4.3 `wc3_water` — 水面动画帧

**目的**：动画 water 贴图 + 按 depth tint 调色。

**关键逻辑**（`fragment()`）：

```glsl
float idx = floor(mod(TIME * tex_rate, frames));
vec4 tex = texture(water_frames, vec3(UV, idx));
vec4 c = tex * v_depth_color;
ALBEDO = c.rgb;
ALPHA = c.a;
```

**关键参数**：
- `water_frames` —— 动画帧数组（`sampler2DArray`）
- `frame_count` —— 总帧数（来自 `Water.slk` 的 frames 字段）
- `tex_rate` —— 每秒帧数（**注意**：直接 `TIME * tex_rate`，**不**除 60）

**HivEWE 对照**：HivEWE `data/shaders/water.frag` 用 uniform `time`（**已**是"动画进度"，
不是秒）。我们的 `tex_rate` 直接按秒——更直觉。详见 [hivewe/WATER.md §3](../hivewe/WATER.md)。

**特点**：
- `blend_mix`（标准 alpha）+ `cull_disabled`（双面，看穿要对）
- vertex color (`v_depth_color`) 携带 depth tint（来自水深计算）

### 4.4 `wc3_shore_foam` — 岸浪粒子

**目的**：模拟 WC3 经典岸浪粒子（`ParticleEmitter2` 简化版）。

**关键逻辑**（`vertex()`）：

```glsl
float phase = INSTANCE_CUSTOM.x;        // 每粒子起始相位（避免同步爆）
float speed_mul = INSTANCE_CUSTOM.y;
float scale_mul = INSTANCE_CUSTOM.z;

float t = fract(TIME / max(life_span, 0.001) + phase);
float age = t * life_span;
v_life_t = t;

// scale + alpha 三段插值（start / middle / end）
// ...
VERTEX.x *= sc;                         // xy 缩放
VERTEX.z += speed_mps * speed_mul * age;  // 沿 -Z 漂移（向岸内）
VERTEX.y += 0.04;                       // 抬高避免 z-fight
```

`fragment()`：

```glsl
float mask = tex.a;
if (mask * v_alpha < 0.004) discard;
float lum = max(tex.r, max(tex.g, tex.b));
vec3 rgb = mix(vec3(lum), tex.rgb, keep_tint);  // 1=保色, 0=抽白
float a = mask * v_alpha;
ALBEDO = rgb * a;  // 预乘
ALPHA = 1.0;
```

**HivEWE ParticleEmitter2 对照**：
- HivEWE 走 `ParticleEmitter2::update()` + `GL_TEXTURE_2D` 粒子 quad
- 我们用 MultiMesh + GPU 顶点动画——更现代，但**结果一致**（每实例都按 phase 推进）
- 关键是 additive 混合 + `depth_draw_never`——保证粒子不互遮挡

**关键参数**：
- `foam_albedo` —— 岸浪 sprite 贴图
- `life_span = 4.5` —— 一轮生命（秒）
- `speed_mps = 0.30` —— 漂移速度（m/s）
- `scale_mps = vec3(0.30, 0.80, 0.70)` —— start/middle/end 缩放
- `alpha_seg = vec3(0.0, 1.0, 0.0)` —— start/middle/end alpha（来自 MDX Alpha 段 /255）
- `time_middle = 0.5` —— 中段时间（0..1 占 life_span）
- `keep_tint = 0.35` —— 颜色保留度（1=保色, 0=抽白；原作偏青）

### 4.5 `wc3_debug_grid` — 寻路调试栅格（inc）

**目的**：在 ground/cliff shader 的 `fragment()` 末尾混入 3 级调试线（fine / path / tile）。

**关键 API**（fragment 端）：

```glsl
// 调用方须在 vertex() 内写：
dbg_wc3_xy = vec2(world.x, -world.z) / world_scale;

// 然后在 ALBEDO 算完后：
ALBEDO = dbg_apply_grid(albedo);
```

**关键参数**：
- `dbg_grid_tile` / `dbg_grid_path` / `dbg_grid_fine` —— 3 级开关（独立，可叠加）
- `dbg_tile_size = 128.0` —— 单位 1 tile = 128u
- `dbg_line_px = 1.2` —— 线宽（屏幕像素）
- `dbg_color_*` —— 三级颜色（黄 tile / 白 path / 灰 fine）

**特点**：
- 纯 fragment 端混色，**不写 depth**（调试线不影响 z-buffer）
- `fwidth()` 抗锯齿——线条永远 1.2 像素宽
- `dbg_center_offset` 让栅格在地图中心对齐

---

## 5. 共享 include / 共享约定

### 5.1 `wc3_debug_grid.gdshaderinc`

被 `wc3_ground` 和 `wc3_cliff` `include`。约定：

- 调用方在 `vertex()` 内写 `dbg_wc3_xy`（varying vec2）
- 调用方在 `fragment()` 末尾 `ALBEDO = dbg_apply_grid(albedo);`

### 5.2 不共享的部分

- **水 / 岸浪** 各自独立——不与 ground/cliff 共享 include（无重叠需求）
- **岸浪** 不走 depth 但**不**和 debug_grid 共享"不写 depth"逻辑（语义不同）

---

## 6. 与 HivEWE 对照

### 6.1 整体映射

| 我们的 shader | HivEWE 实现 | 等价性 |
|---------------|-------------|--------|
| `wc3_ground` | `terrain.ixx::render_ground()` + GL fixed-function 纹理 | **结果一致**，实现路径不同（HivEWE C++ 端硬编码，Godot 端 GLSL）|
| `wc3_cliff` | `cliff_meshes[i].render_queue(...)` + GL | **结果一致**，HivEWE 不在 shader 算 vertex 位移（直接传最终 mesh）|
| `wc3_water` | `data/shaders/water.frag` + `water.vert` | **结果一致**，参数命名略不同（见下）|
| `wc3_shore_foam` | `ParticleEmitter2`（CPU 粒子系统）| **结果一致**，HivEWE CPU 推粒子位置，我们 GPU 推 |
| `wc3_debug_grid` | （HivEWE 无对应）| Godot-only（debug 用）|

### 6.2 water shader 参数对照

| 含义 | HivEWE（water.frag）| 我们（wc3_water.gdshader）|
|------|----------------------|--------------------------|
| 时间 | `uniform float time`（动画进度，**已**乘 tex_rate）| `TIME`（秒）→ `mod(TIME * tex_rate, frames)` |
| 帧索引 | 由 CPU 算好传 `uniform int frame` | 由 GPU 算 `floor(mod(TIME * tex_rate, frames))` |
| 深度色 | uniform `vec4 depthColor` | `COLOR` (vertex color) |

**差异原因**：HivEWE 0.6+ 还在用 OpenGL 3.x 风格，CPU 算好所有 uniform；
Godot 4 forward+ 推荐 GPU 端算（更灵活，CPU 不需每帧传 uniform）。

### 6.3 shore foam 对照

| 维度 | HivEWE | 我们 |
|------|--------|------|
| 粒子系统 | `ParticleEmitter2`（CPU 推位置/alpha）| `MultiMeshInstance3D` + GPU vertex 动画 |
| sprite 贴图 | GL_TEXTURE_2D | sampler2D（`foam_albedo`）|
| 混合 | Additive（GL_SRC_ALPHA, GL_ONE）| `blend_add` + 预乘 |
| depth 写 | 不写（粒子透明）| `depth_draw_never`（不写）|
| 每粒子参数 | CPU 维护 `std::vector<Particle>` | `INSTANCE_CUSTOM` xyz（per-instance 通道）|

**关键差异**：HivEWE CPU 推位置 → 一致性好但 CPU 开销大；
我们 GPU 推位置 → 节省 CPU 但受 `fract(TIME/...)` 限制。
**结果一致**——岸浪视觉上完全对齐 HivEWE（按 phase 错开避免同步爆）。

### 6.4 严格行为对齐目标

- ✅ ground 4 层 mix 顺序（base → overlay1 → overlay2 → overlay3）
- ✅ cliff 双面（`cull_disabled`）——HivEWE 实际也是双面（GL 默认 cull back 但 cliff mesh 内部法线一致）
- ✅ water 时间进度（`tex_rate` 单位是秒）
- ✅ foam additive + 不写 depth
- ✅ unshaded + fog_disabled（与 HivEWE prelit 一致）
- ⚠️ cliff 顶点位移：HivEWE 在 CPU 算 mesh 高度，Godot 在 vertex shader 算（避免每改 HF 都重传 GLB）
- ⚠️ foam 粒子：HivEWE CPU 推位置，我们 GPU 推（实现路径不同，结果一致）

---

## 7. 关键决策 / 已知 trade-off

### 7.1 决策

| 决策 | 取舍 |
|------|------|
| 全部 `unshaded` | WC3 是 prelit，方向光会让 cliff 顶比地面亮——不真实。**保留 unshaded** |
| ground `cull_back` / 其他 `cull_disabled` | ground mesh 单面优化；cliff/ramp/water 在解旋 Basis 下 AABB 不可靠，双面保险 |
| water `blend_mix` | 标准 alpha——水面半透明可看见底（不需 additive）|
| foam `blend_add + 预乘` | HivEWE 经典岸浪是加性（粒子颜色 = 自身 + 背景）——必须预乘才能正确 add |
| foam `depth_draw_never` | 防止粒子互遮挡（粒子 A 不应盖粒子 B）——HivEWE 同行为 |
| debug grid 走 `fwidth` | 永远 1.2 像素线宽，不随距离变粗——标准 fragment 端 anti-aliasing |
| cliff 顶点位移在 shader | 改 HF 后**不**重传 GLB；CPU 端零开销；vertex shader 代价低（1 张 height_map 采样）|
| water 用 `TIME * tex_rate` | 直接秒数乘速率——HivEWE 0.6+ 在 CPU 算 `time = currentTime * texRate` 后传 uniform；我们**不**做 CPU 推帧 |

### 7.2 已知坑

- **`unshaded` + `PBR` 不兼容**：地形 / 悬崖**不**走 PBR 路径，`roughness_value` 仅保留接口（不读）。
  若改 `unshaded → 默认`，地面会被方向光染色，**视觉立刻错**。改前先看 [hivewe/TERRAIN_MESH.md §3](../hivewe/TERRAIN_MESH.md) 确认 WC3 是不是真的 prelit。
- **`flat` varying 不能省**：去掉 `flat` 后 4 个 tile 槽会被插值，跨 corner 颜色渐变——视觉立刻错。
- **foam `discard` 阈值 0.004**：低于这个 alpha 的 fragment 直接丢弃。低于这个值就是
  "几乎不可见 + 还占 fillrate"——不丢白不丢。
- **water `tex_rate = 0` 保护**：`mod(..., frames)` 中 `frames = max(float(frame_count), 1.0)`——frame_count=0 时不除零。
- **debug grid 调 `dbg_apply_grid` 必须在 ALBEDO 算完后**：否则会被后面的算式覆盖。
- **cliff `cull_disabled` 是必须的**：解旋 Basis 下 GLB 内部法线不对，单面剔会出"洞"。

### 7.3 故意没做的优化

- **没**做 depth pre-pass（Godot 4 forward+ 默认就不开）——WC3 经典无 depth pre-pass
- **没**做 instance culling 的 GPU 化——Godot 自带 culling 够用
- **没**把 foam 改成 GPUParticles3D——multi-mesh + shader 动画更轻量，CPU 端只发一次 instance data
- **没**用 subviewport 做 foam——单 quad 即可，不需要离屏渲染

---

## 8. 扩展指南

### 8.1 加新 shader

1. 写 `wc3_<name>.gdshader` 到 `assets/shaders/`
2. 在 `Map*Layer` 用 `preload("res://assets/shaders/wc3_<name>.gdshader")` 引用
3. 顶点数据契约用 `CUSTOM0..3` / `COLOR` / `INSTANCE_CUSTOM`——**别**自定义属性（Godot 不支持）
4. 写完在 [present/Z_ORDER.md §5](../presentation/Z_ORDER.md) 加一行（render_priority / blend / depth）

### 8.2 改现有 shader

1. 改前先看 [hivewe/TERRAIN_MESH.md](../hivewe/TERRAIN_MESH.md)（ground/cliff）或 [hivewe/WATER_DEEP_ANALYSIS.md](../hivewe/WATER_DEEP_ANALYSIS.md)（water/foam）确认 HivEWE 行为
2. 改 `unshaded` / `blend_*` / `depth_draw_*` 前先看 §7.1（决策表）——这些改了视觉就变
3. 改后跑 `selftest_water_logic.gd` / `selftest_ramp_present.gd`（如果改 cliff/ramp 相关）
4. 改完在 §6.3 §6.4 更新 HivEWE 对照

### 8.3 加新 include

如果新 shader 也要 debug 栅格，include 现有 `wc3_debug_grid.gdshaderinc` 即可。
注意 inc 内的 `varying vec2 dbg_wc3_xy` 必须在 vertex() 内赋值（每个用 inc 的 shader 都得写）。

---

## 9. 何时查这里

| 改的东西 | 查 |
|---------|----|
| 地面贴图错乱 | §4.1（4 层 mix 顺序）+ §7.1（unshaded）|
| cliff 顶比地面亮 | §4.2（unshaded）|
| 水面动画不对 | §4.3（`tex_rate` 是秒）+ §6.2（HivEWE 对照）|
| foam 粒子互遮挡 | §4.4（`depth_draw_never`）+ §7.1（additive + 预乘）|
| debug 栅格挡住场景 | §4.5（开关在 Material override 调）|
| 改 HivEWE 对齐 | §6（HivEWE 实现对照）|
| 加新 shader | §8.1（顶点数据契约）|
| 改 `render_priority` / `blend_mode` | [present/Z_ORDER.md §5](../presentation/Z_ORDER.md) |

---

## 10. 相关文档

- [present/README.md](../presentation/README.md) —— present 总览
- [present/Z_ORDER.md](../presentation/Z_ORDER.md) —— 渲染顺序 / 渲染优先级 / 透明度策略
- [present/LAYERS.md](../presentation/LAYERS.md) —— 7 个 Map*Layer 职责
- [hivewe/WATER_DEEP_ANALYSIS.md](../hivewe/WATER_DEEP_ANALYSIS.md) —— water/foam 11 节深度对照
- [hivewe/TERRAIN_MESH.md](../hivewe/TERRAIN_MESH.md) —— HivEWE 地面渲染管线
- [hivewe/WATER.md](../hivewe/WATER.md) —— HivEWE 水面参数
- [doodad/Y_REFRESH.md](../doodad/Y_REFRESH.md) —— doodad Y 重算（影响 doodad shader）

---

最后更新：2026-07-31
