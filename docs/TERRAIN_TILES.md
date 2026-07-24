# 地表纹理与 Autotile

> 表现管线：`Wc3GroundTileCatalog` + `Wc3TerrainAutotile` + `MapTerrainLayer`。  
> 最后更新：2026-07-24

## 数据

- 顶点 `groundTextures[i]`：该 tilepoint 的地表 tileset 下标  
- `groundVariations[i]`：底层 fill 变体（HiveWE 加权表，见 `random_ground_variation`）  
- 地图级 `groundTilesets[]`：四字符 tileID 列表  

## 选图（四角 bitmask）

官方图集角权重（**非**教学口诀 BL=1）：

| 角 | 权重 |
|----|------|
| BR | 1 |
| BL | 2 |
| TR | 4 |
| TL | 8 |

多纹理：索引最小类型做底层整格 fill；其余类型各自 bitmask 叠层（最多 4 槽）。

## 资源映射

- `Wc3TerrainTiles`：tileID → PNG（SLK）  
- `Wc3GroundTileCatalog.build_texture_array`：运行时组 `Texture2DArray`  
- **不**检入预烘焙 `.tres` 图集表  

## 脚本位置

| 脚本 | 层 |
|------|----|
| `catalog/wc3_terrain_tiles.gd` | Catalog |
| `catalog/wc3_ground_tile_catalog.gd` | Catalog |
| `presentation/mesh/wc3_terrain_autotile.gd` | 表现（组 Mesh） |
| `presentation/mesh/heightfield_mesh*.gd` | 表现（挂载 / 采样） |
| `presentation/layers/map_terrain_layer.gd` | 表现（Layer） |
