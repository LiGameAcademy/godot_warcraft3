# `scripts/` 目录全景

> Godot 4.6 侧的脚本组织。`scripts/` 仍处于**渐进归位**阶段——目录已按分层划好，但部分层内仍平铺（如 presentation/water/、data/）；`Map*Layer` 集中在 `presentation/layers/`，`Wc3*` Domain 散在 `map/logic/、map/data/、map/catalog/`。
>
> 总纲：[LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md)

## 1. 顶层布局

```text
scripts/
├── auto/                          Autoload 全局单例脚本
├── definitions/                   静态 SLK 表 → Resource（按 SLK 表名分目录）
│   └── terrain_art/               TerrainArt 四表
├── presentation/                  跨地图/游戏/编辑器共用表现
│   └── wc3_model/                 模型 .scn 门面 / AnimPlayer / 名解析
├── shared/                        游戏/编辑器共用
│   ├── infra/                     AppLog 等
│   ├── selection/
│   └── world/
├── tool/                          Godot headless 工具（导出 .scn / pe2 / visuals）
└── map/                           地图相关
    ├── catalog/                   Catalog（资源映射）
    ├── data/                      Data（纯数据类）
    ├── infra/                     Infra（基础设施）
    ├── logic/                     Logic（规则与计算）
    └── presentation/              Presentation（场景层：地形/水/单位层…）
```

Autoload（见 [LAYERED_ARCHITECTURE.md §2](LAYERED_ARCHITECTURE.md)）：

| Autoload | 脚本 | 职责 |
|----------|------|------|
| `AssetProvider` | [`addons/asset_provider/asset_provider.gd`](../../addons/asset_provider/asset_provider.gd) | 逻辑路径解析（mods → converted → .cache） |
| `EditorI18n` | [`editor/ui/editor_i18n.gd`](../../editor/ui/editor_i18n.gd) | 编辑器字符串 i18n |
| `Wc3DefStore` | `scripts/auto/wc3_def_store.gd` | SLK 静态表缓存（TerrainArt 四表预加载） |

---

## 1b. `scripts/tool/` — Godot headless 工具

> 由 Node 管线（`tools/*.mjs`）调用：`godot --headless -s res://scripts/tool/...`。  
> **不要**再往 `tools/` 放 `.gd`；`tools/` 只放外部工具（js / mjs / ps1）。

| 脚本 | 职责 |
|------|------|
| `export_model_scenes.gd` | `asset-converted` 下 gltf/glb → 同目录 `.scn`（含 PE2） |
| `export_pe2_scenes.gd` | 已弃用：PE2 打进 `.scn` |
| `export_visual_scenes.gd` | bake → `assets/visuals/`（薄继承，不再 instance pe2.tscn） |
| `split_meshes_by_group.gd` | 可选：按 VertexGroup 拆 geoset（bake 默认不调用） |
| `wc3_scn_animkeys.gd` | bake：animkeys → loop/meta + Event Method Track |
| `wc3_scn_pe2.gd` | bake：pe2.json → Pe2Root + `:emitting` / position |

**模型 .scn 运行时职责（门面 / AP / 策略变薄 / 迁出 map）：**  
见 [WC3_MODEL_SCENE.md](../design/presentation/WC3_MODEL_SCENE.md)（目录 `scripts/presentation/wc3_model/`）。

粒子字段对照与未做项：[PE2_GODOT.md](../design/asset-convert/PE2_GODOT.md)。

编辑器笔刷仍在 `editor/scripts/tools/`（运行时编辑器工具，不是 headless 导出）。

---

## 2. `scripts/auto/` — Autoload

| 脚本 | 职责 |
|------|------|
| `wc3_def_store.gd` | SLK 静态表缓存。注册：`register_table(name, slk_rel, key, factory)`；查询：`get_row(name, key)` / `get_ids(name)`。`_ready` 预加载 TerrainArt 四表（CliffType / TerrainTile / WaterType / WeatherEffect） |

---

## 3. `scripts/definitions/` — 静态表定义

每张 SLK 表对应一个 `*Def` Resource。负责：
- `@export` 字段映射 SLK 列
- `TABLE_NAME` / `SLK_REL_PATH` / `PRIMARY_KEY` 常量
- `static from_slk_record(rec)` 工厂
- `static register_to(store)` 挂到 `Wc3DefStore`

