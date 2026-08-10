# 地图数据模型（map-parsed ↔ RefCounted）

> WC3 地形网格是**基于顶点（tilepoint）**的：笔刷、斜坡旗、层高改的都是某一个顶点。  
> 离线产物在 `assets/map-parsed/<slug>/`。本文件约定 Godot 侧如何用 `RefCounted` 映射这些 JSON。

---

## 1. 核心原则

| 原则 | 说明 |
| ------ | ------ |
| **一文件一类型（地图级）** | `info.json` / `terrain.json` / `terrain-heightfield.json` / `doodads.json` … 各对应一个 RefCounted（或薄包装） |
| **顶点是一等公民** | 对 heightfield 的改动一律通过「瓦片顶点」视图读写，避免满屏 `hf["heights"][i]` |
| **内存主存储用 SoA** | heightfield JSON 本身是平行数组；doodads/units JSON 磁盘仍是 AoS 对象数组，**内存**拆成平行数组，`to_dict()` 再拼回 AoS |
| **条目是视图，不是拷贝** | `Wc3TileVertex` / `Wc3Doodad` / `Wc3UnitPlacement` 持有 `容器 + index`，改属性即改底层数组；**不要**默认 new 出大量常驻对象 |

术语：

- **tilepoint / 瓦片顶点**：`(ix, iy)`，`index = iy * width + ix`  
- **地表格（cell）**：四角顶点构成的 1×1 格（直崖/地面三角形的单位）  
- **mapWidth/Height**：格数；`tilepointWidth/Height = map + 1`

---

## 2. JSON 文件 ↔ 脚本映射

以 Lost Temple（`losttemple/`）为例：

| JSON | 职责 | 建议脚本 | 粒度 |
| ------ | ------ | ---------- | ------ |
| `terrain-heightfield.json` | 地形主数据（顶点平行数组） | `Wc3Heightfield` | 地图级 SoA |
| （派生）单顶点读写 | 笔刷 / 斜坡逻辑 API | `Wc3TileVertex`（`class_name`） | 顶点视图 |
| `terrain.json` | 地形头信息 + stats（无大数组） | `Wc3TerrainHeader` | 地图级 |
| `info.json` | w3i 地图信息、玩家、雾等 | `Wc3MapInfo` | 地图级 |
| `doodads.json` | 装饰物列表 | `Wc3DoodadList` + `Wc3Doodad` | 列表 + 单条 |
| `units.json` | 单位放置 | `Wc3UnitList` + `Wc3UnitPlacement` | 列表 + 单条 |
| `pathing.json` | WPM 寻路面 | `Wc3PathingMap` | 地图级（格更细） |
| `strings.json` / `regions.json` / `cameras.json` | 杂项 | 同名薄包装 | 地图级 |
| `summary.json` | 解析摘要（只读） | 可不建类，或 `Wc3MapSummary` | 工具用 |
| 目录整体 | 一次打开一张图 | `Wc3ParsedMap` | 包一层 `load_dir` |

**已落地**：`Wc3Heightfield` + `Wc3TileVertex`、`Wc3DoodadList` + `Wc3Doodad`、`Wc3UnitList` + `Wc3UnitPlacement`、`Wc3ParsedMap.load_dir`（heightfield 必载；doodads/units 有文件则加载）。`info` / `terrain` 头仍为 Dictionary，按需再拆类。

---

## 3. `terrain-heightfield.json` 字段 ↔ 顶点

### 3.1 地图级（Header）

| JSON 字段 | 类型 | Heightfield 属性 | 语义 |
| ----------- | ------ | ------------------ | ------------------ |
| `tilepointWidth` / `tilepointHeight` | int | `width` / `height` | 瓦片点宽度 / 高度 |
| `mapWidth` / `mapHeight` | int | `map_width` / `map_height` | 地图宽度 / 高度 |
| `centerOffset` | `{x,y}` | `center_offset: Vector2` | 中心偏移 |
| `tileSize` | number | `tile_size`（默认 128） | 瓦片大小 |
| `mainTileset` / `mainTilesetName` | string | 同名 | 主地形纹理集 |  
| `groundTilesets` / `cliffTilesets` | string[] | 同名 | 地面纹理集 / 悬崖纹理集 |

