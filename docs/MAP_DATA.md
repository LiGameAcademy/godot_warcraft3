# 地图数据模型（map-parsed ↔ RefCounted）

> WC3 地形网格是**基于顶点（tilepoint）**的：笔刷、斜坡旗、层高改的都是某一个顶点。  
> 离线产物在 `assets/map-parsed/<slug>/`。本文件约定 Godot 侧如何用 `RefCounted` 映射这些 JSON。

---

## 1. 核心原则

| 原则 | 说明 |
|------|------|
| **一文件一类型（地图级）** | `info.json` / `terrain.json` / `terrain-heightfield.json` / `doodads.json` … 各对应一个 RefCounted（或薄包装） |
| **顶点是一等公民** | 对 heightfield 的改动一律通过「瓦片顶点」视图读写，避免满屏 `hf["heights"][i]` |
| **存盘保持 SoA** | JSON 里是平行数组（Structure of Arrays）；内存主存储也是 SoA，与 `terrain-heightfield.json` 同形，便于 load/save |
| **顶点是视图，不是拷贝** | `Wc3TileVertex` 持有 `heightfield + index`，改属性即改底层数组；**不要**默认 new 出 2.5 万个常驻对象 |

术语：

- **tilepoint / 瓦片顶点**：`(ix, iy)`，`index = iy * width + ix`  
- **地表格（cell）**：四角顶点构成的 1×1 格（直崖/地面三角形的单位）  
- **mapWidth/Height**：格数；`tilepointWidth/Height = map + 1`

---

## 2. JSON 文件 ↔ 脚本映射

以 Lost Temple（`losttemple/`）为例：

| JSON | 职责 | 建议脚本 | 粒度 |
|------|------|----------|------|
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

**第一阶段只落地**：`Wc3Heightfield` + `Wc3TileVertex` + `Wc3ParsedMap`（至少能挂上 heightfield）。其余 JSON 按需加，避免一次造完空壳。

---

## 3. `terrain-heightfield.json` 字段 ↔ 顶点

### 3.1 地图级（Header）

| JSON 字段 | 类型 | Heightfield 属性 |
|-----------|------|------------------|
| `tilepointWidth` / `tilepointHeight` | int | `width` / `height` |
| `mapWidth` / `mapHeight` | int | `map_width` / `map_height` |
| `centerOffset` | `{x,y}` | `center_offset: Vector2` |
| `tileSize` | number | `tile_size`（默认 128） |
| `mainTileset` / `mainTilesetName` | string | 同名 |
| `groundTilesets` / `cliffTilesets` | string[] | 同名 |

### 3.2 每顶点平行数组（长度 = width × height）

| JSON 数组 | 顶点语义 | `Wc3TileVertex` 属性建议 |
|-----------|----------|---------------------------|
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
├── info: Wc3MapInfo?                 ← info.json（可后补）
├── terrain_header: Wc3TerrainHeader? ← terrain.json（可后补）
├── heightfield: Wc3Heightfield       ← terrain-heightfield.json  ★
├── doodads: Wc3DoodadList?           ← doodads.json（可后补）
└── …

Wc3Heightfield                        ← SoA，可 to_dict / from_dict
└── vertex_at(ix, iy) -> Wc3TileVertex

Wc3TileVertex                         ← RefCounted 视图
├── ix, iy, index
├── height / layer / flags / …
└── 写回时改 Heightfield 对应数组元素
```

### 为何不用「每个顶点一个常驻 Resource」？

161×161 ≈ 2.6 万顶点。若全部 `new` 成独立对象：内存与 GC 压力大，且与 JSON SoA 往返要拆装。  
**视图模式**：按需 `vertex_at`，刷子只拿当前点；批量重建 mesh 仍直接扫 SoA。

---

## 5. 与现有代码的关系

| 现状 | 目标 |
|------|------|
| `MapDocument.hf: Dictionary` 与 JSON 同形 | 内部改为持有 `Wc3Heightfield`；对外可暂时 `to_dict()` 兼容 Domain |
| Domain（`Wc3CliffTiles` 等）吃 `Array` / `meta` | 逐步改为吃 `Wc3Heightfield` 或仍传 `to_dict()`，避免一次改爆 |
| 编辑器笔刷 | 改为 `doc.heightfield.vertex_at(ix,iy).has_ramp = true` 这类 API |

迁移顺序建议：先建数据类 + 自测读写 Lost Temple → 笔刷/斜坡改用 `TileVertex` → 最后 Domains 去 Dictionary。

---

## 6. 文件布局（建议）

```text
scripts/map/data/
  wc3_tile_vertex.gd      # 顶点视图
  wc3_heightfield.gd      # terrain-heightfield
  wc3_parsed_map.gd       # 目录加载
  # 后补：wc3_map_info.gd / wc3_doodad.gd / …
docs/MAP_DATA.md          # 本文
```

---

## 7. 验收

1. `Wc3ParsedMap.load_dir("res://assets/map-parsed/losttemple")` 成功，`heightfield.width==161`  
2. `vertex_at(0,0).height` 与 JSON `heights[0]` 一致  
3. 修改 `vertex_at` 的 `layer` / `flags` 后，`to_dict()["layerHeights"]` 同步变化  
4. 不默认分配 width×height 个 `Wc3TileVertex` 常驻实例  
