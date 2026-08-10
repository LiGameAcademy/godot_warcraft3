# LAYERS — 各 Map*Layer 职责 + 关键 API

> **角色**：present 7 个 `Map*Layer` 的逐层职责 + 关键 API + 调用链。改 present
> 层时必读——避免混多个 layer 逻辑。
> **依据源码**：`scripts/map/presentation/layers/*.gd`（17 文件 / 1300+ 行总）
> 最后更新：2026-07-31

---

## 0. 共同模式

所有 `Map*Layer` 继承 `Node3D`，**核心 API 模式**：

```gdscript
class_name MapXxxLayer
extends Node3D

@export var terrain: MapTerrainLayer  # 依赖注入（部分 layer）
@export var cliffs: MapCliffLayer      # 依赖注入

var last_count: int = 0               # 调试统计

func build(ctx: MapBuildContext) -> void:
    _clear_children()
    if ctx == null: return
    # ... 渲染逻辑 ...
```

**约定**：
- `build(ctx)` 是**唯一**入口——`MapLoader` 调
- **不**重入（不要在 `build` 内调其他 `Map*Layer.build`）
- **不**调 Logic API（Logic 已通过 ctx 算好）
- **不**改 heightfield / flags_packed / ramp / cliff_placements

---

## 1. MapTerrainLayer（地面 + 贴图 + 入口挖洞）— 323 行

**路径**：`scripts/map/presentation/layers/map_terrain_layer.gd`

### 1.1 职责

- **地面 mesh 构建**：4 角插值 + `corner_texture` 贴图选型
- **挖洞 API**：`apply_ramp_dig(dig, entrances, boost, romp)` —— ramp 入口 undig + 低角 +0.5
- **多 API**：`apply_dig_mask(extra)` / `undig_tiles(tiles)` —— 单独调用
- **状态缓存**：`_last_hf` / `_last_romp` / `_last_cliff_to_ground` / `_entrance_h_boost` 供增量 rebuild

### 1.2 关键 API

| API | 行 | 用途 |
|-----|----|----|
| `build(ctx)` | 42 | 完整重建（`_load_all` 时调）|
| `apply_ramp_dig(extra, entrances, boost, romp)` | 128 | **ramp 入口 +0.5 + undig + dig** 一次 API（`MapRampLayer` 调）|
| `apply_dig_mask(extra)` | 116 | 仅追加挖洞（不动 boost / undig）|
| `undig_tiles(tiles)` | 122 | 仅 undig 入口格 |
| `_build_ground_mesh(hf, ext, gap, cliff_to_ground)` | 234 | 核心 mesh 构建 |
| `corner_texture(ground_tex, layer_heights, cliff_tex, cliff_to_ground, tp_w, tp_h, col, row)` | 205 | **4 角纹理选型**（HivEWE `real_tile_texture` 等价）|
| `_rebuild_ground_mesh_only()` | 155 | 增量重建（apply_ramp_dig 后）|

### 1.3 关键成员

```gdscript
var _last_hf: Wc3Heightfield           # 上次 heightfield 缓存
var _last_extended: PackedByteArray   # 扩展标志（>=16 变体）
var _base_gap: PackedByteArray        # 基础 gap（cliff_gap_mask）
var _extra_dig: PackedByteArray       # 追加 dig（apply_ramp_dig）
var _undig: PackedByteArray           # undig mask
var _entrance_h_boost: PackedByteArray  # 入口低角 +0.5 标志
var _last_cliff_to_ground: PackedInt32Array  # cliff_type → ground_tile 映射
var _last_romp: PackedByteArray       # CornerTrans 过渡 mask（HivEWE a_romp）
```

### 1.4 `corner_texture` 行为（HivEWE `real_tile_texture` L711-743 等价）

1. **自己 ramp corner 排除** —— `!corner_ramp[idx]`（避免冲 ramp 顶颜色）
2. **4 角 OR 邻居 cliff** → 用 `cliff_to_ground[ci]`（崖地砖）
3. **4 角 OR 邻居 romp** → 用 `cliff_to_ground[ci]`（同上）
4. **否则** → 用 `ground_tex[idx]`（原地表）
5. **未实现** `corner_blight` 优先级（[ROADMAP §⑪](../../roadmap/ROADMAP.md)）

详见 commit `fa2b97b`。

### 1.5 调用链

