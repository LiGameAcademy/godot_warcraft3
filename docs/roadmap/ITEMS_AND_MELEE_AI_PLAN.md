# 基于当前代码的下一阶段计划：道具系统与对战 AI

日期：2026-09-13。范围：当前工作区（含未提交改动），不是仅依据旧路线图。

## 1. 结论

项目已经具有相当完整的人族玩法基础，应从现有采集、建造、生产、英雄、技能和单位战斗逻辑上继续扩展。下一阶段主线确定为：

**道具最小闭环 → 多玩家命令与经济隔离 → 人族电脑经营和进攻 → 电脑使用道具与完整对局验收。**

推荐先做道具，是因为地图掉落数据、英雄与技能效果已有基础，能够较快让清野产生可用奖励。对战 AI 的主要前置工作是消除本地玩家耦合；它不依赖完整商店系统，可以在道具第一版之后直接启动。

本计划采用单机 Echo Isles、人族玩家对人族电脑的首版范围；这是建议范围，不是已实现事实。暂不把 Keep、全科技树或完整战争迷雾设为第一版的必需前置项。

## 2. 已核实的项目状态

以下按 [ITEM_SYSTEM.md](../design/game/ITEM_SYSTEM.md) 与 [MELEE_AI.md](../design/game/MELEE_AI.md) 的最新进度。「闭环」=代码、自测与端到端集成测试齐备；「部分」=核心已落地但某条验收未闭环；「缺失」=仓库内无对应实现。

### 道具系统（I0–I4）

| 段 | 当前 | 关键证据 |
|---|---|---|
| I0 ItemCatalog / ItemInstance / Inventory（六格） | **闭环** | `item_catalog.gd:18-42`、`item_instance.gd:14-22`、`inventory.gd:16-160` |
| I1 GroundItem / ItemService / Pickup / UI / 智能右键拾取 | **闭环** | `item_pickup_controller.gd:31-56`、`inventory_panel.gd:1-103`、`smart_handler_registry.gd:243-256` |
| I2 使用效果 / 装备护甲 / 死亡保留 / 复活恢复 / 共享冷却组 | **闭环** | `inventory.gd:99-134`、`hero_death_registry.gd:21-39`、`production_module.gd:144-160` |
| I3 死亡掉落 / 互斥组 / 全局表 / 随机码 / seed / 幂等 | **闭环** | `item_drop_table.gd:21-62`、`item_service.gd:65-73` |
| I4 商店 / 回城卷轴 / PowerUp 自动触发 | **缺失**（第二批，不阻塞主线）| 全仓零 `shop*.gd`、零 `purchase/cost_gold` |

### 对战 AI（A0–A4）

| 段 | 当前 | 关键证据 |
|---|---|---|
| A0 双玩家开局 + owner 隔离 + 命令入口校验 | **闭环** | `melee_bootstrap.gd:23-185`、`game_session.gd:4-40`、`command_router.gd:89-105`、`production_module.gd:32-70` |
| A1 经营 AI（工人 / 农场 / 兵营 / 祭坛 / 步兵 / 英雄） | **闭环** | `player_economy_ai.gd:33-203`（1Hz 决策、三档占位校验、首英雄预留五人口） |
| A2 军队调度 + 进攻 + 回防 + 撤退 | **闭环** | `player_army_ai.gd:3-86`（状态机、阈值 4、`%d:%d:%d` 一次发令不重置） |
| **A3 电脑英雄清野 + 拾取 + 使用道具** | **闭环** | `player_army_ai.gd` `_consider_pickup/_consider_use`；`ItemService.get_ground_items_in_radius` |
| A4 胜负结算 + 重开 | **闭环** | `melee_victory_rules.gd:1-41`、`production_module.gd:165-225`、`match_result_screen.gd` |

### 其它模块