### 3.1 `terrain_art/` — TerrainArt 四表

| 类 | 表名 | 主键 | 关键字段 |
|----|------|------|----------|
| `CliffTypeDef` | `CliffTypes` | `cliffID` | `cliff_id` / `cliff_model_dir` / `ramp_model_dir` / `ground_tile` / `upper_tile` / `cliff_class` / `name_key` / `in_beta` |
| `TerrainTileDef` | `Terrain` | `tileID` | `tile_id` / `cliff_set` / `buildable` / `walkable` / `flyable` / `dir` / `file` / `name_key` |
| `WaterTypeDef` | `Water` | `waterID` | `water_id` / `height` / `tex_file` / `num_tex` / `shallow_min/max` / `deep_min/max` / `shore_*` |
| `WeatherEffectDef` | `Weather` | `effectID` | `effect_id` / `tex_dir` / `tex_file` / `lifespan` / `particles` / 颜色三段 |

**约定**：
- ID 第 2 字符 = 地形集字母（`CLdi` → `L`）
- tileID 首字符 = 地形集字母（`Ldrt` → `L`）
- `name_key` / `comment` 优先前者；`display_name_key()` 返回

---

## 4. `scripts/map/data/` — 纯数据类

> 原则：Data 不进场景树，无业务规则。**单顶点用 `vertex_at()` → `Wc3TileVertex`**，不要手写 `hf["heights"][i]`。

### 4.1 高度场核心

| 类 | 职责 | 关键字段 |
|----|------|----------|
| `Wc3Heightfield` | SoA 平行数组；对应 `terrain-heightfield.json` | `width/height` / `map_width/height` / `tile_size` / `center_offset` / `main_tileset` / `ground_tilesets` / `cliff_tilesets`；SoA: `heights` / `layer_heights` / `water_heights` / `flags_packed` / `ground_textures` / `ground_variations` / `cliff_textures` / `cliff_variations` |
| `Wc3TileVertex` | 单顶点视图，getter/setter 直写 SoA | `heightfield` / `ix` / `iy` / `index`；属性 `height` / `layer` / `water_height` / `ground_texture` / `ground_variation` / `cliff_texture` / `cliff_variation` |
| `Wc3DoodadList` | doodads.json 内存 SoA；`to_dict()` → AoS | 根：`format_version` / `subversion` / `special_doodads` / `bytes_remaining`；SoA：`ids` / `variations` / `pos_*` / …；`rebuild_by_id` / `at(i)` / `append_dict` / `load_json_path` |
| `Wc3Doodad` | 单条 doodad 视图 | `list` / `index`；`id` / `variation` / `position` / `angle` / `scale` / `life` / … |
| `Wc3UnitList` | units.json 内存 SoA；`to_dict()` → AoS | 根：`format_version` / `subversion` / `bytes_remaining`；SoA：`type_ids` / `owners` / …；`rebuild_by_type_id` / `rebuild_by_owner` / `at(i)` / `load_json_path` |
| `Wc3UnitPlacement` | 单条单位放置视图 | `list` / `index`；`type_id` / `owner` / `position` / `hero_level` / … |
| `Wc3Coords` | WC3 ↔ Godot 坐标 | 常量：`TILE_SIZE=128.0` / `WORLD_SCALE=0.01` / `FLAG_WATER=1` / `FLAG_RAMP=4`；静态方法 `wc3_to_godot` / `tilepoint_wc3` / `yaw_wc3_to_godot` |
| `Wc3ParsedMap` | `map-parsed/<slug>/` 薄包装 | `slug` / `dir_res` / `heightfield` / `doodads` / `units` / `terrain_header` / `info` / `summary`；`load_dir` / `doodad_at` / `unit_at` |

### 4.2 Logic → Present 契约

