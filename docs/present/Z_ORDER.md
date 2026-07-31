# present/ Z_ORDER — 渲染顺序与几何策略

> **角色**：定义 7 个 `Map*Layer` + 2 个 debug 层的**节点添加顺序**、**渲染优先级**
> （`render_priority` / `z_index` / `cull_mode` / `blend_mode` / `depth_draw`）和**几何策略**
> （投影 / mesh 拓扑 / 网格 AABB）。所有判定在 present 边界内解决——Logic 只决定
> "谁是谁"，present 决定"谁画在谁上面"。
> **对应**：[README.md §2](README.md)（架构）+ [LAYERS.md §1-§7](LAYERS.md)（各层职责）
> 最后更新：2026-07-31

---

## 1. 一句话规则

> **`MapLoader.main()` 的 build 调用顺序 = 节点添加顺序 = 默认渲染顺序**；
> 需要"后画但 depth 仍参与"的层（water / foam / debug）用 `render_priority` 提权；
> 需要"完全不参与 depth"的层（foam / ramp debug）用 `depth_draw_never` 或 `no_depth_test`。
> **没有任何层主动设 `z_index`**——靠 `render_priority` + child order 排。

---

## 2. 渲染层清单

按 `MapLoader.main()` 的 build 调用顺序：

| # | Layer | 节点类型 | 投影 | 渲染优先级 | 透明度 | 用途 |
|---|-------|----------|------|-----------|--------|------|
| 1 | `MapTerrainLayer` | `HeightfieldMesh` (ArrayMesh) | OFF | 0（默认）| `cull_back, unshaded, blend_mix` | 地面 heightfield mesh + 直崖 gap |
| 2 | `MapCliffLayer` | `MultiMeshInstance3D` ×N（每 GLB/tex 一组）| OFF | 0（默认）| `cull_disabled, unshaded, blend_mix` | 悬崖模型实例化 |
| 3 | `MapRampLayer` | `MeshInstance3D` ×N（每块一节点）| OFF | 0（默认）| 同 cliff material | 斜坡模型（解旋 Basis）|
| 4 | `MapWaterLayer` | `HeightfieldMesh` (ArrayMesh) + `MultiMeshInstance3D` ×N | OFF | **水 1 / 岸浪 16** | 水 `blend_mix`，岸浪 `blend_add, depth_draw_never` | 水面 + 岸浪 PE2 |
| 5 | `MapUnitLayer` | `Node3D` 子树（GLB 实例 + placeholder）| 默认 ON | 0（默认）| 走 GLB 自带 material | 单位模型 |
| 6 | `MapDoodadLayer` | `Node3D` 子树 / `MultiMeshInstance3D` ×N | 默认 ON | 0（默认）| 走 GLB/内置 material | 装饰物 |
| 7 | `MapDebugGridLayer` | （god 自带） | — | 0 | — | 寻路栅格调试 |
| 8 | `MapRampDebugLayer` | `MeshInstance3D` ×N（只画 ramp corner）| OFF | **90** | `StandardMaterial3D, no_depth_test` | 斜坡调试标记 |

> **投影 = OFF** 是 WC3 经典行为：Warcraft III 引擎**完全不投影**（自己查渲染可知
> shadows 是用 blob texture 模拟的，不开 directional light shadow）。
> 复刻保持原行为，所有 layer 都 `cast_shadow = SHADOW_CASTING_SETTING_OFF`，
> 唯一例外是 doodad/unit（用 GLB 内置 PBR 材质）默认 ON。

---

## 3. Build 顺序（MapLoader.main）

