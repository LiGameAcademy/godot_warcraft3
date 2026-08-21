# 分层架构：数据 · 资源映射 · 逻辑 · 表现 · 编辑

> 目标：用 **WC3 数据 + 资产** 建映射，再在其上写逻辑，最后在逻辑正确的前提下做渲染。  
> 难点与终点都在「映射正确」；表现层只消费映射结果。  
> 相关：[MAP_DATA.md](docs/architecture/MAP_DATA.md) · [ROADMAP.md](docs/roadmap/ROADMAP.md) · [MAP_ARCHITECTURE.md](docs/architecture/MAP_ARCHITECTURE.md) · [EDITOR.md](docs/editor/EDITOR.md) · [HEX_MAP_LESSONS.md](docs/terrain/HEX_MAP_LESSONS.md)  
> 最后更新：2026-08-10（新增 WorldMembership 在场性抽象；F2 已落地进矿 / 工地）

---

## 1. 原则是否合理？

**合理，且应作为本仓库的硬门禁。**

| 驱动方式 | 含义 | 本项目落点 |
| ---------- | ------ | ------------ |
| **设计驱动** | 先文档/契约，再改代码 | `docs/*` + `.cursor/rules` |
| **数据驱动** | 地图态来自 map-parsed JSON / SoA，不靠硬编码场景 | `scripts/map/data/` |
| **资产驱动** | ID / TAG / tileset → 贴图·模型路径由 Catalog 查，不散落 `load()` | `scripts/map/catalog/`（目标目录） |

禁止：在 Layer / Mesh 脚本里直接改 `flags`、算拓扑；禁止在笔刷里拼 GLB 路径。

---

## 2. 五层职责

```text
┌─────────────────────────────────────────────────────────┐
│  Editor（编辑层）  Editor 总管 + Document / Tools / UI   │
│  改数据、调逻辑 API；不建 Mesh、不 resolve 资产路径       │
└───────────────────────────┬─────────────────────────────┘
                            │ mutate / query · 请求重建
┌───────────────────────────▼─────────────────────────────┐
│  Logic（逻辑层）  Domain：拓扑、门禁、选型、placements   │
│  输入 Heightfield + Catalog；输出「放什么 / 哪张贴图索引」│
└─────────────┬─────────────────────────────┬─────────────┘
              │ 读/写地图态                  │ 查资产
┌─────────────▼─────────────┐   ┌───────────▼─────────────┐
│  Data（数据映射）           │   │  Catalog（资源映射）      │
│  JSON ↔ RefCounted / SoA  │   │  ID/TAG/tile → 路径/索引 │
│  不含 Godot Mesh           │   │  不含「这一格该用哪 TAG」  │
└───────────────────────────┘   └───────────┬─────────────┘
                                            │
┌───────────────────────────────────────────▼─────────────┐
│  Presentation（表现层）  MapRoot / Layer / Mesh         │
│  只消费 placements + 已解析资源；不写 heightfield         │
└─────────────────────────────────────────────────────────┘
```

### 2.1 编辑层总管：`Editor`

**同意并定为契约：** 编辑层有一个明确的 **总管节点**，不要把编排脚本挂在场景根上散落 `$` 路径。

| 项 | 约定 |
|----|------|
| 类型 | `extends Node`（不继承 `Node3D`；世界与相机仍是兄弟节点） |
| 场景位置 | `editor/scenes/editor_main.tscn` 的 **直接子节点** |
| 脚本 | 目标 `editor/scripts/editor.gd`；`class_name` 建议 `MapEditor`（避免与引擎概念混淆；口语可称 Editor） |
| MapRoot | `@export var map_root: MapLoader`（或 Node 路径 + 类型提示）**注入**，禁止写死依赖场景根脚本 |
| 职责 | 持有/创建 `MapDocument`；串联 Tools、UI、Camera、对话框；把脏区交给 `map_root` 重建 |
| 禁止 | 组 Mesh、算崖 TAG、拼 GLB 路径 |

目标场景树（示意）：

```text
EditorMain (Node3D)                    ← 场景壳：环境光、挂载子节点；无业务脚本或仅薄壳
├── Editor (Node)                      ← 总管 MapEditor；@export map_root → MapRoot
├── MapRoot (instance)                 ← 表现入口 MapLoader
├── EditorCamera
├── TerrainBrush                       ← 由 Editor 在 _ready 绑定，或 @export 注入
├── NewMapDialog
└── UI (CanvasLayer)
    └── …
```

现状：`EditorMain` 根节点挂 `editor_app.gd`（`Node3D`）并用 `$MapRoot`。迁徙时把编排迁入子节点 `Editor`，根只保留 3D 世界壳；`editor_app.gd` 可改名/瘦身为兼容层后删除。

细节见 [EDITOR.md](docs/editor/EDITOR.md)。

### 2.2 命名与目录（摘要）

