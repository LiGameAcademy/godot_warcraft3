# 能力系统插件接入评估与双仓迭代计划

日期：2026-09-13。

后续实施：首个共享治疗切片已经落地，实际范围、已知限制和测试结果见 [GAS 首轮集成记录](../design/game/GAS_INTEGRATION.md)。下文保留初始评估，不能将其中所有计划项视为已实现。

评估对象：当前工作区（包含正在开发的道具和其他未提交功能）；插件 `LiGameAcademy/godot_ability_system`，本次下载的 main 提交 `a360f40528b7e79160466d89d73d4a7def0d7d62`。

本轮为源码评估与方案设计，没有启用插件、添加子模块或替换运行中的技能系统。以下缺陷来自静态调用链检查，尚未用插件独立运行测试复现；接入阶段应先把它们转成测试。

## 1. 结论

适合通过 Git 子模块引入，并以本项目作为真实集成样例。推荐路径是“修正插件基础契约 → 游戏适配层 → 小范围共用效果 → 逐项迁移施法流程”。现有 Resource 定义、运行时实例、Feature、行为树和 Cue 的分层可以保留，不需要为接入先全盘重写。

需要避免同一单位同时存在两套可独立写入的 HP、MP、护甲、Buff 和冷却。首阶段保留本项目的战斗状态，由插件通过适配接口访问；迁移单位是一个明确的职责，而不是一次给所有单位挂齐插件所有组件。

行为树适合组织等待、引导和复杂阶段。简单治疗仍然是可直接执行的效果，不必强制每瓶药水配置复杂树。

## 2. 当前游戏已经具备的基础

| 当前模块 | 实际行为 | 迁移判断 |
|---|---|---|
| AbilityCastController | 接近、前摇、引导、取消；引导直接关联 BlizzardZone | 保留 RTS 接近与订单，逐步把通用施法生命周期移到插件 |
| AbilityExecutor / 具体 Ability | 按目标种类和 behavior 分发；具体技能再做校验、效果、表现和扣费 | 可逐项替换，不能在上层和技能内部重复提交消耗 |
| EffectHeal / EffectApplyBuff 等 | 已有可复用的效果原子，但仍依赖 WC3 数据及项目组件 | 作为适配起点；治疗数值解析与治疗执行分离 |
| AbilityCastRules | 法力、冷却、距离检查及提交 | 距离属于游戏；消耗与冷却可通过桥接实现单一写入 |
| Inventory.try_use | 自行恢复生命/魔法并扣次数、设置冷却 | 优先迁出回血/回蓝执行，保留背包归属和槽位事务 |
| DamagePipeline / DeathService | 项目伤害及死亡结算链 | 首阶段保留，插件伤害不能绕过它直接扣另一份 HealthVital |
| BuffHost / BuffQuery | 限时状态、护甲等查询；背包装备按实例加成 | 首阶段保留，不双写到 GameplayStatusComponent |
| AbilityFxCatalog / Presenter | WC3 动画、挂点、模型、音效表现 | 用 Cue 适配调用，继续利用已有资源转换体系 |

## 3. 插件接入前的具体检查项

源码链接固定到本次审查提交，避免后续 main 更新造成结论错位。

### P0：支付与效果结果

- [AbilityNodeCommitCost](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/abilities/ability_nodes/ability_node_commit_cost.gd) 调用 `try_pay()` 后直接返回 SUCCESS，没有传播失败。提交时法力或道具已不足仍可能继续执行。
- [CostFeature](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/abilities/features/cost_feature.gd) 按顺序支付多项费用；后一项失败时没有撤销已支付项。
- [GameplayEffect](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/effects/gameplay_effect.gd) 的 apply/_apply 返回 void；通过过滤之后，即使具体效果因缺组件而直接返回，基类仍会继续 Cue 和子效果。
- [AbilityNodeApplyEffect](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/abilities/ability_nodes/ability_node_apply_effect.gd) 无有效目标/效果时也返回 SUCCESS。无法直接表达“满血，无效果，不消耗药水”。
- [ActiveAbilityDefinition](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/abilities/definitions/active_ability_definition.gd) 默认流程先提交冷却，再支付，再搜索目标。该策略不能直接用于要求无有效效果不扣费的药水。

建议引入结构化 EffectResult（至少 outcome、reason、actual_amount），区分 applied / no_effect / rejected / pending。BT 的 SUCCESS/FAILURE/RUNNING 用于流程推进，不能替代效果结果。普通攻击发射成功后未命中与满血药水拒绝使用，提交语义不同，必须可配置。

