# 人族对战 · 游玩竖切（Gameplay Vertical）

> 目标：按**真实开局游玩顺序**，在 Echo Isles 上跑通「采矿伐木 → 基建 → 英雄 → 兵营产兵 → 科技分支 → 大法师技能」闭环。  
> 范围：**仅人族 Melee 最小集**；不做完整科技树、不做多族、不做联机。  
> 配套：[ROADMAP.md](ROADMAP.md)（阶段 A–E）· [ARCHITECTURE.md](ARCHITECTURE.md) · [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) · [HUD.md](HUD.md)  
> 最后更新：2026-09-05  
> **当前进度：F0–F10、C0–C3、F8–F9 已接线；技能重构 Phase A–E ✅。**  
> **下一步不在本文扩技能** → [../../roadmap/NEXT.md](../../roadmap/NEXT.md) **N1**（U3 手测 · 英雄复活 · Keep · 铁匠升级 · 生产队列 HUD）。

---

## 0. 现状锚点（写代码前先对齐）

| 已有 | 位置 | 备注 |
|------|------|------|
| 游戏壳 + Echo Isles | `game/scenes/game_main.tscn` | F6 跑当前场景 |
| Melee 开局 | `melee_bootstrap.gd` + `GameSession` + `PlayerStock` | 主城/农民/金木/人口已有 |
| 选中 / 移动 / Stop | `UnitSelector` + `PathQuery` + `UnitNavigator` | 阶段 D 够用 |
| 命令层 | `CommandRouter` + `UnitOrder` + `SmartTarget` | 右键智能按能力匹配 |
| 采集金/木 | `HarvestController` + `CarrySlot` + `TreeRegistry` | F1 闭环；智能送回主城 / Mill |
| 建造 | BuildSite + 人族 Strategy | `hhou/halt/hbar/hlum/hbla` |
| 训练 + 集结 | `TrainQueue` + `BuildingRally` | 祭坛 `Hamg`；兵营 `hfoo`/`hrif` |
| Requires | `UnitRequiresCatalog` + `TechPresence` | 按钮置灰 +「需要：…」 |
| 资源 HUD | `GameHud.set_resources` / `bind_stock` | 金木人口可刷 |
| 命令格 | `CommandCard` | 建造二级面板 / 训练格 |
| 数值权威 | `UnitBalanceDef` / `UnitWeaponsDef` / … | 造价、人口、武器表（战斗待接） |

**下一步缺口：** 见 [NEXT.md N1](../../roadmap/NEXT.md)（可玩闭环，非新技能）。  
**Present 并行：** 野怪/小动物 Stand 藏尸体 Geoset（`geosetvis` + `snap_stand_geoset_visibility`，见 §5）。

---

## 1. 竖切总览

```text
F0  命令与单位运行时骨架     ✅ Order / Smart / Router
F1  采集金币 + 采集木材      ✅ 农民 ↔ 金矿 / 树木 / 送回
F2  建造祭坛、农场、兵营     ✅
F3  召唤大法师               ✅ 祭坛训 Hamg（英雄上限 1）
F4  训练步兵                 ✅ 兵营产 hfoo
F5  建造伐木场               ✅ hlum；收木
F6  建造铁匠铺 → 解锁火枪手  ✅ Requires + hrif（铁匠科技后置）
─── 战斗插入（优先于科技/技能）───
C0  攻击命令 + 自动接敌      ✅
C1  攻击移动（Attack-Move）  ✅
C2  射程 / 冷却 / 面向 / 弹道壳  ✅
C3  攻防类型 + 伤害公式（读 UnitWeapons / UnitBalance）  ✅
F7  主城升级                 后置 htow → hkee
F8  研究顶盾科技             Barracks 研究 Rhde           ✅
F9  步兵切换顶盾             Adef 开/关                   ✅
F10 大法师技能               ✅ 原生子集 + 山丘 + P0 支援；重构 A–E
─── 可玩闭环（NEXT N1）───
     U3 / 英雄复活 / Keep / 铁匠升级 / 生产队列 HUD  ← 当前主线
```

