# water/ — 水体

> 水面 + 岸浪 + Shoreline 远期规划。

## 文件

| 文件 | 内容 |
|------|------|
| [WATER.md](WATER.md) | 水体复刻路线（HiveWE 对齐的岸浪 + 远期 Shoreline / ShorelineWave 增强） |

## 状态（按 [ROADMAP §"⑨ 水体"](../../roadmap/ROADMAP.md)）

**暂缓** — 等高度 + 崖 + 坡稳定后按同五层节奏接入（Data→Catalog→Logic→Present→Editor）。

当前已就位：

- ✅ 自动岸浪（PE2 近似）
- ⏳ 完整 MDX 粒子 / ShorelineWave 装饰浪
- ⏳ 浅水/深水区分
- ⏳ 水面序列帧精修
- ⏳ 泡沫精调（见 [TODO.md §"岸浪"](../../roadmap/TODO.md)）

## 关键概念

| 名 | 位置 | 职责 |
|----|------|------|
| `Wc3WaterParams` | `scripts/map/`（平铺，待归位） | Water.slk → 序列帧/深浅色 |
| `Wc3WaterMesh` | `scripts/map/presentation/water/` | 水面 ArrayMesh |
| `Wc3ShorelineBuilder` | `scripts/map/presentation/water/` | 岸浪发射点 |
| `Wc3ShoreFoam` | `scripts/map/presentation/water/` | 岸浪 MultiMesh / 粒子近似 |
| `MapWaterLayer` | `scripts/map/presentation/layers/` | 水面 Layer；同步 `foam_*` 参数 |
| `MapShoreFoamLayer` | `scripts/map/presentation/layers/` | 岸浪 Layer |

## 何时查这里

- 启动水体模块：先读 [WATER.md](WATER.md)，再按同五层节奏
- 改水面格子几何 → `scripts/map/presentation/water/wc3_water_mesh.gd`
- 改岸浪发射点 → `scripts/map/presentation/water/wc3_shoreline_builder.gd`
- 改岸浪视觉 → `scripts/map/presentation/water/wc3_shore_foam.gd` + `shaders/wc3_shore_foam.gdshader`
- 跑水体自测 → `selftest_shoreline.gd`（`tests/water/`）
