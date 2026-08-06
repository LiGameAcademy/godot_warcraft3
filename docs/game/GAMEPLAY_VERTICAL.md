# 人族对战 · 游玩竖切（Gameplay Vertical）

> 目标：按**真实开局游玩顺序**，在 Echo Isles 上跑通「采矿伐木 → 基建 → 英雄 → 兵营产兵 → 科技分支 → 大法师技能」闭环。  
> 范围：**仅人族 Melee 最小集**；不做完整科技树、不做多族、不做联机。  
> 配套：[ROADMAP.md](ROADMAP.md)（阶段 A–E）· [ARCHITECTURE.md](ARCHITECTURE.md) · [HUD.md](HUD.md)  
> 最后更新：2026-08-05

---

## 0. 现状锚点（写代码前先对齐）

| 已有 | 位置 | 备注 |
|------|------|------|
| 游戏壳 + Echo Isles | `game/scenes/game_main.tscn` | F6 跑当前场景 |
| Melee 开局 | `melee_bootstrap.gd` + `GameSession` + `PlayerStock` | 主城/农民/金木/人口已有 |
| 选中 / 移动 / Stop | `UnitSelector` + `PathQuery` + `UnitNavigator` | 阶段 D 够用 |
| 资源 HUD | `GameHud.set_resources` / `bind_stock` | 金木人口可刷 |
| 命令格占位 | `GameHud.command_pressed` | 主城已有调试标签 |
| 建造判定雏形 | `unit_placement_rules.gd`（编辑器侧） | 游戏侧需抽/复用 |
| 数值权威 | `UnitBalanceDef` / `UnitDataDef` / `UnitUiDef` / `UnitAbilitiesDef` | 造价、人口、技能表 |
| 金矿类型 | `ngol`（Bootstrap 已识别） | 地图上已有金矿实体 |

**明确缺口（本竖切要补）：** 单位命令状态机、采集、建造队列、训练队列、科技树/需求、防御姿态、技能施放。

---

## 1. 竖切总览

```text
F0  命令与单位运行时骨架     Order / 队列 / Session 单位权威
F1  采集金币 + 采集木材      农民 ↔ 金矿 / 树木
F2  建造祭坛、农场、兵营     农民建造 + 占位 + 完工
F3  召唤大法师               祭坛训练英雄
F4  训练步兵                 兵营产 hfoo
F5  建造伐木场               木材回收点（效率/路径）
F6  建造铁匠铺 → 解锁火枪手  需求建筑 + 训练 hrif
F7  主城升级                 htow → hkee（本竖切到 Keep 即可）
F8  研究顶盾科技             Barracks 研究 Rhde
F9  步兵切换顶盾             Adef 开/关
F10 大法师技能               先原生子集，再评估 AbilitySystem 插件
```

编号即推荐实现顺序；**F0 是 F1–F10 的前置公共基建**，不要跳过。

游玩验收剧本（人工点一遍）：

1. 开局 → 农民右键金矿开始采矿，金增加  
2. 农民右键树木开始伐木，木增加  
3. 造 Farm → 人口上限涨；造 Altar / Barracks  
4. 祭坛训出 Archmage  
5. 兵营训出 Footman  
6. 造 Lumber Mill；伐木仍可交回（或效率可见差异）  
7. 造 Blacksmith 后兵营出现 Rifleman  
8. 主城升 Keep  
9. 兵营研究 Defend；步兵可切换顶盾  
10. 大法师能放至少 1 个主动技能（建议先 Water Elemental 或 Blizzard）

---

## 2. 人族 ID 速查（本竖切锁定）

| 用途 | typeId | 说明 |
|------|--------|------|
| 主城 / Keep | `htow` / `hkee` | 升级链；Castle `hcas` 本竖切可选后置 |
| 农民 | `hpea` | 采集、建造 |
| 祭坛 | `halt` | 训英雄 |
| 农场 | `hhou` | +食物 |
| 兵营 | `hbar` | 训兵 + 研究顶盾 |
| 伐木场 | `hlum` | 木材交接点 |
| 铁匠铺 | `hbla` | 解锁火枪手（建筑需求） |
| 步兵 | `hfoo` | 顶盾载体 |
| 火枪手 | `hrif` | 需 Barracks + Blacksmith |
| 大法师 | `hamg` | 英雄 |
| 金矿 | `ngol` | 中立可采集 |
| 顶盾科技 | `Rhde` | UpgradeData |
| 顶盾技能 | `Adef` | 步兵姿态 |
| 采集金/木相关 | `Ahar` 等（以 UnitAbilities / AbilityData 为准） | 农民默认技能 |

