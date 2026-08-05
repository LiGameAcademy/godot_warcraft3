# godot_warcraft3 文档

> Godot 4.6 复刻《魔兽争霸 3》玩法的实验项目。
>
> 总纲：[architecture/LAYERED_ARCHITECTURE.md](architecture/LAYERED_ARCHITECTURE.md)
> 路线图：[roadmap/ROADMAP.md](roadmap/ROADMAP.md)
> **新电脑资源准备**：[../README.md](../README.md) · [../tools/README.md](../tools/README.md)（`node tools/dev-setup.mjs`）
> 最后更新：2026-08-05

本文档按"代码模块对应"组织成子目录：

| 目录 | 内容 | 阅读时机 |
|------|------|----------|
| [architecture/](architecture/) | 分层总纲、MapRoot 节点树、`scripts/` 目录全景、数据契约、悬崖重构历史 | 入坑第一天；改任何代码前 |
| [game/](game/) | **游戏场景**路线图 + 架构 + 环境复刻方案（Echo Isles / Melee / 天空天气光照） | 玩法竖切、对战初始化、环境表现时 |
| [roadmap/](roadmap/) | 地图模块路线图 ROADMAP + 细粒度待办 TODO | 选下一个地图/编辑器 PR 时 |
| [data/](data/) | 经典资产路径、合规、离线解包/转换管线 | 处理资产/解包/转换时 |
| [terrain/](terrain/) | 地面 tile、Autotile、HEX_MAP 经验 | 改地面渲染/几何时 |
| [cliff/](cliff/) | 直崖数据、选型、异种策略、回归 | 改悬崖 Logic/Catalog/Present 时 |
| [ramp/](ramp/) | 斜坡 HiveWE 思路 + 分层重构历史 | 改斜坡（tag `milestone/ramp-layered` 待打）时 |
| [water/](water/) | 水体 + 岸浪路线 | 改水面/岸浪时（暂缓） |
| [editor/](editor/) | 编辑器架构、笔刷、命令模式、i18n、UI 组件 | 改编辑器/笔刷/撤销时 |
| [tests/](tests/) | 测试索引与跑法 | 写/改 selftest 时 |

## 阅读顺序

新人建议按这个顺序读：

1. **[architecture/LAYERED_ARCHITECTURE.md](architecture/LAYERED_ARCHITECTURE.md)** — 五层分层总纲
2. **[roadmap/ROADMAP.md](roadmap/ROADMAP.md)** — 地图模块节奏（①–⑫）
3. **[game/ROADMAP.md](game/ROADMAP.md)** — 游戏场景 / 对战竖切（⑬）
4. **[architecture/MAP_ARCHITECTURE.md](architecture/MAP_ARCHITECTURE.md)** — 节点树 + 逻辑流
5. **[architecture/SCRIPTS_LAYOUT.md](architecture/SCRIPTS_LAYOUT.md)** — `scripts/` 目录全景
6. **[editor/EDITOR.md](editor/EDITOR.md)** — 编辑器入口

## 分层约定（5 层硬门禁）

**Data → Catalog → Logic → Presentation → Editor**

- **Data**（`scripts/map/data/`）：纯数据类（`Wc3*`），不进场景树，无业务规则
- **Catalog**（`scripts/map/catalog/`）：资源映射表（SLK → 贴图/GLB），运行时扫盘
- **Logic**（`scripts/map/logic/`）：规则 + 计算（Autotile、CliffBuilder、ShorelineBuilder），输出结构化数据，不碰场景树
- **Presentation**（`scripts/map/presentation/`）：场景层（`Map*` + `Map*Layer`），只挂树，消费 Logic 输出
- **Editor**（`editor/scripts/`）：编辑器，通过 Logic API 改数据

**禁止**：
- Layer 写 `flags` / `layerHeights` / 拓扑
- Catalog 计算拓扑
- Editor 绕过 Logic / Command 直写 Document 私有

详见 [architecture/LAYERED_ARCHITECTURE.md](architecture/LAYERED_ARCHITECTURE.md) §「分层门禁」。

## 编辑器 · 游戏 · 预览

| 入口 | 场景 | 用途 |
|------|------|------|
| 地图编辑器 | [`editor/scenes/editor_main.tscn`](../editor/scenes/editor_main.tscn) | 现主场景；笔刷走 Logic API |
| 游戏场景 | [`game/scenes/game_main.tscn`](../game/scenes/game_main.tscn) | 目标：Echo Isles 对战竖切（见 [game/](game/)） |
| 旧预览 | [`scenes/main.tscn`](../scenes/main.tscn) | Lost Temple 静态预览 |

**操作**：WASD 平移，QE 升降，Shift 加速，右键旋转，滚轮缩放。

## 资产合规

仓库**不包含**暴雪游戏资产。开发与运行前须自备正版经典客户端。
详见 [data/LEGAL.md](data/LEGAL.md) 与 [data/WC3_ASSET_PATHS.md](data/WC3_ASSET_PATHS.md)。
所有解包/转换产物进 `.cache/`、`assets/asset-converted/` 等目录，均被 `.gitignore` / `.gdignore` 排除。

## 相关

- 项目 README：[README.md](../README.md)
- 编辑器入口：[`editor/scenes/editor_main.tscn`](../editor/scenes/editor_main.tscn)
- 离线工具：[`tools/`](../tools/)（mpq-extract / asset-convert / map-parse / slk-export）
- Cursor rules：[`.cursor/rules/`](../.cursor/rules/)