```text
MapLoader.main()                                            # map_loader.gd:240-309
├─ ctx.ensure_*_topology()                                  # tileset / cliff_catalog / ramp_collect
├─ _terrain.build(ctx)                                      # 1) 地面 mesh
├─ _ensure_terrain_collision()                              #   可选：collision 体
├─ _cliffs.build(ctx)                                       # 2) 悬崖 MultiMesh
├─ _ramps.build(ctx)                                        # 3) 斜坡 MeshInstance
├─ _water.build(ctx)                                        # 4) 水面 + 岸浪
│   ├─ _water.set_array_mesh(...)                           #   render_priority = 1
│   └─ _build_shore_foam(ctx, params)                       #   _shore_root → MultiMesh  render_priority = 16
├─ _units.build(ctx)                                        # 5) 单位
└─ _doodads.build(ctx)                                      # 6) doodad
```

**debug 走独立 build 入口**（不在 main 内）：

```text
_build_ramp_debug(ctx)                                      # map_loader.gd:152-156
└─ _ramp_debug.build(ctx)                                   # MapRampDebugLayer  render_priority = 90
```

**关键不变量**：
- `_terrain.build()` **必须最先**——后续 cliff/ramp 调 `apply_ramp_dig(extra, entrances, boost, romp)` 改 terrain 顶点
- `_water.build()` 在 cliff/ramp 之后——水面 height 由 HF 决定，**不**依赖 cliff/ramp mesh
- `_units` / `_doodads` **永远在最后**——Y 由 HF 决定，blit 时**不再**依赖前面 layer

---

## 4. 几何策略（每个 layer 怎么画）

### 4.1 Terrain（`MapTerrainLayer`）

- **节点**：`HeightfieldMesh`（`$Ground`）
- **mesh 拓扑**：`ArrayMesh` + `PRIMITIVE_TRIANGLES`（`HeightfieldMesh.set_array_mesh()`）
- **顶点属性**：`CUSTOM0 = vec4(4 个 tile 槽位)` / `CUSTOM1 = vec4(4 个 variation)`（详见 `wc3_ground.gdshader`）
- **几何来源**：`_ground_layer_slots_for(hf, ctx)` 算每个 corner 的 4 层 tileset（base / overlay1-3）
- **斜坡挖洞**：`_last_hf` / `_last_extended` / `_base_gap` / `_extra_dig` / `_undig` / `_entrance_h_boost` / `_last_romp` 缓存——`apply_ramp_dig(extra, entrances, boost, romp)` 增量调（present-only 状态）
- **关键代码**：`scripts/map/presentation/layers/map_terrain_layer.gd:44-`

### 4.2 Cliff（`MapCliffLayer`）

- **节点**：`MultiMeshInstance3D` ×N（每 `(GLB, tex_idx)` 一组）
- **拓扑**：`MultiMesh.transform_format = TRANSFORM_3D`（不用 2D，省得 GLB 旋转丢失）
- **材质**：`_cliff_material(tex, hf)` —— `ShaderMaterial` + `wc3_cliff.gdshader`（`cull_disabled, unshaded`）
- **顶点位移**：shader `vertex()` 内 `VERTEX.y += h * 128.0`（高度从 `height_map` uniform 采）
- **斜坡隐藏**：`hide_pieces_for_ramp(hf, ramp_data)` 调 `Transform3D(Basis.from_scale(Vector3.ZERO), …)` 把 instance 缩到 0
- **关键代码**：`map_cliff_layer.gd:60-105`

### 4.3 Ramp（`MapRampLayer`）

- **节点**：`MeshInstance3D` ×N（**每块**一节点——MultiMesh 在解旋 Basis 下 AABB 易被裁掉，挖洞 CliffTrans 看不见）
- **材质**：复用 cliff 的 `ShaderMaterial`（同 `wc3_cliff.gdshader`）
- **投影**：OFF
- **AABB 修正**：`mi.custom_aabb = local_aabb` + `extra_cull_margin = 4.0`（避免 frustum 误裁）
- **关键代码**：`map_ramp_layer.gd:120-167`

### 4.4 Water（`MapWaterLayer`）

- **水面**：`HeightfieldMesh` (ArrayMesh) + `ShaderMaterial` + `wc3_water.gdshader`（`cull_disabled, blend_mix`）
  - `render_priority = 1`（比地形后画——同 z 时覆盖地形）
  - `cast_shadow = OFF`
