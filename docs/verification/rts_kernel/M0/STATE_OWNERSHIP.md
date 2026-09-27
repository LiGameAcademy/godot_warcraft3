# M0 权威状态迁移台账

日期：2026-09-27。状态：初版源码审计，迁移时持续更新。

## 使用规则

每次切换以一类权威状态为单位。`旧写入者` 尚未全部移除时，新内核不能同时推进同一字段；允许旧侧只读镜像。每个工作包需补充具体函数和测试，不把本表当作完整逐行审计。

| 状态 | 当前权威 / 代表写入者 | 已发现的隐式载体 | 目标权威 | 切换里程碑 |
|---|---|---|---|---|
| 实体身份与类型 | `EntityRegistry`、`UnitsModule`、Map unit layer | Node、`unit_data` meta、creationNumber、instance_id | Match/Entity lifecycle + EntityId | M1，完整生成在 M4/M5 |
| 位置与朝向 | `UnitNavigator`、`UnitsModule` | Node3D global_position/rotation | Navigation state | M2 |
| 路径、预约、群体落点 | PathQuery、PathCellReservation、UnitMoveSlots | RefCounted/Dictionary/Node 引用 | Navigation systems | M2 |
| 订单与模式 | CommandRouter、OrderQueue、PatrolController、UnitAI | `order_queue`、hold/attack_move meta | Commands/Orders | M2–M3 |
| 生命与建造状态 | UnitLife、DamagePipeline、DeathService、BuildModule | life/max_life/under_construction meta | Health/Damage + Build state | M3/M4 |
| 攻击与目标 | AttackController、CombatQuery、UnitAI | Node 控制器字段、目标 Node | Combat state | M3 |
| 逻辑弹道 | ProjectileService | Array[Dictionary]，attacker/target Node | Projectile state | M3 |
| 玩家资源与人口 | GameSession/PlayerStock、Build/Production 模块 | RefCounted、session stocks、food_released meta | Economy state | M4 |
| 采集、携带、矿木 | HarvestController、GoldMineRuntime、TreeRegistry、CarrySlot | Node/meta/控制器字段 | Harvest state | M4 |
| 建造、占地、训练、集结 | BuildController/Site、ProductionOrders/Queue、BuildingRally | Node/meta、动态 pathing | Build/Production state | M4 |
| 科技 | PlayerStock upgrades、TechPresence | mutable static session WeakRef、Node 查询 | Technology state | M4 |
| 法力、冷却、施法 | UnitMana、AbilityCooldowns、AbilityCastController | Node meta、Node 控制器、float 倒计时 | Ability/Cast state | M5 |
| Buff、属性修正、被动 | UnitStatusEffects、BuffHost、各专用 controller | Node/meta、信号订阅 | Buff/Attribute systems | M5 |
| 英雄等级/经验/死亡 | HeroProgression/Experience/DeathRegistry | Node meta、mutable static Dictionary | Hero state | M5 |
| 物品与商店 | Inventory、ItemService、ShopService、ItemsModule | Node/meta/RefCounted | Item/Economy state | M5 |
| 单位 AI | UnitAI、TeamRegistry | Node target、meta、逐帧 delta | Unit AI state | M3/M6 |
| 玩家 AI | PlayerEconomyAI、PlayerArmyAI | Node 查询、直接服务引用 | Match-owned AI state，提交标准命令 | M4/M6 |
| 随机数 | GameDirector、MatchBootstrap、CombatRng、MeleeBootstrap | randomize 后的 Godot RNG、测试序列 | 可保存的 match RNG streams | M1 起，M6 收口 |
| 胜负、阶段与重开 | GameSession、MatchLifecycleModule、GameDirector | 信号与场景生命周期 | Match state | M6 |
| 选择、相机、HUD、特效 | Godot client/presentation | Node/Control/本地时间 | 继续由 Godot 视图拥有 | 不迁入内核 |

## 首批必须消除的全局状态

- `TechPresence._session_ref`：对局级可变 static，阻止多实例隔离。
- `HeroDeathRegistry._dead_by_owner`：对局级可变 static，必须进入 Match。
- GameDirector/CombatRng/MeleeBootstrap 的 `randomize()`：不能用于确定性模拟。
- Catalog 中只读缓存可以保留在内容层，但必须冻结并以内容版本区分；不得引用当前对局。

## M1 桥接约束

- Godot Node 仅保存 EntityId 和表现资源；不持有可反写的 C# 状态对象。
- 每帧批量读取视图/变更，禁止 GDScript 对每个字段进行高频跨语言 Get/Set。
- 迁移中的命令必须记录从旧输入到新 CommandEnvelope 的转换；执行结果返回明确错误。
- 快照恢复创建新 Match 实例，不能在旧实例上半覆盖；成功后再替换宿主引用。