```text
MapLoader._load_all
  → MapTerrainLayer.build
     → _build_ground_mesh
        → corner_texture (×4 per cell)
        → _build_layers
        → _ground.add_quad

MapRampLayer.build
  → MapTerrainLayer.apply_ramp_dig(dig, entrances, boost, ramp_data.romp)
     → _rebuild_ground_mesh_only
        → _build_ground_mesh（重读 _last_* 缓存）
```

---

## 2. MapCliffLayer（直崖 MultiMesh）— 177 行

**路径**：`scripts/map/presentation/layers/map_cliff_layer.gd`

### 2.1 职责

- **直崖 MultiMesh 实例化**：按 `glb + cliff_tex_index` 分桶
- **hide 调试 API**：`should_hide_piece` / `hide_by_piece` —— 单块隐藏
- **不**读 ctx.ramp（ramp 过滤在 `MapLoader._apply_ramp_cliff_filter` 挂前完成）

### 2.2 关键 API

| API | 行 | 用途 |
|-----|----|----|
| `build(ctx)` | ? | 完整重建（已 filter 的 cliff_placements）|
| `should_hide_piece(piece)` | 113 | 单块 hide（调试/运行时）|
| `hide_by_piece(ix, iy, base_layer, ramp_data)` | 144 | 按位置 + base_layer hide（ramp/入口覆盖）|

### 2.3 关键成员

```gdscript
const CLIFF_SHADER: Shader            # wc3_cliff.gdshader
@export var terrain: MapTerrainLayer
@export var height_tex: Texture2D      # 注入 Wc3CliffHeightMap 纹理

var _height_tex: Texture2D
var _cliffs_root: Node3D               # 父节点（按 glb 分桶）
```

### 2.4 调 `Wc3CliffBuilder.build_from_placements`（同 MapRampLayer）

- 直崖用 **`instance_transform`**（无解旋，经典锚 `ix+1`）
- 斜坡用 **`instance_transform_trans`**（`HivEWE modern (y, -x) Basis` 解旋 + 锚 `ix`）

### 2.5 调用链

```text
MapLoader._load_all
  → _apply_ramp_cliff_filter(ctx)  ← 挂前 filter
  → MapCliffLayer.build
     → Wc3CliffBuilder.build_from_cliff_placements (直崖)
     → _mount_groups → MultiMesh per glb
```

---

## 3. MapRampLayer（斜坡 CliffTrans 挂模）— 181 行

**路径**：`scripts/map/presentation/layers/map_ramp_layer.gd`

### 3.1 职责

- **挖洞触发**：调 `MapTerrainLayer.apply_ramp_dig`（ramp 入口 undig + +0.5）
- **CliffTrans 挂模**：调 `Wc3CliffBuilder.build_from_ramp_placements`
- **per-instance MeshInstance3D**：不用 MultiMesh（解旋 Basis 触发 AABB 裁剪坑）

### 3.2 关键 API

| API | 行 | 用途 |
|-----|----|----|
| `build(ctx)` | 23 | 完整重建（dig + CliffTrans）|
| `_mount_groups(collected, ctx, hf)` | 110 | 调 Wc3CliffBuilder 挂模 |
| `get_debug_materials() -> Array[ShaderMaterial]` | 211 | 调试用 |

### 3.3 关键成员

```gdscript
@export var terrain: MapTerrainLayer  # 调 apply_ramp_dig
@export var cliffs: MapCliffLayer      # 调试耦合

var last_placement_count: int = 0      # CliffTrans 挂模数
var last_dig_count: int = 0           # dig 格数
var last_entrance_count: int = 0      # 入口数
var last_boost_count: int = 0         # +0.5 boost 数
var _shader: Shader                   # wc3_cliff.gdshader
var _height_tex: Texture2D            # Wc3CliffHeightMap
var _ramp_mats: Array[ShaderMaterial] = []  # 调试材质
```

### 3.4 `_mount_groups` 关键坑

```gdscript
# 每块独立 MeshInstance3D：解旋 Basis 下 MultiMesh AABB 易被裁掉导致
# "挖了洞却看不见 CliffTrans"
# 注释 line 148
```

**对策**：每个 placement 一个 `MeshInstance3D`，不用 `MultiMesh`。

### 3.5 调用链

```text
MapLoader._load_all
  → _apply_ramp_cliff_filter(ctx)  ← cliff 过滤
  → MapRampLayer.build
     → plan_dig_mask / plan_entrance_tiles / plan_entrance_height_boost
     → plan_diagonal_dig_mask（额外 dig）
     → terrain.apply_ramp_dig(dig, entrances, boost, ramp_data.romp)
     → Wc3CliffBuilder.build_from_ramp_placements
     → _mount_groups → per-MeshInstance3D
```