### 3.2 每顶点平行数组（长度 = width × height）

| JSON 数组 | 顶点语义 | `Wc3TileVertex` 属性建议 |
| ----------- | ---------- | --------------------------- |
| `heights` | 最终地面高度（WC3） | `height` |
| `layerHeights` | 悬崖层 0–14 | `layer` |
| `waterHeights` | 水面高度 | `water_height` |
| `flagsPacked` | bit：`WATER=1` `RAMP=4` … | `flags`；`has_water` / `has_ramp` |
| `groundTextures` | 地表 tileset 下标 | `ground_tex` |
| `groundVariations` | 地表变体 | `ground_var` |
| `cliffTextures` | 悬崖 tileset 下标 | `cliff_tex` |
| `cliffVariations` | 悬崖变体 | `cliff_var` |

索引：`index = iy * width + ix`（行主序，与现有 `MapDocument` / Domain 一致）。

---

## 4. 推荐类型关系

```text
Wc3ParsedMap                          ← 打开 map-parsed/<slug>/
├── info: Dictionary                  ← info.json（可后补专用类）
├── terrain_header: Dictionary        ← terrain.json（可后补专用类）
├── heightfield: Wc3Heightfield       ← terrain-heightfield.json  ★
├── doodads: Wc3DoodadList?           ← doodads.json
├── units: Wc3UnitList?               ← units.json
├── doodad_at(i) / unit_at(i) / vertex_at(ix,iy)
└── …

Wc3Heightfield                        ← SoA，可 to_dict / from_dict
└── vertex_at(ix, iy) -> Wc3TileVertex

Wc3DoodadList / Wc3UnitList           ← 内存 SoA；to_dict() → AoS JSON
└── at(i) -> Wc3Doodad / Wc3UnitPlacement

Wc3TileVertex / Wc3Doodad / Wc3UnitPlacement  ← RefCounted 视图
├── 容器引用 + index
└── 写回时改平行数组对应元素
```

### 为何不用「每条一个常驻 Resource」？

161×161 ≈ 2.6 万顶点；大图 doodad/unit 也可上千。若全部 `new` 成独立对象：内存与 GC 压力大，且与 JSON 往返要拆装。  
**视图模式**：按需 `at` / `vertex_at`；批量重建仍直接扫 SoA。

### 4.1 doodads / units 字段（摘要）

**List 根级（文件头 / 旁路段，非单条 SoA）：**

| JSON | List 属性 | 说明 |
|------|-----------|------|
| `formatVersion` / `subversion` | `format_version` / `subversion` | doo 文件头 |
| `count` | `count()` | = 主表长度，不另存 |
| `byId`（doodad）/ `byTypeId`·`byOwner`（unit） | `rebuild_by_*()` | 派生统计，`to_dict` 现算 |
| `specialDoodads` | `special_doodads` | doo 尾段；权威 Array[{id,x,y,z,…}] |
| `_bytesRemaining` | `bytes_remaining` | 解析诊断；≥0 才写回 |

**单条主表：**

| JSON（AoS 单条） | List SoA | 视图属性 |
| ---------------- | -------- | -------- |
| `id` / `typeId` | `ids` / `type_ids` | `id` / `type_id` |
| `variation` | `variations` | `variation` |
| `position.{x,y,z}` | `pos_x/y/z` | `position` / `pos_*` |
| `angle`（弧度） | `angles` | `angle`；`angle_degrees` 派生 |
| `scale.{x,y,z}` | `scale_x/y/z` | `scale` |
| `flags` / `life`（doodad） | `flags` / `lives` | 同名 |
| `owner` / `hitPoints`…（unit） | `owners` / `hit_points`… | 同名 snake_case |
| `droppedItemSets` 等嵌套 | `Array` 平行槽 | 同名 |

