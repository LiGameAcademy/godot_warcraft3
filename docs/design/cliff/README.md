# cliff/ — 悬崖

> 直崖数据、选型、异种策略、回归测试。

## 文件

| 文件 | 内容 |
|------|------|
| [CLIFF.md](CLIFF.md) | 直崖数据、选型、异种策略 B、层高与回归、cliff 路径表 §8、跑法 §9 |

## 状态（按 [TODO.md §"崖 M0"](../../roadmap/TODO.md)）

| 里程碑 | 状态 | 要点 |
|--------|------|------|
| M0 Catalog | ✅ | `Wc3CliffCatalog`；收缩 `Wc3TerrainTileCatalog` |
| M1 Logic | ✅ | `Wc3CliffLogic` + `logic/cliff/`；Document 委托 |
| M2 Present | ✅ | placements 驱动；恢复地面挖洞对接 |
| M3 脏区 | ⏳ 可选；不挡斜坡 | 命令标签 |
| 手测 | ⏳ | Lost Temple 崖外观与拆分前一致 |

**Tag**：`milestone/cliff-layered` ✅

## 关键概念

- **TAG / Variation**：每格用 BL 角 `cliffVariations`（0–7 真随机，0 合法）；挂模按 TAG `clamp`
- **异种崖策略 B**：触及直崖格整格同化当前类型；远处隔离（详见 [CLIFF.md](CLIFF.md)）
- **groundTile**：直崖格四角写入/强制 `cliff.groundTile`（对齐 viewer `cornerTexture`）
- **硬常量**：`LAYER_MIN=0`、`LAYER_MAX=14`、`MAX_CLIFF_ADJ_DELTA=2`

## 何时查这里

- 改悬崖判定/选型 → [CLIFF.md](CLIFF.md) + `scripts/map/logic/cliff/wc3_cliff_logic.gd`
- 改悬崖材质/栅格 → `shaders/wc3_cliff.gdshader` + `scripts/map/presentation/layers/map_cliff_layer.gd`
- 加新崖类型 → `scripts/definitions/terrain_art/cliff_type_def.gd` + `Wc3CliffCatalog`
- 跑悬崖回归 → [CLIFF.md §9](CLIFF.md)（`selftest_cliff_*`）
- 改 HiveWE 选型参考 → `.cursor/rules/hivewe-cliff-reference.mdc`
