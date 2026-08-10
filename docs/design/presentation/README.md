# present/ — 表现层（Presentation）

> **角色**：present 层把 `MapBuildContext` 里的 Logic 结果（heightfield / ramp /
> cliff / water / doodad / unit）渲染成 Godot 3D 场景。**禁止读 ctx 之外的源**——
> Logic 拆给 Logic，Present 只消费。
> **分层纪律**：[architecture/LAYERED_ARCHITECTURE.md §7](../../architecture/LAYERED_ARCHITECTURE.md)
> 最后更新：2026-07-31

---

## 1. 文件目录

| 文件 | 行数 | 角色 |
|------|------|------|
| `LAYERS.md` | — | 每层职责 + 关键 API + 调用链 |
| `Z_ORDER.md` | — | 渲染顺序 + 几何策略 + 与 HivEWE 对照 |
| `LAYERS.md` | — | 7 个 `Map*Layer` 逐层职责 + 关键 API + 调用链（包含 ctx + 工具类）|
| `Z_ORDER.md` | — | 渲染顺序 + 几何策略 |

> 历史上的 `MAP_LOADER.md` / `MAP_BUILD_CONTEXT.md` / `PRESENT_UTILS.md` 三个规划文档**未建**，
> 内容已合入 `LAYERS.md`（build 流程见 §0、§8；ctx/工具类见 §0）。

**对应的 `scripts/map/presentation/`**：

| 子目录 | 内容 |
|--------|------|
| `presentation/layers/` | 7 个 Map*Layer（terrain/cliff/ramp/water/doodad/unit + 2 debug）|
| `presentation/cliff/` | `Wc3CliffBuilder` / `Wc3CliffHeightMap`（直崖 / 斜坡构造工具）|
| `presentation/water/` | `Wc3WaterParams` / `Wc3WaterMesh` / `Wc3ShorelineBuilder` / `Wc3ShoreFoam` |
| `presentation/mesh/` | `HeightfieldMesh`（通用高度场 mesh 工具）|
| `presentation/`（根）| `MapLoader` / `MapBuildContext` / `orbit_camera.gd` |

---

## 2. 架构总览

```text
┌──────────────────────────────────────────────────────────────────────┐
│ MapLoader  (scripts/map/presentation/map_loader.gd, 291 行)            │
│   总编排：ensure_*_topology → filter → build(*Layer)                  │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│ MapBuildContext  (map_build_context.gd, 83 行)                        │
│   持：hf / tiles / catalog / cliff_catalog / ramp / cliff_placements     │
└──────────────────────────────────────────────────────────────────────┘
                                  │
       ┌──────────┬──────────┬────────┬──────────┬──────────┐
       ▼          ▼          ▼        ▼          ▼          ▼
   MapTerrain MapCliff   MapRamp   MapWater   MapDoodad MapUnit
   Layer     Layer      Layer     Layer      Layer      Layer
   (323)     (177)      (181)     (104)      (169)      (57)

+ MapDebugGridLayer (78) + MapRampDebugLayer (104) — 调试
```

**关键约束**：
- Present **不**改 `heightfield` / `ramp` / `cliff_placements` / `flags_packed`——只读
- Present **不**做 ramp 选型 / CliffTrans 匹配 / 入口识别——Logic 已经做完
- Present **可以**写 GPU buffer / 实例化 Mesh / 调 `apply_ramp_dig` 传挖洞 mask（present-only 状态）

---

## 3. 各 Layer 一句话职责

