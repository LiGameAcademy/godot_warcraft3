# 待办

> 细粒度缺陷清单。阶段规划见 [ROADMAP.md](ROADMAP.md)·**玩法冲刺见 [NEXT.md](NEXT.md)**。  
> 最后更新：2026-09-05（文首挂 NEXT；正文编辑器/地图细项仍有效）

## 当前焦点

- **玩法主线**：[NEXT.md](NEXT.md) N0 收口 → N1 人族可玩闭环（勿与下表编辑器待办抢优先级）
- **编辑器/地图**：单位面板筛选已通；单位笔刷 / 装饰物 pathing·Z 等仍见下表

## 编辑器 · 单位面板（对齐装饰物）+ 装饰物缺口补齐

悬崖 / 斜坡 / 边界 / 装饰物主路径已通。下一步（编辑器侧）：单位笔刷；装饰物补 pathing / Z 偏移等。

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
| **单位笔刷** | 待开 | 见 [unit/HIVEWE_ALIGN.md](../design/unit/HIVEWE_ALIGN.md) |
| **水体** | 部分 | 见 [WATER.md](../design/water/WATER.md)；岸浪精调暂搁 |

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

> 对照 [unit/HIVEWE_ALIGN.md](../design/unit/HIVEWE_ALIGN.md)。与装饰物差异：玩家色、单 instance（不 MultiMesh）、字段更多、无 tileset 分类。

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

> 设计拍板：[minimap_phase3_design.md](../design/minimap/PHASE3.md)（2026-08-01）

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

参考：HiveWE `terrain.ixx` L833–871、`ground_texture.ixx`；[WATER_DEEP_ANALYSIS.md §7](../design/hivewe/WATER_DEEP_ANALYSIS.md)；[minimap_phase3_design.md](../design/minimap/PHASE3.md)。

---

## Catalog（崖 M0）

- [x] TerrainArt 四表 → `definitions/terrain_art/*Def` + `Wc3DefStore`
- [x] `Wc3TerrainTileCatalog` 仅地表；`Wc3WaterParams` 读 `WaterTypeDef`
- [x] **`Wc3CliffCatalog`** — CliffTypes 表列 + 岩壁 PNG / modelDir 资源映射
- [x] `MapBuildContext.cliff_catalog` / `MapLoader.get_cliff_catalog()`
- [x] 更新 [CLIFF.md](../design/cliff/CLIFF.md) §8 路径表
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

- [x] **斜坡 Logic（崖边 A）**：Paint + Collect 对齐 [RAMP_WE.md](../design/ramp/RAMP_WE.md)。勿与「应用高度」纯高度坡（B）混淆。
- [x] 存盘权威：`FLAG_RAMP` / `has_ramp`
- [x] Catalog：`Wc3CliffTransCatalog` + `ramp_model_dir`
- [x] Present：`MapRampLayer` 挂 CliffTrans + undig 入口 + romp dig + hide 直崖
- [x] Present：入口低角 +0.5（Present bake，不写 HF）

## 岸浪

- [ ] 泡沫精调暂搁，见 [WATER.md](../design/water/WATER.md)。

## 单位

- [ ] 单位层：先有完整 tscn/资源管线再默认摆放（`place_units` 仍关）。

## 架构债

- [x] 调试栅格 → `MapDebugGridLayer` + `MapLoader.set_view_grid_level`
- [x] GDScript 可见性：禁止跨边界调 `_` 私有 API（`.cursor/rules/gdscript-visibility.mdc`）
- [ ] Doodad/Unit `build(ctx)` 契约统一
- [ ] 删除对第二份 meta Dictionary 手写逻辑的残余调用方（逐步只读 `ctx.heightfield`）

---

## 资产管线（asset-convert）

### GLB 共享贴图外链（减体积）

- [ ] **GLB 外链共享 PNG，避免内嵌重复**  
  现状：多建筑 MDX 共用 `Textures/HumanBase`、`Doodads0`、`DeathSmug`、team_color 等；convert 把 PNG **嵌进每个 GLB**，Godot 导入后再解压成旁路 `建筑名_xxx.png`，磁盘上出现大量同内容副本。  
  目标：运行时只用共享路径（`Textures/...`、`_placeholders/...`）；GLB 改为 URI 外链（或 Godot 可识别的外部依赖），不再 per-model 内嵌。  
  涉及：`tools/asset-convert`（`convert-mdx` / 贴图解析）、导入与 `.scn` 烘焙验证。

### 建筑 Geoset 显隐进 AnimationPlayer（主城升本）