| 类 | 职责 | 关键字段 |
|----|------|----------|
| `Wc3CliffPlacement` | 直崖放置契约 | `ix` / `iy` / `tag` / `base_layer` / `cliff_tex_index` / `model_dir` / `variation`；`static make(...)` |
| `Wc3CliffTopologyResult` | 一次拓扑扫描的只读输出 | `placements: Array[Wc3CliffPlacement]` / `gap_mask: PackedByteArray`（地表格 1=挖洞）/ `gap_stats` |
| `Wc3CliffBuildResult` | Present 输出：placements → MultiMesh 分组 | 内嵌 `Group`: `glb` / `cliff_tex_index` / `transforms` / `tiles` / `base_layers` |
| `Wc3RampPlacement` | 斜坡 CliffTrans 放置 | `ix` / `iy` / `tag` / `axis` (h/v/d) / `variation` (straight/diagonal/l) / `has_glb` |
| `Wc3RampCollectResult` | Logic.collect_placements 输出 | `placements` / `romp: PackedByteArray`（运行时，不进 JSON） |

**约束**：
- Present 禁止改 Heightfield；只拿本结构 + Catalog 做资源解析与挂接
- "数据驱动"含义：换图 = 换 JSON/SLK；规则代码不写死某张图

---

## 5. `scripts/map/catalog/` — 资源映射

> 运行时扫盘，不检入 `.tres` 登记表。所有缓存经 `RuntimeAssets.project_abs` / `converted_path` 解析。

| 类 | 职责 | 关键 API |
|----|------|----------|
| `Wc3CliffCatalog` | 直崖 Catalog：CliffTypeDef 表列 + 岩壁 PNG / Cliffs GLB 变体解析 | `load_default()` / `cliff_ids_for_tileset(letter)` / `png_for_cliff_id(id)` / `ground_tile_for_cliff_id(id)` / `cliff_model_dir(id)` / `resolve_glb(tag, var)` / `pick_cliff_variation(...)` |
| `Wc3CliffTransCatalog` | CliffTrans / CityCliffTrans 模型目录 | `FAMILY_CLIFF_TRANS="CliffTrans"` / `FAMILY_CITY_CLIFF_TRANS="CityCliffTrans"`；角序 `TL=0 / TR=1 / BR=2 / BL=3`（**与直崖 Cliffs 的 BL/TL/TR/BR 不同**）；`VALID_CHARS="ABCHLX"`；`rebuild_from_disk()` / `load_cliff_trans()` / `load_city_cliff_trans()` |
| `Wc3GroundTileCatalog` | 地面纹理资源映射 → Texture2DArray | `ATLAS_W=512 / ATLAS_H=256`；`static build_texture_array(tilesets, tiles)` / `build_extended_flags(tilesets, tiles)` |
| `Wc3IdCatalog` | 四字符 ID（unit/destructable/doodad）→ SLK / GLB | `load_default()`（加载 Units/unitUI / Destructables / Doodads）/ `lookup(type_id)` / `model_base_path(type_id)` / `converted_glb_path(type_id, var=0)` |
| `Wc3TerrainTileCatalog` | 旧 Catalog（已收缩，仅地表） | `tile_ids_for_tileset(letter)` / `png_for_ground_index(tilesets, idx)` / `is_buildable(tile_id)` |

**变体上限不写死表**：`Wc3CliffCatalog` 按磁盘探测 `Cliffs{TAG}{n}.glb`，`VAR_PROBE_MAX=8` 探测上限（WE 直崖变体通常 ≤3）。

---

## 6. `scripts/map/infra/` — 地图基础设施

| 脚本 | 职责 |
|------|------|
| `runtime_assets.gd` | 路径 resolve；`project_abs(res_path)` / `converted_path(rel)` / `slk_path(rel)` / `load_image(path)` / `file_exists(path)` |
| `map_model_cache.gd` | GLB 场景/网格缓存（单位/装饰按 type_id 缓存） |
| `map_placeholders.gd` | 缺模灰盒（`MeshInstance3D` + 简单几何） |

全项目日志见 `scripts/shared/infra/app_log.gd`（`AppLog`）。

---

## 6b. `scripts/shared/infra/` — 共享基础设施

| 脚本 | 职责 |
|------|------|
| `app_log.gd` | 统一调试日志；按层分组（`AppLog.Layer.CATALOG` / `LOGIC` / `PRESENT` / `GAME` / `GM` …） |

---

## 7. `scripts/map/logic/` — 规则与计算

> Domain 纯计算。**不碰场景树**；输出 `{ mesh }` / `{ groups[] }` / `{ placements[] }` 等结构化结果。

