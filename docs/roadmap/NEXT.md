# 近中期开发路线图（NEXT）

> **角色**：在地图 ①–⑫ 与人族竖切 F0–F10 / C0–C3 已基本落地之后，指导「下一步做什么」。  
> **总纲**：[LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md)  
> **地图节奏**：[ROADMAP.md](ROADMAP.md)（①–⑫）  
> **对战竖切**：[../design/game/ROADMAP.md](../design/game/ROADMAP.md) · [GAMEPLAY_VERTICAL.md](../design/game/GAMEPLAY_VERTICAL.md)  
> **细粒度待办**：[TODO.md](TODO.md)  
> 最后更新：2026-09-05

---

## 0. 一句话现状

| 轨道 | 水位 |
|------|------|
| **资产管线** | MPQ → 三车道（视觉 / SLK / 地图）→ `.scn`+PE2；有效覆盖率约 99% |
| **地图** | 高度图 + 地面纹理 + 崖 M0–M2 + 坡核心 ✅；水体 / 装饰物 Y / 单位笔刷仍有缺口 |
| **对战** | Echo Isles 壳 + 采矿伐木 + 建造训兵 + 战斗 C0–C3 + 野怪 AI + 大法师/山丘/支援技能 ✅ |
| **技能架构** | Behavior / Fx / Buff / Effect + Director 外提（Phase A–E）✅ |

入口：`game/scenes/game_main.tscn`（F6 玩法）· `editor/scenes/editor_main.tscn`（编辑器）。

**结论**：主线从「再堆技能」切到 **人族 Melee 可玩闭环收尾**；技能框架已够撑下一阶段扩展。缺的是战役感闭环，不是架构。

---

## 1. 总览（编号即推荐顺序）

```text
N0  收口当前 WIP          暴风雪/HUD/Director 等未提交改动 → 合入 + Echo 手测
N1  人族可玩闭环收尾      野怪 AI 验收 · 英雄复活 · Keep · 铁匠升级 · 生产队列 HUD
N2  战斗与命令手感层      编队/群体寻路 · 弹道 FX · Hold/Patrol/AI 优先级
N3  地图侧补债（并行）    水体 · Y 贴地 · 装饰物 pathing/Z · 单位笔刷
N4  第二竖切扩展（择一）  物品商店 / 人族二线 / 第二种族最小集 / 迷雾小地图
N∞  远期（门禁后）        触发器 VM · 联机 · 物体编辑器 · 全科技树
```

玩法主线优先 **N0 → N1 → N2**；**N3** 低带宽穿插，不插队玩法冲刺；**N4** 在 N1 验收后再开。

---

## 2. 分阶段清单

### N0 · 收口当前 WIP（本周）

工作区常见焦点：暴风雪区域 FX、`GameDirector` 瘦身、选中/HUD、召唤 Effect 等。

- [x] 暴风雪玩法/表现收口（贴图预览、染色、APPROACH、建筑伤、Effect 抽伤害）；音效⏸后置
- [ ] 合入未提交玩法/表现改动；跑相关 selftest
- [ ] Echo 手测：暴风雪 / 水元素 / 传送；野怪拉怪 ↔ 互殴 ↔ leash；HUD 血蓝 / Buff / 自动施法

**验收**：上述剧本无阻塞 bug；主分支可 F6 稳定打开 `game_main`。

**技能下一刀（可选，不挡 N1）**：AHmt 读条/FX 已接；下一刀可做光环 BuffHost 或下个英雄技能 — 见 [BLIZZARD.md §10](../design/game/BLIZZARD.md)。

---

### N1 · 人族竖切「可玩闭环」收尾（当前主线）

F10 技能与 C0–C3 战斗已接线；竖切剧本仍有「像魔兽」的洞。

| 优先级 | 项 | 说明 | 相关文档 |
|--------|-----|------|----------|
| P0 | **U3 Echo 手测抛光** | 拉怪、打断 AI、尸体/归巢 | [UNIT_AI.md](../design/game/UNIT_AI.md) |
| P0 | **英雄死亡 → 祭坛复活** | 已有 `HeroDeathRegistry` 线索 | [GAMEPLAY_VERTICAL.md](../design/game/GAMEPLAY_VERTICAL.md) |
| P1 | **主城 Keep `htow→hkee`** | 解锁后续建筑/科技语义（原 F7） | 同上 |
| P1 | **铁匠武器/护甲升级** | F6 后置；攻防芯片角标才有意义 | 同上 |
| P1 | **HUD 生产队列** | 中栏训练中列表 | [HUD.md](../design/game/HUD.md) |
| P2 | 民兵回退 / 群体移动占位再对齐 | 手感，不挡功能 | [GROUP_MOVE.md](../design/pathfinding/GROUP_MOVE.md) |
| ✅ | **单位自然回血/回蓝** | `UnitRegen`：Balance `regen*` + 英雄 STR/INT×0.05 | [GAMEPLAY_VERTICAL.md](../design/game/GAMEPLAY_VERTICAL.md) |

**验收剧本（人工点一遍）**：

1. 开局采矿伐木 → 造 Farm / Altar / Barracks  
2. 祭坛训出大法师；兵营训步兵 /（铁匠后）火枪手  
3. 攻击野怪营：互殴、leash、Stop 可打断  
4. 英雄阵亡 → 祭坛可复活（费用/时间读 Def）  
5. 主城升 Keep；铁匠升级后伤害/护甲变化可见  
6. HUD 显示训练队列；Buff / 自动施法不花  

**目标**：一个人能在 Echo 上打完「开局 → 基建 → 英雄技能 → 清野」而不靠作弊补洞。

---

### N2 · 战斗与命令「手感层」