- **岸浪**：`Node3D` 子树 + 多个 `MultiMeshInstance3D`（每类 placement 一组）
  - `ShaderMaterial` + `wc3_shore_foam.gdshader`（`blend_add, depth_draw_never`）
  - `render_priority = 16`（必须比水面后画——additive 不然会盖住水面）
  - `cast_shadow = OFF`
  - **关键**：岸浪在水面**之后**画（additive 加在水面像素上），所以 `render_priority` > 水面
- **关键代码**：`map_water_layer.gd:21-119`

### 4.5 Doodad（`MapDoodadLayer`）

- **节点**：`Node3D` 子树（每 doodad 一节点 = GLB 实例）或 `MultiMeshInstance3D` ×N（按 part 分）
- **材质**：GLB 自带 PBR material
- **Y 计算**：`_apply_doodad_xform(node, d, true)` → 读 HF 取平均 Y；改地形后 `refresh_heights()` 重算（详见 [docs/doodad/Y_REFRESH.md](../doodad/Y_REFRESH.md)）
- **投影**：默认 ON（GLB PBR 含阴影）
- **关键代码**：`map_doodad_layer.gd:80-150`

### 4.6 Unit（`MapUnitLayer`）

- **节点**：`Node3D` 子树（GLB 实例 + `MapPlaceholders.make_entity` 占位）
- **材质**：GLB 自带
- **关键代码**：`map_unit_layer.gd:1-57`

### 4.7 Debug layers

- **`MapDebugGridLayer`**：寻路栅格 GPU 渲染（独立，不在主流程）
- **`MapRampDebugLayer`**：仅画 ramp corner（红/绿框）
  - `StandardMaterial3D` + `no_depth_test = true` + `render_priority = 90`
  - 永远在最上（覆盖一切）——debug only
  - 关键代码：`map_ramp_debug_layer.gd:78-100`

---

## 5. 渲染优先级 / 透明度策略

### 5.1 `render_priority` 速查

| priority | 节点 | shader | 作用 |
|----------|------|--------|------|
| **0**（默认）| terrain / cliff / ramp / doodad / unit | — | 大部分 mesh；由 child order 排 |
| **1** | water surface | `wc3_water.gdshader` | 比地形后画（覆盖地形上的水面像素）|
| **16** | shore foam | `wc3_shore_foam.gdshader` | 比水面后画（additive 加在水面像素上）|
| **90** | ramp debug | `StandardMaterial3D` | 永远最上（debug only）|

> **Godot 4 行为**：`render_priority` 只在**同 z_index + 同材质**的节点间有效。
> 我们没有 `z_index`，所以 `render_priority` 跨子节点也生效。
> 优先级**只在同 z 时**打破 child order（不同 z 时 z 大者后画）。

### 5.2 `blend_mode` / `depth_draw` 速查

| 节点 | blend | depth_draw | 含义 |
|------|-------|-----------|------|
| terrain | `blend_mix`（默认）| `opaque`（默认）| 正常 alpha blend + 写 depth |
| cliff / ramp | `blend_mix`（默认）| `opaque`（默认）| 同上 |
| water | `blend_mix` | `opaque`（默认）| 正常 alpha，但 `render_priority` 让它后画 |
| shore foam | **`blend_add`** | **`depth_draw_never`** | 加性混合 + **不写 depth**——防止互遮挡（粒子 A 在粒子 B 前不会盖 B）|
| ramp debug | `blend_mix` | `no_depth_test` | 关 depth test——**永远**画在最上 |

### 5.3 `cull_mode` 速查

| 节点 | cull | 含义 |
|------|------|------|
| terrain | `cull_back` | 正常背面剔除（heightfield mesh 单面）|
| cliff | `cull_disabled` | 双面（解旋 Basis 下 AABB 不严格，避免背面变透明）|
| ramp | `cull_disabled` | 同 cliff |
| water | `cull_disabled` | 双面（水面会看穿，从水底看也要对）|
| shore foam | `cull_disabled` | 双面（粒子 billboard 不剔）|

