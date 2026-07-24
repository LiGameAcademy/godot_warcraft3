# 待办

> 细粒度缺陷清单。阶段规划见 [ROADMAP.md](ROADMAP.md)。  
> 最后更新：2026-07-24

## 当前焦点：悬崖模块分层重构（⑦）

地面纹理 + 编辑总管 + 命令模式已可测。下一波按 [CLIFF_REFACTOR.md](CLIFF_REFACTOR.md)：

1. M0：`Wc3CliffCatalog` 从 `Wc3TerrainTiles` 拆出  
2. M1：`Wc3CliffLogic` 承接 Document 蛋糕/策略 B  
3. M2：Present 只消费 placements；恢复地面挖洞对接  
4. 然后再开斜坡 [RAMP.md](RAMP.md)

---

## Catalog 债（崖 M0）

- [ ] **拆分 `Wc3TerrainTiles`** — 详见 [CLIFF_REFACTOR.md](CLIFF_REFACTOR.md) §4.2 / §5 M0
  - 地表：仅 `Terrain.slk`
  - 悬崖：`Wc3CliffCatalog`（CliffTypes → 贴图、groundTile、modelDir）

---

## 编辑层（⑤ — 已打通）

- [x] **Editor 总管** + **命令模式** + 地表笔刷可见重建
- [ ] 脏区局部重建 Ground（接口已有 dirty rect）
- [ ] 撤销 UI 灰显 / i18n
- [ ] 悬崖笔刷全面委托 `Wc3CliffLogic`（M1）

**验收（地面）**：改地表 → 数据变 → Ground 更新；Ctrl+Z 可撤销。

---

## 地形 / 斜坡

- [ ] **斜坡（崖边 A）**：设计与路线图见 [RAMP.md](RAMP.md)（M0–M4）。**实现按里程碑**；勿与「应用高度」纯高度坡（B）混淆。直崖见 [CLIFF.md](CLIFF.md)。排在 ⑦ 悬崖之后。

## 岸浪

- [ ] 泡沫精调（偏移/贴图细节）暂搁，见 [WATER.md](WATER.md)。

## 单位

- [ ] 单位层：先有完整 tscn/资源管线再默认摆放（`place_units` 仍关）。

## 架构债（摘自 MAP_ARCHITECTURE）

- [x] 调试栅格统一到 `MapDebugGridLayer` + `MapLoader.set_view_grid_level`
- [ ] Doodad/Unit `build(ctx)` 契约统一
- [ ] 删除对第二份 meta Dictionary 手写逻辑的残余调用方（逐步只读 `ctx.heightfield` / `ctx.meta`）