费用协议建议为 validate → reserve → commit/release。延迟施法在生效点再次检查目标和来源。组合费用先校验/预留所有项；只有同一次 activation 可以提交，且最多一次。不可逆效果不能靠“事后把 HP 加回去”回滚；即时效果在一个同步提交段处理，投射物/引导在明确的释放点提交。

### P0：定义、长期状态与单次施法状态

- [GameplayAbilityDefinition](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/abilities/gameplay_ability_definition.gd) 在创建实例时注入 blackboard_defaults；[GameplayAbilityInstance](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/abilities/gameplay_ability_instance.gd) 在新激活时清空整个黑板，却未重新注入默认值。
- Feature 长期数据也使用同一个黑板，包括冷却和已应用被动状态记录。不能把它与一次施法的临时变量一起清掉。正常冷却检查在清空之前，因此不能简单概括为“所有技能均可绕过冷却”；问题是存储生命周期混在一起。
- Definition 的 preview_strategy 被实例直接使用，而 [GroundIndicatorPreviewStrategy](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/abilities/targeting/strategies/preview_strategies/ground_indicator_preview_strategy.gd) 含 indicator、caster、鼠标位置等可变状态；多个实例共享同一资源存在相互覆盖风险，其 begin 也未给成员 caster 赋值。

建议保留不可变 Definition / 行为树配置，运行状态分成 AbilitySpec（授予来源、等级、启停及长期状态）和 ActivationContext（本次目标、流程内存、取消状态）。预览运行状态独立创建；不要一律深拷贝所有资源来掩盖边界问题。

### P0：同类道具需要多个授予实例

[GameplayAbilityComponent](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/components/gameplay_ability_component.gd) 按 ability_id 存储一个实例并拒绝重复学习。这适合“一个单位学会一种技能”，不足以表示两瓶同类药水、两枚同类指环。

建议增加 GrantHandle（来源授予句柄）：definition_id 可以相同，但 grant_handle 和 source_instance_id 不同。技能等级、物品次数、共享冷却组是不同概念。按句柄移除装备贡献，不能遗忘一个 definition_id 时删掉另一个来源的加成。

[PassiveStatusFeature](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/scripts/abilities/features/passive_status_feature.gd) 记录 status_id 并按 status_id 移除，迁移装备前需要支持应用句柄/来源贡献撤销。

### P1：取消、安装和调度