### 7.1 `terrain/`

| 脚本 | 职责 | 关键 API |
|------|------|----------|
| `wc3_terrain_logic.gd` | 高度图 / 地表逻辑；只改 `Wc3Heightfield`，不建 Mesh | 常量：`LAYER_MIN=0` / `LAYER_MAX=14` / `FLAT_LAYER=2` / `VARIATION_CHANCE_SUM=570` + 18 项加权表；`bind(hf)` / `is_bound()` / `random_ground_variation(rng)` / `set_ground_tex(...)` / `set_height(...)` / 脏矩形 (`dirty_min/max`, `clear_dirty`) |

### 7.2 `cliff/`

| 脚本 | 职责 | 关键 API |
|------|------|----------|
| `wc3_cliff_logic.gd` | 笔刷 + 拓扑 TAG/叠段/挖洞（吸收自原 `Wc3CliffTiles`） | `is_cliff_tile` / `cliff_slices_at` / `count_gaps` / `paint_cliff_corner` / `_propagate_cliff_adjacency`（`MAX_CLIFF_ADJ_DELTA=2`）/ `_sync_cliff_corner_textures`（策略 B） |

### 7.3 `ramp/`

| 脚本 | 职责 |
|------|------|
| `wc3_ramp_paint.gd` | Paint ≈ `update_ramp`；只写 `FLAG_RAMP`（**不**写 HF 高度） |
| `wc3_ramp_collect.gd` | Collect ≈ `update_cliff_meshes` 数据侧；输出 `Wc3RampCollectResult`（含 `romp`） |
| `wc3_ramp_logic.gd` | 斜坡逻辑层入口（对齐 HiveWE / [RAMP_WE.md](../design/ramp/RAMP_WE.md)） |

权威：[RAMP_WE.md](../design/ramp/RAMP_WE.md) §4-§5。

---

## 8. `scripts/map/presentation/` — 场景层

> 只挂树，消费 Logic 输出。**禁止**改 `flags` / `layerHeights` / 拓扑。

### 8.1 顶层（MapRoot 编排）

| 脚本 | 职责 | 关键 API |
|------|------|----------|
| `map_loader.gd` | 读 JSON/内存 hf；建 Context；按序调 Layer；export 开关；状态栏；碰撞；查看栅格 | `_ready` → `Wc3TerrainTileCatalog.load_default()` → [可选] `Wc3IdCatalog.load_default()` → [auto_load_on_ready] `_load_all()`；可走 `reload_from_hf(hf, info, map_dir)` / `rebuild_terrain_only` / `rebuild_terrain_cliffs_water` |
| `map_build_context.gd` | 共享 `hf` / `meta` / `info` / `tiles` / `catalog` / `cache`；`ensure_cliff_topology()` 只算一次 | 跨层共享状态；不要在 Layer 直读 hf |
| `orbit_camera.gd` | 主场景预览相机 | WASD/QE/Shift/右键/滚轮 |