造价、时间、人口一律读 **`UnitBalanceDef` / `UpgradeDataDef`**，禁止在逻辑里写死 80 金之类常量（Melee 开局资源除外，已在 `PlayerStock`）。

---

## 3. F0 · 命令与单位运行时骨架（前置）

### 目标

所有玩法命令走同一管道，避免每个功能在 `GameDirector` 里堆 `if`。

### 建议模块

```text
game/scripts/
├── session/
│   ├── game_session.gd          # 已有：玩家、stock
│   ├── player_stock.gd          # 已有
│   └── runtime_unit.gd          # 新增：运行时单位权威（id/type/owner/hp/orders…）
└── logic/
    ├── command/
    │   ├── order.gd             # 命令枚举/结构：Move/Stop/Harvest/Build/Train/Research/Ability…
    │   ├── order_queue.gd       # 当前命令 + 可选队列
    │   └── command_router.gd    # 输入/HUD → 合法 Order → 派发
    ├── economy/
    │   └── (F1) harvest_*.gd
    ├── construction/
    │   └── (F2) build_*.gd
    ├── production/
    │   └── (F3–F4) train_*.gd
    ├── tech/
    │   └── (F7–F8) upgrade_*.gd
    └── ability/
        └── (F9–F10) …
```

### 必须定的语义

| 项 | 决策 |
|----|------|
| 单位权威 | `RuntimeUnit`（Session）为主；Present 节点只同步姿态/动画 |
| 右键智能命令 | 对金矿/树/地面/敌我：先做**最小智能**（金矿→HarvestGold，树→HarvestLumber，空地→Move） |
| 建筑占位 | 建造中写入 pathTex；完工后保持；取消需回滚脚印 |
| 进度条 | HUD Info 区显示「建造中/训练中/研究中」百分比即可 |

### 验收

- 选中农民右键地面仍移动；右键金矿发出 `HarvestGold`（即使采集未完成，命令已入队）  
- Director 不再直接解析所有玩法分支（只做输入 → Router）

---

## 4. 分步细化（F1–F10）

### F1 · 采集金币、采集木材

**玩法**

- 农民对 `ngol`：走近 → 进入采矿周期 → 负金 → 回最近己方主城（`htow/hkee/hcas`）交货 → 金入 `PlayerStock` → 自动返回矿  
- 农民对可伐树木（装饰/可破坏树）：伐木周期 → 负木 → 回最近 **Town Hall 或 Lumber Mill** 交货 → 木入库存 → 自动返回树  

**实现要点**

| 层 | 做什么 |
|----|--------|
| Data/Catalog | 金矿剩余量（可先无限或固定 12500）；树用 doodad/destructable 标记可伐 |
| Logic | `HarvestController`：状态机 `MoveToResource → Gather → MoveToDropoff → Deposit` |
| Present | 负资源模型/动画可后置；先改库存 + HUD |
| Session | `PlayerStock.add_gold/add_lumber` |

**简化（允许）**

- 第一版：金矿无限；树无限（点一下树即可循环）  
- 交货建筑搜索：距离最近、同玩家、类型匹配  

**验收**

- 5 农民挂机采矿，金持续增加且 HUD 同步  
- 伐木同理；农民被移动命令打断后可重新右键恢复  

**依赖**：F0

---

### F2 · 建造祭坛、农场、兵营

**玩法**

- 选中农民 → 命令卡选建筑（或临时快捷键）→ 进入放置预览 → 左键确认  
- 合法性：金钱木材、pathing、与己方建筑间距（复用/移植 `unit_placement_rules`）  
- 农民走去工地 → 建造计时（`UnitBalanceDef.bldtm`）→ 完工刷建筑、扣资源在**下单时或开工时**（对齐 WC3：下单扣费）  
- Farm 完工：`PlayerStock.add_food_cap`（读建筑 `fmade`）

**本步建筑集（锁死）**

| 建筑 | id | 为何先做 |
|------|-----|----------|
| 农场 | `hhou` | 人口门槛，否则无法训兵/英雄 |
| 祭坛 | `halt` | F3 |
| 兵营 | `hbar` | F4 |

**验收**

