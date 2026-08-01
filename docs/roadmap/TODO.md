# 待办

> 细粒度缺陷清单。阶段规划见 [ROADMAP.md](ROADMAP.md)。  
> 最后更新：2026-08-01

## 当前焦点：单位面板（对齐装饰物）+ 装饰物缺口补齐

悬崖 / 斜坡 / 边界 / 装饰物主路径已通。下一步：单位面板筛选 UI → unit_brush；装饰物补 pathing / Z 偏移等。

| 里程碑 | 状态 | 要点 |
|--------|------|------|
| **崖 M0–M2** | ✅ + tag | `milestone/cliff-layered`；M3 脏区可选 |
| **坡 Paint / Collect** | ✅ | HiveWE 同构；蓝菱形验收 |
| **坡 Present** | ✅ | CliffTrans + dig/undig/hide + 入口低角 +0.5 |
| **实用区域 / 边界** | ✅ | MAP_EDGE + Nothing 笔刷 + 暗色 overlay |
| **小地图（静态）** | ✅ 初版 | `war3mapMap.png` + `minimap.json` + 梯形视口 + 灰框 |
| **小地图（实时）** | 待开 | 对齐 HiveWE `terrain.ixx::minimap_image` |
| **装饰物面板 + 笔刷编辑** | ✅ 二期 | 放置/选中/移旋删/撤销/PE2/Inspect |
| **单位面板** | 进行中 | 种族筛选 + 列表 + 玩家色 + Inspect |
| **单位笔刷** | 待开 | 见 [unit/HIVEWE_ALIGN.md](../unit/HIVEWE_ALIGN.md) |
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

### 待做（相对经典 WE 缺口）

#### P0 — 核心体验

- [ ] **路径阻挡可视化 / 避让**（View→Pathing；放置脚印 pathTex）— 现仅用 pathTex 算选中环
- [ ] **实例属性**（life / flags / 不可选中等）— `make_doodad_entry` 写死默认，无属性面板
- [ ] **选中后缩放编辑** — 放置可随机缩放，选中只能移/旋
- [ ] **Z / 高度偏移**（PageUp/Down）— 一律贴地，无手动抬高

#### P1 — 常用

- [ ] 地图选中 **同步** 面板列表高亮 / 滚动
- [ ] 面板 **搜索** / **最近使用**
- [ ] 吸附开关（现一律半格吸附）
- [ ] 框选 / 多选 / 批量删移
- [ ] 可破坏物 **掉落物品表** UI
- [ ] **`war3map.doo` 写出**（现只读 doo→json，存盘仅 doodads.json）
- [ ] MultiMesh 组内精确删除（失败时回退全量 rebuild）

#### P2 — 进阶

- [ ] 随机组（Advanced → Random Groups；菜单壳）
- [ ] 特殊放置选项
- [ ] 最大数量校验 / 超限警告
- [ ] skinId（1.32+）
- [ ] 树/草错相位 MultiMesh（见 HIVEWE_ALIGN §3.2）

---

## 单位面板 / 笔刷

> 对照 [unit/HIVEWE_ALIGN.md](../unit/HIVEWE_ALIGN.md)。与装饰物差异：玩家色、单 instance（不 MultiMesh）、字段更多、无 tileset 分类。

### 进行中

- [x] 单位面板：种族 / Standard·Campaign·Special 筛选 + 列表 + 玩家色
- [x] 选中 → Inspect 模型预览（复用 GLB 管线）

### 待做

- [ ] `unit_brush.gd`：放置 / 选中 / 拖动 / 旋转 / 删除 / 撤销
- [ ] `MapDocument` units API + `units.json` 读写补齐
- [ ] `MapUnitLayer.refresh_heights`（改地形后贴地）
- [ ] GLB 玩家色染色；owner palette
- [ ] schema 字段（hp/mp/flags/skin…）与 doo 回写
- [ ] 单位面板：搜索 / Neutral Passive Buildings 细分 / 出生点特殊项

---

## 小地图（编辑器导航窗）

> 设计拍板：[minimap_phase3_design.md](../minimap_phase3_design.md)（2026-08-01）

### 已完成

- [x] 优先加载解析目录 `war3mapMap.png`（来自 MPQ `war3mapMap.blp`）
- [x] `war3map.mmp` → `minimap.json`；金矿 / 中立建筑 / 出生点 / 野怪营图标
- [x] 视口改为四角梯形；允许画出地图外（灰边）
- [x] 方形深灰边框；`map-parse` 导出底图 + MMP
- [x] 视口 footprint 相对观察点收缩（旧默认 `≈0.52`；Phase 3 改等效 FOV）

### 待做（Phase 3）

- [x] **实时地形光栅**（对齐 HiveWE `minimap_image`，设计已拍板）：
  1. Catalog：`build_minimap_colors`（贴图块平均色 / 最低 mip）
  2. 崖邻域 → 灰 `(128,128,128)`；不可玩区继续 `darkened(0.55)`
  3. 水色完整：`waterH+offset > groundH` 深浅叠蓝（HiveWE）
  4. 实时分辨率 **1 px / tilepoint**；UI/存盘 **256 Nearest**；装饰物不进底图
  5. `corner_texture` / `real_tile_texture` 抽到 Logic，Present + Raster 共用
  6. 刷新：与地形 Mesh rebuild **同节流**；松手 / undo-redo **强制一次**；相机移动只更新黄框
- [x] 模式：LIVE 光栅（默认）vs GAME_PREVIEW（磁盘 `war3mapMap.png`）
- [x] 视口黄框：**等效 FOV 初值 50°**（`MapMinimapUtils.DEFAULT_EFFECTIVE_FOV_DEG`）；手测后再定
- [x] 存盘：bake **256×256** PNG，`Image.INTERPOLATE_NEAREST`；挂钩 `save_json` / `file_export_minimap`
- [x] UI：`AspectRatioContainer` + 方框同步，缓解方图被拉扁
- [ ] 勾选文案 / 过滤与 WE 对齐（中立建筑 vs 中立生物 vs 单位）
- [ ] 游戏内 HUD 小地图（迷雾、队伍色单位点）— 后置

### 调优备忘（手测跟进）

- [ ] **显示比例再校准**：金矿等圆形图标仍可能略扁；核对 Window DPI / `oversampling_override`、Frame 实际像素是否 1:1，必要时固定 `MinimapFrame` 边长不随窗宽变
- [ ] **视口黄框手感**：`DEFAULT_EFFECTIVE_FOV_DEG`（现 50°）与 WE 对拍；可加 Inspect 临时 SpinBox
- [ ] **与官方 PNG 色差**：地表平均色采样步长 / 变体 0 选取；不可玩区 `darkened(0.55)` 权重是否过重
- [ ] **romp 接线**：刷新时传入 `ctx.ramp.romp`，斜坡邻域色与 3D 地表一致
- [ ] 真增量 dirty-rect blit（大地图拖刷时）
- [ ] 存盘插值 A/B：Nearest vs Bilinear
- [ ] 写回 `.w3x` / BLP（选图菜单真机资源）

参考：HiveWE `terrain.ixx` L833–871、`ground_texture.ixx`；[WATER_DEEP_ANALYSIS.md §7](../hivewe/WATER_DEEP_ANALYSIS.md)；[minimap_phase3_design.md](../minimap_phase3_design.md)。

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
