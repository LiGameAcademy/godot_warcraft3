# 待办

> 细粒度缺陷清单。阶段规划见 [ROADMAP.md](ROADMAP.md)。

## 地形 / 斜坡
- [ ] **斜坡材质与剖面仍不对**：当前用「停放 CliffTrans + romp 地面 A→B 甲板」仍未对齐原作；需继续对照 HiveWE（几何/贴图/两侧岩壁）。相关：`wc3_cliff_builder.gd`、`wc3_cliff_tiles.gd`、`wc3_terrain_autotile.gd`。

## 岸浪
- [ ] 泡沫精调（偏移/贴图细节）暂搁，见 `docs/WATER.md`。

## 单位
- [ ] 单位层：先有完整 tscn/资源管线再默认摆放（`place_units` 仍关）。

## 架构债（摘自 MAP_ARCHITECTURE）
- [ ] 调试栅格双通路：统一到 `MapLoader.set_view_grid_level`
- [ ] Doodad/Unit `build(ctx)` 契约统一