- 能造出三座建筑；人口随 Farm 增加；pathing 脚印正确；取消建造退款（至少 P1）

**依赖**：F0；建议 F1 可并行，但验收剧本按游玩顺序

---

### F3 · 召唤英雄（大法师）

**玩法**

- 选中 `halt` → 训练 `hamg`  
- 条件：金木、人口（英雄 `fused`）、祭坛空闲、**每位玩家限 1 英雄**（Melee 简化：先限 1）  
- 训练时间读 Balance；完成后祭坛旁刷出英雄并选中  

**验收**

- 祭坛可训出一只 `hamg`；资源/人口正确；训练中命令卡显示进度  

**依赖**：F2（有祭坛 + 足够 Farm）

---

### F4 · 训练士兵（步兵）

**玩法**

- 选中 `hbar` → 训练 `hfoo`  
- 队列：至少支持长度 1（P0）；长度 ≥3 为 P1  
- 刷兵位置：兵营 rally 点（P0 可固定建筑前方一格；P1 右键设 rally）

**验收**

- 连续训出 ≥3 名步兵；人口满时无法开训并有提示  

**依赖**：F2

---

### F5 · 建造伐木场，收集木材

**玩法**

- 建造 `hlum`（规则同 F2）  
- 伐木交货优先：有 Mill 时优先最近 Mill，否则 Town Hall  
- P1：Mill 提供视野/效率加成可后置；本步以**路径更短、逻辑正确**为主  

**验收**

- 造好 Mill 后，负木农民会改去 Mill 交货  

**依赖**：F1 + F2 建造管线

---

### F6 · 建造铁匠铺，解锁火枪手

**玩法**

- 建造 `hbla`  
- **解锁规则（对齐经典）：** 玩家拥有完成的 Barracks + Blacksmith 时，兵营命令卡出现 `hrif`  
- 不在本步做武器/护甲升级（`Rhme`/`Rhar` 等后置）

**验收**

- 无铁匠铺时不能训火枪手；有铁匠铺后可训，造价/时间正确  

**依赖**：F2 建造 + F4 训练框架

---

### F7 · 主城升级

**玩法**

- 选中 `htow` → 升级为 `hkee`（读升级时间与费用；可用「训练式」进度挂在建筑上）  
- 升级中：主城仍可作为交货点（简化允许）  
- 表现：模型替换 `htow→hkee`；队色/uberSplat 保持  

**本竖切范围**

- P0：`htow → hkee`  
- P1：`hkee → hcas`（可另开迭代）

**验收**

- 金木足够时升到 Keep；单位 typeId 与 Catalog/模型一致  

**依赖**：F2（有主城）；建议在 F3–F4 之后做，符合游玩节奏

---

### F8 · 研究士兵顶盾科技

**玩法**

- 选中 `hbar` → 研究 `Rhde`（Defend）  
- 费用/时间读 `UpgradeDataDef`  
- 写入 `PlayerStock` 或 `Session.tech_flags`：`player.has_upgrade("Rhde")`  

**验收**

- 研究完成后全图己方步兵解锁顶盾命令；重复研究不可用  

**依赖**：F4（有兵营 + 步兵）

---

### F9 · 士兵切换顶盾状态

**玩法**

- 已研究 `Rhde` 的 `hfoo`：命令卡「顶盾」开关  
- 开启：移速降低、防御姿态（数值可读 Ability/Upgrade；P0 可先改移速倍率 + 状态旗）  
- 移动/攻击命令是否自动取消顶盾：P0 跟随 WC3（Defend 下可移动但慢）  

**验收**

- 开关切换有反馈（动画可后置，先状态 + 移速）；未研究无此命令  

**依赖**：F8

---

### F10 · 大法师技能（含 AbilitySystem 评估）

**技能子集（建议顺序）**

| 优先级 | 技能 | 说明 |
|--------|------|------|
| P0 | 召唤水元素 | 目标点召唤可控单位，持续时间结束移除 |
| P0 | 暴风雪 | 目标区域 DOT（可先简化伤害数字） |
| P1 | 辉煌光环 | 光环回蓝（依赖魔法值系统） |
| P2 | 群体传送 | 依赖魔法免疫/传送规则，最后做 |

**魔法值**

- 英雄 `mana` 从 `UnitBalanceDef` 读；施放扣蓝；P0 可用简单回复（每秒固定或光环）

#### AbilitySystem 插件策略