编号即推荐实现顺序；**F10 已完成**。铁匠铺武器/护甲升级与 Keep 收入 [NEXT N1](../../roadmap/NEXT.md)。

游玩验收剧本（人工点一遍）：

1. 开局 → 农民右键金矿开始采矿，金增加  
2. 农民右键树木开始伐木，木增加  
3. 造 Farm → 人口上限涨；造 Altar / Barracks  
4. 祭坛训出 Archmage  
5. 兵营训出 Footman  
6. 造 Lumber Mill；伐木仍可交回（或效率可见差异）  
7. 造 Blacksmith 后兵营出现 Rifleman  
8. **攻击 / 攻移：步兵可攻击野怪或敌单位，按射程与伤害公式扣血致死**  
9. 主城升 Keep（后置可跳）  
10. 兵营研究 Defend；步兵可切换顶盾  
11. 大法师能放至少 1 个主动技能（建议先 Water Elemental 或 Blizzard）

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
| 大法师 | `Hamg` | 英雄（UnitFunc/Balance 主键大小写敏感） |
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
    │   ├── unit_order.gd        # Move/Stop/Harvest/Return…
    │   ├── smart_target.gd      # 右键交互目标（Ground/Mine/Tree/Dropoff）
    │   ├── order_queue.gd       # 当前命令 + 可选队列
    │   └── command_router.gd    # issue_smart / 具体 Order 派发
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
| 右键智能命令 | Director 识别 `SmartTarget` → `CommandRouter.issue_smart`：全体广播，按单位能力匹配（能采→Harvest，能交→Return，否则→Move）。远期加 Attack 等 Kind / Capability，不在 Director 按兵种分支 |
| 建筑占位 | 建造中写入 pathTex；完工后保持；取消需回滚脚印 |
| 进度条 | HUD Info 区显示「建造中/训练中/研究中」百分比即可 |

### 验收

- 选中农民右键地面仍移动；右键金矿发出 `HarvestGold`（即使采集未完成，命令已入队）  
- Director 不再直接解析所有玩法分支（只做输入 → Router）

---

## 4. 分步细化（F1–F10）

### F1 · 采集金币、采集木材

**玩法**

- 农民对 `ngol`：走近 → **排队候矿** → 进入采矿周期 → 负金 → 回最近己方主城交货 → 金入 `PlayerStock` → 自动返回矿  
- 农民对可伐树木（装饰/可破坏树）：伐木周期 → 负木 → 回最近 **Town Hall 或 Lumber Mill** 交货 → 木入库存 → 自动返回树  

**实现要点**

| 层 | 做什么 |
|----|--------|
| Data/Catalog | 金矿剩余量：`unit_data.goldAmount` 或 `Agld.DataA1`（默认 12500） |
| Logic | `GoldMineRuntime` + `HarvestController` + `CarrySlot`（资源 id+数量；采到异类时丢弃旧负重） |
| Present | 负金/负木 geoset；进矿隐藏 |
| Session | `PlayerStock.add_gold/add_lumber`；交货走 `ReceiveResources` |

换采集目标：**不**因负异类资源而先交货；出矿/砍中第一击时 `CarrySlot` 整槽替换。  
送回：面板/热键「交付」，或负重单位**右键**己方主城/伐木场（`SmartTarget.DROPOFF`；无负重者降级为移动）。

伐木 / 树 Present / 选中环专项设计（落地前必读）：

- [TREE_INTERACT.md](TREE_INTERACT.md) — MultiMesh promote、`apply_damage` 统一入口、防闪烁  
- [SELECTION_RINGS.md](SELECTION_RINGS.md) — 己方绿环 / 中立金矿·树黄环  

**简化（允许）**

- 金矿可先无限或读地图储量  
- 交货建筑搜索：距离最近、同玩家、类型匹配、**已完工**  
- 伐木场优先交货见 F5；树闲置 demote 回 MM 后置  

