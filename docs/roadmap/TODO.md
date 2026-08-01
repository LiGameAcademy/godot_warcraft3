# 待办

> 细粒度缺陷清单。阶段规划见 [ROADMAP.md](ROADMAP.md)。  
> 最后更新：2026-08-01

## 当前焦点：小地图对齐收尾 + 实时光栅（自定义图）

悬崖 / 斜坡 Present 已可用。编辑器小地图已能加载 `war3mapMap` + MMP 图标 + 梯形视口；自定义图编辑时需跟 HiveWE 一样**实时光栅**地形色。

| 里程碑 | 状态 | 要点 |
|--------|------|------|
| **崖 M0–M2** | ✅ + tag | `milestone/cliff-layered`；M3 脏区可选 |
| **坡 Paint / Collect** | ✅ | HiveWE 同构；蓝菱形验收 |
| **坡 Present** | ✅ | CliffTrans + dig/undig/hide + 入口低角 +0.5 |
| **小地图（静态）** | ✅ 初版 | `war3mapMap.png` + `minimap.json` + 梯形视口 + 灰框 |
| **小地图（实时）** | 待开 | 对齐 HiveWE `terrain.ixx::minimap_image` |
| **水体** | 部分 | 见 [WATER.md](../water/WATER.md)；岸浪精调暂搁 |

---

## 小地图（编辑器导航窗）

### 已完成

- [x] 优先加载解析目录 `war3mapMap.png`（来自 MPQ `war3mapMap.blp`）
- [x] `war3map.mmp` → `minimap.json`；金矿 / 中立建筑 / 出生点 / 野怪营图标
- [x] 视口改为四角梯形；允许画出地图外（灰边）
- [x] 方形深灰边框；`map-parse` 导出底图 + MMP
- [x] 视口 footprint 相对观察点收缩（`footprint_scale≈0.52`，可再调）

### 待做

- [ ] **实时地形光栅（自定义图 / 编辑中）**— 对齐 HiveWE `Terrain::minimap_image()`：
  1. 每格颜色 = 地表贴图 **最低 mip 平均色**（HiveWE：`glGetTextureSubImage` 取 1×1 → `minimap_color`）
  2. 崖角（`corner_cliff` 邻接）→ 灰 `(128,128,128)`
  3. 可见水：`waterH > groundH` 时叠蓝——深 `*0.5625 + (0,0,80,112)`，浅 `*0.75 + (0,0,48,64)`
  4. 笔刷 / 脏区后增量重绘；`update_minimap()` 式信号刷新 UI
  5. 装饰物不进底图（与 HiveWE 注释一致）；图标仍走 MMP / units
- [ ] 模式切换：「游戏小地图」(war3mapMap 预览) vs 「编辑实时」(光栅)——对齐 WE「察看游戏小地图」勾选语义
- [ ] 视口框与 WE 再对拍：按游戏相机 FOV/距离校准 `footprint_scale`（或专用投影 FOV）
- [ ] 存盘时烘焙 `war3mapMap`（+ 可选写回 `.w3x`），供选图菜单用
- [ ] 勾选文案 / 过滤与 WE 对齐（中立建筑 vs 中立生物 vs 单位）
- [ ] 游戏内 HUD 小地图（迷雾、队伍色单位点）— 后置

参考：HiveWE `src/base/terrain.ixx` L833–871、`src/resources/ground_texture.ixx`（mip → `minimap_color`）；本仓库 [WATER_DEEP_ANALYSIS.md §7](../hivewe/WATER_DEEP_ANALYSIS.md)。

---

## Catalog（崖 M0）

- [x] TerrainArt 四表 → `definitions/terrain_art/*Def` + `Wc3DefStore`
- [x] `Wc3TerrainTileCatalog` 仅地表；`Wc3WaterParams` 读 `WaterTypeDef`
- [x] **`Wc3CliffCatalog`** — CliffTypes 表列 + 岩壁 PNG / modelDir 资源映射
- [x] `MapBuildContext.cliff_catalog` / `MapLoader.get_cliff_catalog()`
- [x] 更新 [CLIFF.md](../cliff/CLIFF.md) §8 路径表
- [x] `selftest_cliff_*` / `selftest_def_store_cliff` 绿（Catalog 接线后）
- [ ] Lost Temple 手测：崖外观与拆分前一致

---

## 编辑层（⑤ — 地面已打通）

- [x] Editor 总管 + 命令模式 + 地表笔刷可见重建
- [ ] 脏区局部重建 Ground（接口已有 dirty rect）
- [ ] 撤销 UI 灰显 / i18n
- [x] 悬崖笔刷全面委托 `Wc3CliffLogic`
- [x] 删除 `Wc3CliffTiles`：拓扑→Logic，GLB/变体→Catalog（磁盘探测）
- [x] Document 去掉 `hf` 属性（仅 `as_build_dict()` 过渡）

**验收（地面）**：改地表 → 数据变 → Ground 更新；Ctrl+Z 可撤销。

---

## 地形 / 斜坡

- [x] **斜坡 Logic（崖边 A）**：Paint + Collect 对齐 [RAMP_WE.md](../ramp/RAMP_WE.md)。勿与「应用高度」纯高度坡（B）混淆。
- [x] 存盘权威：`FLAG_RAMP` / `has_ramp`
- [x] Catalog：`Wc3CliffTransCatalog` + `ramp_model_dir`
- [x] Present：`MapRampLayer` 挂 CliffTrans + undig 入口 + romp dig + hide 直崖
- [x] Present：入口低角 +0.5（Present bake，不写 HF）

## 岸浪

- [ ] 泡沫精调暂搁，见 [WATER.md](../water/WATER.md)。

## 单位

- [ ] 单位层：先有完整 tscn/资源管线再默认摆放（`place_units` 仍关）。

## 架构债

- [x] 调试栅格 → `MapDebugGridLayer` + `MapLoader.set_view_grid_level`
- [x] GDScript 可见性：禁止跨边界调 `_` 私有 API（`.cursor/rules/gdscript-visibility.mdc`）
- [ ] Doodad/Unit `build(ctx)` 契约统一
- [ ] 删除对第二份 meta Dictionary 手写逻辑的残余调用方（逐步只读 `ctx.heightfield`）
