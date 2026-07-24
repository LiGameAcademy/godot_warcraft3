# 地表纹理与地面网格

> 表现管线：`Wc3GroundTileCatalog` + `HeightfieldMesh` + `MapTerrainLayer`。  
> 最后更新：2026-07-24

## 数据

- 顶点 `groundTextures[i]`：该 tilepoint 的地表 tileset 下标  
- `groundVariations[i]`：底层 fill 变体（`Wc3TerrainLogic.random_ground_variation`）  
- 地图级 `groundTilesets[]`：四字符 tileID 列表  

## 选图（四角 bitmask）

官方图集角权重（**非**教学口诀 BL=1）：

| 角 | 权重 |
|----|------|
| BR | 1 |
| BL | 2 |
| TR | 4 |
| TL | 8 |

多纹理：索引最小类型做底层整格 fill；其余类型各自 bitmask 叠层（最多 4 槽）。实现在 `MapTerrainLayer`。

## 资源与材质

- `Wc3TerrainTiles`：tileID → PNG（SLK）  
- `Wc3GroundTileCatalog.build_texture_array`：运行时组 `Texture2DArray`  
- `presentation/materials/wc3_ground_material.tres`：静态 shader 参数；Layer `duplicate` 后只设 `tilesets` / 调试偏移  

## 脚本位置

| 脚本 | 职责 |
|------|------|
| `catalog/wc3_terrain_tiles.gd` | Catalog：ID→路径 |
| `catalog/wc3_ground_tile_catalog.gd` | Catalog：Texture2DArray |
| `presentation/mesh/heightfield_mesh.gd` | 底层：采样、三角/四边形、挂材质 |
| `presentation/layers/map_terrain_layer.gd` | 地面规则 + 组网 + 赋贴图 |
| `logic/terrain/wc3_terrain_logic.gd` | 改顶点 / variation 随机 |

拆分尺度见 [LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md) §6。
