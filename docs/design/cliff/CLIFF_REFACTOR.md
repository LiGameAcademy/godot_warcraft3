# 悬崖模块重构计划

> 前置：地面纹理管线 + 编辑总管 + 命令模式已打通（见 [TERRAIN_TILES.md](../terrain/TERRAIN_TILES.md)、[EDITOR.md](../editor/EDITOR.md)）。  
> 领域规则仍以 [CLIFF.md](CLIFF.md) 为准；本文只定 **怎么按五层拆** 与验收顺序。  
> 斜坡待重做；代码侧崖 M0–M2 已打 tag `milestone/cliff-layered`。  
> 最后更新：2026-07-25

---

## 1. 目标

把「直崖」做成与 **Ground** 同构的可测闭环：

```text
Data（层高 / cliffTextures）
  → Logic（蛋糕传播、TAG 选型、placements）
  → Catalog（cliffID / TAG → PNG·GLB）
  → Present（MapCliffLayer 挂 MultiMesh）
  → Editor（笔刷命令 → History → 分路径重建）
```

**禁止**：Layer 内改 `flags`/`layerHeights`；Builder 内拼 `Doodads/Terrain/Cliffs/...` 路径；笔刷绕过 Logic/Command。

---

## 2. 现状债（为何要拆）

| 问题 | 现状落点 |
|------|----------|
| Catalog 混装 | `Wc3TerrainTileCatalog` 同时吃 Terrain.slk + CliffTypes.slk |
| Logic 散落 | `MapDocument.paint_cliff_corner` 蛋糕/策略 B；`wc3_cliff_tiles.gd` TAG/叠段；与 Document 强耦合 |
| Present 纠缠 | `map_cliff_layer.gd` + `wc3_cliff_builder.gd` 仍读 `hf`/`meta` 字典 |
| 地面阶段已注释 | `MapTerrainLayer` 挖洞 / `corner_texture` 暂关，恢复时需走 Logic 输出而非 Layer 内重算 |
| 笔刷干扰 | 崖 sync 曾盖掉地表笔刷（已修：先崖后地 + sync 仅层变时）；崖阶段需命令化 |

参考地面已落地形态：

| Ground | Cliff 目标对称物 |
|--------|------------------|
| `Wc3Heightfield` | 同 SoA；必要时 `Wc3CliffLogic` 读写层/崖贴图 |
| `Wc3GroundTileCatalog` | `Wc3CliffCatalog`（直崖）+ 已有 `Wc3CliffTransCatalog`（坡） |
| `MapTerrainLayer` + `HeightfieldMesh` | `MapCliffLayer` + placements→MultiMesh |
| `PaintStrokeCommand` | `CliffStrokeCommand`（或扩展同一笔划快照，已含层/崖字段） |

---

## 3. 目标目录

```text
scripts/map/
├── data/          # 已有 heightfield / coords（层、cliff_* 数组）
├── catalog/
│   ├── wc3_terrain_tile_catalog.gd      # 收缩为地表索引（或改名 GroundTileIndex）
│   ├── wc3_cliff_catalog.gd      # 【新建】CliffTypes → 贴图 / groundTile / Cliffs 目录
│   └── wc3_cliff_trans_catalog.gd
├── logic/cliff/
│   └── wc3_cliff_logic.gd        # 笔刷 + 拓扑 TAG/叠段/挖洞（原 cliff_tiles 已并入）
├── catalog/
│   └── wc3_cliff_catalog.gd      # CliffTypes + PNG + Cliffs GLB 变体探测（无穷举表）
├── presentation/layers/
│   └── map_cliff_layer.gd        # 自根目录迁入；只消费 placements + Catalog.resolve
└── （builder）presentation/cliff/wc3_cliff_builder.gd  # 组 MultiMesh，不查拓扑

editor/scripts/
├── commands/                     # 复用 History；崖笔划可共用 PaintStrokeCommand 快照
└── tools/terrain_brush.gd        # 调 CliffLogic，不直写 Document 私有传播
```

材质/shader：继续 `assets/materials/`、`assets/shaders/`（已迁）。

---

## 4. 分层契约

### 4.1 Data

- 权威：`Wc3Heightfield`（`layer_heights` / `heights` / `cliff_textures` / `cliff_variations` / `cliff_tilesets`）
- 不再新增平行权威 Dictionary；`ctx.hf`/`meta` 仅过渡，Layer 优先 `ctx.heightfield`

### 4.2 Catalog — `Wc3CliffCatalog`

| API（示意） | 含义 |
|-------------|------|
| `load_default()` | 扫 `CliffTypes.json` + 解包贴图命名回退（现 `_resolve_cliff_png`） |
| `png_for_cliff_id` / `ground_tile_for_cliff_id` | 贴图与台面 groundTile |
| `cliff_model_dir` | `Cliffs` 家族目录 |
| `resolve_glb(tag, variation)` / `pick_cliff_variation` | 磁盘探测变体上限并缓存；拼 `…/Cliffs{TAG}{var}.glb` |

从 `Wc3TerrainTileCatalog` **迁出** cliff 侧字段；`MapBuildContext` 增加 `cliff_catalog`。

### 4.3 Logic — `Wc3CliffLogic`

