# 地图运行时架构

> 范围：Godot 侧如何把 `assets/map-parsed/*` + SLK + 转换后 GLB/PNG 变成可游玩场景。  
> 不含离线工具链细节（见 README / 各 `tools/*/README.md`）。水体专项见 [WATER.md](WATER.md)。
>
> **状态（已合入 `master`）：** `MapBuildContext`、统一资源入口、死代码清理已完成。  
> **仍可选：** 物理目录归位（`domain/` / `layers/` / `infra/`）、Pipeline 配置化。

原则：**离线解析 → 运行时装配 → 分层渲染**。

---

## 1. 分层约定

依赖只允许自上而下：

```text
Presentation（场景节点）
  MapRoot / *Layer / OrbitCamera / UI
  挂节点、设材质、MultiMesh、清空子节点
        │ 消费 Mesh / Transforms / placements
Application（装配）
  MapLoader + MapBuildContext
  读 JSON、建 Context、按序调 Domain、把结果交给层
        │ 纯函数 / RefCounted 构建器
Domain（WC3 规则，无 Node）
  Autotile / Cliff* / WaterMesh / Shore* / Coords / Catalog / WaterParams
  heightfield → 几何或实例列表（不碰场景树）
        │ 读表、读盘、缓存
Infrastructure
  RuntimeAssets / MapModelCache / AssetProvider
```

文件仍集中在 `scripts/map/`；命名上 `Map*` ≈ 场景层，`Wc3*` ≈ Domain。物理拆目录见 §6。

---

## 2. 离线产物 → 运行时输入

```text
经典客户端 MPQ
    │ tools/mpq-extract
    ▼
.cache/wc3-assets/          （原始 BLP/MDX/…，gitignore）
    │ tools/asset-convert / slk-export / map-parse
    ▼
assets/
  map-parsed/<slug>/        ← 地图 JSON（本架构主输入）
  slk-exported/             ← 表数据（单位/装饰/地形/水体参数）
  asset-converted/          ← PNG/GLB（.gdignore，运行时按需加载）
```

`map-parsed/<slug>/` 关键文件：

| 文件 | 用途 |
|------|------|
| `terrain-heightfield.json` | 高度、水面高、flags、地表/悬崖索引（主数据） |
| `info.json` | 地图名、flags（如 `waterWavesCliff`） |
| `units.json` / `doodads.json` | 单位与装饰物实例 |
| 其它 | `terrain.json`、`summary.json` 等，预览阶段可选 |

---

## 3. 场景与加载链

### 3.1 场景树

```text
Main (scenes/main.tscn)
├── WorldEnvironment / Sun
├── MapRoot (scenes/map/map_root.tscn) ← MapLoader
│   ├── Terrain / Ground          MapTerrainLayer + HeightfieldMesh
│   ├── Cliffs                    MapCliffLayer
│   ├── Water / Surface           MapWaterLayer + HeightfieldMesh
│   ├── Doodads                   MapDoodadLayer
│   └── Units                     MapUnitLayer
├── OrbitCamera
└── UI/Status
```

### 3.2 加载顺序（`MapLoader._load_all`）

```text
读 terrain-heightfield.json + info.json
    → MapBuildContext.create(...)
    → ctx.ensure_cliff_topology()     # romp / ramp / gaps 只扫一次
    → Terrain.build(ctx)
    → Cliffs.build(ctx)               # 可关 build_cliffs
    → Water.build(ctx)                # 水面 + 岸浪；可关 build_water
    → Units.build(units.json)         # 默认开 place_units
    → Doodads.build(doodads.json)     # 默认开 place_doodads
```

共享对象由 Loader 创建并注入 Context：`Wc3TerrainTiles`、`Wc3IdCatalog`、`MapModelCache`。

### 3.3 `MapBuildContext`

一次加载解析 heightfield **一次**，各层共用：

| 字段 | 含义 |
|------|------|
| `map_dir` / `hf` / `meta` | 地图目录、原始 JSON、`read_heightfield_meta` 结果 |
| `info` / `map_flags` | info.json 与其中 flags |
| `main_tileset` | 如 `"I"` |
| `tiles` / `catalog` / `cache` | SLK 索引与 GLB 缓存 |
| `cliff_romp` / `cliff_ramp_placements` / `cliff_gap_stats` | `ensure_cliff_topology()` 后有效 |

Layer 签名以 `build(ctx)` 为主；Builder 可收可选 `meta`，避免再拆 JSON。

---

## 4. 文件职责（`scripts/map/`）

### 编排 / 场景层

| 文件 | 角色 |
|------|------|
| `map_loader.gd` | 读 JSON、建 Context、排程各层、状态栏 |
| `map_build_context.gd` | 单次加载共享状态与悬崖拓扑 |
| `map_terrain_layer.gd` | 地面：Autotile → shader |
| `map_cliff_layer.gd` | 悬崖：实例收集 → MultiMesh + 高度变形（经 MapModelCache） |
| `map_water_layer.gd` | 水面 + 岸浪编排 |
| `map_doodad_layer.gd` | 装饰物 GLB / MultiMesh / 占位 |
| `map_unit_layer.gd` | 单位 GLB / 占位 |
| `heightfield_mesh.gd` | MeshInstance3D 薄封装（挂 mesh / 材质） |
| `orbit_camera.gd` | 预览相机（非地图逻辑） |

### Domain（`Wc3*` + heightfield 工具）