**验收**

- 5 农民挂同一矿：队外「连连看」，**同时仅 1 人进矿**；金持续增加且 HUD 同步  
- 移动/停止打断后可重新右键恢复；打断释放矿槽  

**依赖**：F0

---

### F1 附：金矿 / 采金语义（WC3 对齐备忘）

> 人族竖切只实现 **普通中立金矿 `ngol` + 农民进出矿**。闹鬼/缠绕是另一套建筑与槽位规则，本竖切不实现。

| 项 | WC3 语义 | 本项目落地 |
|----|----------|------------|
| 单位 | `ngol` + 技能 `Agld` | `GoldMineRuntime` 挂在矿节点上 |
| 默认储量 | `Agld.DataA1` = **12500**；地图可覆盖 `goldAmount` | 优先读实例，否则读 Agld |
| 同时进矿 | 普通矿 **1** 人（`Agld.DataB1≈1`） | `max_inside`；队外 FIFO 只定进矿权 |
| 「5 连连看」 | 主城贴矿时约 **5** 农民效率最高（约 **1 人在矿内、4 人在路上**），不是队外站成一列 | 车道散开 + ~1.3s 进矿时长形成传送带节奏 |
| 进矿时长 | 实机观感约 **1.3s**（非 `Ahar.Dur1`） | `GoldMineRuntime.dwell_sec`（默认 1.3） |
| 单次负金 | `Ahar.DataC1` = **10** | `HarvestController` 读 Ahar |
| 伐木每击 | `DataA1=1` 伤树兼得木；`DataB1=10` 容量；`Dur1=1.1` 每击间隔 | 攒满容量再交货 |
| `Ahar.Dur1=1.1` | **伐木每击间隔**，不是进矿 | 勿混用 |
| 矿口散开 | 多选下令时自然停在矿口附近不同点 | `entrance_slot_wc3(lane)` 仅候位 |
| 采矿寻路 | 出矿/交货/入矿找空闲落点，自然错开 | 朝主城贴矿采样空位；approach 避开已占点；幽灵模式互不挡 |
| 归属 | `ngol` 保持中立；任何玩家都可采 | P0 不锁矿；软宣称可后置 |
| 闹鬼金矿 | `ugol` 等，多侍僧站桩采（≠进出矿） | 远期，另设 `max_inside`/无排队 |
| 缠绕金矿 | 暗夜生命之树缠绕，小精灵站桩 | 远期 |
| 矿空 | 储量 0 播 Death 塌陷，播完移除 | `depleted` → Present `BuildingVisual.play_death`；农民停采 |
| 低储量提示 | ≤1500 警告 | P1 HUD |
| 自动回城/回矿 | 属于 **Harvest 订单 AI**，非硬编码坐标 | 交货点由 `ReceiveResources` 查询 |

**排队状态机（人族）**

```text
MOVE_TO_MINE →（首趟：车道候位散开 / 循环：统一出矿门）enqueue
  ├─ try_enter 成功 → IN_MINE（仅隐藏，不改坐标，dwell≈1.3s）
  │     → 瞬移到统一出矿点并显示 → MOVE_TO_DROPOFF（统一交货点）→ 回统一出矿门
  └─ 满员 → WAIT_IN_QUEUE（站本车道 entrance_slot）→ slot_available → 队首进矿
```

**「5 连连看」口径**

- 效率最优：约 1 人在矿内采、其余在路上往返；进矿短、路程长时形成稳定间距。
- 不是：5 人在矿外排成一列长时间站岗。

**WC3 订单语义（对齐参考）**

- `Harvest` 是**持续订单**：记住目标矿；交金后自动 `resume` 回同一矿，不因一次寻路失败而取消。
- 回城：找最近可接收建筑（pathing 意义下的近，而非纯欧氏）；从矿的默认出口方向出发更合理。
- 本项目：`HarvestController` 状态机承担订单 AI；交金后先弹到可走格再回矿；途中 path fail 重试而非立刻 abort。

