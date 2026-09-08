# 战斗系统：攻击管线 · 伤害公式 · 开发路线

> 状态：**C0–C3 已接线**（DamagePipeline 骰×表×护甲；Death → Decay Flesh 停留后移除尸体；离场不可选）  
> 相关：[GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) · [ROADMAP.md](ROADMAP.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [WORLD_MEMBERSHIP.md](../../architecture/WORLD_MEMBERSHIP.md) · [TREE_INTERACT.md](TREE_INTERACT.md) · **[UNIT_AI.md](UNIT_AI.md)**（单位级 AI，非 AI 玩家） · [WEAPON_MISSILE_FX.md](../presentation/WEAPON_MISSILE_FX.md)（飞弹 Present / PE2 / Ribbon）  
> 竖切进度：F0–F6 ✅ → C0–C3 战斗 ✅ → F8–F9 顶盾 ✅ → **单位 AI（野怪对抗）** → F10 技能  
> 最后更新：2026-09-06

---

## 0a. 实现现状（as-built · 2026-08-21）

> 本节描述**仓库里已经跑通的代码**，供单位 AI / 后续技能直接挂钩。设计意图仍以 §0 之后为准。

### 已落地模块


| 模块                  | 路径                                               | 职责                                                                                         |
| ------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `AttackController`  | `game/scripts/logic/combat/attack_controller.gd` | 订单 FSM：`ATTACK` / `ATTACK_MOVE` / `HOLD`；追击 → WINDUP(dmgpt) → instant 或 missile → COOLDOWN |
| `CombatQuery`       | `…/combat_query.gd`                              | 敌对 / 合法目标 / 出手射程 vs 交战容差 / acquire 索敌 / weapTp 投送分类                                        |
| `DamagePipeline`    | `…/damage_pipeline.gd`                           | 唯一扣血：骰 × 攻防表 × 护甲（pierce 可读顶盾因子）→ `UnitLife` → `DeathService`                              |
| `CombatDamageTable` | `game/scripts/data/combat_damage_table.gd`       | atk×def 倍率 + 护甲公式                                                                          |
| `CombatRng`         | `…/combat_rng.gd`                                | 可注入 RNG                                                                                    |
| `DeathService`      | `…/death_service.gd`                             | 清选中、`WorldMembership.exit`、通知同宿主其它 `AttackController`                                      |
| `ProjectileService` | `…/projectile_service.gd`                        | Logic 弹道；真 missile 命中后再 Pipeline；instant 远程可 `visual_only`                                 |
| Present             | `combat_projectile_shell` / `damage_float_text`  | 真 missile 挂 UnitFunc 飞弹模型（Hamg→FireBall Stand；hwat→WaterElementalMissile **Birth 循环** + 命中 Death）；instant 仅命中特效；**禁止** `set_life` |
| 命令入口                | `CommandRouter.issue_attack_*` / Hold / Patrol   | 懒挂 `AttackController`；与 Harvest/Build 互斥 abort                                             |




### 运行时接线（`GameDirector`）

```text
_damage_pipeline.death = _death_service
_damage_pipeline.damage_applied → DamageFloatText
_projectile_service.pipeline = _damage_pipeline
projectile_launched → CombatProjectileShell
projectile_resolved → AttackController.notify_strike_result
死亡 → Unit.play_death → Decay 链 → remove_unit_instance
```

`AttackController` **按需**挂载：玩家下 Attack / Attack-Move / Hold 时 `_ensure_attack_controller`。地图野怪默认**没有**在跑的攻击 FSM。

### 模式语义（已实现）


| Mode          | 索敌                                  | 追击          | 典型入口        |
| ------------- | ----------------------------------- | ----------- | ----------- |
| `ATTACK`      | 固定目标                                | 是           | 右键敌 / A 点单位 |
| `ATTACK_MOVE` | `find_acquire_target`（`acquire` 半径） | 有目标则追；清场后续走 | A 点地面       |
| `HOLD`        | 仅 `attack_range` 内                  | **不**追出射程   | H 键         |




### 仍缺（交给 [UNIT_AI.md](UNIT_AI.md)）

- 野怪 / 闲置单位 **idle 主动索敌**、**受击反击**、营地 leash / 助攻
- 独立 `OrderArbiter` 薄壳（今日靠 Router 里 `_abort_*`）
- AI 玩家宏观策略（**明确不做**，见 UNIT_AI 非目标）



### 自测

- `tests/unit/selftest_c_combat_damage.gd`
- `tests/unit/selftest_c_combat_attack_resolve.gd`
- `tests/unit/selftest_c_combat_projectile.gd`

---



## 0. 结论（先读）

**应该**在做人族「能打野怪 / 互殴致死」之前，先立 **Attack 订单 + 统一伤害入口 + 攻防表**，而不是在 `GameDirector` 里写「步兵贴怪减血」。

原因：

1. 顶盾（F8–F9）、技能伤害（F10）、投石车砸树、将来溅射，都必须走同一 `DamagePipeline.apply`；否则每条玩法各写一套扣血。
2. WC3 数值权威已在仓库：`UnitWeaponsDef`（射程/冷却/骰伤/攻类型）+ `UnitBalanceDef`（HP/护甲/防类型）；禁止再硬编码 12.5 伤之类常量。
3. 命令层已有 `UnitOrder` / `SmartTarget` / `SmartHandlerRegistry`；战斗只加 Kind + Handler，**不**在 Director 按兵种 `if`。

**竖切范围不变**：Echo Isles 上 `hfoo` / `hrif` / 野怪能 Attack、Attack-Move、按公式扣血致死。  
**契约要先立**：`AttackController`（订单 AI）+ `DamagePipeline`（纯结算）+ `CombatQuery`（敌对/射程/索敌）；Present 只播动画与弹道壳。

---



## 1. 范围与非目标



### 1.1 本里程碑要做（C0–C3）


| ID  | 玩法                 | 最小交付                                 |
| --- | ------------------ | ------------------------------------ |
| C0  | 攻击命令 + 追击          | `Attack` Order；右键敌单位；进距反复出手          |
| C1  | 攻击移动               | `Attack-Move` 到地面；`acquire` 索敌；清场后续走 |
| C2  | 射程 / 冷却 / 面向 / 弹道壳 | 读武器表；近战 instant；远程可先瞬时+朝向            |
| C3  | 攻防类型 + 伤害 + 死亡     | 骰伤 × 攻防表 × 护甲减伤；HP≤0 离场              |




### 1.2 明确不做（战斗竖切；单位 AI 另文）

- ~~完整电脑战斗 AI / 自动防守反击~~ → **单位微观 AI** 见 [UNIT_AI.md](UNIT_AI.md)（野怪反击 / idle 索敌）；**AI 玩家**仍不做
- 溅射 / 弹跳 / 武器槽 2 / 攻城弹道抛物线
- 魔法抗性细分、护甲升级科技（铁匠 `Rhme`/`Rhar` 后置）
- 隐身 / 魔法免疫 / 无敌 buff 全表（预留钩子即可）
- 联机确定性 RNG（先用 Session 可注入的 RNG，接口留好）
- 把战斗写进 `Map*Layer` 或 `scripts/map/`



### 1.3 与已有模块边界


| 模块                                     | 关系                                                                 |
| -------------------------------------- | ------------------------------------------------------------------ |
| `CombatSteering`                       | **只算期望速度**（pursue/evade）；不判敌、不扣血。Attack 追击可选用，也可先用 Navigator 点目标   |
| `UnitNavigator`                        | 消费路径；`apply_steering_override` 留给战斗追击可选路径                          |
| `HarvestController` / 树 `apply_damage` | 伐木伤树**不**走单位攻防表；投石车等未来单位伤树 → 仍调 `TreeRegistry.apply_damage`，由战斗层发起 |
| `UnitLife`                             | 扣血权威字段；死亡由战斗层触发 `WorldMembership.exit` + 清选中                       |
| `UnitVisual`                           | 已有 Attack 动画回退；Logic 发「strike / death」事件即可                         |


---



·游戏仍是 Application 层；战斗属 **Game Logic**，不进 map 五层。

```text
┌─────────────────────────────────────────────────────────┐
│  GameDirector / CommandRouter / HUD                     │
│  输入 → Order；不写伤害公式                              │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  logic/combat/                                          │
│  AttackController · CombatQuery · DamagePipeline        │
│  AttackMoveBrain（可与 Controller 同文件先起步）         │
└───────┬─────────────────────────┬───────────────────────┘
        │ UnitLife / meta         │ 事件
┌───────▼─────────┐   ┌───────────▼───────────────────────┐
│  Session / 节点  │   │  Present：朝向、Attack 动画、弹道壳 │
└─────────────────┘   └───────────────────────────────────┘
        │
        ▼ 只读
 UnitWeaponsDef / UnitBalanceDef / 攻防倍率表（Data/Catalog）
```

**禁止**：在 Layer 里 `set_life`；在 HUD 里算骰子；在 Navigator 里判断 `atkType`。

---



## 2.1 架构裁决（逻辑/表现 · SOLID · 组件化）

> 本节回答：是否已分离、该不该分离、SRP/OCP、是否组件化、如何落设计。



### A. 逻辑 / 表现分离 —— **应该，且本契约以之为硬门禁**


| 问题       | 裁决                                                                                      |
| -------- | --------------------------------------------------------------------------------------- |
| 该不该分离？   | **应该。** 与仓库总纲（map 五层 + Game 应用层）及 Harvest/Build 一致：Logic 决定「打不打、打多少、死不死」；Present 只消费结果。 |
| 文档现状够不够？ | **意图够、契约偏软。** §2/§7 已画边界，但缺「强制订阅面」；若 Present 在弹道命中时直接改 `UnitLife`，分离当场破裂。               |


**硬规则（实现必须遵守）：**

1. **权威状态只在 Logic**：生命、冷却、订单态、死亡、敌对判定 —— Present / HUD / Navigator **只读**。
2. **Logic → Present 只出事件（或只读快照）**，不反向调用「播什么动画才算伤害」。
3. **伤害结算永远在 Logic**：`instant` 在 `AttackController` 伤害点调 `DamagePipeline`；`missile` 由 Logic 的 `ProjectileService`（可挂在 combat/）推进命中，**再**调 Pipeline。Present 的飞矛 Node 最多是视觉镜像，**禁止** Present 命中回调里 `set_life`。
4. **朝向 / Attack 动画 / 血条**：订阅 `strike_begun` / `damaged` / `died`；缺订阅时游戏仍应能「隐形正确结算」（可测）。

推荐信号面（挂在 `AttackController` 或会话级 `CombatEvents`）：

```text
strike_begun(attacker, target, weapon_slot)   # 开打 / 出弹
damage_applied(result: DamageResult)         # 含 amount、killed
target_lost(attacker, reason)
unit_died(unit)                              # 亦可由 DeathService 发
```



### B. 单一职责（SRP）—— **模块切分正确，Controller 要防变胖**


| 模块                                                   | 单一职责                      | 现状评价                            |
| ---------------------------------------------------- | ------------------------- | ------------------------------- |
| `CombatQuery`                                        | 敌对 / 射程 / acquire / targs | ✅                               |
| `DamagePipeline` + `CombatDamageTable` + `CombatRng` | 算伤与写生命                    | ✅（表与 RNG 可并列文件）                 |
| `DeathService`                                       | 死亡编排（清选中、离场、广播）           | ✅ 编排≠公式                         |
| `SmartAttackHandler`                                 | Order 映射                  | ✅ 开闭友好                          |
| `AttackController`                                   | **一种订单的状态机**              | ⚠️ 最大风险点：勿塞公式、勿播 Mesh、勿解析 Input |


**防胖法则：** Controller 只做 `状态转移 + 调 Query/Pipeline/Navigator`；Attack-Move 索敌可先内联，一旦 >~80 行逻辑就拆 `AttackMoveBrain`（纯决策，返回「当前目标 / 继续走」）。

### C. 开闭原则（OCP）—— **命令侧已对齐；结算与弹道要预留扩展点**


| 扩展场景                            | 做法（对扩展开放 / 对修改关闭）                                                                               |
| ------------------------------- | ----------------------------------------------------------------------------------------------- |
| 新右键交互                           | 加 `SmartHandler`，**不改** `issue_smart` 中枢（已有 Registry）                                           |
| 新伤害来源（技能/溅射/光环）                 | 都调 `DamagePipeline.apply(StrikeRequest)`；用 `source_kind` / modifiers 扩展请求，**不**新开 `set_life` 入口 |
| 新 `weapTp`（missile / artillery） | `WeaponDelivery` 策略接口：`InstantDelivery` / `MissileDelivery`；Controller 只调 `delivery.fire(...)`  |
| 顶盾 / 护甲升级                       | Pipeline 内读防御方修正（或 `DamageModifier` 链），**不**改 Controller 状态机                                    |
| 攻防表换数据源                         | 表实现换盘读，**调用方仍只认** `multiplier(atk, def)`                                                        |


P0 可不实现完整 Modifier 链，但 **StrikeRequest 字段要一次定好**（attacker、target、atk_type、raw 或 dice 参数、source_kind），避免 C3/F10 大改签名。

### D. 组件化 / 模块化 —— **应该采用「Godot 组件 + 纯服务」，不上 ECS**


| 问题       | 裁决                                                                                   |
| -------- | ------------------------------------------------------------------------------------ |
| 该不该组件化？  | **应该**，且与已有 `HarvestController` / `BuildController` / `UnitNavigator` **同构**，降低心智成本。 |
| 要不要 ECS？ | **本阶段不要。** WC3 单位数量与系统耦合度用 Node 组件足够；ECS 迁移成本高于竖切收益。                                 |
| 模块化指什么？  | 目录按职责拆文件（§8）+ 每单位挂行为组件 + 无状态纯函数/服务可单测。                                               |


**推荐组合（每单位运行时）：**

```text
Unit (Node3D)                         # Present 壳 + meta（life/owner/typeId）
├── UnitNavigator                     # 已有：移动
├── UnitVisual                        # 已有：动画（只听事件）
├── HarvestController?                # 工人
├── BuildController?                  # 工人
└── AttackController?                 # 可战斗单位（无武器则不挂或 idle 空实现）
```

共享、**不**挂在每个单位上的服务：

```text
DamagePipeline / CombatQuery / DeathService / CombatDamageTable / CombatRng
（Session 或 CombatFacade 持有单例式引用，注入给 Controller）
```

挂载时机：与 Harvest 相同 —— `GameDirector`（或 UnitFactory）在单位入场时 `ensure_attack_controller(unit)`，按 `UnitWeaponsDef.weaps_on` / 有无有效武器决定。

### E. 一句话总评与补强


| 维度     | 当前设计                    | 补强                                    |
| ------ | ----------------------- | ------------------------------------- |
| 逻辑表现分离 | 方向正确                    | 钉死「弹道命中也在 Logic」+ 事件面                 |
| SRP    | Query/Pipeline/Death 清晰 | Controller 只编排；Brain/Delivery 可拆      |
| OCP    | Handler Registry 好      | `StrikeRequest` + `WeaponDelivery` 预留 |
| 组件化    | 推荐方案 A                  | 与 Harvest 同构；服务集中注入                   |


**不采纳：** 把战斗写进 `UnitVisual`；集中式巨型 `CombatSystem._process` 里 `match type_id`；Present 弹道回调扣血。

### F. 单位行为编排 —— **订单仲裁 + 域内小状态机；不上单位级行为树**

> 问题：单位（含建筑）要不要统一状态机层？要不要行为树？



#### 裁决（先读）


| 方案                                                | 裁决          | 理由                                          |
| ------------------------------------------------- | ----------- | ------------------------------------------- |
| **每域一个小 FSM**（Harvest / Attack / Build / Train…）  | **采用（已在走）** | 与 WC3「一条当前订单」同构；可单测；职责清晰                    |
| **单位级巨型 FSM**（Idle/Move/Attack/Harvest/Build 全枚举） | **不采用**     | 组合爆炸；每加玩法改核心；和现有多 Controller 冲突             |
| **行为树（BT）管玩家单位**                                  | **本阶段不采用**  | 玩家单位是 **命令驱动**，不是自主决策；BT 适合电脑 AI / 野怪主动反击   |
| **薄层 OrderArbiter（当前订单互斥）**                       | **应补**      | 多 Controller 并存时缺「谁占有单位」；打断/替换靠它，而不是互相 `if` |


WC3 语义对照：引擎核心是 **Order（即时/队列）→ 单位执行器**，不是 BT。复刻应对齐 Order，而不是用 BT 模拟 Order。

#### 推荐结构

```text
                    UnitOrder（命令层）
                           │
                    OrderArbiter（每单位一份，很薄）
                     │ 互斥：新订单 cancel 旧域
        ┌────────────┼────────────┬─────────────┐
        ▼            ▼            ▼             ▼
  AttackController  Harvest    BuildCtrl    TrainQueue…
   （小 FSM）      （小 FSM）   （小 FSM）   （队列态）
        │            │            │             │
        └────────────┴─────┬──────┴─────────────┘
                           ▼
                    UnitNavigator / UnitLife / …
                           │ events
                           ▼
                       UnitVisual（Stance×Activity，已有）
```

**OrderArbiter 职责（刻意保持小）：**

1. 持有 `current_order: UnitOrder`（+ 可选短队列，P1）
2. `issue(order)`：按 Kind 路由到对应 Controller，并对其他域 `cancel()`
3. 查询：`is_busy()` / `current_kind()`（HUD、混选、死亡清引用）
4. **不**内含追击/采矿/建造细节状态

建筑同构、域不同：


| 实体      | 典型域 FSM / 服务               | 不需要的           |
| ------- | -------------------------- | -------------- |
| 士兵 / 英雄 | Attack（+ 日后 Ability）       | Harvest        |
| 农民      | Harvest + Build +（弱）Attack | TrainQueue     |
| 兵营 / 祭坛 | `TrainQueue` / Research    | Attack（非塔）     |
| 防御塔（远期） | Attack（acquire 自动）         | Harvest        |
| 完成建筑闲置  | Arbiter=`NONE` + 队列空       | 巨型 BuildingFSM |




#### 何时才考虑行为树？


| 时机                               | 用途                     |
| -------------------------------- | ---------------------- |
| 电脑玩家 AI（Melee AI 脚本替代）           | 宏观：扩张/进攻/撤兵            |
| 野怪 / 守卫「主动反击、巡逻、警戒」              | 微观：感知→选目标→Attack Order |
| **不要**用 BT 替换玩家右键 Attack/Harvest | 玩家输入已是最高优先级 Order      |


野怪主动行为已单列 [UNIT_AI.md](UNIT_AI.md)：P0 用决策表发 Attack Order，仍走 `AttackController`；不上 BT。电脑玩家宏观 AI 才考虑 BT。

#### 与动画层关系

`UnitVisual` 的 Stance×Activity **不是**玩法状态机，只是表现映射（Stand/Walk/Attack/Work）。玩法态以 Arbiter + 域 Controller 为准；Visual 订阅事件即可，禁止 Visual 反推「当前能不能采」。

#### 实现节奏建议

1. **C0**：`AttackController` 自带小 FSM（与 Harvest 并列）；打断靠 Router/`cancel`（与今日 Harvest 相同）
2. **C0 末或 C1**：抽出 `OrderArbiter`（或 `UnitBrain` 薄壳），统一 `issue` / `cancel_others`
3. **F10 / 电脑 AI**：再评估 BT，且只挂在 AI 侧，不进玩家单位主路径

---



## 3. 数据权威



### 3.1 武器（攻击方）

路径：`UnitWeapons.slk` → `UnitWeaponsDef`（已落地）。


| 字段                              | 用途                                                                  |
| ------------------------------- | ------------------------------------------------------------------- |
| `acquire`                       | 主动索敌半径（Attack-Move / 日后 idle）                                       |
| `range_n1`                      | **出手射程**（`in_attack_range`）                                         |
| `rng_buff1`                     | **交战容差**（`in_engage_range`：前摇中不立刻丢目标）；**不要**整段加进出手判定（步兵 90+250=340） |
| `min_range`                     | 过近不可打（竖切可先忽略火枪除外）                                                   |
| `cool1` / `dmgpt1`              | 冷却周期；伤害点（windup 起点起算，到点再 `DamagePipeline`）                          |
| `dice1` / `sides1` / `dmgplus1` | 基础伤害                                                                |
| `atk_type1`                     | normal / pierce / siege / magic / chaos / hero / spells…            |
| `weap_tp1`                      | instant / missile / …                                               |
| `targs1`                        | 目标过滤器（ground,air,structure…）；P0 可只认 ground 单位                       |




### 3.2 护甲与生命（防守方）

`UnitBalanceDef`：`hp`、`def` / `realdef`、`def_type`（small/medium/large/fort/hero/divine/none…）。

运行时生命：`UnitLife` meta（已有）。自然回血 / 回蓝：`UnitRegen`（`regenType=always`；英雄叠加 STR/INT×0.05）。

### 3.3 攻防倍率表

WC3 经典表：`atkType × defType → multiplier`（如 pierce vs large = 0.75 等）。


| 方案        | 说明                                                                                       |
| --------- | ---------------------------------------------------------------------------------------- |
| **P0 推荐** | `game/scripts/data/combat_damage_table.gd`（或 `scripts/definitions/combat/`）硬编码官方表常量 + 单测 |
| P1        | 若 slk-exported 有 Misc/Damage 表则改为读盘；接口不变                                                 |


护甲减伤（经典）：

```text
armor_factor = 1 - (0.06 * armor) / (1 + 0.06 * |armor|)
# armor 可为负（易伤）
final = max(0, roll * type_mult * armor_factor)  # 另有最低伤规则可后置
```

骰伤：

```text
roll = dmgplus + sum(dice times random(1..sides))
```

RNG：`CombatRng` 接口挂在 Session（`randi_range`）；测试可注入固定序列。

### 3.4 敌对关系（竖切简化）


| 规则   | P0                                                                      |
| ---- | ----------------------------------------------------------------------- |
| 己方   | 智能右键 / 自动索敌 **不**打友军；**显式 Attack（A 点单位）允许**强制攻击友军                       |
| 中立被动 | 野怪 / 小动物：可被玩家攻击；**主动反击 / 警戒** 由 [UNIT_AI.md](UNIT_AI.md) 交付（战斗层只提供敌对判定） |
| 敌对玩家 | `owner` 不同且非中立玩家槽 → 可互攻                                                 |
| 建筑   | P0 允许打敌方建筑；金矿 `ngol` **不可**当攻击目标（仍走采集）                                  |
| 树木   | 不走 Attack Order；伐木保持 Harvest                                            |


`CombatQuery.is_hostile(a, b)` / `is_valid_attack_target(attacker, target)` 集中实现。

---



## 4. 运行时管线（一击）

```text
AttackController（单位每帧 / tick）
  ├─ 目标失效？ → Stop / 重索敌（Attack-Move）
  ├─ 距离 > range_n1？ → 追击（Navigator / Steering）
  ├─ 距离 OK 且冷却就绪 → WINDUP（播 Attack，strike_begun）
  │     └─ 到 dmgpt1 → StrikeRequest → DamagePipeline
  │     └─ cool1 从 windup 起点计；剩余进 COOLDOWN
  └─ DamagePipeline.apply(StrikeRequest)
        ├─ 过滤：存活、在场、敌对、targs
        ├─ roll + type_mult + armor
        ├─ UnitLife.set_life
        └─ life≤0 → DeathService.kill(target)
              · 清选中 / 清以其为目标的订单
              · WorldMembership.exit（或 Death 表现后再 exit）
              · 发 unit_died（触发器远期 / HUD）
```

**统一入口不变式：**

- 单位扣血：只经 `DamagePipeline.apply`（或它调用的 `UnitLife` 包装）。
- 树扣血：仍经 `TreeRegistry.apply_damage`；单位武器打树时由战斗层转发，不复制扣血逻辑。

---



## 5. 命令层扩展



### 5.1 `UnitOrder.Kind`

```text
ATTACK = 60        # 指定目标（target_id = 单位 instance_id）
ATTACK_MOVE = 61   # goal_wc3 = 地面点；途中索敌
```

工厂：`UnitOrder.attack(target, src)` / `UnitOrder.attack_move(goal, src)`。

### 5.2 `SmartTarget.Kind`

```text
ENEMY_UNIT = 5     # 右键敌对/中立可攻击单位
```

Director 拾取：射线命中单位 → `CombatQuery.is_valid_attack_target(local_selected?, hit)`  
混选时：能攻击的发 Attack，不能的降级 Move 到目标脚下（对齐采集混选策略）。

### 5.3 Router / Handler

- 新增 `SmartAttackHandler`（或等价），注册到 `SmartHandlerRegistry`。
- 命令卡 / A 键：进入「攻击瞄准」模式 → 点单位 Attack，点地面 Attack-Move（WC3 经典）。
- **禁止**在 `issue_smart` 中枢堆 `if enemy`；只加 Handler。



### 5.4 Move vs Attack-Move


| 命令          | 途中遇敌                                               |
| ----------- | -------------------------------------------------- |
| Move        | **不**主动攻击                                          |
| Attack-Move | `acquire` 内有合法目标 → 切入临时 Attack；目标死/丢失 → 继续走向原 goal |
| Attack      | 死追指定目标；丢失则 Stop（P0）或弱索敌（P1）                        |


---



## 6. `AttackController` 状态机（建议）

```text
IDLE
  └─ 收到 ATTACK / ATTACK_MOVE →

CHASE          # 路径/steering 靠近目标或 A-M 点
  ├─ in_range → WINDUP / STRIKE
  └─ target lost →（Attack）STOP /（A-M）回到 MOVE_TO_GOAL

WINDUP         # 可选；P0 可与 STRIKE 合并
  └─ damage point →

STRIKE         # 调用 DamagePipeline；进入 COOLDOWN
  └─

COOLDOWN       # cool1；面向保持；目标仍在距内则循环 STRIKE
  └─ out of range → CHASE

MOVE_TO_GOAL   # 仅 Attack-Move：无目标时走向 goal
  └─ acquire hit → CHASE(target)
  └─ arrived → IDLE
```

挂载方式（二选一，实现时定一种并写进决策记录）：


| 方案          | 说明                                                    |
| ----------- | ----------------------------------------------------- |
| **A. 节点组件** | 每个可战斗单位挂 `AttackController`（类似 Harvest）               |
| **B. 集中服务** | `CombatSystem` 持有 `id → state`，Director `_process` 驱动 |


**推荐 A**：与 `HarvestController` / `BuildController` 一致，便于单测与打断。

打断：新 Order（Move/Stop/Harvest/…）→ `AttackController.cancel()`。

---



## 7. Present 钩子（不挡 Logic）


| 事件            | Present                                                                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 进入 CHASE / 移动 | 已有 Walk                                                                                                                                                 |
| STRIKE        | `UnitVisual` Attack（已有 fallback）；yaw 朝向目标                                                                                                               |
| missile P0    | Logic 瞬时结算；Present 可只播音效                                                                                                                                |
| missile P1    | Logic `MissileDelivery` 推进命中再 Pipeline；Present 飞矛仅为镜像（**禁止** Present 回调扣血）                                                                              |
| **C2 落地**     | `weapTp`→`CombatQuery.Delivery`：`instant`/`normal`（含 **hrif**）dmgpt 结算 + Present `CombatProjectileShell`；`missile`* 走 `ProjectileService` 飞行后再 Pipeline |
| 死亡            | 订阅 `unit_died`：Death 动画 + 尸体 Geoset；Logic 已 `WorldMembership.exit` / 不可选                                                                                |
| **C3 落地**     | Pipeline 骰×表×护甲；`exit` 后 `visible=true` 播 Death → **完整** `Decay Flesh` → `Decay Bone`（片长即停留），然后 `remove_unit_instance`；血条不跟尸体                           |
| 命中飘字          | `DamagePipeline.damage_applied` → Present `DamageFloatText` 挂目标；禁改 `UnitLife`                                                                           |


血条：`HealthBarManager` 已读 `UnitLife`，无需战斗特判。命中数字：`DamageFloatText`（调试用，挂受击单位）。

---



## 8. 代码落点（目标树）

```text
game/scripts/
├── logic/
│   ├── combat/
│   │   ├── attack_controller.gd      # 订单状态机
│   │   ├── attack_move_brain.gd      # 可先并入 controller
│   │   ├── combat_query.gd           # 敌对、射程、acquire、targs
│   │   ├── damage_pipeline.gd        # roll + 表 + 护甲 + 写 UnitLife
│   │   ├── death_service.gd          # kill / 清引用
│   │   ├── projectile_service.gd     # C2：missile 飞行 + 命中结算；instant 远程仅登记壳
│   │   └── combat_rng.gd             # 可注入 RNG
│   ├── command/
│   │   ├── unit_order.gd             # + ATTACK / ATTACK_MOVE
│   │   ├── smart_target.gd           # + ENEMY_UNIT
│   │   └── handlers/…                # SmartAttackHandler
│   └── pathing/
│       └── combat_steering.gd        # 已有；可选接入追击
├── data/
│   └── combat_damage_table.gd        # atk×def 倍率（或 definitions/）
└── presentation/
    ├── combat_projectile_shell.gd    # C2 Present 弹道壳（tscn 挂载；禁 set_life）
    └── damage_float_text.gd          # 受击飘字（订阅 Pipeline；禁 set_life）
```

自测：`tests/unit/selftest_c_combat_damage.gd`（公式表 + 护甲）；场景验收用 `game_main`。

---



## 9. 与竖切剧本对齐

人工点一遍（接 GAMEPLAY_VERTICAL §1 第 8 条）：

1. 训出 `hfoo`，A 键 / 右键打 Echo 野怪 → 追击 → 近战出手 → 血条下降
2. 打死野怪 → 不可再选；选中清空；尸体/Death 可后置抛光
3. A 键点地面途经野怪 → 停下打 → 打完继续走
4. 普通右键地面 Move → **不**主动惹怪
5. 训 `hrif`：射程外追，进距开火，冷却不连发

6.（C3）同攻击打不同 `defType` 单位，伤害差与表一致（可用自测代替肉眼）

---



## 10. 开发路线图（实现顺序）

编号即推荐顺序；**1 关注点 / 1 commit**（对齐 F2 节奏）。


| #        | 关注点                                           | 关键产物                                       | 依赖   |
| -------- | --------------------------------------------- | ------------------------------------------ | ---- |
| **C0-0** | docs：本文 + ROADMAP/VERTICAL 互链                 | `COMBAT_SYSTEM.md`                         | —    |
| **C0-1** | data：攻防倍率表 + 护甲公式 + selftest                  | `combat_damage_table.gd` + selftest        | —    |
| **C0-2** | query：敌对 / 合法目标 / 射程判定                        | `combat_query.gd`                          | C0-1 |
| **C0-3** | command：Order + SmartTarget + Handler + A 键瞄准 | Order/Smart/Router                         | C0-2 |
| **C0-4** | logic：`AttackController` 追击 + 近战瞬时伤           | `attack_controller` + `damage_pipeline` 最小 | C0-3 |
| **C0-5** | death：`DeathService` + WorldMembership + 清订单  | `death_service.gd`                         | C0-4 |
| **C1**   | Attack-Move + acquire 索敌                      | controller 扩展                              | C0-4 |
| **C2**   | cool/面向；远程 weapTp 分支（missile 壳）               | controller + 可选 present                    | C0-4 |
| **C3**   | 完整接入骰+表+护甲（若 C0-4 用了平均伤则此处替换）                 | pipeline 完备                                | C0-1 |
| **C3+**  | Present 抛光：Death Geoset、命中闪白（可选）              | present                                    | C0-5 |


建议合并策略：

- **PR1**：C0-0～C0-5 → 「点目标能打死野怪」  
- **PR2**：C1 + C2 → 「攻移 + 远程手感」  
- **PR3**：C3 公式验收 + selftest 绿灯（若未进 PR1）

之后回到竖切：**F8–F9 顶盾 ✅ → F10 技能**（技能伤害复用 `DamagePipeline`）。

```text
时间线（玩法主线）

F0–F6 ✅ ──► C0–C3（本文件）──► F8–F9 顶盾 ──► F10 技能
                 │
                 └─ 并行 Present：尸体 Geoset（已有则只接线 Death）
```

---



## 11. 风险与门禁


| 风险          | 门禁                                                       |
| ----------- | -------------------------------------------------------- |
| Director 膨胀 | 战斗逻辑不得进 `game_director.gd` 长分支；只发 Order                  |
| 双套扣血        | 禁止 Present/HUD 直接改 `META_LIFE`；审查 grep `set_meta("life"` |
| 追击抖振        | 射程用 `range+rngBuff` 进、略小滞后出（或滞回常数）                       |
| 与采集冲突       | 右键金矿/树优先 Harvest Handler；敌对单位才 Attack                    |
| Steering 滥用 | P0 可用「move_to 目标脚底」；Steering 作优化项不挡验收                    |
| 死亡泄漏        | 所有持有 `target_id` 的控制器在 `unit_died` 时失效                   |


---



## 12. 决策记录


| 日期         | 决策                                                                                                                                      |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-08-16 | 竖切插入 C0–C3，优先于 F8/F10（见 GAMEPLAY_VERTICAL）                                                                                              |
| 2026-08-17 | 单独立 `COMBAT_SYSTEM.md` 为战斗契约；与 BUILD_SYSTEM 同级                                                                                          |
| 2026-08-17 | 单位扣血唯一入口 `DamagePipeline`；树仍 `TreeRegistry.apply_damage`                                                                                |
| 2026-08-17 | `CombatSteering` 不升格为战斗系统，仅可选追击速度                                                                                                       |
| 2026-08-17 | P0 中立野怪不反击；攻防表 P0 可硬编码 + 单测                                                                                                             |
| 2026-08-17 | 推荐每单位 `AttackController` 组件（对齐 Harvest）                                                                                                 |
| 2026-08-17 | A 键：点单位=Attack，点地面=Attack-Move                                                                                                          |
| 2026-08-17 | **架构裁决**（§2.1）：坚持逻辑/表现分离；组件=Controller+共享服务（非 ECS）；OCP 靠 Handler/`StrikeRequest`/`WeaponDelivery`；弹道命中结算属 Logic                         |
| 2026-08-17 | **行为编排**（§2.1-F）：域内小 FSM + 薄 OrderArbiter；不做单位级巨型 FSM；玩家单位不用 BT；BT 仅留给电脑 AI / 复杂野怪（反击 P0 不做）                                            |
| 2026-08-17 | 命令卡常规键：`CmdAttack` / `CmdHoldPos` / `CmdPatrol` 与 Move/Stop 同列上卡；Hold=停步+旗；Attack 瞄准；Patrol=A↔B；扣血仍待 C0-4                               |
| 2026-08-17 | **C0 落地**：`CombatDamageTable` + `DamagePipeline` + `AttackController` + `DeathService`；右键 `ENEMY_UNIT` Handler；selftest_c_combat_damage |
| 2026-08-17 | **C2 落地**：`ProjectileService` + `CombatProjectileShell`；hrif=`instant` 伤在 dmgpt、壳仅 Present；真 `missile` 飞行后再 Pipeline                    |
| 2026-08-17 | **C2 Present**：PE2 脉冲 `active_sequences` 修复（枪口 Flame）；hrif 命中 `RifleImpact`；单位 `_fm2` 披风改 DEPTH_PRE_PASS+双面                             |
| 2026-08-18 | **C3 落地**：公式 selftest 扩表/负甲；死亡离场仍可见尸体（Death → Decay Flesh 定格）                                                                           |
| 2026-08-18 | **尸体移除**：Death → 播完 `Decay Flesh` → `Decay Bone`（用动画片长，不定格）后 Director `remove_unit_instance`；死亡立即释人口                                    |
| 2026-08-18 | **命中飘字**：Present `DamageFloatText` 订阅 `damage_applied`，挂受击单位                                                                            |
| 2026-08-21 | **as-built**：补 §0a；野怪反击从「战斗非目标」迁出，由 [UNIT_AI.md](UNIT_AI.md) 交付                                                                         |
| 2026-08-21 | **Hamg 普攻**：`CombatQuery` 读 `*UnitFunc` Missileart/speed/arc；真 missile 壳挂 FireBall；hrif 仍 instant+RifleImpact                                 |
| 2026-09-05 | **hwat 飞弹**：`WaterElementalMissile` 无 Stand（仅 Birth/Death PE2）；飞行壳改 Stand→Birth 并强制 LOOP，命中仍 Death                                         |
| 2026-08-21 | **弹道制导**：Logic/Present 同速追目标，命中半径结算（非物理碰撞）；目标丢失/超时不扣血                                                |


---



## 13. 维护检查清单

改战斗管线或接单位 AI 前确认：

- [x] C0–C3 已接线（见 §0a）  
- [ ] 新伤害来源只走 `DamagePipeline.apply`  
- [ ] Present 弹道 / 飘字不 `set_life`  
- [ ] 单位自主行为进 `logic/ai/`，不进 Controller 公式  
- [ ] 死亡走 `WorldMembership`（见 WORLD_MEMBERSHIP.md）