---

## 6. 与 HivEWE 对照

### 6.1 HivEWE 渲染顺序

HivEWE 0.6+ 用单 `OpenGLRenderer` 顺序调：

```text
terrain.ixx::render_ground()    // line 484
  → 地面 mesh（含 pathing/lighting/regions uniforms）
terrain.ixx::render_cliffs()    // line 536-577  // Render cliffs
  → cliff_meshes[i].render_queue(...)
terrain.ixx::render_water()     // line 581
  → 水面 + shore foam（用粒子 emitter）
```

HivEWE 没有 `z_index` / `render_priority` 概念——靠**调用顺序**（ground → cliffs → water）。
cliffs 是 `render_queue(...)` 入队，按 `min_corner_layer_height - 2` 排序。

### 6.2 我们的差异

| 维度 | HivEWE | 我们的实现 | 原因 |
|------|--------|------------|------|
| 渲染 API | OpenGL 4.x + 自定义 pipeline | Godot 4 forward+ 渲染 | Godot 渲染管线接管 |
| cliff 排序 | 手动 `render_queue`（按 corner height 排）| child order（同 heightfield 顺序）| Godot 走 depth test，排序冗余 |
| shore foam | ParticleEmitter2 粒子系统 | `MultiMeshInstance3D` ×N + GPU 动画 shader | 简化（不上 GPU particles）|
| ramp debug | 编辑器内临时 | `MapRampDebugLayer`（scene 节点）| 可开关（`show_ramp_debug` 开关）|
| shadow | 不投影 | 不投影（doodad/unit 默认 ON 是 PBR 默认）| 后续若要严格对齐可全 OFF |
| z_index / render_priority | 无 | 用 `render_priority` 排 water/foam/debug | Godot 4 API 习惯 |

### 6.3 对齐目标

- ✅ Build 顺序与 HivEWE 一致：terrain → cliffs → ramp → water → foam
- ✅ 投影行为：cliff/ramp/water/foam 全 OFF（doodad/unit 默认 PBR 投影暂保留）
- ✅ water `blend_mix`、foam `blend_add, depth_draw_never`（与 HivEWE 粒子系统语义一致）
- ⚠️ Foam 顺序：我们 `render_priority = 16` vs HivEWE "water 之后调 emitter"——实现不同但**结果一致**
- ⚠️ Cliff 排序：我们靠 depth test；HivEWE 手动排——**视觉一致但渲染顺序记录不可比**

---

## 7. 何时查这里

| 改的东西 | 查 |
|---------|----|
| 加新 Layer | §3 决定 build 顺序，§5 决定 render_priority / blend |
| 改 water / foam 顺序错乱 | §5.1 §5.2（priority 1/16，blend_add, depth_draw_never）|
| cliff / ramp 被裁掉 | §4.2 §4.3（custom_aabb + extra_cull_margin）|
| doodad/unit 投影太重 | §2 投影列（doodad/unit 默认 ON，其余 OFF）|
| 调试线框挡住场景 | §4.7（ramp debug 90 永远最上，临时关 `show_ramp_debug`）|

---

## 8. 相关文档

- [README.md](README.md) —— present 总览
- [LAYERS.md](LAYERS.md) —— 7 个 Map*Layer + 2 debug 逐层职责
- [hivewe/WATER_DEEP_ANALYSIS.md §3](../hivewe/WATER_DEEP_ANALYSIS.md) —— water 顶点 / shore foam 几何策略
- [hivewe/TERRAIN_MESH.md](../hivewe/TERRAIN_MESH.md) —— HivEWE ground 渲染管线
- [doodad/Y_REFRESH.md](../doodad/Y_REFRESH.md) —— doodad Y 重算流程

---

最后更新：2026-07-31
