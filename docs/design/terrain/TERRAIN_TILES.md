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

- `Wc3TerrainTileCatalog`：tileID → PNG（SLK）  
- `Wc3GroundTileCatalog.build_texture_array`：运行时组 `Texture2DArray`  
- `assets/materials/wc3_ground_material.tres` + `assets/shaders/wc3_ground.gdshader`：静态材质；场景 `@export` 注入 Layer，Mesh `duplicate` 后只设运行时参数  
- 调试栅格：`MapDebugGridLayer`（不在 TerrainLayer 内）

## 脚本位置

| 脚本 | 职责 |
|------|------|
| `catalog/wc3_terrain_tile_catalog.gd` | Catalog：ID→路径 |
| `catalog/wc3_ground_tile_catalog.gd` | Catalog：Texture2DArray |
| `presentation/mesh/heightfield_mesh.gd` | 底层：采样、Packed* 三角/四边形、`active_material` |
| `presentation/layers/map_terrain_layer.gd` | 地面规则 + 组网；`@export ground_material` |
| `presentation/layers/map_debug_grid_layer.gd` | 跨层调试栅格 |
| `logic/terrain/wc3_terrain_logic.gd` | 改顶点 / variation 随机 |

拆分尺度见 [LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) §6。
