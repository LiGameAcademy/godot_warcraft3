# godot_warcraft3 文档

> Godot 4.6 复刻《魔兽争霸 3》玩法的实验项目。  
>
> 总纲：[architecture/LAYERED_ARCHITECTURE.md](architecture/LAYERED_ARCHITECTURE.md)  
> **近中期冲刺**：[roadmap/NEXT.md](roadmap/NEXT.md)（N0–N4 · 选下一个玩法 PR）  
> 地图路线图：[roadmap/ROADMAP.md](roadmap/ROADMAP.md)  
> **新电脑资源准备**：[../README.md](../README.md) · [../tools/README.md](../tools/README.md)（`node tools/dev-setup.mjs`）  
> 最后更新：2026-09-05

本文档按"类型 + 子系统"组织成二级目录：

| 一级目录 | 内容 | 阅读时机 |
|----------|------|----------|
| **[design/](design/)** | **设计驱动**（11 个子系统按专题二级归类） | 改任何模块前；查子系统设计/口径/决策 |
| [architecture/](architecture/) | 分层总纲、MapRoot 节点树、`scripts/` 目录全景、数据契约 | 入坑第一天；改任何代码前 |
| [data/](data/) | 经典资产路径、合规、离线解包/转换管线 | 处理资产/解包/转换时 |
| [roadmap/](roadmap/) | **NEXT** 近中期冲刺 + 地图 ROADMAP + 细粒度 TODO | 选下一个玩法/地图/编辑器 PR 时 |
| [test-cases/](test-cases/) | **测试用例文档**（手动验收 / 复刻对比） | 手动测试 / 回归 / 复刻对比 |
| [tests/](tests/) | 测试索引与 headless 跑法 | 写/改 selftest 时 |
| [blog/](blog/) | 公开向 blog 系列（开发心得 / 对齐笔记） | 公开/分享时 |
| **[dev-log/](dev-log/)** | **开发日志**（按分支/里程碑的简要记事）+ 知乎专栏素材（方案 + 草稿） | 回顾某次竖切做了什么 / 写知乎专栏时 |

## 阅读顺序

新人建议按这个顺序读：

1. **[architecture/LAYERED_ARCHITECTURE.md](architecture/LAYERED_ARCHITECTURE.md)** — 五层分层总纲
2. **[roadmap/NEXT.md](roadmap/NEXT.md)** — 近中期冲刺（N0–N4 · 当前主线）
3. **[roadmap/ROADMAP.md](roadmap/ROADMAP.md)** — 地图模块节奏（①–⑫）
4. **[design/game/ROADMAP.md](design/game/ROADMAP.md)** — 游戏场景 / 对战竖切（A–F–E）
5. **[architecture/MAP_ARCHITECTURE.md](architecture/MAP_ARCHITECTURE.md)** — 节点树 + 逻辑流
6. **[architecture/SCRIPTS_LAYOUT.md](architecture/SCRIPTS_LAYOUT.md)** — `scripts/` 目录全景
7. **[design/editor/EDITOR.md](design/editor/EDITOR.md)** — 编辑器入口

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

## docs 历史

- 2026-08-10 docs 拍平（B 方案）+ 链接修复：所有 ramp/cliff/water/doodad/unit/editor/shader/terrain/hivewe/present/game 拍平到 `design/<topic>/`；保留 architecture/data/roadmap/test-cases/tests/blog 一级。`test-cases/` 新建为手动验收文档目录（与 `tests/` 测试索引互补）。提交前用 `node tools/check-docs-links.mjs` 验证 docs/ 内零死链。见 [design/README.md](design/README.md) · [roadmap/TODO.md 死链清单](roadmap/TODO.md)。
- 2026-08-03 原始结构：ramp/cliff/water/doodad/... 各自为一级 + game/architecture/data/roadmap/blog 并存。