| Layer | 行 | 职责 |
|-------|----|-----|
| `MapTerrainLayer` | 323 | 地面 mesh + `corner_texture` 贴图 + `apply_ramp_dig` 入口 undig/boost + `_build_ground_mesh` |
| `MapCliffLayer` | 177 | 直崖 MultiMesh + `_should_hide_piece` + `hide_by_piece` 调试 |
| `MapRampLayer` | 181 | 斜坡 CliffTrans 挂模 + `apply_ramp_dig` 触发 + `_mount_groups` 调 `Wc3CliffBuilder` |
| `MapWaterLayer` | 104 | 水面 ArrayMesh + 岸浪 MultiMesh（`foam_cliff_out_extra` / `foam_ramp_pull_tiles` / `foam_shore_pull_tiles` 调参）|
| `MapDoodadLayer` | 169 | doodad GLB 实例化 + MultiMesh placeholder（按 `multimesh_threshold`）+ 动画检测 |
| `MapUnitLayer` | 57 | 单位（v2 项，按 catalog 选）|
| `MapDebugGridLayer` | 78 | 寻路 debug 网格 |
| `MapRampDebugLayer` | 104 | 斜坡 debug 钻石（独立 MeshInstance3D）|

详见 [LAYERS.md](LAYERS.md)。

---

## 4. 入口

```gdscript
# 编辑器主入口（场景根节点）
MapLoader  # 编排所有 build
├── MapTerrainLayer    # @export var terrain: MapTerrainLayer  ← MapRampLayer 依赖
├── MapCliffLayer      # @export var cliffs: MapCliffLayer
├── MapRampLayer       # @export var terrain: MapTerrainLayer
├── MapWaterLayer      # @export var height_bias_wc3 / foam_*
├── MapDoodadLayer     # @export var try_load_glb / multimesh_threshold
└── MapUnitLayer       # @export var ...（v2）
```

`MapLoader._ready()` 调 `reload_from_hf`（自动从 `map_dir` 读 JSON）；外部 `MapDocument` 调 `reload_from_hf(hf, info, p_map_dir)`。

---

## 5. 关键流程

### 5.1 完整 build 流程（`MapLoader.reload_from_hf` → `_load_all`）

```text
MapLoader.reload_from_hf(hf, info, p_map_dir)
  → _load_all() (L259+)
     1. Wc3IdCatalog / Wc3TerrainTileCatalog / Wc3CliffCatalog 加载
     2. MapBuildContext.create(map_dir, hf, info, _tiles, _catalog, _cache, _cliff_catalog)
     3. _apply_ramp_cliff_filter(ctx)  ← 挂崖前 filter（详见 [LAYERS.md](LAYERS.md)）
     4. _terrain.build(ctx)           ← MapTerrainLayer.build
        → ensure_ramp_topology()      ← 间接触发 Wc3RampCollect.collect
        → plan_dig_mask + plan_entrance_tiles + plan_entrance_height_boost
        → apply_ramp_dig(dig, entrances, boost, ramp_data.romp)
     5. _ramp.build(ctx)              ← MapRampLayer.build
        → apply_ramp_dig(...)
        → CliffTrans 挂模
     6. _cliff.build(ctx)             ← MapCliffLayer.build
        → 已 filter 的 cliff_placements
     7. _water.build(ctx)             ← MapWaterLayer.build
        → Wc3WaterMesh + Wc3ShorelineBuilder + Wc3ShoreFoam
     8. _doodads.build(ctx)           ← MapDoodadLayer.build
        → GLB + MultiMesh placeholder
     9. _pathing.build(ctx)           ← 待补（v2）
     10. _terrain_collision (optional)
     11. _build_ramp_debug(ctx)        ← 调试蓝菱形
```

### 5.2 增量 build（编辑后）

```gdscript
# MapRampLayer 不直接暴露——MapLoader 调
MapLoader.rebuild_terrain_only(hf, info)        # 仅地形
MapLoader.rebuild_terrain_cliffs_water(hf, info) # 地形 + 崖 + 水（不含 ramp）
```

> **注**：rebuild 不含 ramp——ramp 改动走 `EditorCommandHistory` 撤销/重做 + `Wc3RampLogic` paint 路径。

### 5.3 寻路 debug

