# ramp/ — 斜坡

> HiveWE 思路 + 分层重构历史 + 验收。

## 文件

| 文件 | 内容 |
|------|------|
| [RAMP_WE.md](RAMP_WE.md) | HiveWE 思路权威（Paint/Collect 行为、CliffTrans 选型、GLB 探测） |
| [HIVEWE_ALIGN.md](HIVEWE_ALIGN.md) | 斜坡层向 HivEWE 对齐的路线图（已对齐 / 待对齐 / 测试状态）|
| [RAMP_REFACTOR.md](RAMP_REFACTOR.md) | 分层重构历史 + tag 计划 + 入口低角 +0.5 决策记录 |

## 状态（按 [TODO.md §"斜坡"](../../roadmap/TODO.md)）

| 阶段 | 状态 |
|------|------|
| Logic（Paint + Collect，对齐 HiveWE） | ✅ |
| 存盘权威 `FLAG_RAMP` / `has_ramp` | ✅ |
| Catalog：`Wc3CliffTransCatalog` + `ramp_model_dir` | ✅ |
| Present：挂 CliffTrans + undig 入口 + romp dig + hide 直崖 | ✅ |
| Present：入口低角 +0.5（bake，不写 HF） | ✅ |
| 脏区 / tag `milestone/ramp-layered` | ⏳ |

**WE 思路门禁**（[RAMP_WE.md](RAMP_WE.md)）：
- Paint 只写 `FLAG_RAMP`
- Collect 匹配 CliffTrans（数据侧，与 cliff 拓扑分离）
- 崖边 A 区别于"应用高度"纯高度坡 B

## 关键概念

- **Paint** ≈ `update_ramp`（`scripts/map/logic/ramp/wc3_ramp_paint.gd`）
- **Collect** ≈ `update_cliff_meshes` 数据侧（`scripts/map/logic/ramp/wc3_ramp_collect.gd`）
- **Present**：`MapRampLayer` 挂 CliffTrans；挖洞/藏崖由 `MapRampLayer` 调 Terrain/Cliff API
- **入口低角 +0.5**：Present bake，不写 HF

## 何时查这里

- 改 Paint/Collect → [RAMP_WE.md](RAMP_WE.md) §4-§5 + `scripts/map/logic/ramp/wc3_ramp_*.gd`
- 改 Present 挂模 → `scripts/map/presentation/layers/map_ramp_layer.gd`
- 验收 → 跑 `selftest_ramp_logic.gd` / `selftest_ramp_present.gd` / `selftest_ramp_data.gd`
- 重构历史 → [RAMP_REFACTOR.md](RAMP_REFACTOR.md)