**归属（设计口径）**

- **硬归属**：仅闹鬼/缠绕等「改造后的矿建筑」属玩家。  
- **软宣称**：普通矿中立；P1 可做「最近己方主城势力」提示，不阻止敌方来采。  

### F2 · 建造祭坛、农场、兵营

> **当前进度：人族竖切可玩**（Catalog / Placement / BuildSite / CommandCard 已接线；2026-04-14 修 Ghost `_get_ground_hit` arity）  
> 分支：`feature/building-system`（已与 `master` 同步）  
> **设计契约（必读）：** 四族建造非对称 → 用 `ConstructionProfile` + Strategy，F2 只实现人族；**禁止**把「工人隐藏」当默认（那是兽/灵）。  
> 状态与缺口详见 [BUILD_SYSTEM.md](BUILD_SYSTEM.md) §13。

**玩法**

- 选中农民 → 命令卡选建筑（或临时快捷键）→ 进入放置预览 → 左键确认  
- 合法性：金钱木材、pathing、与己方建筑间距（复用/移植 `unit_placement_rules`）  
- 农民走去工地 → **人族保持可见施工**（可后续多农民 Repair 加速）→ 计时/HP 进度（`bldtm`）→ 完工刷建筑  
- 扣资源在**下单时**（对齐 WC3；一单只扣一次，不按选中农民人数倍扣）  
- Farm 完工：`PlayerStock.add_food_cap`（读建筑 `fmade`）

**本步建筑集（锁死）**

| 建筑 | id | 为何先做 |
|------|-----|----------|
| 农场 | `hhou` | 人口门槛，否则无法训兵/英雄 |
| 祭坛 | `halt` | F3 |
| 兵营 | `hbar` | F4 |

**实现子步（7 commit · 1 关注点 / 1 commit）**

| # | 关注点 | 关键产物 | 状态 |
|---|--------|----------|------|
| **F2-1** | docs: F2 计划 + [BUILD_SYSTEM.md](BUILD_SYSTEM.md) 四族契约 | 本节 + BUILD_SYSTEM + ROADMAP | ✅ |
| **F2-2** | data: BuildingCatalog + ConstructionProfile（人族） | `BuildingCatalog` + `construction_profile_catalog.gd` | ✅ |
| **F2-3** | logic: BuildSite 共享真相 + HumanStrategy + 单次扣费 | `construction/*` + Router 映射 `BuildOrder` | ✅ |
| **F2-4** | present: PlacementGhost（绿/红合法性预览） | `build_placement_ghost.gd` | ✅ |
| **F2-5** | logic/present: 工地进度（人族可见施工；非隐藏农民） | `BuildSite` + F2-C 多工加速；进度条可再抛光 | ✅ |
| **F2-6** | logic: TrainQueue 最小（兵营训步兵 1 队列 + 出门） | `train_queue.gd`（延伸 F3/F4） | ⏳ |
| **F2-7** | test: selftest 覆盖 Profile 语义 | `selftest_f2_build_system.gd`（Profile/Builds/多工） | ✅ |

**代码落点（不破架构）**

```text
game/scripts/
├── logic/
│   ├── construction/         # F2 关注点（契约见 BUILD_SYSTEM.md）
│   │   ├── build_site.gd           # 工地共享真相（进度/builders/退款）
│   │   ├── build_controller.gd     # 工人侧：走位 / join
│   │   ├── placement_rules.gd      # 组合谓词（pathing + requirePlace）
│   │   ├── build_order.gd
│   │   └── strategies/             # Human 必做；兽灵亡 stub
│   └── production/
│       └── train_queue.gd
├── data/
│   ├── building_catalog.gd
│   └── construction_profile_catalog.gd
├── presentation/
│   ├── placement_ghost.gd
│   └── build_progress_bar.gd
└── session/
    └── player_stock.gd
```

**复用与边界**