---

## 4. MapWaterLayer（水面 + 岸浪）— 104 行

**路径**：`scripts/map/presentation/layers/map_water_layer.gd`

### 4.1 职责

- **水面 ArrayMesh**：`Wc3WaterMesh.build` + `Wc3WaterParams.load_for_tileset`
- **岸浪 MultiMesh**：`Wc3ShorelineBuilder.collect_foam_placements` + `Wc3ShoreFoam`
- **岸浪调参 UI**：`foam_cliff_out_extra` / `foam_ramp_pull_tiles` / `foam_shore_pull_tiles`（`@export_range`）

### 4.2 关键 API

| API | 行 | 用途 |
|-----|----|----|
| `build(ctx)` | 21 | 完整重建（water mesh + foam）|
| `last_cell_count` / `last_shore_count` | 16-17 | 调试统计 |

### 4.3 关键成员

```gdscript
const WATER_SHADER: Shader = preload("res://assets/shaders/wc3_water.gdshader")
@export var height_bias_wc3: float = 0.0
@export_range(0.0, 0.40, 0.01) var foam_cliff_out_extra: float = 0.08
@export_range(0.0, 0.55, 0.01) var foam_ramp_pull_tiles: float = 0.38
@export_range(0.0, 0.40, 0.01) var foam_shore_pull_tiles: float = 0.10
@onready var _water: HeightfieldMesh = $Surface
var _shore_root: Node3D
```

### 4.4 调参顺序（5%/4%/1% 原则）

> 95% 是 shader 美术调参；4% 是 `Wc3ShorelineBuilder.collect_foam_placements` 发射点；1% 是 `Wc3WaterMesh` 几何

详见 [hivewe/WATER_DEEP_ANALYSIS.md §5](../hivewe/WATER_DEEP_ANALYSIS.md)。

### 4.5 调用链

```text
MapLoader._load_all
  → MapWaterLayer.build
     → Wc3WaterParams.load_for_tileset
     → Wc3WaterMesh.build(hf, params, height_bias_wc3, meta)
     → ShaderMaterial (water_frames Texture2DArray + frame_count + tex_rate)
     → _water.set_array_mesh
     → Wc3ShorelineBuilder.collect_foam_placements
     → Wc3ShoreFoam.build (MultiMesh INSTANCE_CUSTOM 推进)
```

---

## 5. MapDoodadLayer（装饰物 + 单位）— 169 行

**路径**：`scripts/map/presentation/layers/map_doodad_layer.gd`

### 5.1 职责

- **doodad 实例化**：按 `type_id + variation` 分组
- **GLB 优先**：`try_load_glb` + `_cache.glb_has_animation(glb)` 决定走 GLB 实例还是 MultiMesh placeholder
- **分桶**：按 `(glb_path, geoset_id, animation)` 三个 key 分
- **动画**：`glb_has_animation` 时单实例（避免共享动画状态）

### 5.2 关键 API

| API | 行 | 用途 |
|-----|----|----|
| `setup(catalog, cache)` | 15 | 注入依赖（`MapLoader._ready` 调）|
| `build(ctx)` | 20 | 完整重建（按 `ctx.doodads`）|

### 5.3 关键成员

```gdscript
@export var try_load_glb: bool = true
@export var multimesh_threshold: int = 8  # ≥ 这个数用 MultiMesh
var _catalog: Wc3IdCatalog
var _cache: MapModelCache
var last_placed: int = 0
var last_placeholder: int = 0
```

### 5.4 渲染策略

| 条件 | 渲染方式 |
|------|----------|
| 有 GLB + 无动画 + ≥ `multimesh_threshold` | **MultiMesh**（按 glb 分桶）|
| 有 GLB + 有动画 | **单 MeshInstance3D**（避免动画状态共享）|
| 无 GLB | **placeholder**（灰块 / 默认 mesh）|

### 5.5 调用链

```text
MapLoader._load_all
  → MapDoodadLayer.build
     → 按 (type_id, variation) 分组
     → _catalog.converted_glb_path(type_id, variation)
     → _cache.glb_has_animation 判断
     → GLB: per-MeshInstance3D (动画) 或 MultiMesh (静态)
     → placeholder: 默认 mesh
```

### 5.6 关联

- **`MapDoodadLayer` 改地形时自动 refresh Y**（commit `365efab`）—— `Wc3Heightfield` 改 corner_height 后调 `MapDoodadLayer.refresh_y_from_heightfield` 重新算 doodad Y
- 详细分析见 [docs/doodad/](../doodad/)（v2 待补）