| 模块 | 当前证据 | 对下一步的意义 |
|---|---|---|
| 开局与玩家库存 | `game_session.gd` owner→PlayerStock；`melee_bootstrap.gd` 双方各刷主城与工人 | 双玩家已就位，不再仅 local_player |
| 采集、建造 | `HarvestController`、`BuildController`、`BuildSite`、PlacementRules | AI 复用订单执行 |
| 训练与研究 | `ProductionModule` + `command_owner` 校验 | 已按 owner 隔离，不再依赖 Director |
| 生产队列 UI | `production_panel.gd:305` 暴露 `ProductionModule.queue_changed/progress_changed` | 已模块化 |
| 英雄复活 | `production_module.gd:165-225` + `HeroDeathRegistry` + `Inventory.restore` | 道具也已跨复活保留 |
| 单位战斗 AI | `UnitAI` Profile + ThreatTable + sticky + 切目标冷却；`TeamRegistry` 队伍 / 营地助攻 | 这是单位级战斗决策 |
| 技能与效果 | AbilityExecutor、EffectHeal、BuffQuery；道具 abilList 仅白名单 `AIhe/AIma/AIde` | 不能假设任意道具 abilList 已被支持 |
| 道具静态数据 | `ItemDef` 注册到 `Wc3DefStore` | 不需要新增表 |
| 地图道具数据 | `Wc3UnitPlacement` inventory / droppedItemSets / itemTablePtr；`ItemDropTable` 解析 randomItemTables | 已闭环到 `ItemService.on_unit_died` |
| 掉落提示 | `map_unit_layer.gd:647` droppedItemSets 提示环 | 已与 I3 联动（提示+真实掉落并行） |
| 玩家级 AI、结算 | `PlayerEconomyAI` / `PlayerArmyAI` / `MeleeVictoryRules` | 全闭环；唯一缺 A3 道具决策 |

不能照搬旧文档的完成勾选。例如 [NEXT.md](NEXT.md) 仍将英雄复活和生产队列 HUD 列为缺口，而当前代码已有对应实现；是否稳定应实测，不应重新开发一遍。

## 3. 历史接口缺口（已闭环，保留作为变更背景）

### 3.1 电脑玩家接入的本地玩家耦合 → A0 闭环

历史问题（已修）：`_bootstrap_melee` 只为 `local_player` 建库存；`issue_train/issue_research` 围绕 `local_owner_id` 校验；`_session.local_stock()` 在退款/扣费/出生失败里硬绑。

**当前实现**：命令入口显式接收执行玩家上下文（`command_owner`），由 `CommandRouter` + `ProductionModule` 一起按 owner 结算；建筑易主后取消按**原订单 owner** 退款；电脑工人造建筑只扣电脑库存；电脑与玩家各自有独立 `PlayerStock`。详见 [MELEE_AI.md §3](../design/game/MELEE_AI.md)。

### 3.2 道具与技能/Buff 的边界 → I0–I2 闭环

历史问题（已修）：道具 abilList 不能直接走 `AbilityExecutor`；`BuffHost` 不能表达同类装备独立叠加；`HeroDeathRegistry` 当时未存背包。

**当前实现**：`ItemCatalog.effect(id)` 仅白名单 `AIhe/AIma/AIde`；装备按实例 ID 独立叠加（`BuffQuery.bonus_armor` 汇总）；`HeroDeathRegistry` 持久化 `Inventory.snapshot()`，复活走 `ProductionModule.apply_revived_hero_state` 调 `Inventory.restore`。详见 [ITEM_SYSTEM.md](../design/game/ITEM_SYSTEM.md)。

### 3.3 当前剩余缺口（最新）

对战 AI **A0–A4 已闭环**。道具侧剩余 **I4**（商店 / 回城卷轴 / PowerUp 自动触发），不阻塞电脑对局。A3 详见 [MELEE_AI.md §4](../design/game/MELEE_AI.md)。

## 4. 道具系统计划

### I0：道具定义与实例契约（约 1～2 个开发日）

建议新增：

- `game/scripts/data/item_catalog.gd`：包装 ItemDef，解析技能、图标、名称、提示与模型；复用现有资产车道。
- `game/scripts/logic/item/item_instance.gd`：实例 ID、类型 ID、剩余次数、所在位置/持有者等动态状态。
- `game/scripts/logic/item/inventory.gd`：首版英雄六格，统一新增、移除、交换和快照；以信号通知 UI。

先支持少量真实数据中可确认的物品：生命恢复、魔法恢复、单一护甲加成。具体 rawcode、数值和资源从本地数据核验后写入白名单，不在本计划猜测。

验收：同一种道具的两个实例不共用充能；背包满时拒绝添加且不丢物；快照恢复实例与槽位；未知道具返回明确原因。

### I1：地面道具、拾取、丢弃和背包 UI（约 2～3 日）