| 前缀 / 目录 | 层 |
| ------------- | ---- |
| `scripts/map/data/` | 数据映射 |
| `scripts/map/catalog/` | 资源映射 |
| `scripts/map/logic/` | 逻辑 |
| `scripts/map/presentation/` | 表现（Loader / Layer / Mesh） |
| `scripts/map/infra/` | 读盘、缓存、占位 |
| `editor/scripts/` | 编辑（`editor.gd` 总管 + document / tools / ui） |

完整树见 **§4**。短期内可平铺，但 **新文件按目标目录落位**；旧文件渐进搬迁。

---

## 3. 对现有脚本的裁决

### 3.1 `wc3_coords.gd` → 可否进 `data/`？

**可以，作为数据层的「基础常量与 WC3 空间工具」。**

| 内容 | 归属 |
|------|------|
| `TILE_SIZE`、`FLAG_WATER` / `FLAG_RAMP`、`tilepoint_wc3` | **Data**（纯 WC3） |
| `wc3_to_godot` / `yaw_wc3_to_godot` | 表现边界；可仍放在同一脚本，由 Presentation 调用，**逻辑层禁止用 Godot 坐标做拓扑** |

不要做成 Catalog；它不是资产表。

### 3.2 `heightfield_mesh_builder.gd` 是否还有必要？

**已删除。** meta → `Wc3Heightfield`；`sample_vert` / 三角四边形 → `HeightfieldMesh`。

### 3.3 `wc3_cliff_trans_catalog.gd` 抽象如何？算数据层吗？

**抽象方向正确，但属于 Catalog（资源映射），不是 map-parsed 数据层。** 运行时 `load_*()` 扫盘，不检入 `.tres` 登记表。

### 3.4 与 `wc3_cliff_tiles.gd` 是否重叠？

**拆清：** Tiles = 逻辑选型；Catalog = TAG→路径；Layer = 挂树。

### 3.5 地形纹理 / Autotile

**已落地：**

1. `docs/terrain/TERRAIN_TILES.md`  
2. `Wc3GroundTileCatalog` → `Texture2DArray`  
3. bitmask / 组网在 `MapTerrainLayer`；底层画网格在 `HeightfieldMesh`  
4. 静态材质 `assets/materials/wc3_ground_material.tres`（shader 在 `assets/shaders/`）

原 `wc3_terrain_autotile.gd` 已并入 Layer + Catalog。

### 3.6 `wc3_id_catalog.gd` 与统一 Catalog 层

**算 Catalog，不算 map-parsed Data。**

| Catalog | 键 | 值 |
|---------|----|----|
| `Wc3IdCatalog` | 四字符单位/装饰 ID | 显示名、GLB 候选路径 |
| `Wc3GroundTileCatalog` | tileset 列表 | Texture2DArray / extended |
| `Wc3CliffCatalog`（目标） | 家族 + TAG + var | Cliffs GLB |
| `Wc3CliffTransCatalog` | TAG + var | CliffTrans GLB |

---

## 4. 目标目录拆分（可读性）

原则：**一层一目录**；逻辑/表现内再按 **子系统**（terrain / cliff / ramp / water / doodad / unit）分子目录。  
搬迁服从 [ROADMAP.md](docs/roadmap/ROADMAP.md)：先契约与 Ground 管线，再机械 `git mv`，避免大爆改。

### 4.1 `scripts/map/`（运行时地图）

```text
scripts/map/
├── data/                          # 数据映射
│   ├── wc3_coords.gd
│   ├── wc3_heightfield.gd
│   ├── wc3_tile_vertex.gd
│   ├── wc3_parsed_map.gd
│   └── …                          # placements / topology 结果
│
├── catalog/                       # 资源映射：运行时扫盘 / resolve
│   ├── wc3_id_catalog.gd
│   ├── wc3_terrain_tile_catalog.gd
│   ├── wc3_ground_tile_catalog.gd
│   ├── wc3_cliff_catalog.gd
│   └── wc3_cliff_trans_catalog.gd
│
├── logic/                         # 规则 / API（无 Node）
│   ├── terrain/
│   ├── cliff/
│   └── ramp/
│
├── presentation/                  # 表现：挂树 + 建 Mesh
│   ├── map_loader.gd
│   ├── map_build_context.gd
│   ├── orbit_camera.gd
│   ├── layers/                    # 全部 Map*Layer
│   │   ├── map_terrain_layer.gd
│   │   ├── map_cliff_layer.gd
│   │   ├── map_ramp_layer.gd
│   │   ├── map_ramp_debug_layer.gd
│   │   ├── map_water_layer.gd
│   │   ├── map_doodad_layer.gd
│   │   ├── map_unit_layer.gd
│   │   └── map_debug_grid_layer.gd
│   ├── mesh/
│   ├── …                          # water / cliff 等地图子系统
│   └── （过渡）wc3_model_scene / wc3_anim_player …
│       # 目标迁出 → scripts/presentation/wc3_model/，见 docs/design/presentation/WC3_MODEL_SCENE.md
│   │   └── heightfield_mesh.gd
│   ├── cliff/
│   │   ├── wc3_cliff_builder.gd
│   │   └── wc3_cliff_height_map.gd
│   └── water/
│       ├── wc3_water_mesh.gd
│       ├── wc3_water_params.gd
│       ├── wc3_shoreline_builder.gd
│       └── wc3_shore_foam.gd
│
└── infra/                         # 地图基建
    ├── runtime_assets.gd
    ├── map_model_cache.gd
    └── map_placeholders.gd

# 全项目日志：scripts/shared/infra/app_log.gd（AppLog）
```