---

## 6. MapUnitLayer（单位）— 57 行

**路径**：`scripts/map/presentation/layers/map_unit_layer.gd`

### 6.1 职责

- **单位挂模**：从 `ctx.units` 读，按 catalog 选 GLB
- **v2 项**：当前实现**薄**——大部分单位走 catalog placeholder

### 6.2 关键 API

| API | 行 | 用途 |
|-----|----|----|
| `build(ctx)` | ? | 完整重建（v2：玩家单位 + 中立生物 + 物品）|

### 6.3 状态

- ❌ **未实现**动画 / 阵营色 / 血条 / 选中圈（v2 项）
- ❌ 玩家单位 vs 中立生物（catalog 区分）
- ⚠️ `MapLoader.place_units: bool = false` 默认关

详见 [roadmap/ROADMAP.md §⑦ 单位](../../roadmap/ROADMAP.md)。

---

## 7. Debug layers

### 7.1 `MapDebugGridLayer`（78 行）

- **寻路 debug 网格**：按 `MapLoader.show_pathing_debug_grid` 开关
- **3 模式**：`ViewGridLevel.NONE` / `EDITABLE` / `WALKABLE`
- **调** `MapLoader.set_view_grid_level(level)` 切

### 7.2 `MapRampDebugLayer`（104 行）

- **斜坡 debug 钻石**（蓝菱形）—— `MapLoader.show_ramp_debug` 开关
- **`MapLoader._build_ramp_debug(ctx)`** 调
- 独立 `MeshInstance3D` per ramp corner
- 详情见 `map_ramp_debug_layer.gd`

---

## 8. 关键调用链总览

```text
MapLoader._load_all
  ├── _apply_view_grid
  ├── MapBuildContext.create
  ├── _apply_ramp_cliff_filter
  ├── MapTerrainLayer.build
  │     ├── _build_ground_mesh
  │     │     ├── corner_texture (4 角)
  │     │     ├── _build_layers
  │     │     └── _ground.add_quad
  │     └── 调 ramp: 后续 apply_ramp_dig
  ├── MapCliffLayer.build
  │     └── Wc3CliffBuilder.build_from_cliff_placements
  ├── MapRampLayer.build
  │     ├── MapTerrainLayer.apply_ramp_dig
  │     └── Wc3CliffBuilder.build_from_ramp_placements
  │           └── _mount_groups (per-MeshInstance3D)
  ├── MapWaterLayer.build
  │     ├── Wc3WaterMesh.build
  │     ├── Wc3ShorelineBuilder.collect_foam_placements
  │     └── Wc3ShoreFoam.build
  ├── MapDoodadLayer.build
  │     └── 按 (type_id, variation) 分组 + GLB/placeholder
  ├── MapUnitLayer.build（v2）
  ├── _build_ramp_debug（可选）
  └── _ensure_terrain_collision（可选）
```

---

## 9. 何时查这里

- **改 ramp 表现** → §3 + `map_ramp_layer.gd`
- **改地面贴图 / 挖洞 / 入口** → §1 + `map_terrain_layer.gd` + [Z_ORDER.md](Z_ORDER.md)
- **改崖 / 隐藏** → §2 + `map_cliff_layer.gd`
- **改水面 / 岸浪** → §4 + `map_water_layer.gd` + [hivewe/WATER_DEEP_ANALYSIS.md §5](../hivewe/WATER_DEEP_ANALYSIS.md)
- **改 doodad** → §5 + `map_doodad_layer.gd` + [docs/doodad/](../doodad/)（v2）
- **改单位** → §6 + `map_unit_layer.gd`（v2）

---

## 10. 相关文档

- [README.md](README.md) —— present 总览
- [Z_ORDER.md](Z_ORDER.md) —— 渲染顺序 + 几何策略
- [LAYERS.md §8](LAYERS.md) —— `MapLoader` 编排（关键调用链总览）
- [LAYERS.md §0](LAYERS.md) —— ctx 数据结构 + 工具类
- [hivewe/WATER_DEEP_ANALYSIS.md §5](../hivewe/WATER_DEEP_ANALYSIS.md) —— water/foam shader 对照
- [hivewe/RAMP.md §5](../hivewe/RAMP.md) —— HivEWE 入口判定
- [architecture/LAYERED_ARCHITECTURE.md §7](../../architecture/LAYERED_ARCHITECTURE.md) —— present 边界