- 增加地面道具实体与表现，通过 Catalog 获取资源；首版无模型时可用明确的占位外观。
- 给 SmartTarget/SmartHandlerRegistry 增加道具交互：英雄接令→移动接近→再次验证距离与归属→拾取。
- 道具只在成功转移到背包后移除地面实例；两英雄同时抢同一道具只成功一次。
- 增加六格背包 UI、图标、提示、次数、点击使用入口和丢弃入口。先完成点击交互，拖拽作为后续打磨。
- 拾取不应把普通单位误判为携带者；目标被他人拾走、死亡、取消或满包时正确结束订单。

验收：地面→背包→地面→另一英雄背包的实例身份与次数保持一致，远距离不能瞬间拾取。

### I2：使用效果、装备加成及英雄生命周期（约 2～3 日）

- 使用物品：验证实例/持有者/目标/冷却→执行效果→确认成功→提交扣次数与冷却；失败不消耗。
- 补充魔法恢复效果，生命恢复复用已有生命值入口；共享目标与表现机制，但增加道具行为适配。
- 装备加成以实例 ID 作为来源，汇总后接入实际战斗属性查询及 HUD。首版只验证护甲加成，不提前构造完整属性框架。
- 死亡时按 ItemDef.drop 策略处理；留存道具进入英雄登记；复活恢复，取消复活不丢失实例。
- 定义换槽、丢弃和重新拾取的冷却规则，防止通过转移物品重置冷却。

验收：药水不会超上限；零效果是否允许消耗须在物品规则中固定；失败施放不扣次数；两件同类装备的叠加/移除准确；死亡复活后不复制或丢失背包。

### I3：清野掉落与首版验收（约 1～2 日）

- 独立掉落服务订阅 `DeathService.unit_died`，不要把随机表解析塞进死亡清理函数。
- 消费 droppedItemSets 与 itemTablePtr/randomItemTables；区分互斥抽取组和多组掉落，随机使用可固定 seed 的来源。
- 核对随机类别/等级编码；首版无法解析时明确记录，不静默换成任意道具。
- 单位死亡重复通知必须幂等，不能重复发奖励。

最终剧本：英雄清掉一个营地→道具真实掉落→拾取显示→使用/装备生效→丢弃与复活状态正确。

### I4：商店与回城卷轴（第二批，约 3～5 日）

第一批道具闭环完成即可启动 AI，不必等待此项。

商店复用 ItemDef 造价与库存字段，补交易距离、所属买家、库存补充、满包与退款一致性。回城卷轴可研究复用 MassTeleport 的传送和表现能力，但安全目的地、友方主城选择、使用次数与中断规则必须单独定义，不能简单给卷轴绑定英雄大招。

## 5. 对战 AI 计划

### A0：双玩家基础与公共命令服务（约 2～4 日）

- GameSession 增加参与者配置：owner、种族、HUMAN/COMPUTER、出生点；双方出生点唯一分配。
- 用已有 MeleeBootstrap 为双方各刷基地，初始化各自 PlayerStock；HUD 仍只绑定本地玩家。
- 完成第 3.1 节的 owner 隔离，并检查采集交付、建造完成与单位死亡时的人口路径。
- 增加 `UnitOrder.Source.PLAYER_AI`；宏观订单优先于 UnitAI 自动索敌，显式进攻/撤退期间不被低级决策抢单。
- 公共动作服务返回成功/失败原因，供人类 UI 与电脑共同使用；训练完成接线不依赖当前选中建筑。

硬验收：电脑建造、训练、取消、研究、阵亡与失败回滚都只修改电脑库存；人类不能控制电脑单位；生产无需选中也能完工出兵。

### A1：经营 AI（约 2～3 日）

建议新增 `game/scripts/logic/ai/player_ai.gd` 与 `human_build_plan.gd`，以小型状态机/规则表驱动固定开局。第一版不需要先接行为树框架。

行为顺序：分配采金/伐木→补工人→按人口余量造农场→造兵营/祭坛→持续生产步兵和一名英雄。

建造点用现有 PlacementRules 校验，同时考虑工人可达性、出兵通道和有限次数重试。成功才推进计划；资源不足等待，工人死亡或落点无效则重新规划；不能每次 tick 都重复排同一栋建筑。

建议初始决策间隔 0.5～1 秒；这是可调参数，不是性能保证。保留当前目标、等待原因和最近失败，便于排查电脑为什么停住。