| 文件 | 角色 |
|------|------|
| `wc3_coords.gd` | WC3 ↔ Godot；`FLAG_WATER` / `FLAG_RAMP` |
| `heightfield_mesh_builder.gd` | `sample_vert` + `read_heightfield_meta`（几何由各 Builder 自建） |
| `wc3_terrain_tiles.gd` | 地表/悬崖贴图与 `cliffModelDir` / `rampModelDir` |
| `wc3_terrain_autotile.gd` | 官方图集 bitmask 地面网格 |
| `wc3_cliff_tiles.gd` | 悬崖 TAG、斜坡、GAP、`resolve_glb` |
| `wc3_cliff_builder.gd` | 悬崖/斜坡实例 transform 收集 |
| `wc3_cliff_height_map.gd` | 悬崖变形用高度纹理 |
| `wc3_water_params.gd` | Water.slk → 贴图序列 / 偏移 / 深度色 |
| `wc3_water_mesh.gd` | 水面网格（斜坡不画水） |
| `wc3_shoreline_builder.gd` | 岸浪发射点 |
| `wc3_shore_foam.gd` | 岸浪 MultiMesh + PE2 近似 |
| `wc3_id_catalog.gd` | 四字符 ID → SLK / GLB |

### Infrastructure

| 文件 | 角色 |
|------|------|
| `runtime_assets.gd` | `converted_path` / `slk_path` / `load_*`；经 AssetProvider `resolve` |
| `map_model_cache.gd` | GLB 场景/网格缓存（Cliff / 单位 / 装饰共用） |
| `map_placeholders.gd` | 缺模占位体 |
| `addons/asset_provider/` | Autoload：overlay → converted → `.cache`（含 .blp→.png / .mdx→.glb） |

### 着色器（`shaders/`）

| 文件 | 用途 |
|------|------|
| `wc3_ground.gdshader` | 地表多层图集 |
| `wc3_cliff.gdshader` | 悬崖贴图 + 高度变形 |
| `wc3_water.gdshader` | 水面序列帧 + 深浅色 |
| `wc3_shore_foam.gdshader` | 岸浪 XYQuad Additive |

---

## 5. 数据流

```mermaid
flowchart TB
  subgraph Offline
    MPQ[经典 MPQ]
    PARSE[map-parse / slk-export / asset-convert]
    MPQ --> PARSE
  end

  subgraph Inputs
    HF[terrain-heightfield.json]
    INFO[info.json]
    SLK[slk-exported]
    GLB[asset-converted PNG/GLB]
  end
  PARSE --> HF & INFO & SLK & GLB

  subgraph App
    CTX[MapBuildContext]
    LOADER[MapLoader]
  end
  HF & INFO --> CTX
  SLK --> CTX
  LOADER --> CTX

  subgraph Domain
    G[Ground Autotile]
    C[CliffBuilder]
    W[WaterMesh]
    S[ShorelineBuilder]
  end
  CTX --> G & C & W & S

  subgraph Layers
    LT[TerrainLayer]
    LC[CliffLayer]
    LW[WaterLayer]
    LD[Doodad/UnitLayer]
  end
  G --> LT
  C --> LC
  W & S --> LW
  GLB --> LD
  CTX --> LD
```

Domain 输出契约（Layer 不碰规则，只实例化）：

| 系统 | 输入 | 输出（不碰场景） |
|------|------|------------------|
| Ground | ctx | `{ mesh, gap_count, … }` |
| Cliff | ctx | `{ groups: [{ glb, tex_idx, transforms[] }] }` |
| Water | ctx | `{ mesh, cell_count, skipped_ramp }` |
| Shore | ctx | `{ placements[] }` |
| Foam | placements | 由 `Wc3ShoreFoam` / WaterLayer 建 MultiMesh |
| Doodad/Unit | JSON + catalog + cache | 直接挂子节点（可再抽描述列表） |

---

## 6. 后续（可选）

| 项 | 说明 |
|----|------|
| **目录归位** | 按 §1 把文件搬到 `app/` / `layers/` / `domain/` / `infra/` / `view/`；`class_name` 可减轻路径改动 |
| **Pipeline 配置化** | `build_water` / `place_doodads` 等改成步骤列表，便于单层测试 |
| **收紧 Domain 输出** | 单位/装饰也先出描述再由 Layer 实例化；材质绑定继续下沉 |

建议目录（尚未落地）：

```text
scripts/map/
  app/          map_loader.gd, map_build_context.gd
  layers/       map_*_layer.gd, heightfield_mesh.gd
  domain/       wc3_*.gd, heightfield_mesh_builder.gd
  infra/        runtime_assets.gd, map_model_cache.gd, map_placeholders.gd
  view/         orbit_camera.gd
```

自测门槛：Lost Temple 主场景可运行 + `tools/selftest_shoreline.gd` 通过。

---

## 7. 明确不做 / 暂缓

| 项 | 原因 |
|----|------|
| 运行时直接读 MPQ | 规划在玩家端 GDExtension；开发期继续用预解析 JSON |
| 完整 PE2 / 触发器 / 寻路 | 预览阶段未开工；岸浪仅近似 |
| Domain 写成 GDExtension | 过早；先把 GDScript 边界划清 |
| 合并全部 `Wc3Cliff*` 为一个上帝类 | 判定与实例化宜保持分离 |

---

## 8. 相关文档

- [README.md](../README.md) — 首次解包 / 转换 / 解析
- [WATER.md](WATER.md) — 水体与岸浪对标
- [WC3_ASSET_PATHS.md](WC3_ASSET_PATHS.md) — 经典资产路径
- [LEGAL.md](LEGAL.md) — 资产合规