- 无参数 cancel_ability 直接访问当前施法实例，需要空值保护；结束只调用 on_completed，Feature.on_cancel 的语义需要接通。死亡、遗忘、场景卸载都应有明确释放入口。
- [plugin.gd](https://github.com/LiGameAcademy/godot_ability_system/blob/a360f40528b7e79160466d89d73d4a7def0d7d62/plugin.gd) 使用 `scripts/singletons/...` 注册 Autoload，没有从插件目录构造路径。按 addons 子模块安装时应修正并在干净宿主验证，不依赖根目录恰好存在同名 scripts。
- 组件当前每帧遍历全部已学技能并更新 Feature。应允许外部统一 tick，优先调度活跃执行及有计时状态的实例；先压测再决定是否优化，不声称目前已有性能瓶颈。
- 游戏道具/Buff 使用进程时间，插件冷却使用 delta；先明确暂停、time_scale、死亡和地面道具冷却的语义，再注入统一会话时钟。复活快照不保存 Node 指针或整棵行为树。

## 4. 推荐的项目适配边界

以下名字是拟议接口，不是已存在的插件 API。

```text
玩家命令 / AI 决策 / 自动施法 / 道具槽位
                    ↓
          游戏 AbilityFacade
                    ↓
    AbilitySpec + ActivationContext + 效果/流程
                    ↓
      Wc3AbilityAdapter（游戏仓库内）
         ├─ 生命/魔法 → UnitLife / UnitMana
         ├─ 伤害 → DamagePipeline → DeathService
         ├─ 状态/装备 → BuffHost / 属性贡献句柄
         ├─ 距离/目标 → CombatQuery / Wc3Coords
         └─ Cue → 现有动画、模型、挂点和音效 Presenter
```

插件负责通用生命周期、来源句柄、效果结果、费用协议、计时接口和执行取消；游戏负责 WC3 数据解析、攻击护甲表、阵营关系、地图坐标、寻路、订单、背包、复活规则和资源路径。

插件当前的 GE_ModifyVital、GE_ApplyDamage 直接依赖插件 Vital/HealthVital，不能原样挂到现有单位。首阶段新增项目侧桥接效果/后端接口，并只写现有状态；后续若整体迁移某项属性，再一次性切换该属性的权威存储。

SLK 继续是游戏数值来源，由工厂转换成能力配置。不要手工再维护一套相同技能数值的 tres。Resource 适合存行为模板、组合方式和插件独立示例。

AI 与玩家共用执行入口，AI 只负责选择使用者、能力和目标。RTS 的接近目标由订单/导航负责；首阶段已有 AbilityCastController 保留前摇时，插件只执行即时效果，不能再加一次相同前摇。

## 5. 首个验证切片与后续顺序

| 阶段 | 交付 | 通过条件 |
|---|---|---|
| A：插件基础修正 | 支付失败传播、效果结果、状态生命周期、安装路径；独立宿主测试 | 干净安装可启动；默认参数不丢；支付失败无效果/无冷却；取消可重复调用 |
| B：治疗术 + 生命药水 | 同一个治疗效果执行实现，两种来源和消耗策略 | 治疗术只扣魔法；药水只扣次数；满血药水不扣；没有双重治疗/扣费 |
| C：魔法药水 + 两枚指环 | 回蓝效果、同定义多来源、来源撤销、共享冷却桥接 | 共享冷却转交不重置；丢一枚只减一枚加成；死亡复活无复制 |
| D：风暴之锤 | 单位目标、投射物、眩晕、现有伤害死亡链 | 目标失效与施法取消处理正确；命中只结算一次 |
| E：暴风雪 | 通用引导和周期效果；取消清理 | 移动/停止/眩晕/死亡中断后不残留伤害和表现 |
| F：其余能力 | 召唤、传送、自动施法和复杂状态逐项迁移 | 对应旧测试与真实场景通过后删除该能力旧入口 |

首轮接入应只覆盖 A+B，完成后实际手动测试再扩大范围。不是等插件“完美”才验证，也不是先替换所有能力再排错。

为每个能力设置明确后端归属。运行中已选插件后端的能力失败时，不得自动补跑旧后端，否则可能重复效果；回退通过配置在下一次测试/对局选择旧实现。核对数值时可以做只读校验，不能同时执行两套副作用。

## 6. Git 子模块与双仓协作

推荐落点：`addons/godot_ability_system`。上游仓库根就是 plugin.cfg/scripts，适合直接作为该路径的子模块，不需再嵌套一层 addons。

建议在第一批接入实施时添加子模块，固定 SHA；本次缓存克隆只用于评估。插件需要改造的通用部分直接在子模块自己的开发分支维护，WC3 适配代码放游戏仓库的 `game/scripts/integration/ability_system/`。

每个验证切片按以下顺序交付：

1. 插件仓库建立 `codex/` 前缀开发分支；补回归用例，再改通用能力接口。
2. 游戏仓库开发适配代码，在工作区用插件新代码跑集成测试。
3. 插件独立测试及游戏集成测试通过后，先提交插件，再提交游戏代码及其子模块 SHA。
4. 需要推送/发布时，确保插件提交先在远端可获取，再推送引用它的游戏提交；不能留下只有开发机能找到的 SHA。
5. 干净克隆使用递归子模块初始化复验；CI 固定已提交 SHA，不追踪 main 最新版本。
6. 有破坏性接口变更时同步提供迁移说明和插件独立样例，游戏适配层承担项目差异。

插件测试使用最小假宿主，不依赖本项目资产；游戏测试负责验证 WC3 伤害、背包、寻路、死亡/复活、输入和表现接线。这样才能判断插件本身可复用，而不只是“在一个大项目里勉强跑通”。

## 7. 必须保留的验收场景

- 两个单位共享同一能力 Definition，冷却、黑板、预览和取消互不影响。
- 一个英雄持有两瓶同类药水、两枚同类指环；实例身份、消耗和装备贡献独立。
- 预检查后资源发生变化，提交失败不产生效果；多项费用不会部分扣除。
- 满血药水 no_effect；成功释放的投射物随后失去目标按其提交策略处理，不能混用规则。
- 同次 activation 重复通知不重复支付或结算；取消/死亡/忘记能力/卸载清理一次。
- 自动施法与手动施法在同一单位上不会重复提交；不允许多套 tick 推进同一实例。
- 暂停、加速、道具丢弃/转交、死亡与复活使用一致的冷却规则。
- 治疗术、生命药水通过同一个治疗后端，并保留各自表现配置。
- 卸载本局后无遗留定时执行、事件订阅、Cue 或授予实例。

建议下一次实施任务：完成 A+B，交付子模块、最小能力适配层、治疗术与生命药水共用效果，以及针对该切片的手动测试清单。
