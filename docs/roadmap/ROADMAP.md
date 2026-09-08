# 开发路线图（架构重构优先 · 地图 ①–⑫）

> 总纲：[LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md)  
> 原则：**先搭框架与映射，再按「数据 → 逻辑 → 表现 → 编辑」逐模块推进**。  
> 当前阶段 **不是** 斜坡功能冲刺，而是底层可维护性重构；斜坡排在悬崖之后。  
> **玩法近中期冲刺**（人族闭环 / 手感 / 扩展）→ **[NEXT.md](NEXT.md)**（2026-09-05 起以 NEXT 为选 PR 优先入口）  
> 最后更新：2026-09-05（文首挂 NEXT；正文 ①–⑫ 清单仍有效）

---

## 0. 现状（相对目标）

| 层 | 现状 |
| ---- | ------ |
| Data | ✅ Heightfield / DoodadList / UnitList / ParsedMap 已落地；`MapDocument` 已持 SoA List；Present 仍经 AoS entries 过渡 |
| Catalog | ⚠️ `Wc3CliffTransCatalog`、`Wc3IdCatalog` 有雏形；直崖/地面纹理 Catalog 未独立 |
| Logic | ⚠️ 规则散落 `Wc3CliffTiles` / Autotile / `MapDocument`；与 Dictionary 耦合 |
| Presentation | ⚠️ Layer 可用，但与逻辑/资产解析纠缠 |
| Editor | ⚠️ 笔刷可改旗/层；未统一走 Heightfield API |

首条可跑通管线：**高度图数据 → 改顶点 API → Ground Mesh（SurfaceTool）+ 纹理映射**。水体等后置。

---

## 1. 总览（编号即推荐顺序）

```text
① 框架层          分层目录约定、数据/Catalog 契约、Cursor rules
② 高度图数据定义  巩固 Wc3Heightfield / TileVertex；Coords 归位
③ 高度图逻辑 API  合法读写、邻域查询、脏区；Document 迁 Heightfield
④ 高度图表现      SurfaceTool Mesh、地形纹理 Catalog + 选图、Layer 只消费
⑤ 编辑器可编辑    地表/高度笔刷走 Logic API，预览重建
⑥ 模块节奏固化    后续一律 Data→Logic→Present→Editor
⑦ 悬崖层
⑧ 斜坡层
⑨ 水体（深/浅）
⑩ 应用高度（装饰物等 Y 落地）
⑪ 装饰物绘制
⑫ 单位绘制
⑬ 游戏场景（对战竖切）→ 见 docs/game/
```

地图编辑相关 ①–⑫ 告一段落后，玩法进入 **[design/game/ROADMAP.md](../design/game/ROADMAP.md)**（Echo Isles、Melee Bootstrap；触发器远期）。  
**当前冲刺优先级**见 **[NEXT.md](NEXT.md)**（N0 收口 → N1 人族闭环 → N2 手感 → N3 地图补债 → N4 扩展）。

---

## 2. 分阶段清单

### ① 框架层搭建

- [x] 落地 `docs/architecture/LAYERED_ARCHITECTURE.md` 为总纲（本文档配套）
- [x] Cursor rules：分层门禁、Catalog vs Data vs Logic
- [x] 文档约定目标目录：`data/` · `catalog/` · `logic/` · `presentation/` · `infra/`；`editor/scripts/editor.gd` 总管
- [x] Catalog 落位：`scripts/map/catalog/`（Id + CliffTrans）；Coords → `data/`
- [x] meta 双通路：`Wc3Heightfield.to_build_meta` 为唯一来源；`read_heightfield_meta` 仅委托
- [x] **Editor 总管**：`editor_main.tscn` 下直接子节点 `Editor`（`Node`），`@export map_root`；从 `editor_app.gd` 迁编排
- [x] 命令模式骨架（笔划撤销/重做）
- [ ] 按目标树渐进 `git mv`（logic / presentation / infra）

**验收**：新人只读架构文 + ROADMAP 能说出「改贴图路径找谁、改顶点找谁、挂 Mesh 找谁、编辑总管在哪」。

### ② 地形高度图 — 数据定义

- [x] 巩固 `Wc3Heightfield` / `Wc3TileVertex` 与 JSON 往返（`as_dict_view` / `to_build_meta`）
- [x] `Wc3Coords` 迁入 `data/`
- [x] `MapDocument` 以 `heightfield` 为权威；`hf` 为兼容视图
- [x] `MapBuildContext` 持有 `heightfield`，meta 由其生成
- [ ] 删除对第二份 meta Dictionary 手写逻辑的残余调用方（逐步改为只读 `ctx.meta` / `heightfield`）