```gdscript
MapLoader.set_view_grid_level(level)  # NONE / EDITABLE / WALKABLE
MapLoader.get_view_grid_level()       # 当前级别
MapLoader.show_pathing_debug_grid     # @export
MapLoader.show_ramp_debug             # @export
```

---

## 6. 与 Logic / Data 的边界

| 维度 | Present | Logic / Data |
|------|---------|--------------|
| 改 `heightfield` | ❌ | ✅ |
| 改 `flags_packed` / `ramp` | ❌ | ✅ |
| 改 `ramp.romp` / `cliff_placements` | ❌ | ✅ |
| 调 ramp 选型 / CliffTrans 匹配 | ❌ | ✅（`Wc3RampCollect`）|
| 调入口识别（`is_corner_ramp_entrance`）| ❌ | ✅ |
| 算 ramp 入口 `+0.5` boost | ❌ | ✅（`plan_entrance_height_boost`）|
| 写 `apply_ramp_dig`（dig/undig/boost）| ✅ | — |
| 写 `apply_dig_mask` / `undig_tiles` | ✅ | — |
| 写 GPU `gpu_final_ground_heights` / `gpu_ground_exists` | ✅（`MapTerrainLayer`）| — |
| 写 `corner_texture` 贴图 | ✅ | — |
| 写 `MapBuildContext` 字段 | ❌ | ✅ |
| 写 catalog / tileset | ❌ | ✅ |

**核心**：present 调 Logic 的 API 来"算"，自己**只**负责"画"。

---

## 7. vibecoding 指导

### 7.1 改 present 层时——必读

1. **[LAYERS.md](LAYERS.md)** —— 确认改哪个 layer（不要混多个 layer 逻辑）
2. **[Z_ORDER.md](Z_ORDER.md)** —— 确认渲染顺序（`render_priority` / `cull_mode` / `blend_mode`）
3. **[LAYERS.md](LAYERS.md) §8** —— 确认 build 流程入口（`MapLoader.reload_from_hf` → 各 layer.build）

### 7.2 改 MeshInstance3D / MultiMesh

- **ramp cliff** 用 **per-instance MeshInstance3D**（`MapRampLayer._mount_groups` line 154+）——
  `MultiMesh` + `Basis` 解旋会触发 AABB 裁剪坑（注释 line 148）
- **直崖 / doodad** 走 **MultiMesh**（已分桶 by `glb + tex_idx`）
- **doodad placeholder** —— 缺 GLB 时退化（`MapDoodadLayer` 推断 placeholder 路径）

### 7.3 改 shader

- `wc3_water.gdshader` —— `TIME * tex_rate` 直接用秒（不要再 /60，踩坑标记）
- `wc3_shore_foam.gdshader` —— Additive `blend_add, depth_draw_never`（防止粒子互相遮挡）
- `wc3_cliff.gdshader` —— 含 `corner_cliff_texture` / `corner_height` uniform（`Wc3CliffHeightMap.build_texture` 注入）
- 完整对照见 [hivewe/WATER_DEEP_ANALYSIS.md §5](../hivewe/WATER_DEEP_ANALYSIS.md)

### 7.4 改挖洞 / 入口

`apply_ramp_dig(dig, entrances, boost, romp)`：
- `dig` —— CliffTrans footprint + 对角 ramp（`Wc3RampLogic.plan_dig_mask` + `Wc3RampCollect.plan_diagonal_dig_mask`）
- `entrances` —— `Wc3RampLogic.plan_entrance_tiles`（含 L 凹陷 / 外角未齐四旗）
- `boost` —— `Wc3RampLogic.plan_entrance_height_boost`（含 L 凹陷 / 外角）
- `romp` —— `Wc3RampCollectResult.romp`（HivEWE 风格，corner_texture 看 a_romp）

详见 `MapTerrainLayer.apply_ramp_dig` 注释 + [hivewe/WATER_DEEP_ANALYSIS.md §4](../hivewe/WATER_DEEP_ANALYSIS.md)。