```text
决策门（做完 P0 原生施放后再选）：
  A. 继续自研 thin Ability 层（Order + Cooldown + Effect）
  B. 接入 Godot AbilitySystem 类插件，Def 技能 ID → 插件 Ability
```

| 若选 B，必须满足 | 说明 |
|------------------|------|
| 不污染 `scripts/map/` | 插件只进 `game/` 或 `addons/` |
| 技能 ID 仍来自 WC3 | `AbilityDataDef` / `UnitAbilitiesDef` 为数据源 |
| 可单测 Effect | 伤害、召唤、光环与 Present 解耦 |
| 迁移成本可控 | 先只迁大法师 1–2 个技能，步兵顶盾可仍走原生状态 |

**建议**：F10 先用**原生 AbilityRunner** 跑通 1 个主动技能；并行做 1～2 天插件 spike（文档结论写入本节「决策记录」）。确认插件能吃四字符 ID 与目标选取后再迁。

**验收**

- 大法师可学/可放至少 1 个主动技；有 CD 与扣蓝；水元素可被选中移动（若选召唤）  

**依赖**：F3；建议 F9 完成后或并行 spike

---

## 5. 跨步公共能力（穿插交付）

这些不是独立「游玩步骤」，但会反复用到：

| 能力 | 首次需要 | 说明 |
|------|----------|------|
| 智能右键 | F1 | 矿/树/地面 |
| 建造预览幽灵 | F2 | 绿/红合法性 |
| 训练/研究队列 UI | F3 | 命令卡 + Info 进度 |
| 需求检查（建筑/科技） | F6/F8 | `Requirements` 查询 |
| Rally point | F4 P1 | 右键设集结点 |
| 死亡与尸体 | 不阻塞竖切 | 可后置 |
| 攻击与伤害 | F10 前可无 | 暴风雪可先「只特效+假数字」 |

---

## 6. 非目标（本竖切不做）

- 兽族/暗夜/不死对称科技  
- 完整人族科技树（坐骑、牧师、骑士、炮厂等）  
- 真正的树木耗尽/金矿挖空经济（可后续加）  
- 完整战斗 AI、防守反击  
- 触发器 VM（仍见 ROADMAP 阶段 E）  
- 联机 / 录像 / 物体编辑器  

---

## 7. 建议迭代切分（可多次 PR）

| 迭代 | 交付 | 约当步骤 |
|------|------|----------|
| G1 | Order 骨架 + 智能右键空壳 | F0 |
| G2 | 采矿 + 伐木 + 交货 | F1 |
| G3 | 建造三件套 + Farm 人口 | F2 |
| G4 | 祭坛训英雄 + 兵营训步兵 | F3–F4 |
| G5 | Mill + Blacksmith + 火枪手 | F5–F6 |
| G6 | Keep 升级 + Defend 研究/切换 | F7–F9 |
| G7 | 大法师技能 P0 + AbilitySystem 评估结论 | F10 |

每迭代验收以 §1 剧本对应条目为准；合并前 F6 跑 `game_main` 不破现有移动。

---

## 8. 代码落点（目标树）

在现有 `game/scripts/` 上扩展，**不要**把玩法写进 `Map*Layer`：

```text
game/scripts/logic/
  command/          # Order、Router
  economy/          # Harvest、Dropoff
  construction/     # BuildOrder、Placement（可调用 map/logic 纯函数）
  production/       # TrainQueue
  tech/             # Upgrade research
  ability/          # 原生技能；插件适配器也放这
```

数据继续：

- 造价/时间/人口 → `UnitBalanceDef` / `UpgradeDataDef`  
- 技能列表 → `UnitAbilitiesDef` + `AbilityDataDef`  
- 模型/命令卡艺术 → `UnitUiDef` + 既有 Func/Strings（Catalog）  

---

## 9. 决策记录

| 日期 | 决策 |
|------|------|
| 2026-08-05 | 玩法按游玩顺序推进；本竖切锁人族最小集（见 §2 ID 表） |
| 2026-08-05 | F0 命令骨架为硬前置；Director 只做输入路由 |
| 2026-08-05 | 火枪手解锁 = 建筑需求（Barracks+Blacksmith），本竖切不做铁匠铺武器升级 |
| 2026-08-05 | 主城升级本竖切 P0 只到 Keep |
| 2026-08-05 | 大法师技能先原生 P0，再评估 AbilitySystem 插件（禁止未评估就全盘接入） |
