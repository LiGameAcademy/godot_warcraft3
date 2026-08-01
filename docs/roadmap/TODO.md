# 待办

> 细粒度缺陷清单。阶段规划见 [ROADMAP.md](ROADMAP.md)。  
> 最后更新：2026-08-01

## 当前焦点：装饰物放置笔刷（一期已接通）+ 小地图实时光栅

悬崖 / 斜坡 Present 已可用。小地图静态对齐 ✅。装饰物面板筛选 UI ✅。装饰物单击/拖拽放置（含撤销）✅；选中/删除/移动下一期。

| 模块 | 状态 | 备注 |
|------|------|------|
| **装饰物放置笔刷** | ✅ 一期 | LMB 放置 + 尺寸形状 + 随机样式 + Ctrl+Z |

- [x] `editor/scripts/tools/doodad_brush.gd`：LMB 单击/拖拽放置（尺寸/形状批量戳点）
- [x] `MapDocument`：`doodads` 数组 + add/remove + doodads.json 读写
- [x] `DoodadEditCommand` 撤销/重做
- [ ] Delete 删除 / 选中拖动 / 旋转 90°
- [ ] `MapDoodadLayer` MultiMesh 组内精确删除优化

| 里程碑 | 状态 | 要点 |
|--------|------|------|
| **崖 M0–M2** | ✅ + tag | `milestone/cliff-layered`；M3 脏区可选 |
| **坡 Paint / Collect** | ✅ | HiveWE 同构；蓝菱形验收 |
| **坡 Present** | ✅ | CliffTrans + dig/undig/hide + 入口低角 +0.5 |
| **小地图（静态）** | ✅ 初版 | `war3mapMap.png` + `minimap.json` + 梯形视口 + 灰框 |
| **小地图（实时）** | 待开 | 对齐 HiveWE `terrain.ixx::minimap_image` |
| **装饰物面板（筛选 UI）** | ✅ | tileset / 分类 / 列表 / 变体 / 尺寸形状 |
| **装饰物放置笔刷** | ✅ 一期 | LMB 放置 + 尺寸形状 + 随机样式 + Ctrl+Z |
| **水体** | 部分 | 见 [WATER.md](../water/WATER.md)；岸浪精调暂搁 |

---

## 装饰物面板

### 已完成（一期）

- [x] `Wc3IdCatalog`：`category` / `tilesets` + `list_placeables_filtered`
- [x] `WorldEditData` 解析 `[DoodadCategories]` / `[DestructibleCategories]`
- [x] 工具面板装饰物页：地形集 / 分类 / ItemList（无「全部」、无来源下拉；空分类隐藏；WESTRING 中文名）
- [x] 变体 ←→ / 随机样式 → Inspect 预览同步
- [x] Inspect 3D 模型预览 + 动画列表切换（Stand/Death/…）
- [x] 尺寸 / 形状控件（与地形笔刷共享状态，供下期放置用）

### 已完成（一期放置）

- [x] `editor/scripts/tools/doodad_brush.gd`：LMB 单击/拖拽放置（尺寸/形状）
- [x] `MapDocument`：`doodads` + add/remove + doodads.json
- [x] `DoodadEditCommand` + 撤销/重做刷新 Present
- [x] `MapDoodadLayer.add_one` / `rebuild_from_list` 增量 + 全量

### 已完成（二期编辑 + 朝向 UX）

- [x] 放置幽灵预览（半透明，朝向随「放置朝向」）
- [x] 选中（点击已有）/ 拖动 / Delete / `[` `]` / R 旋转 90°
- [x] Inspect：**环视**（拖拽仅相机）与 **放置朝向**（输入框 + ↺↻）分离

### 待做

- [ ] MultiMesh 组内精确删除（当前失败时回退全量 rebuild）

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