### 7.5 改贴图（ground 4 角纹理）

`MapTerrainLayer.corner_texture` 已对齐 HivEWE `real_tile_texture`：
- 4 角 OR 邻居 cliff + 自己非 ramp → 用 `cliff.groundTile`
- 4 角 OR 邻居 romp → 用 `cliff.groundTile`（HivEWE L729）
- 自己 ramp corner 排除（避免冲 ramp 顶颜色）
- corner_blight 优先级留 ROADMAP §⑪

详见 `MapTerrainLayer.corner_texture` 注释 + commit `fa2b97b`。

---

## 8. 已知坑

1. **`MapRampLayer._mount_groups` 不用 MultiMesh** —— 注释 line 148："MultiMesh AABB 易被裁掉导致挖了洞却看不见 CliffTrans"——per-MeshInstance3D 解决。
2. **`wc3_water.gdshader` TIME 不要 /60** —— 注释 line 20。
3. **`Wc3ShorelineBuilder.INSET_*` 调参顺序** —— `collect_foam_placements`（发射点）→ `INSET_*`（内缩）→ `Wc3ShoreFoam`（材质）→ `wc3_shore_foam.gdshader`（视觉）。
4. **`MapCliffLayer` 不读 ctx.ramp** —— 斜坡过滤走 `MapLoader._apply_ramp_cliff_filter`（挂前），不在 cliff layer 内部判断（避免 cliff layer 重入）。
5. **`MapTerrainLayer._last_romp` 缓存** —— 必须在 `build` 或 `apply_ramp_dig` 时设置，否则 `corner_texture` 看不到 romp。

---

## 9. 何时查这里

- **改 ramp 表现层**（CliffTrans 挂模 / mount） → [LAYERS.md](LAYERS.md) §3 + `map_ramp_layer.gd`
- **改崖表现层**（hide / unhide 直崖） → [LAYERS.md](LAYERS.md) §2 + `map_cliff_layer.gd`
- **改地面贴图 / 挖洞** → [LAYERS.md](LAYERS.md) §1 + `map_terrain_layer.gd` + [Z_ORDER.md](Z_ORDER.md)
- **改水面 / 岸浪** → [LAYERS.md](LAYERS.md) §4 + `map_water_layer.gd` + [hivewe/WATER_DEEP_ANALYSIS.md §5](../hivewe/WATER_DEEP_ANALYSIS.md)
- **改 doodad 挂模 / placeholder** → [LAYERS.md](LAYERS.md) §5 + `map_doodad_layer.gd`
- **改 build 流程**（顺序 / 跳过某步） → [LAYERS.md](LAYERS.md) §8
- **改 ctx 数据结构** → [LAYERS.md](LAYERS.md) §0
- **改工具类**（cliff_builder / water_mesh / heightfield_mesh） → [LAYERS.md](LAYERS.md) §0 + `scripts/map/presentation/` 源码

---

## 10. 相关文档

- [architecture/LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) —— 分层总纲
- [architecture/SCRIPTS_LAYOUT.md](../../architecture/SCRIPTS_LAYOUT.md) —— `scripts/` 目录全景
- [hivewe/CLIFF.md](../hivewe/CLIFF.md) + [hivewe/RAMP.md](../hivewe/RAMP.md) —— HivEWE 算法对照
- [hivewe/WATER.md](../hivewe/WATER.md) + [hivewe/WATER_DEEP_ANALYSIS.md](../hivewe/WATER_DEEP_ANALYSIS.md) —— HivEWE 水体
- [ramp/RAMP_WE.md](../ramp/RAMP_WE.md) —— 斜坡 paint 门禁
- [cliff/CLIFF.md](../cliff/CLIFF.md) —— 直崖 paint 门禁
- [roadmap/ROADMAP.md](../../roadmap/ROADMAP.md) —— milestone 进度
