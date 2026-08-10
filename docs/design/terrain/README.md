# terrain/ — 地形

> 地面 tile、Autotile、HEX_MAP 项目经验教训。

## 文件

| 文件 | 内容 |
|------|------|
| [TERRAIN_TILES.md](TERRAIN_TILES.md) | 地面 tile 索引 / 纹理 Catalog 路径 |
| [HEX_MAP_LESSONS.md](HEX_MAP_LESSONS.md) | Catlike 六边形地图项目的可吸收经验（脏区、Layer 拆分、HexEditor vs MapEditor 映射） |

## 关键概念

| 名 | 位置 | 职责 |
|----|------|------|
| `Wc3TerrainTileCatalog` | `scripts/map/catalog/` | 旧 Catalog（已收缩，仅地表） |
| `Wc3GroundTileCatalog` | `scripts/map/catalog/` | 地面 tile 专项 Catalog |
| `Wc3TerrainAutotile` | `scripts/map/logic/terrain/` | bitmask 地面网格 + Texture2DArray；改地面几何/留缝/斜坡甲板改这里 |
| `HeightfieldMesh` | `scripts/map/presentation/mesh/` | MeshInstance3D 薄封装（三角/四边形） |
| `MapTerrainLayer` | `scripts/map/presentation/layers/` | 地面 Layer；调 Autotile + 挂 `wc3_ground.gdshader` |

## 脏区

`MapDocument` 提供 `dirty_rect` 接口；**接口已有，Ground 重建走全量**。  
`HEX_MAP_LESSONS.md` 给出的"5×5 chunk"脏区思路可借鉴——按 tile 块（如 16×16 / 32×32）分 Mesh 节点，脏矩形映射到 chunk 集合再局部 build。

## 何时查这里

- 改地面三角形 / 留缝 / 斜坡甲板 → [TERRAIN_TILES.md](TERRAIN_TILES.md) + `scripts/map/logic/terrain/wc3_terrain_autotile.gd`
- 借鉴 hex_map 的脏区思路 → [HEX_MAP_LESSONS.md](HEX_MAP_LESSONS.md)
- 地面 shader、图集混合 → `shaders/wc3_ground.gdshader` + `scripts/map/presentation/layers/map_terrain_layer.gd`
- 改 Ground Mesh 节点 → `scripts/map/presentation/mesh/heightfield_mesh.gd`