**`MapBuildContext`：** 单次构建会话（tiles / catalog / cache / 崖拓扑缓存），**不是**数据权威。权威地形态是 `Wc3Heightfield`。`hf`/`meta` 字典视图为过渡兼容，Layer 优先读 `ctx.heightfield`。

| 现文件 | 状态 |
|--------|------|
| ~~`wc3_terrain_autotile.gd`~~ | ✅ 并入 `MapTerrainLayer` + Catalog |
| ~~`heightfield_mesh_builder.gd`~~ | ✅ 并入 `HeightfieldMesh` / `Wc3Heightfield` |
| Layer / water / infra 平铺 | ✅ 已迁入 `presentation/` · `infra/` |

### 4.2 `editor/`（编辑层）

```text
editor/
├── scenes/
│   └── editor_main.tscn           # 壳 + 子节点 Editor / MapRoot / UI …
├── resources/
├── locale/
└── scripts/
    ├── editor.gd                  # 总管 MapEditor（Node）；@export map_root
    ├── document/
    │   └── map_document.gd        # 会话文档；持有 Wc3Heightfield
    ├── tools/
    │   └── terrain_brush.gd       # 拾取与笔划；只调 Document / Editor
    ├── camera/
    │   └── editor_camera.gd
    ├── ui/                        # 菜单、工具条、浮窗、对话框、i18n
    └── settings/
        └── editor_settings_store.gd
```

- **总管**只做接线与生命周期；具体笔刷算法在 `tools/`，文档在 `document/`，Chrome 在 `ui/`。  
- 现状 `editor_app.gd` → 迁入 `editor.gd` 后删除或变薄壳。

### 4.3 `docs/` 与 rules

| 路径 | 用途 |
|------|------|
| `docs/architecture/LAYERED_ARCHITECTURE.md` | 本文（总纲） |
| `docs/architecture/MAP_DATA.md` / `TERRAIN_TILES.md` / `CLIFF.md` … | 单域规则 |
| `.cursor/rules/map-*.mdc` | vibecoding 门禁 |

---

## 5. 模块开发节奏（强制顺序）

每个玩法/渲染模块一律：

```text
1. Data     定义/扩展数据类型与 JSON 映射
2. Catalog  （若需要资产）建立 ID→资源表与文档
3. Logic    API：读邻域、改顶点、产出 placements / 选中索引
4. Present  Mesh / MultiMesh / Layer 只读结果
5. Editor   笔刷与 UI 调 Logic API
```

**禁止**先堆表现再反推数据；**禁止**跳过 Catalog 在 Layer 里硬编码路径。

---

## 6. 脚本拆分尺度（表现层尤甚）

**目标：** 可读、可维护；**禁止**为拆而拆，也**禁止**上帝类。

| 该拆 | 不该拆 |
|------|--------|
| 跨层边界（Data / Catalog / Logic / Present） | 一行转发的 `*Builder` |
| ≥2 个无关模块共用的底层能力 | 同一职责拆成多个几乎空的文件 |
| Node 挂树 vs 纯算法 vs 落盘 Resource | Catalog 解析与 Layer 组网揉成一个 800 行文件 |

**地面参照：**

- `HeightfieldMesh`：三角/四边形、采样、材质挂载（底层）
- `MapTerrainLayer`：地表 bitmask / 挖洞 / 调底层画网格（领域表现）
- `wc3_ground_material.tres`：静态材质参数；运行时只改 `tilesets` 等
- `Wc3GroundTileCatalog`：贴图数组

评判由实现者拿捏：新增文件前问「删掉它会不会只剩转发？」；塞进已有文件前问「是否已在讲另一个子系统？」。

---

## 7. 与旧文档关系

| 文档 | 角色 |
|------|------|
| 本文 | **架构总纲与 vibecoding 门禁来源** |
| [MAP_DATA.md](docs/architecture/MAP_DATA.md) | 数据层细节 |
| [EDITOR.md](docs/editor/EDITOR.md) | 编辑层总管、场景树、与 MapRoot 接线 |
| [TERRAIN_TILES.md](docs/terrain/TERRAIN_TILES.md) | 地表贴图 / Autotile |
| [MAP_ARCHITECTURE.md](docs/architecture/MAP_ARCHITECTURE.md) | 现 MapRoot 节点树与历史职责表（逐步对齐本文） |
| [WORLD_MEMBERSHIP.md](docs/architecture/WORLD_MEMBERSHIP.md) | 「在世界成员资格」抽象：进矿 / 工地 / 训练 / 死亡统一切换 |
| [ROADMAP.md](docs/roadmap/ROADMAP.md) | 实施顺序 |
| CLIFF / RAMP / WATER | 单模块规则；服从本文分层，不另起一套架构 |