- 四族机制与数据钩子：**[BUILD_SYSTEM.md](BUILD_SYSTEM.md)**（`AHbu`/`Builds=`/`requirePlace`）
- `scripts/shared/selection/`：框选只己方（已落）+ 命令卡入口（已落）
- `scripts/map/presentation/layers/map_unit_layer.gd`：建筑放置走 unit layer API（**不**直接 `add_child` 到 MapRoot）
- `unit_placement_rules.gd`（编辑器侧）：游戏侧 `placement_rules.gd` 共享纯规则，不依赖 Document
- WC3 ID 表固定 3 个：`hhou` / `halt` / `hbar`（本步锁死；菜单数据源目标仍是 `Builds=`，再过滤子集）

**验收剧本（人工 · 人族语义）**

1. 开局后选农民 → 命令卡出现「建 Farm/Altar/Barracks」（资源不足 disabled）
2. 点 Farm → ghost 绿/红随合法性变化
3. 左键确认：**只扣一次**资源（hhou 金/木读 Balance）；农民走向工地
4. 施工期间农民**保持可见**（Work/等效修理）；**不是**隐身进建筑
5. 完工刷 Farm；人口 +`fmade`；农民释放可再下令
6. （P1）第二农民加入同一工地 → 进度加快且不二次扣费
7. 同样流程造 Altar / Barracks；Barracks 训 Footman（F2-6）
8. 取消：工地消失、按 Profile 退款、农民恢复 IDLE/可见

**下一步：** 实机验收 Ghost→完工；第二农民 join UI；TrainQueue 并入 F3/F4。兽/灵/亡与 blight 见 BUILD_SYSTEM §13.5。

---

### F3 · 召唤英雄（大法师）

**玩法**

- 选中 `halt` → 训练 `Hamg`  
- 条件：金木、人口（英雄 `fused`）、祭坛空闲、**每位玩家限 1 英雄**（Melee 简化：先限 1）  
- 训练时间读 Balance；完成后祭坛旁刷出英雄并选中  

**验收**

- 祭坛可训出一只 `Hamg`；资源/人口正确；训练中命令卡显示进度  

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
- 伐木交货优先：有 **已完工** Mill 时优先最近 Mill，否则 Town Hall  
- 未完工 Mill **不能**收木（与 TechPresence 一致：半成品不提供能力）  
- P1：Mill 提供视野/效率加成可后置；本步以**路径更短、逻辑正确**为主  

**验收**

- 造好 Mill 后，负木农民会改去 Mill 交货  
- 建造中的 Mill 交货失败/不入账；农民改去主城  

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

### C0–C3 · 战斗框架（插入 · 优先于 F8）

> **已完成。** 顶盾与技能都依赖「能打出真实伤害」；战斗框架已接线。  
> **设计契约（落地前必读）：** [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) — Attack 订单 · `DamagePipeline` · 攻防表 · 分 commit 路线 · 与 `CombatSteering`/树伤边界。

#### 摘要

| 步 | 内容 | 验收一句话 |
|----|------|------------|
| C0 | Attack 命令 + 追击 + 近战出手 | 步兵右键野怪能打死 |
| C1 | Attack-Move + `acquire` | A 键点地途经会打，Move 不惹怪 |
| C2 | 射程 / 冷却 / 面向 / 弹道壳 | ✅ weapTp 分支 + Present 壳；hrif 远程不连发 |
| C3 | 攻防表 + 骰伤 + 死亡离场 | ✅ 公式可单测；Death→尸体停留后移除；清选中 |

**代码落点**：`game/scripts/logic/combat/`（见 COMBAT_SYSTEM §8）  
**依赖**：F0；建议已有 `hfoo`/`hrif`（F4/F6）

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
- 费用/时间读 `UpgradeDataDef`（150 金 / 100 木 / 45 秒）  
- 写入 `PlayerStock.has_upgrade("Rhde")`（玩家级，不是单兵旗）  

**验收**