嵌套结构（掉落表、背包、技能、random）不拆 Packed*，每槽一个 `Array`/`Dictionary`。

---

## 5. 与现有代码的关系

| 现状 | 目标 |
| ------ | ------ |
| `MapDocument` 持 `Wc3Heightfield` + `Wc3DoodadList` + `Wc3UnitList` | Present 经 `doodad_entries()` / `unit_entries()` 或 List.`to_dict()` 过渡；CRUD 仍对外 Dictionary |
| Domain（`Wc3CliffTiles` 等）吃 `Array` / `meta` | 逐步改为吃 `Wc3Heightfield` 或仍传 `to_dict()`，避免一次改爆 |
| 编辑器笔刷 | `doc.heightfield.vertex_at(ix,iy).has_ramp = true` 这类 API |

迁移顺序建议：数据类已齐 → 笔刷/斜坡用 `TileVertex` → Layer/Document 改用 List → Domains 去 Dictionary。

---

## 6. 文件布局（建议）

```text
scripts/map/data/             # 地图态 JSON ↔ 类型（本文）
  wc3_coords.gd               # FLAG / TILE / 坐标（含 FLAG_RAMP）
  wc3_tile_vertex.gd          # has_ramp 读写旗位
  wc3_heightfield.gd
  wc3_doodad_list.gd / wc3_doodad.gd
  wc3_unit_list.gd / wc3_unit_placement.gd
  wc3_parsed_map.gd
  wc3_cliff_placement.gd
  wc3_cliff_topology_result.gd

scripts/map/logic/cliff/      # 直崖 Logic
scripts/map/catalog/          # 资源映射（非 map-parsed）
  wc3_id_catalog.gd
  wc3_cliff_trans_catalog.gd  # CliffTrans（斜坡 mesh 待重做时再用）
  wc3_cliff_catalog.gd

docs/architecture/MAP_DATA.md              # 本文
docs/architecture/LAYERED_ARCHITECTURE.md  # 分层总纲
```

权威为 `Wc3Heightfield`：`to_build_meta()` / `as_dict_view()` 供构建与兼容路径。  
`sample_vert` / 三角四边形在 `HeightfieldMesh`；勿再引入仅转发的 MeshBuilder。

---

## 7. 斜坡派生（Logic；非 JSON 权威）

存盘权威仍是 `FLAG_RAMP`。Paint/Collect 契约见 [RAMP_WE.md](../design/ramp/RAMP_WE.md)。

| 类型 | 职责 |
|------|------|
| `Wc3RampPlacement` | 一格 CliffTrans（TAG / model_dir / axis）；`AXIS_*` / `VARIANT_*` |
| `Wc3RampCollectResult` | `placements` + `romp`；`ROMP_*` |
| `Wc3RampLogic` | 门面：`paint_*` / `collect_placements` + 落旗；常量转发自 Data |
| `Wc3RampPaint` | 笔刷规划（只算标记） |
| `Wc3RampCollect` | 拓扑匹配 / dig / entrance |


## 8. 验收

1. `Wc3ParsedMap.load_dir("res://assets/map-parsed/losttemple")` 成功，`heightfield.width==161`  
2. `vertex_at(0,0).height` 与 JSON `heights[0]` 一致  
3. 修改 `vertex_at` 的 `layer` / `flags` 后，`to_dict()["layerHeights"]` 同步变化  
4. 不默认分配 width×height 个 `Wc3TileVertex` 常驻实例  
5. `doodads.count()` / `units.count()` 与 JSON `count` 一致；`doodad_at(0).id` / `unit_at(0).type_id` 与首条一致  
6. `list.to_dict()` 输出 AoS，含根字段：`byId`/`byTypeId`/`byOwner`（现算）、`specialDoodads`（doodad）；有诊断时带 `_bytesRemaining`  