逻辑对了之后，差在细节。仍属玩法，**不扩种族**。

| 优先级 | 项 | 说明 |
|--------|-----|------|
| P0 | 编队 / 群体寻路 | 见 [GROUP_MOVE.md](../design/pathfinding/GROUP_MOVE.md)；网格 A\* 权威不变 |
| P1 | 弹道与命中 FX | 继续 `Wc3FxPresenter` / PE2（FireBall 方案 B 已有） |
| P1 | Hold / Patrol / 攻击优先级 | 与 UnitAI 优先级表对齐 |
| P2 | 伤害飘字 / 选中环 / 悬停环微调 | 已有基础，肉眼标定 |

**验收**：一队步兵 + 大法师清野怪营，手感接近原作（允许数值/特效差一档）。

---

### N3 · 地图侧补债（与玩法并行、低带宽）

服从地图 [ROADMAP.md](ROADMAP.md) ⑨–⑫；**不把斜坡大改或全量 `git mv` 插入玩法冲刺**。

| 项 | 对应 | 状态提示 |
|----|------|----------|
| 水体稳定化 | ⑨ · [WATER.md](../design/water/WATER.md) | 部分已有；岸浪精调可后置 |
| 装饰物 / 单位 Y 贴 heightfield | ⑩ · [Y_REFRESH.md](../design/doodad/Y_REFRESH.md) | 不在 Layer 瞎估 |
| 装饰物 pathing 可视化 / Z 偏移 | 编辑器 P0 · [TODO.md](TODO.md) | 对战不依赖 |
| 单位笔刷 | ⑫ · [unit/HIVEWE_ALIGN.md](../design/unit/HIVEWE_ALIGN.md) | 编辑器侧 |

---

### N4 · 第二竖切扩展（N1 验收后 · 择一）

**不要并行三条**；开新里程碑前在 PR/日志标明所选：

| 选项 | 内容 | 备注 |
|------|------|------|
| A | **物品 + 商店 + 回城卷轴** | 对齐 Melee Bootstrap P1 |
| B | **人族二线单位** | 骑士 / 狮鹫等（需 Keep + 科技） |
| C | **第二种族最小集** | 建议兽族：苦工 → 大厅 → 猎头 → 英雄一技能 |
| D | **迷雾 / 游戏内小地图单位点** | 对战 HUD；编辑器小地图 Phase 3 已大部分落地 |

---

### N∞ · 远期（明确不做，直到门禁满足）

| 能力 | 门禁 |
|------|------|
| 完整触发器 / wtg VM | Melee 动作表稳定 + N1 竖切验收 |
| 联机 / 录像 | 单机闭环稳定 |
| 物体编辑器、全科技树、全技能插件化 | 非本阶段 |

详见 [design/game/ROADMAP.md §E](../design/game/ROADMAP.md) · [ARCHITECTURE.md](../design/game/ARCHITECTURE.md)。

---

## 3. 建议节奏（约 4～6 周）

| 周 | 产出 |
|----|------|
| **W1** | N0：合入 WIP；Echo 技能 + 野怪 AI 验收清单打勾 |
| **W2** | N1：英雄复活 + Keep；生产队列 HUD |
| **W3** | N1/N2：铁匠升级 + 战斗手感（编队/弹道）一小步 |
| **W4+** | N4 择一开新竖切；N3 水体/Y 贴地穿插 |

---

## 4. 工程纪律（继续守住）

1. **改贴图路径 → Catalog；改拓扑 → Logic；挂 Mesh → Present**  
2. 数值读 SLK Def，禁止逻辑里写死造价 / 伤害  
3. 新技能优先 **拼 Effect + 注册 Behavior**，少再堆 `*Ability` 分叉  
4. 资产只进 `assets/` 三车道；正版 MPQ 自备（[LEGAL.md](../data/LEGAL.md)）  
5. 新模块 PR / commit 标明所处层（Data / Catalog / Logic / Present / Editor / Game）

---

## 5. 文档索引（改代码前先对口径）

| 主题 | 文档 |
|------|------|
| 地图分层与模块顺序 | [ROADMAP.md](ROADMAP.md) · [LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md) |
| 对战阶段 A–F–E | [design/game/ROADMAP.md](../design/game/ROADMAP.md) |
| 人族 ID / 验收剧本 | [GAMEPLAY_VERTICAL.md](../design/game/GAMEPLAY_VERTICAL.md) |
| 战斗 / AI / 技能 / HUD | [COMBAT_SYSTEM.md](../design/game/COMBAT_SYSTEM.md) · [UNIT_AI.md](../design/game/UNIT_AI.md) · [ABILITY_SYSTEM.md](../design/game/ABILITY_SYSTEM.md) · [HUD.md](../design/game/HUD.md) |
| 技能重构 as-built | [ABILITY_REFACTOR_PLAN.md](../design/game/ABILITY_REFACTOR_PLAN.md) |
| 编辑器细项 | [TODO.md](TODO.md) |
| 资产三车道 | [ASSET_LANES.md](../architecture/ASSET_LANES.md) · [PIPELINE.md](../data/PIPELINE.md) |

---

## 6. 与旧路线图的关系

| 文档 | 职责 |
|------|------|
| [ROADMAP.md](ROADMAP.md) | 地图编辑重构 ①–⑫（长期模块清单） |
| [design/game/ROADMAP.md](../design/game/ROADMAP.md) | 对战场景阶段 A–F–E（竖切历史 + 契约） |
| **本文 NEXT.md** | **当前冲刺优先级**（N0–N4）；选下一个 PR 时先读这里 |
| [TODO.md](TODO.md) | 编辑器/地图细粒度缺陷，不替代本文件的玩法主线 |