验收：玩家完全不干预，电脑自行采集、建造和产兵；人口满能补农场；损失工人后能补充；没有免费刷兵或跨玩家扣费。

### A2：军队调度、进攻和防守（约 2～3 日）

建议增加独立军队调度模块，状态为集结、进攻、回防、撤退、补充。宏观只发 Move/AttackMove/Attack，具体追击和攻击继续归 UnitAI、AttackController 与 Navigator。

- 军队达到配置阈值再出击，补兵加入集结点，避免逐只送兵。
- 基地受到威胁可回防；损失过大回撤并重新组军。
- 只在目标/状态变化时发令，避免每次 tick 重置攻击和移动。
- 通过观察接口获取敌情。首版可明确采用全图可见的测试规则，但不让 AI 模块直接散读所有敌军节点，便于以后接迷雾。

验收：至少形成两轮进攻；玩家偷袭基地时触发回防；目标建筑消失后不会永久卡在旧目标。

### A3：英雄、清野和道具（约 2～3 日）

连接英雄技能升级/施法、营地选择和背包服务：选择较弱营地→清野→拾取适用道具；按生命/魔法阈值使用药水；阵亡后通过祭坛复活。

应先确保 A1/A2 可靠，再加入这些决策。电脑使用道具走 I2 的相同规则，不能直接改生命值或跳过冷却。

验收：电脑能清野获取道具并合理使用；无技能点或冷却未结束时不反复发无效命令；复活后能重返军队。

### A4：胜负结算与完整对局（约 1～2 日）

新增会话级 MatchRules 与结果状态。建议首版使用明确的简化规则：某玩家全部存活建筑被摧毁则失败，排除中立建筑；若双方同时失去全部建筑则平局。该规则是本项目首版建议，不宣称完整还原原作。

初始化结束后才开启胜负检测；判定后停止 AI 下单并显示结果。重新开始需清理静态英雄死亡登记、队伍注册、道具实例、库存和计时状态。

验收：胜利、失败、同时毁灭均有结果；结果只触发一次；重新开始无上局残留。

## 6. 推荐执行顺序与预算（最新）

| 顺序 | 交付 | 当前 | 估算 |
|---|---|---|---|
| 1 | I0～I3：可玩的道具闭环 | **已完成** | 6～10 日（实际投入已落地） |
| 2 | A0：双玩家与 owner 隔离 | **已完成** | 2～4 日 |
| 3 | A1～A2：自行经营、出兵、回防 | **已完成** | 4～6 日 |
| 4 | A4：胜负结算 + 重开 | **已完成** | 1～2 日 |
| **5** | **A3：电脑英雄拾取 + 使用道具** | **已完成** | 2～3 日 |
| 后续 | I4：商店与回城卷轴 | 未开始 | 3～5 日，单独安排 |

**对战 AI A0–A4 已全部闭环**；道具侧下一笔为 I4（商店 / 回城）。A3 验收见 `selftest_player_army_pickup` / `selftest_player_army_item_use`。

## 7. 本次验证情况及工程边界

本次用 Godot 4.6.3 console、headless 脚本入口执行：

- `tests/unit/selftest_unit_ai.gd`
- `tests/unit/selftest_threat_table.gd`
- `tests/unit/selftest_buff_system.gd`

三项均打印 PASS、进程返回 0，但均同时记录 `ability_catalog.gd:34` 的 `Identifier not found: Wc3DefStore` 及依赖编译错误；另有字符解析警告。**这些结果不是干净通过。** 当前只能确认部分断言打印成功，不能证明整个测试加载链或玩法正常。需区分脚本启动时 Autoload/依赖加载问题与实际逻辑错误；此处不预判根因，也不据此断言游戏场景无法运行。

自动验收应同时检查退出码和脚本编译/运行错误，不能只 grep PASS。新功能测试重点覆盖资源归属、物品唯一性、失败事务、死亡复活和订单冲突，再做 Echo 实机验收。

本次未启动完整对战场景进行视觉/操作验收，未修改玩法代码。工作区原有 UnitAI、CommandRouter、Director、弹道表现和相关测试的未提交修改保留；分析以这些当前文件为准。

工程结构遵循现有 Data/Catalog/Logic/Presentation 分层；背包 UI 用状态信号刷新。旧路线图保留历史记录，本计划给出本次方向的实施顺序，不把旧勾选作为事实。
