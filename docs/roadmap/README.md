# roadmap/ — 路线图与待办

> 当前阶段、模块节奏、细粒度待办。  
> 最后更新：2026-09-05

## 文件

| 文件 | 内容 |
|------|------|
| **[NEXT.md](NEXT.md)** | **近中期冲刺（N0–N4）——选下一个玩法 PR 先读这里** |
| [ROADMAP.md](ROADMAP.md) | 地图 ①–⑫ 模块清单 + 验收；Data→Logic→Present→Editor |
| [TODO.md](TODO.md) | 编辑器/地图细粒度缺陷清单（带「最后更新」日期） |

## 当前焦点（2026-09-05）

**玩法主线** → [NEXT.md](NEXT.md)：

1. **N0** 收口 WIP（暴风雪/HUD 等）  
2. **N1** 人族可玩闭环（野怪 AI 验收 · 英雄复活 · Keep · 铁匠升级 · 生产队列 HUD）  
3. **N2** 战斗手感（编队 / 弹道）  
4. **N3** 地图补债并行（水体 / Y / 单位笔刷）——低带宽，不插队  

地图侧崖/坡核心已 ✅；细节仍见 [TODO.md](TODO.md)。

## 模块节奏固化

按 [LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md)：

- 新模块 PR / commit 说明必须标明所处层（Data / Catalog / Logic / Present / Editor / Game）
- 禁止跨层：Layer 不写 flags；Catalog 不算拓扑
- 编辑器笔刷只调 Logic API

## 跨文档原则

- 不以「先做出好看斜坡」驱动架构（地图 [ROADMAP.md §3](ROADMAP.md)）
- 玩法不以「再堆技能」驱动；优先可玩闭环（[NEXT.md](NEXT.md)）
- 不一次性搬完所有文件到 `logic/`（先契约后搬家）

## 何时查这里

| 意图 | 文档 |
|------|------|
| 选下一个**玩法** PR | **[NEXT.md](NEXT.md)** |
| 选下一个**编辑器/地图**缺陷 | [TODO.md](TODO.md) 顶部 |
| 评估地图模块进度 | [ROADMAP.md](ROADMAP.md) §2 |
| 对战竖切历史契约 | [../design/game/ROADMAP.md](../design/game/ROADMAP.md) |
