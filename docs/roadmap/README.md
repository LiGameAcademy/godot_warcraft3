# roadmap/ — 路线图与待办

> 当前阶段、模块节奏、细粒度待办。

## 文件

| 文件 | 内容 |
|------|------|
| [ROADMAP.md](ROADMAP.md) | ①–⑫ 模块清单 + 验收；按 Data→Logic→Present→Editor 节奏；总体原则"先搭框架再做功能" |
| [TODO.md](TODO.md) | 细粒度缺陷清单 + 当前焦点 + 状态符号（带"最后更新"日期） |

## 当前焦点（看 [TODO.md](TODO.md) 顶部）

按 TODO.md 最后更新（2026-08-01），焦点：**装饰物放置笔刷 + 小地图实时光栅**。

- ✅ 悬崖 M0–M2 完成（tag `milestone/cliff-layered`）
- ✅ 斜坡 Logic + Present 核心（入口低角 +0.5、undig 入口、romp dig、hide 直崖）
- ⏳ **斜坡脏区 + tag `milestone/ramp-layered`**
- ⏳ **水体**（ROADMAP 标"暂缓"，TODO 标"待开"——以最新 commit 为准）

## 模块节奏固化

按 [LAYERED_ARCHITECTURE.md §"固化模块节奏"](../architecture/LAYERED_ARCHITECTURE.md)：

- 新模块 PR / commit 说明必须标明所处层（Data / Catalog / Logic / Present / Editor）
- 禁止跨层：Layer 不写 flags；Catalog 不算拓扑
- 编辑器笔刷只调 Logic API

## 跨文档原则（ROADMAP §3 "明确不做"）

- 不以"先做出好看斜坡"驱动架构
- 不一次性搬完所有文件到 `logic/`（先契约后搬家）
- 不并行维护长期双权威（`Dictionary` hf 与 `Wc3Heightfield`；迁移窗口要短）

## 何时查这里

- 选下一个 PR → [TODO.md](TODO.md) 顶部 + 当前分支
- 评估模块进度 → [ROADMAP.md](ROADMAP.md) §2 对应小节
- 改 PR / commit 习惯 → ROADMAP §3 原则
