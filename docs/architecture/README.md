# architecture/ — 架构总纲

> 分层、MapRoot 节点树、`scripts/` 目录全景、数据契约、悬崖重构历史。

## 文件

| 文件 | 内容 |
|------|------|
| [LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md) | 五层分层总纲（Data / Catalog / Logic / Presentation / Editor）+ 门禁 + 命名约定 |
| [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) | MapRoot 节点树 + 脚本职责全表 + 手动干预速查 + 重构优先级 |
| [MAP_DATA.md](MAP_DATA.md) | 地图数据契约（`Wc3Heightfield` / `Wc3TileVertex` JSON 键表 + 序列化示例） |
| [CLIFF_REFACTOR.md](../design/cliff/CLIFF_REFACTOR.md) | 悬崖分层重构历史（M0–M2 已完成于 tag `milestone/cliff-layered`） |
| [SCRIPTS_LAYOUT.md](SCRIPTS_LAYOUT.md) | `scripts/` 目录树 + 分层映射（catalog / data / logic / presentation / infra） |

## 阅读顺序

1. **[LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md)** — 总纲
2. **[SCRIPTS_LAYOUT.md](SCRIPTS_LAYOUT.md)** — `scripts/` 全景
3. **[MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md)** — 节点树 + 手动干预速查
4. **[MAP_DATA.md](MAP_DATA.md)** — 数据契约

## 何时查这里

- 改任何代码前 → LAYERED §「分层门禁」
- 新增模块 → 照 SCRIPTS_LAYOUT 找目录（`scripts/map/{catalog,data,logic,presentation,infra}/`）
- 改场景树/构建顺序 → MAP_ARCHITECTURE §1.1 / §5
- 改 heightfield JSON 字段 → MAP_DATA
- 改自动加载 / Autoload → LAYERED §2（`AssetProvider` / `Wc3DefStore` / `EditorI18n`）

## 重构优先级（来自 MAP_ARCHITECTURE §7.3）

| 优先级 | 项 |
|--------|----|
| **P0** | 统一调试栅格（`MapLoader.set_view_grid_level` 为唯一入口） |
| **P0** | 文档与默认值对齐（`place_units=false`、编辑器 `auto_load_on_ready=false`） |
| **P1** | 统一 Layer 契约（Doodad/Unit 改为 `build(ctx)`） |
| **P1** | Pipeline 配置化（`_load_all` 步骤表） |
| **P1** | 泡沫参数单源（`Wc3WaterBuildOptions` 或挂 Context） |
| **P2** | 目录归位（`app/` `layers/` `domain/` `infra/` `view/`） |
| **P2** | 更细重建粒度（悬崖笔刷只重建 Cliffs+Water） |
| **P2** | Domain 输出结构化（TypedDict / 小 RefCounted） |
