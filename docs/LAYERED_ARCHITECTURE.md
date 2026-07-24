# 分层架构：数据 · 资源映射 · 逻辑 · 表现 · 编辑

> 目标：用 **WC3 数据 + 资产** 建映射，再在其上写逻辑，最后在逻辑正确的前提下做渲染。  
> 难点与终点都在「映射正确」；表现层只消费映射结果。  
> 相关：[MAP_DATA.md](MAP_DATA.md) · [ROADMAP.md](ROADMAP.md) · [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md)  
> 最后更新：2026-07-24

---

## 1. 原则是否合理？

**合理，且应作为本仓库的硬门禁。**

| 驱动方式 | 含义 | 本项目落点 |
|----------|------|------------|
| **设计驱动** | 先文档/契约，再改代码 | `docs/*` + `.cursor/rules` |
| **数据驱动** | 地图态来自 map-parsed JSON / SoA，不靠硬编码场景 | `scripts/map/data/` |
| **资产驱动** | ID / TAG / tileset → 贴图·模型路径由 Catalog 查，不散落 `load()` | `scripts/map/catalog/`（目标目录） |

禁止：在 Layer / Mesh 脚本里直接改 `flags`、算拓扑；禁止在笔刷里拼 GLB 路径。

---

## 2. 五层职责

```text
┌─────────────────────────────────────────────────────────┐
│  Editor（编辑层）  MapDocument / TerrainBrush / UI       │
│  改数据、调逻辑 API；不建 Mesh、不 resolve 资产路径       │
└───────────────────────────┬─────────────────────────────┘
                            │ mutate / query
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
│  Presentation（表现层）  Map*Layer / SurfaceTool Mesh    │
│  只消费 placements + 已解析资源；不写 heightfield         │
└─────────────────────────────────────────────────────────┘
```

命名约定（目标）：

| 前缀 / 目录 | 层 |
|-------------|----|
| `scripts/map/data/` | 数据映射 |
| `scripts/map/catalog/` | 资源映射 |
| `scripts/map/logic/` 或现有 `Wc3*` 中「规则」部分 | 逻辑 |
| `scripts/map/map_*_layer.gd`、`heightfield_mesh*.gd` | 表现 |
| `editor/scripts/` | 编辑 |

短期内文件可仍平铺在 `scripts/map/`，但 **职责边界按上表执行**；搬目录是后续机械步骤。

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

**作为独立「数据读取器」没有必要，应拆进两处：**

| 现有 API | 去向 |
|----------|------|
| `read_heightfield_meta(hf: Dictionary)` | **删除/吸收** → `Wc3Heightfield`（数据层已有字段，勿再造第二份 meta Dictionary） |
| `sample_vert(...)` | **表现层** 网格构建（如 `HeightfieldMesh` / 将来的 GroundMeshBuilder）——把 WC3 高度采样成 Godot 顶点 |

数据层提供「高度、中心、tile_size」；表现层负责 `SurfaceTool` / `ArrayMesh`。

### 3.3 `wc3_cliff_trans_catalog.gd` 抽象如何？算数据层吗？

**抽象方向正确，但属于 Catalog（资源映射），不是 map-parsed 数据层。**

- Catalog：磁盘上有哪些 `CliffTrans{TAG}{var}.glb`、如何 parse 文件名、`resolve(tag, var)`  
- Logic（现 `wc3_cliff_tiles` 等）：这一格四角 layer → 该用哪个 TAG、要不要洞  

**直崖 Cliffs 应同样模式**：`Wc3CliffCatalog`（A/B/C TAG + variation → 路径），与 CliffTrans 对称。

### 3.4 与 `wc3_cliff_tiles.gd` 是否重叠？可否整合？

**有重叠嫌疑，应拆清，不要糊成一个大文件。**

| 职责 | 留在 | 说明 |
|------|------|------|
| `is_cliff_tile`、四角 layer → TAG、挖洞集合 | **Logic** | 「这一格是什么」 |
| `CLIFF_VAR_MAX`、resolve GLB 路径、扫盘登记 | **Catalog** | 「这种 TAG 有哪些资产」 |
| MultiMesh 挂树、材质 | **Presentation** | `map_cliff_layer` |

整合原则：**逻辑选型结果 + Catalog.resolve → 表现实例化**。不要把「算 TAG」和「找文件」写进同一个 300 行脚本的同一段落。

### 3.5 地形纹理 / Autotile

理想形态（与你描述一致）：

1. **文档**：邻接 bitmask / 变体规则（独立 `docs/TERRAIN_TILES.md`，阶段 4 再写细）  
2. **Catalog**：某 tileset 的「纹理级」→ `Texture2DArray`（或多张图 + 索引表）  
3. **Logic 方法（可挂在 Catalog 旁的纯函数）**：给定顶点邻域 → 选中 array 下标 / variation  
4. **Presentation**：Autotile 只组几何 + 采样已选中的层  

现 `wc3_terrain_autotile.gd` 把规则、组 mesh、贴图加载揉在一起 —— 重构时按上表拆。

### 3.6 `wc3_id_catalog.gd` 与统一 Catalog 层

**算 Catalog，不算 map-parsed Data。**

目标：`scripts/map/catalog/` 下统一「资源 ↔ ID」：

| Catalog | 键 | 值 |
|---------|----|----|
| `Wc3IdCatalog`（已有） | 四字符单位/装饰 ID | 显示名、GLB 候选路径 |
| `Wc3GroundTileCatalog`（目标） | tileset + tex 下标 + bitmask/var | 贴图 / array 层 |
| `Wc3CliffCatalog`（目标） | 家族 + TAG + var | Cliffs GLB |
| `Wc3CliffTransCatalog`（已有） | TAG + var | CliffTrans GLB |

逻辑层只调用 `catalog.resolve(...)`；表现层拿路径去 `RuntimeAssets` / `MapModelCache`。

---

## 4. 目标目录（渐进搬迁）

```text
scripts/map/
  data/           # JSON ↔ 类型；Coords 基础常量
  catalog/        # 资产映射 Resource / RefCounted
  logic/          # 拓扑、笔刷门禁、选型（可暂缓搬家）
  # 表现仍可：map_*_layer.gd、heightfield_mesh*.gd
editor/scripts/   # 编辑层
docs/             # 设计驱动
```

搬迁顺序服从 [ROADMAP.md](ROADMAP.md)：先跑通 **高度图数据 → API → Ground Mesh + 纹理**，再 Cliffs / Ramp / Water…

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

## 6. 与旧文档关系

| 文档 | 角色 |
|------|------|
| 本文 | **架构总纲与 vibecoding 门禁来源** |
| [MAP_DATA.md](MAP_DATA.md) | 数据层细节 |
| [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) | 现 MapRoot 节点树与历史职责表（逐步对齐本文） |
| [ROADMAP.md](ROADMAP.md) | 实施顺序 |
| CLIFF / RAMP / WATER | 单模块规则；服从本文分层，不另起一套架构 |