- [x] **修复 Godot 丢弃 Geoset scale 动画轨**（2026-08-04）  
  根因：蒙皮 `Geoset_*` 上的 TRS 轨被 `GLTFDocument` 丢掉；空父节点 `GeosetVis_*` 也会在导入时被拆掉。  
  已做：convert 写旁路 `*.geosetvis.json`（Sequence 作用域 alpha 关键）；`MapModelCache` 加载/bake 时注入 `Geoset_*:visible`；`export_model_scenes --force` 可删旧 `.scn` 重烤。  
  验收：重转 TownHall 后 `Stand` 含 Geoset visible 轨；仅主城外壳可见；`Stand_Upgrade_*` / `Birth*` 显隐正确。

### 模型视觉封装 `assets/visuals/`（继承 .scn + PE2）

- [x] **薄封装层**（2026-08-04）  
  可提交 `assets/visuals/**/*.tscn`：继承 bake `.scn`，挂 `Pe2Root`，根脚本 `ModelVisualSync`（`animation_started` → PE2）。  
  导出：`godot --headless -s res://scripts/tool/export_visual_scenes.gd -- --include Buildings/Human/TownHall --force`  
  运行时 `MapModelCache` 优先 visuals → `.scn` → GLB；`attach_to` 遇已有 Pe2Root 跳过。

### 建筑队伍色（双层垫底）

- [x] **TownHall 旗帜等 Rep1+漫反射 Blend**（2026-08-04）  
  convert 标 `_rep1`；`apply_team_color` 用 `wc3_team_color_underlay.gdshader` 做 `mix(team, diffuse, a)`。  
  放置路径原本就会 `apply_team_color(owner)`；需重转含双层材质的建筑 GLB。

### 单位 Geoset 显隐（与建筑同一管线）

- [x] **Stand 隐藏尸体 / 农民金袋木材**（2026-08-04）  
  同 `*.geosetvis.json` + AnimationPlayer `:visible`；加载后先 snap 到 Stand 姿态。  
  旧转换物无 geosetvis 时需 `node src/cli.js --models-only --force --include "Units/**"` 后 bake。  
  验收 Peasant：`Stand` 仅身体；`Stand_Gold`/`Stand_Lumber` 出袋/木；`Death` 出尸体。

- [x] **树桩 Stand 藏 / Death 显**（2026-08-08）  
  `MapDoodadLayer.ensure_promoted` → `snap_stand_geoset_visibility`；禁止 reveal_all。  
  `MapModelCache`：有 Stand 即定格（勿因「非骨骼 Stand」跳过）；注入名大小写不敏感。

- [x] **野怪 / 小动物尸体 Geoset**（2026-08-09）  
  Present：`MapUnitLayer` 放置后 `snap_stand_geoset_visibility`。  
  资产：`Units/Critters/**` + Echo Isles 常用 Creeps 已补 `geosetvis`；其余 Creeps 按需 `--include`。  
  验收：开局羊/猪/豺狼人等脚下无尸体叠影；Death 后尸体片可见。  
  详见 [GAMEPLAY_VERTICAL.md §5.1](../design/game/GAMEPLAY_VERTICAL.md)。

---

## 游戏竖切 · 战斗 / 表现（2026-08-24 起）

> 对照 [GAMEPLAY_VERTICAL.md](../design/game/GAMEPLAY_VERTICAL.md)、[ABILITY_REFACTOR_PLAN.md](../design/game/ABILITY_REFACTOR_PLAN.md)。  
> 本节只记**尚未完成**或**仅局部落地**项，避免与上文编辑器/地图主线混淆。

### 已局部落地（待手测 / 待提交）

- [x] 仇恨助攻：同 owner + 警戒半径 `_alert_nearby_allies`（非完整营地表）
- [x] 心灵之火：单位死亡 `InnerFireController.cleanup_on_death`
- [x] 大法师 / 远程：火球 tracer + `weapon_missile_art`
- [x] 牧师 / 女巫：无 `Attack` 时回退 `SpellAttack`
- [x] 野怪脱战：`find_acquire_target` 转火
- [x] 农民 / 民兵：`Amil`（Order=`militia`）+ 主城敲钟半径武装
- [x] 英雄死亡：Dissipate 升天、无尸体、`HeroDeathRegistry` 登记
- [x] 祭坛复活（初版）：`revive:` 按钮 + 等级角标 + TrainQueue + 费用/时间随等级
- [x] 肖像框：Portrait geoset snap + 全隐兜底 reveal
- [x] 水元素：`_fm2` 软 alpha 初调（0.48 系数）
- [x] convert：`sanitizeMdxText` 剥 MDX 名字 NUL

