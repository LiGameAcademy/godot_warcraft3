# 人族电脑对手机制（PlayerAI · 1v1）

2026-09-13。对应 [实施计划 A0–A4](../../roadmap/ITEMS_AND_MELEE_AI_PLAN.md)。

## 1. 范围与边界

- 范围：单机 Echo Isles、人类玩家 vs 人族电脑（owner=1）。
- 不做：科技树/全阵营决策、行为树框架、电脑自定义建造脚本（脚本化建造仍在策划层）。
- 与 UNIT_AI 区别：本组件做**基地经营 + 进攻时机**，单位级索敌/追击/反击由 [UNIT_AI.md](UNIT_AI.md) 完成。

## 2. 模块与权威

| 模块 | 职责 |
|---|---|
| `MeleeBootstrap` | 双方 sloc 收集 + 唯一分配；为 owner=0/1 各刷主城与工人 |
| `GameSession` | 玩家 owner 注册 + 双方 `PlayerStock` + `match_finished` 信号 |
| `PlayerEconomyAI` | 1Hz 决策：补工人、造农场、造兵营/祭坛、产步兵/英雄 |
| `PlayerArmyAI` | 阈值集结、攻击移动、回防、撤退、补援 |
| `MeleeVictoryRules` | 团队建筑清场判定（含未完工工地）|
| `MeleeGameConstants` | SLK 复活报价 / 经济参数 |
| `MatchResultScreen` | 胜负 / 平局 UI + 重开信号 |
| `ProductionModule` | 训练 / 取消 / 复活按订单 owner 结算；与 Director 解耦 |
| `UnitOrder.Source.PLAYER_AI` | 宏观订单优先级，压制单位级 UnitAI 自动索敌 |

## 3. 当前实现进度（与计划 A0–A4 对照）

| 段 | 内容 | 当前 | 关键证据 |
|---|---|---|---|
| A0 | 双玩家开局 + owner 隔离 + 命令入口校验 | **闭环** | `melee_bootstrap.gd:23-185`、`game_session.gd:4-40`、`command_router.gd:89-105`、`production_module.gd:32-70`；测试 `selftest_two_player_start.gd`、`selftest_production_owners.gd`、`selftest_construction_owners.gd` |
| A1 | 经营 AI（工人 / 农场 / 兵营 / 祭坛 / 步兵 / 英雄）| **闭环** | `player_economy_ai.gd:33-203`（间隔 1s、跨 hall 补工人、按人口余量造农场、三档占位校验、首次英雄预留五人口） |
| A2 | 军队调度 + 进攻 + 回防 + 撤退 | **闭环** | `player_army_ai.gd:3-86`（状态机 ASSEMBLE/ATTACK/DEFEND/RETREAT、阈值 4、`%d:%d:%d` 一次发令不重置、`observe_enemies` 注入便于接迷雾）|
| A3 | 电脑英雄清野 + 拾取 + 使用道具 | **闭环** | `player_army_ai.gd` `_consider_pickup` / `_consider_use`；`ItemService.get_ground_items_in_radius`；测试 `selftest_player_army_pickup`、`selftest_player_army_item_use` |
| A4 | 胜负结算 + 重开 | **闭环** | `melee_victory_rules.gd:1-41`、`game_session.gd:4-40`、`production_module.gd:165-225`、`match_result_screen.gd`；测试 `selftest_melee_victory.gd`、`selftest_match_end_game.gd`、`selftest_opponent_campaign.gd` |

## 4. A3 电脑侧道具决策（已实现）

> 电脑在集结/撤退时拾取白名单地面道具；每秒按 HP/MP 阈值走 `Inventory.try_use`（与玩家同规则）。

### 4.1 拾取决策

`PlayerArmyAI._consider_pickup()`（仅 `ASSEMBLE` / `RETREAT`）：

- 扫描 `ItemService.get_ground_items_in_radius`（480 WC3）
- 仅 `ItemCatalog.is_ai_pickup_worth`（效果白名单 AIhe/AIma/AIde）
- 满包 / 已认领 / 拾取中 → 跳过；`issue_pickup(..., PLAYER_AI)`
- 进攻/回防不绕路；拾取中的英雄不被宏观 Move/AttackMove 打断

### 4.2 使用决策

`PlayerArmyAI._consider_use()`（每秒，与状态无关）：

| 触发 | 道具 | 阈值 |
|---|---|---|
| HP < 50% | AIhe | `HEAL_HP_RATIO` |
| MP < 30% | AIma | `MANA_MP_RATIO` |

走 `Inventory.try_use`：满血/满蓝不扣次数；装备（AIde）不主动消耗。

### 4.3 测试

| 文件 | 覆盖 |
|---|---|
| `tests/unit/selftest_player_army_pickup.tscn` | 集结拾取、满包跳过、进攻不绕路、认领跳过 |
| `tests/unit/selftest_player_army_item_use.tscn` | 低 HP 吃药、满血不耗、低蓝回蓝、指环保留 |

## 5. 与其它设计文档的关系

- [UNIT_AI.md](UNIT_AI.md) §4.4：单位级 Profile 矩阵（含 REACTIVE）+ 仇恨表；
- [ITEM_SYSTEM.md](ITEM_SYSTEM.md)：玩家侧道具闭环；A3 接入它但不修改它；
- [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md)：EI 1v1 竖切；
- [ABILITY_SYSTEM_INTEGRATION_PLAN.md](../../roadmap/ABILITY_SYSTEM_INTEGRATION_PLAN.md)：电脑使用技能走 `AbilityExecutor`；
- [CLASSIC_RULES_BASELINE.md](../../roadmap/CLASSIC_RULES_BASELINE.md)：电脑与玩家共享规则（复活报价 / 人口）。

## 6. 风险与边界

- 「电脑必须会玩」≠「电脑要会所有微操」——本版目标是「能赢得了一局」，**不**承诺操作多样性或英雄控制；
- 迷雾接驳：`PlayerArmyAI.observe_enemies` 已是 Callable 注入，首版可接 `CombatQuery` 全图敌情；迷雾接驳后只改 `observe_enemies.call()` 即可；
- 性能：`PlayerEconomyAI` 1Hz、`PlayerArmyAI` 1Hz（待定），双人对局下每次决策 O(单位数)；与现有 16Hz 单位 AI 互相独立，不会冲撞；
- 平衡：本版电脑**固定**人类开局配方（4 工人 + 主城），玩家也可以同样配方作镜像开局；不引入难度档。

## 7. 本版不含

- 多电脑同图（team > 2）；
- 联盟 / 团队 AI；
- 英雄走位微操（侧移、卡位）；
- 电脑建造脚本（人类建筑菜单的「AI 可造子集」目前=全部人族基础建筑）；
- 商店 / 回城卷轴 / PowerUp 自动触发（I4 范围）。