模型 `.scn` 门面已迁至 [`scripts/presentation/wc3_model/`](#8b-scriptspresentationwc3_model--模型门面)（见下）。

### 8b. `scripts/presentation/wc3_model/` — 模型门面

> 游戏 / 编辑器 / 地图单位层共用；**不是** map 地形拓扑。契约见 [WC3_MODEL_SCENE.md](../design/presentation/WC3_MODEL_SCENE.md)。

| 脚本 | 职责 |
|------|------|
| `wc3_model_scene.gd` | bake `.scn` 根门面：挂点 / AP / `play_logical` |
| `wc3_anim_player.gd` | `extends AnimationPlayer`：族 rarity 抽签 + play |
| `anim_playback.gd` | 名规范化 / 找 AP / 低层 play（无状态） |
| `anim_sequence_resolver.gd` | Stance×Activity → 逻辑名 |
| `anim_soft_loop.gd` | ping-pong 软循环 |
| `mdx_anim_events.gd` | Event Method Track 回调 |
| `model_visual_sync.gd` | 旧 `assets/visuals` ExtResource 兼容 |

PE2 / UberSplat 仍在 `scripts/map/presentation/effects/`（地图装饰物与单位共用）。

### 8.2 `mesh/`

| 脚本 | 职责 |
|------|------|
| `heightfield_mesh.gd` | `MeshInstance3D` 薄封装；三角/四边形组装 |

### 8.3 `layers/`（待精读确认完整列表）

按 MAP_ARCHITECTURE.md 节点树：

| 脚本 | 对应节点 |
|------|----------|
| `map_terrain_layer.gd` | `Terrain/Ground`（MeshInstance3D） |
| `map_cliff_layer.gd` | `Cliffs`（运行时 MultiMeshInstance3D 子节点） |
| `map_ramp_layer.gd` | `Ramps` |
| `map_water_layer.gd` | `Water/Surface` |
| `map_doodad_layer.gd` | `Doodads` |
| `map_unit_layer.gd` | `Units` |
| `map_debug_grid_layer.gd` | `DebugGrid` |
| `map_ramp_debug_layer.gd` | `RampDebug` |

**契约差异**（MAP_ARCHITECTURE §7.2 指出）：Terrain/Cliff/Water 用 `build(ctx)`；Doodad/Unit 仍用 `build(json)`（**未吃 Context** —— P1 重构项）。

### 8.4 `water/`

| 脚本 | 职责 |
|------|------|
| `wc3_water_params.gd` | `Water.slk` → 序列帧/深浅色 |
| `wc3_water_mesh.gd` | 水面 ArrayMesh |
| `wc3_shoreline_builder.gd` | 岸浪发射点 |
| `wc3_shore_foam.gd` | 岸浪 MultiMesh / 粒子近似 |

### 8.5 `cliff/`、`ramp/`

> 详见 `MAP_ARCHITECTURE.md §2.1` / §2.2（构建器：placements → MultiMesh）。

---

## 9. 自动加载与目录的对应

| Autoload | 注册 | 路径 |
|----------|------|------|
| `AssetProvider` | `project.godot` | [`addons/asset_provider/asset_provider.gd`](../../addons/asset_provider/asset_provider.gd) |
| `EditorI18n` | `project.godot` | [`editor/ui/editor_i18n.gd`](../../editor/ui/editor_i18n.gd) |
| `Wc3DefStore` | `project.godot` | `scripts/auto/wc3_def_store.gd` |

---

## 10. 重构方向（与 MAP_ARCHITECTURE §7.3 一致）

- **P1** 统一 Layer 契约：Doodad/Unit 改 `build(ctx)`；JSON 由 Loader/Context 预解析
- **P1** Pipeline 配置化：`_load_all` 步骤表 `{ id, enabled, build }`
- **P1** 泡沫参数单源：`Wc3WaterBuildOptions` 或挂 Context，去字段拷贝
- **P2** 目录归位：`app/` `layers/` `domain/` `infra/` `view/`（可用 `class_name` 减路径痛）

---

## 11. 何时查哪里

| 想改什么 | 去哪 |
|----------|------|
| 高度图字段 / 顶点读写 | `data/wc3_heightfield.gd` / `data/wc3_tile_vertex.gd` |
| 坐标变换 | `data/wc3_coords.gd` |
| SLK 表字段 | `definitions/terrain_art/*_def.gd` |
| 悬崖/斜坡目录解析 | `catalog/wc3_cliff_catalog.gd` / `wc3_cliff_trans_catalog.gd` |
| 地面纹理 → Texture2DArray | `catalog/wc3_ground_tile_catalog.gd` |
| 单位/装饰 ID → 模型 | `catalog/wc3_id_catalog.gd` |
| 资源路径 | `infra/runtime_assets.gd` |
| 缺模灰盒 | `infra/map_placeholders.gd` |
| 加载顺序与开关 | `presentation/map_loader.gd` |
| Layer 挂树 | `presentation/layers/*_layer.gd` |
| 地形三角形 / 留缝 | `logic/terrain/wc3_terrain_logic.gd`（旧 `wc3_terrain_autotile.gd`） |
| 悬崖判定 / 叠段 | `logic/cliff/wc3_cliff_logic.gd` |
| 斜坡 Paint/Collect | `logic/ramp/wc3_ramp_*.gd` |
| 水面几何 | `presentation/water/wc3_water_mesh.gd` |
| 岸浪 | `presentation/water/wc3_shoreline_builder.gd` / `wc3_shore_foam.gd` |