### 待做 — P0（玩法 / 表现）

- [ ] **营地 / 队伍仇恨**：`CampRegistry` 或 map 单位组表；中立营地整组助攻、玩家编组联动（现仅同 owner 半径）
- [ ] **祭坛复活补全**：原作 `ARev` 技能 id / Func 对齐；多英雄阵亡队列 UI；复活后技能点 / 未学技能 / 装备态手测；取消队列与 `HeroDeathRegistry` 一致性回归
- [ ] **肖像全单位**：缺 `*_Portrait.gltf` 的单位仍只有队色底 → 批量 convert + bake；主城以外建筑肖像抽验
- [ ] **Unicode NUL 清零**：已改 convert，**须批量重转**常用 Units（至少 Human 竖切包）后 Godot 启动才不刷 ERROR
- [ ] **水元素流体**：PE2 速率 / Birth 序列 / alpha 与原作对拍；必要时专用 shader
- [ ] **暴风雪音效**（⏸ 后置）：`AbilitySfx` 已占位；待音频管线 / wav 进 convert 包后再验收（不挡玩法）
- [x] **技能重构 Phase D**：`game/scripts/logic/effect/` 原子 Effect（2026-09-04）；暴风雪波次伤害已走 `EffectDamageAoe.run_all_victims`（2026-09-05）
- [x] **技能重构 Phase E**：`game_director` 技能逻辑外提（2026-09-04）

### 待做 — P1

- [ ] 民兵：`Amic`（主城 `townbellon`）与 `Amil` 行为完全对齐原作（音效 `TownHallCallToArms`、Buff `Bmil`）
- [ ] 英雄复活：人口 / 英雄上限与「训练中 + 待复活 + 场上」统一计数规则文档化 + selftest
- [ ] `InnerFire` / `Avatar` / 光环等 Buff **迁入 BuffHost spec**（仍部分走独立 Controller）
- [ ] 投射物：更多 order 的 missile art / 命中 FX 数据化（`AbilityFxCatalog` 补表）

---

## 技能系统重构进度

> 权威计划：[ABILITY_REFACTOR_PLAN.md](../design/game/ABILITY_REFACTOR_PLAN.md)（最后更新 2026-09-04）

| Phase | 内容 | 状态 | 说明 |
|-------|------|------|------|
| **A** | `AbilityBehaviorCatalog` | ✅ | order → behavior / target / passive |
| **B** | `AbilityFxCatalog` + 附着 Presenter | ✅ | Casterart / Targetart / fallback |
| **C** | `BuffHost` + `BuffCatalog` + `BuffQuery` | ✅ 门面 | 部分技能仍用 `InnerFireController` 等独立 Controller |
| **D** | Effect 原子 + `*Ability` 变薄 | ✅ | `logic/effect/`；Heal/InnerFire/Clap/Slow/Summon/Avatar/StormBolt |
| **E** | `game_director` 技能外提 | ✅ | Targeting / Runtime / HudFeedback / CastContextFactory |

**Phase D 已建**：`effect_context`、`effect_heal`、`effect_damage_aoe`、`effect_apply_buff`、`effect_spawn_summon`、`effect_play_present`。

**Phase E 已建**：`AbilityTargetingService`、`AbilityRuntimeRegistry`、`AbilityCastContextFactory`、`AbilityHudFeedback`；Director `_setup_ability_services` 注入后转发。

**后续可选**：MassTeleport 再抽 Effect + 真实读条；`effects: []` Catalog 全表驱动；BuffHost 吃掉 InnerFire/Avatar Controller。

---

## 死链清单（docs/ 拍平后，2026-08-10）

docs/ 拍平到 `design/<topic>/` 后，verify 扫出 9 个 dead link（文件本来就不存在）。

### 已重定向（2026-08-10）

| 源文件 | 旧死链 | 现链向 | 说明 |
|--------|--------|--------|------|
| `docs/design/doodad/Y_REFRESH.md` | `../../architecture/UNDO.md` | `../hivewe/UNDO.md` | UNDO 实际在 `design/hivewe/UNDO.md`（HiveWE 行为参考） |
| `docs/design/presentation/LAYERS.md`（×3） | `../../present/MAP_LOADER.md` / `MAP_BUILD_CONTEXT.md` / `PRESENT_UTILS.md` | `LAYERS.md`（§0 / §8） | 三个规划文档未建，内容已合入 `LAYERS.md`（ctx/工具类见 §0，build 流程见 §8） |
| `docs/design/presentation/README.md`（×3） | 同上 | 同上 | 同上 |
| `docs/design/unit/HIVEWE_ALIGN.md`（×3） | `../../unit/SCHEMA.md` | `../../roadmap/TODO.md`（"待建" 标记保留） | SCHEMA.md 待建（N2 落地），文本已带 TODO 标记，末尾 cross-link 改指 TODO 死链清单 |