- 步兵命令卡**默认就有**顶盾格，未研究时置灰（DISBTN +「需要：…」）  
- 研究完成后：兵营研究按钮**消失**；场上已有 `hfoo` 与之后新训的 `hfoo` 顶盾格一并点亮  

**落地**：兵营 `research:Rhde` 与训兵共用 `TrainQueue`；完工不刷单位。

**依赖**：F4（有兵营 + 步兵）；C0–C3

---

### F9 · 士兵切换顶盾状态

**玩法**

- 已研究 `Rhde` 的 `hfoo`：命令卡顶盾开关（热键 D）  
- 开启：移速 × (1 − `Adef.DataC`)=70%；穿刺承受 `Adef.DataA`=30%；`UnitVisual` Stance.DEFEND  
- 图标切 `Unart`（BTNDefendStop）；可移动、可攻击（不自动取消顶盾）  

**验收**

- 开关有移速/姿态/图标反馈；未研究按钮在但点不了  

**依赖**：F8

---

### F10 · 大法师技能（含 AbilitySystem 评估）

**技能子集（建议顺序）**

| 优先级 | 技能 | 说明 | 状态 |
|--------|------|------|------|
| P0 | 召唤水元素 | 目标点召唤可控单位，持续时间结束移除 | ✅ |
| P0 | 暴风雪 | 目标区域引导 DOT | ✅ |
| P1 | 辉煌光环 | 光环回蓝 | ✅ |
| P2 | 群体传送 | 施法者周围友军传送到点目标 | ✅ |
| P0 | 山丘之王四技 | AHtb/AHtc/AHbh/AHav | ✅ |

详见 [ABILITY_SYSTEM.md](ABILITY_SYSTEM.md)。

**魔法值**

- 英雄 / 单位 `mana` 上限与出生量来自 `UnitBalanceDef`（英雄：INT×12，见 `UnitMana`）
- 施放扣蓝：`UnitMana.spend`
- **自然回复**：`UnitRegen`（`AbilityRuntimeRegistry.tick_all_units` 顺带 tick）
  - 蓝：`regenMana` + 英雄 INT×0.05（与 `regenType` 无关；光环等额外回复仍走 `UnitMana.regenerate`）
  - 血：`regenHP` + 英雄 STR×0.05；仅 `regenType=always`（`none` 不回；`blight` / `night` 待荒芜地与昼夜系统）
- 辉煌光环等技能回蓝叠加在自然回复之上

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
| 智能右键 | F1 ✅ | `SmartTarget` → `issue_smart`；矿/树/交货/地面 |
| 建造预览幽灵 | F2 | 绿/红合法性 |
| 训练/研究队列 UI | F3 | 命令卡 + Info 进度 |
| 需求检查（建筑/科技） | F6/F8 | `Requirements` 查询 |
| Rally point | F4 P1 | 右键设集结点 |
| 单位 Geoset 显隐 | Present 并行 | Stand 藏尸体；Death 显尸体（同树桩管线） |
| 死亡与尸体逻辑 | C3 后 | 扣血致死 → 清选中；Present 尸体 Geoset 已就绪 |
| 攻击与伤害 | **C0–C3（优先）** | Attack / Attack-Move；射程；`atkType`×`defType`；读 `UnitWeaponsDef` |

### 5.1 野怪 / 小动物尸体 Geoset（Present）

WC3 单位 MDX 常把**活体 + 尸体 + 武器变体**放在同一模型，用 GeosetAnim 在 Stand 隐藏无关片。Godot 丢蒙皮 scale 轨后须：

1. convert 写 `*.geosetvis.json`（Sequence 作用域 alpha）  
2. `MapModelCache` 注入 AnimationPlayer `Geoset_*:visible` 并 **Stand 定格**  
3. `MapUnitLayer` 放置非建筑时：`autoplay_stand` + `snap_stand_geoset_visibility`（禁止 `reveal_all`）