| API（示意） | 含义 |
|-------------|------|
| `paint_corner(ix,iy,tool,ctype,anchor)` | 蛋糕 + 策略 B |
| `is_cliff_tile` / `cliff_slices_at` / `count_gaps` | 拓扑与挖洞（原 `Wc3CliffTiles`） |
| `dirty_rect` | 与 `Wc3TerrainLogic` 同形 |

### 4.4 Present

- 输入：`placements: Array[CliffPlacement]`（RefCounted/内部类，忌裸 Dictionary 键）
- `MapCliffLayer.build(ctx)`：`logic` 或 ctx 缓存的 placements → Catalog.resolve → MultiMesh
- 恢复地面挖洞：由 Logic 提供 `should_leave_gap` / romp，**TerrainLayer 只读结果**（解开当前注释时对接）

### 4.5 Editor

- 笔划已进 `EditorVertexSnapshot`（含 layer/cliff/ground）→ 崖刷默认可走同一 `PaintStrokeCommand`
- 重建：`rebuild_terrain_cliffs_water`；栅格经 `MapDebugGridLayer`
- 菜单/工具：apply_cliff 与地表笔刷顺序保持「先崖后地」

---

## 5. 实施里程碑

### M0 — 契约与 Catalog 拆分（不改手感）

1. ~~新建 `Wc3CliffCatalog`~~ ✅（`catalog/wc3_cliff_catalog.gd`；DefStore + PNG/modelDir）  
2. ~~TerrainArt 四表 Def + DefStore~~ ✅；`Wc3TerrainTileCatalog` / `Wc3WaterParams` 只做资源映射  
3. ~~`Wc3TerrainTileCatalog` 仅地表~~ ✅；Context / Loader / Builder / Editor 已接 `cliff_catalog`  
4. 文档：更新 [CLIFF.md](CLIFF.md) §8 路径表  

**验收**：Lost Temple 崖外观与现网一致；`selftest_cliff_*` / `selftest_def_store_cliff` 绿。

### M1 — Logic 迁出 Document

1. ~~`logic/cliff/wc3_cliff_logic.gd` 承接 `paint_cliff_corner` / 传播 / 策略 B~~ ✅  
2. ~~Document 委托；笔刷仍调 Document~~ ✅（Ramp 仍在 Document）  
3. ~~`wc3_cliff_tiles.gd` → 并入 Logic + Catalog 后删除~~ ✅（无独立脚本；变体表改为磁盘探测）  
4. ~~Document 去掉 `hf` 兼容属性~~ ✅（仅留 `as_build_dict()` 给 Present 过渡）  

**验收**：刷崖层高/异种同化与现网一致；撤销笔划仍可用。自测绿；Lost Temple 手测待补。

### M2 — Present 只消费 placements

1. ~~Builder 去掉拓扑扫描，改为吃 Logic 输出~~ ✅  
2. ~~MapCliffLayer 迁 presentation/layers/~~ ✅  
3. ~~恢复 MapTerrainLayer 直崖挖洞（读 Context gap mask）~~ ✅  

**验收**：崖+地面接缝正确；无水地图不误报；DebugGrid 崖材质可收集。自测绿；Lost Temple 手测待补。

### M3 — 命令与脏区（可选增强）

1. 明确崖笔划 label / `affects_cliffs_water`  
2. 脏矩形驱动局部崖重建（可先全量）  
3. ~~再开 斜坡（待重做） M0+~~ → 已开文档；实现按 RAMP 里程碑单独推进  

**Tag**：`milestone/cliff-layered` @ `77648e5`（Catalog + Logic + Present 纯度）。

---

## 6. 结构化数据（纪律）

服从 `.cursor/rules/map-typed-structures.mdc`：

- `CliffPlacement`、`CliffSlice` 用 RefCounted 或内部类  
- 禁止长期 `Dictionary` 字符串键穿过 Logic→Present  
- GDScript 嵌套泛型写到 `Dictionary[String, Dictionary]` 或对象化  

---

## 7. 回归清单

```text
godot --headless --path . -s res://tests/cliff/selftest_cliff_variants.gd
godot --headless --path . -s res://tests/cliff/selftest_cliff_level3.gd
godot --headless --path . -s res://tests/cliff/selftest_cliff_ground_tex.gd
godot --headless --path . -s res://tests/unit/selftest_paint_ground_rebuild.gd
```

编辑器手测：新建图 → 只开崖刷抬一层 → 再开纹理刷 → 撤销/重做 → 栅格仍在。

---

## 8. 明确不做（本重构波次）

- 斜坡 CliffTrans 表现冲刺（属 ⑧）  
- 水体精调  
- 导出 w3e  
- 把 Ground 再拆薄 Builder  

---

## 9. 相关文档

| 文档 | 角色 |
|------|------|
| [CLIFF.md](CLIFF.md) | 领域规则（蛋糕、策略 B、TAG） |
| [LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) | 五层总纲 |
| [ROADMAP.md](../../roadmap/ROADMAP.md) | ⑦ 悬崖层勾选 |
| [TODO.md](../../roadmap/TODO.md) | 细项勾选 |
| [EDITOR.md](../editor/EDITOR.md) | 总管 / 命令 / 重建路径 |