**验收**：Lost Temple 加载；单顶点读写自测通过；Document / Context 无并行权威 Dictionary。

### ③ 地形高度图 — 逻辑 API

- [x] `MapDocument` 持有 `Wc3Heightfield` + `Wc3TerrainLogic`
- [x] API：`vertex_at`、`set_ground_tex` / `set_height`、邻域层、脏矩形（`scripts/map/logic/terrain/`）
- [x] Catalog 改为运行时扫盘；删除根目录 `resources/*.tres`
- [ ] 门禁与撤销挂钩点预留（实现可后置）
- [ ] 悬崖/水/坡笔刷从 Document 继续拆到 `logic/cliff`（⑦）

**验收**：不经 Mesh、仅改数据 + 单元/自测可验证。

### ④ 地形高度图 — 表现（Ground 管线）

- [x] Mesh：`HeightfieldMesh`（三角/四边形）+ `MapTerrainLayer` 组网
- [x] 纹理：`Wc3GroundTileCatalog` + `wc3_ground_material.tres`
- [x] 删除过薄的 `HeightfieldMeshBuilder` / `Wc3TerrainAutotile`

**验收**：主场景 / 编辑器能显示带正确 tileset 纹理的高度网格；改一个顶点纹理后重建可见。

### ⑤ 编辑器可编辑

- [x] `MapEditor` 总管 + 命令历史
- [ ] 地表笔刷、高度笔刷（若启用）只调 Logic API
- [ ] 脏区重建 Ground；不整图无脑全量（可先全量，接口预留脏区）

**验收**：编辑器改地表/高度 → 数据变 → 表现更新；Ctrl+Z 可撤销笔划。

### ⑥ 固化模块节奏

- [ ] 新模块 PR / 提交说明必须标明所处层
- [ ] 禁止跨层：Layer 不写 flags；Catalog 不算拓扑

### ⑦ 悬崖层

> 计划全文：[CLIFF_REFACTOR.md](../design/cliff/CLIFF_REFACTOR.md)  
> Tag：`milestone/cliff-layered`

- [x] M0 Catalog：`Wc3CliffCatalog`；收缩 `Wc3TerrainTileCatalog`
- [x] M1 Logic：`Wc3CliffLogic` + `logic/cliff/`；Document 委托
- [x] M2 Present：placements 驱动；恢复地面挖洞对接
- [ ] M3 脏区 / 命令标签（可选；不挡 ⑧）

### ⑧ 斜坡层（Logic ✅ / Present 核心 ✅）

> **WE 思路权威**：[RAMP_WE.md](../design/ramp/RAMP_WE.md)

- [x] Paint ≈ `update_ramp`（`logic/ramp/`；Document 委托；蓝菱形）
- [x] Collect ≈ `update_cliff_meshes` 数据侧（placements + romp；与 cliff 拓扑分离）
- [x] 分层：cliff `gap_mask` 不含坡；挖洞/藏崖由 `MapRampLayer` 调 Terrain/Cliff API
- [x] Present 核心：挂 CliffTrans + `undig` 入口 + romp dig + hide 直崖
- [x] Present：入口低角 +0.5（bake，不写 HF）
- [ ] 脏区 / tag `milestone/ramp-layered`

### ⑨ 水体（深水 / 浅水）

- [ ] 暂缓；高度+崖+坡稳定后再按同五层节奏接入（见 WATER.md）

### ⑩ 应用高度

- [ ] 装饰物 / 单位放置 Y：由 heightfield（+ 逻辑采样）决定，不在 Layer 瞎估

### ⑪ 装饰物绘制

- [ ] Data：`doodads.json` 映射  
- [ ] Catalog：复用/扩展 `Wc3IdCatalog`  
- [ ] Logic 放置规则 → Present MultiMesh → Editor 工具

### ⑫ 单位绘制

- [ ] 同装饰物节奏；默认预览开关与编辑器放置分离

---

## 3. 明确不做（本阶段）

- 不以「先做出好看斜坡」驱动架构
- 不一次性搬完所有文件到 `logic/`（先契约后搬家）
- 不并行维护长期双权威：`Dictionary` hf 与 `Wc3Heightfield`（迁移窗口要短）

---

## 4. 旧里程碑对照

此前 M0–M5（预览质量、导出 w3x 等）**让位于**本文 ①–⑫。  
导出、撤销、玩法运行时等能力，在 Ground 管线与分层稳定后再挂回编辑器路线（另节补充）。