| 资产范围 | 说明 |
|----------|------|
| `Units/Critters/**` | 羊/猪/浣熊等；缺旁路时 `--models-only --force --include "Units/Critters/**"` |
| Echo Isles 常见 Creeps | Gnoll / Kobold / Murloc / Ogre / ForestTroll 等已补转示例 |
| 验收 | 开局野怪与小动物**无脚下尸体叠影**；播 Death 后尸体 Geoset 可见 |

不阻塞 F2；与建造管线可并行。

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

| 迭代 | 交付 | 约当步骤 | 状态 |
|------|------|----------|------|
| G1 | Order 骨架 + 智能右键 | F0 | ✅ |
| G2 | 采矿 + 伐木 + 交货 + CarrySlot | F1 | ✅ |
| G2.5 | 野怪/小动物 Stand 藏尸体 Geoset | Present | ✅ 代码+Echo 资产；其余 Creeps 按需补转 |
| G3 | 建造三件套 + Farm 人口 | F2 | ✅ |
| G4 | 祭坛训英雄 + 兵营训步兵 | F3–F4 | ✅ |
| G5 | Mill + Blacksmith + 火枪手 Requires | F5–F6 | ✅ |
| **G5.5** | **战斗：Attack / Attack-Move / 射程 / 攻防伤害** | **C0–C3** | ✅ |
| G6 | Defend 研究 | F8 | ✅ |
| G6.5 | Defend 开关 | F9 | ✅ |
| G7 | 大法师技能 P0 + AbilitySystem 评估结论 | F10 | ← 下一步 |

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
  tech/             # Upgrade research + TechPresence
  combat/           # AttackOrder、DamageFormula、Acquire（C0–C3）
  ability/          # 原生技能；插件适配器也放这
```

数据继续：

- 造价/时间/人口 → `UnitBalanceDef` / `UpgradeDataDef`  
- 武器/射程/伤害骰 → `UnitWeaponsDef`；护甲类型 → `UnitBalanceDef.defType`  
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
| 2026-08-07 | 普通金矿同时进矿 1 人 + FIFO 进矿权；「5 连连看」= 效率最优（约 1 矿内 / 4 路上），非队外站列；进矿默认 1.3s（非 Ahar.Dur1）；闹鬼/缠绕后置 |
| 2026-08-07 | 固定运金走廊：端点+路点只算一次；采矿幽灵模式互不挡路；进矿只隐藏、出矿瞬移统一出口 |
| 2026-08-07 | 自动回城/回矿属 Harvest 订单 AI；交货点由 ReceiveResources 查询，非硬编码坐标 |
| 2026-08-08 | 右键智能：`SmartTarget` + `issue_smart`；混选时能采的采、不能的走目标点；完整 UnitCapability 后置 |
| 2026-08-09 | F0+F1 验收通过；玩法主线进 F2；野怪/小动物尸体 Geoset 走 geosetvis+Stand snap（与树桩同管线） |
| 2026-08-09 | F2 拆 7 commit（docs/data/logic×3/present/test）；锁 3 建筑 `hhou`/`halt`/`hbar`；开 `feature/building-system` 分支 |
| 2026-08-16 | F0–F6 竖切接线完成；下一步插入 **C0–C3 战斗框架**（攻击/攻移/射程/攻防伤害），再 F8 顶盾与 F10 技能 |
| 2026-08-17 | 战斗契约单列 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md)；实现按 C0-0～C3 分 commit，单位扣血唯一入口 `DamagePipeline` |
| 2026-08-18 | 尸体 Decay Flesh→Bone 按动画片长播放后移除；F8 兵营研究 `Rhde` 写入 `PlayerStock`；F9 顶盾开关（置灰→解锁、研究按钮消失、减速/姿态/Unart） |
| 2026-08-18 | 未完工建筑不能交货：`ReceiveResources.can_receive` 拒绝 `under_construction`（伐木场半成品不收木） |
| 2026-08-18 | 金矿踩空：`GoldMineRuntime.depleted` → Present 播 Death，结束后 `remove_unit_instance`；候矿农民停采 |
