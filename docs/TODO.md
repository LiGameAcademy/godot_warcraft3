# 待办

> 细粒度缺陷清单。阶段规划见 [ROADMAP.md](ROADMAP.md)。  
> 最后更新：2026-07-25

## 当前焦点：斜坡模块分层重构（⑧）

悬崖 Catalog/Logic/Present 已打 tag `milestone/cliff-layered`。按 [RAMP.md](RAMP.md)。

| 里程碑 | 状态 | 要点 |
|--------|------|------|
| **崖 M0–M2** | ✅ + tag | `milestone/cliff-layered`；M3 脏区可选 |
| **坡 M0 笔刷迁出** | 待开 | Document → `Wc3RampLogic`；蓝菱形手感不变 |
| **坡 M1 Dispatcher** | 待开 | `collect_ramp_placements` + romp + CliffTrans TAG |
| **坡 M2 Present** | 待开 | placements → Layer；挖洞 |
| **坡 M3/M4** | 后置 | 转角/对角；脏区；`milestone/ramp-layered` |

---

## Catalog（崖 M0）

- [x] TerrainArt 四表 → `definitions/terrain_art/*Def` + `Wc3DefStore`
- [x] `Wc3TerrainTileCatalog` 仅地表；`Wc3WaterParams` 读 `WaterTypeDef`
- [x] **`Wc3CliffCatalog`** — CliffTypes 表列 + 岩壁 PNG / modelDir 资源映射
- [x] `MapBuildContext.cliff_catalog` / `MapLoader.get_cliff_catalog()`
- [x] 更新 [CLIFF.md](CLIFF.md) §8 路径表
- [x] `selftest_cliff_*` / `selftest_def_store_cliff` 绿（Catalog 接线后）
- [ ] Lost Temple 手测：崖外观与拆分前一致

---

## 编辑层（⑤ — 地面已打通）

- [x] Editor 总管 + 命令模式 + 地表笔刷可见重建
- [ ] 脏区局部重建 Ground（接口已有 dirty rect）
- [ ] 撤销 UI 灰显 / i18n
- [x] 悬崖笔刷全面委托 `Wc3CliffLogic`（M1；Ramp 仍在 Document）
- [x] 删除 `Wc3CliffTiles`：拓扑→Logic，GLB/变体→Catalog（磁盘探测）
- [x] Document 去掉 `hf` 属性（仅 `as_build_dict()` 过渡）

**验收（地面）**：改地表 → 数据变 → Ground 更新；Ctrl+Z 可撤销。

---

## 地形 / 斜坡

- [ ] **斜坡（崖边 A）**：[RAMP.md](RAMP.md) M0–M4。勿与「应用高度」纯高度坡（B）混淆。
- [ ] M0：`logic/ramp/wc3_ramp_logic.gd` + `Wc3RampPlacement`；`selftest_ramp_logic` 绿
- [ ] M1：直线 4 向 placements；缺模警告
- [ ] M2：`MapRampLayer`（或 CliffLayer 通道）+ 坡格 gap
- [ ] M3：外/内转角 → 对角线锯齿

## 岸浪

- [ ] 泡沫精调暂搁，见 [WATER.md](WATER.md)。

## 单位

- [ ] 单位层：先有完整 tscn/资源管线再默认摆放（`place_units` 仍关）。

## 架构债

- [x] 调试栅格 → `MapDebugGridLayer` + `MapLoader.set_view_grid_level`
- [x] GDScript 可见性：禁止跨边界调 `_` 私有 API（`.cursor/rules/gdscript-visibility.mdc`）
- [ ] Doodad/Unit `build(ctx)` 契约统一
- [ ] 删除对第二份 meta Dictionary 手写逻辑的残余调用方（逐步只读 `ctx.heightfield`）