### 已修深度（仓库外参考，docs/ 内原本也不算死链，但相对深度欠一级，顺手补齐）

| 源文件 | 旧链 | 现链 | 说明 |
|--------|------|------|------|
| `docs/data/WC3_ASSET_PATHS.md` | `../tools/map-parse/README.md` | `../../tools/map-parse/README.md` | 仓库根外部参考 |
| `docs/design/cliff/CLIFF.md` | `../.cursor/rules/hivewe-cliff-reference.mdc` | `../../../.cursor/rules/hivewe-cliff-reference.mdc` | 仓库根外部参考 |
| `docs/design/editor/README.md` | `../../editor/scenes/editor_main.tscn` | `../../../editor/scenes/editor_main.tscn` | 仓库根外部参考 |

> 仓库外参考（`../../../tools/...` / `../../../editor/...` / `../../../addons/...` / `../../../.cursor/...`）一律视为有效外部链接，不计入 docs/ 死链。

### 本轮新增修复（2026-08-10，第二轮）

新增 8 个 markdown 引用 `editor/scripts/ui/...`（commit `aec5e04 editor: move UI to editor/ui` 搬走，但文档没跟上），统一改成 `editor/ui/`：

| 源文件 | 数量 |
|--------|------|
| `docs/architecture/SCRIPTS_LAYOUT.md` | 2 |
| `docs/design/cliff/CLIFF.md` | 1 |
| `docs/design/editor/BRUSHES.md` | 2 |
| `docs/design/editor/I18N.md` | 6 |
| `docs/design/editor/README.md` | 1 |
| `docs/design/editor/UI.md` | 13 |
| `docs/design/minimap/MINIMAP.md` | 4 |
| `docs/design/terrain/HEX_MAP_LESSONS.md` | 1 |

`docs/data/PIPELINE.md` 和 `docs/architecture/SCRIPTS_LAYOUT.md` 多 `../` 深度（从 `../../../` 减为 `../../`）。`PIPELINE.md` 末尾 `../../map/...` 路径错（应是 `../../scripts/map/...`），已修。

### CI 守卫脚本

`tools/check-docs-links.mjs`（无依赖，纯 Node ESM）：

- 默认扫描 `docs/` 下所有 `.md` 的 `[text](path)` 链接
- "docs 内解析失败的文件" 算死链 → 退出码 1
- "解析到 docs 外" 仓库内孤儿路径 → 仅 `--strict` 才算失败
- 用法：
  ```bash
  node tools/check-docs-links.mjs             # 默认（CI 友好，docs 内死链为 0 即过）
  node tools/check-docs-links.mjs --quiet     # 只打印汇总行
  node tools/check-docs-links.mjs --strict    # 仓库外孤儿也视为失败
  node tools/check-docs-links.mjs --docs docs/blog   # 扫描其它子目录
  ```

### 当前状态（2026-08-10）

- `docs/ 内 dead = 0`，仓库外孤儿 = 4（链接到目录但目录无 `README.md`）：
  - `docs/data/PIPELINE.md :: ../../tools/mpq-extract/`（链接到目录，缺 README.md）
  - `docs/design/editor/BRUSHES.md :: ../../../editor/scripts/commands/`（同上）
  - `docs/design/editor/COMMANDS.md :: ../../../editor/scripts/commands/`（同上）
  - `docs/design/editor/UI.md :: ../../../editor/ui/`（同上）

  这 4 个是"指向目录但目录没有 README.md"，**目录本身存在且有内容**——选项 A：补 README；选项 B：链接改到具体文件（如 `editor/scripts/commands/editor_command.gd`）。`--strict` 模式下脚本会报失败。

历史坏 link（错深度，已修）：
- `docs/architecture/SCRIPTS_LAYOUT.md` `../LAYERED_ARCHITECTURE.md` → `LAYERED_ARCHITECTURE.md`（同目录）
- `docs/architecture/SCRIPTS_LAYOUT.md` `../../ramp/RAMP_WE.md` → `../design/ramp/RAMP_WE.md`（ramp 已挪移）
