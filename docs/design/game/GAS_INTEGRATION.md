# GAS 首轮集成实现记录

2026-09-13。设计依据：[接入计划](../../roadmap/ABILITY_SYSTEM_INTEGRATION_PLAN.md)。

## 实际接入范围

Git 子模块位于 `addons/godot_ability_system`，插件开发分支为 `codex/wc3-healing-integration`。项目配置启用插件及其五个服务。游戏单位没有挂载第二套 Vital/属性/状态组件。

插件本轮本地提交：`53e1216`（0.0.2-dev）。主项目已更新暂存的子模块引用；游戏侧改动保留在工作区，未将其他并行开发内容一并提交。

治疗术链路：`HealAbility → EffectHeal → Wc3AbilityEffects.heal → Wc3HealEffect.apply_result → UnitLife`。

生命药水链路：`Inventory.try_use → Wc3AbilityEffects.heal → Wc3HealEffect.apply_result → UnitLife`。

因此两者真正共用插件效果协议及同一个治疗实现，SLK 提供各自数值。技能目标、施法流程、法力支付和技能冷却仍归原有 Ability 系统；物品归属、次数和共享冷却仍归 Inventory。只有有效治疗才提交各自原有费用，没有同时启动第二套行为树或第二份冷却。

药水回血部分已从背包移除；回蓝和装备尚未迁移。治疗术原有表现保留，本轮不包含完整道具表现升级。

## 插件通用修复

- 新增 GameplayEffectResult，区分 APPLIED、NO_EFFECT、REJECTED 和实际数值；新效果支持结果感知。旧 void 效果保留旧语义，不能声称所有插件效果都已准确报告结果。
- 无有效效果时不播放成功 Cue，也不执行子效果；行为树效果节点正确报告失败，并修正空目标、重复目标及自身回退。
- 支付失败传播为 FAILURE，默认主动模板在支付成功后才启动冷却。
- 旧多项费用没有预留/回滚协议，因此第一版明确拒绝多个费用项，不再部分扣费。通用事务型组合费用仍待后续实现；当前治疗术和药水都不走该旧多项费用路径。
- 默认参数在每次激活恢复；Feature 长期状态独立于临时黑板；禁用状态及预览实例独立。
- VitalCost 不再缓存其他单位的 Vital 组件；原生 GE_ModifyVital 返回实际变化与无效果结果。
- 取消、遗忘和组件退出释放能力实例，防止黑板自引用残留。
- 插件从自身目录注册 Autoload，效果按需获取服务，支持独立宿主及当前项目的直接脚本测试。
- 修复 Godot 4.6.3 中效果自类型数组造成的脚本退出泄漏。

插件侧迁移说明：`addons/godot_ability_system/docs/MIGRATION_EFFECT_RESULTS.md`。其中列出行为变化和仍待完成的接口，供另一个项目独立使用。

## 测试与局限

- 插件独立空宿主安装与 33 项契约检查通过，无脚本错误和退出泄漏。
- 游戏共享治疗：`tests/unit/selftest_gas_healing.tscn`，20 项，验证实际 HealAbility 和 Inventory 调用、SLK 数值、独立消耗/冷却、满血、死亡与敌我规则。
- 原有道具：57 项通过，退出无新增插件资源泄漏。
- 完整地图：16 项通过，包括真实鼠标输入使用药水和祭坛复活。最后一次运行 PASS 后仍出现 `material_set_shader: material is null` 的场景退出错误；不能将完整图形场景描述为无错误退出。
- 既有支持单位、Buff、自动施法、暴风雪、辉煌光环、山丘之王及单位 AI 回归通过。
- 扩大回归发现 `selftest_ability_mass_teleport.gd` 失败：当前英雄技能等级读取已学技能字典，测试却假设 6 级自动有 AHmt；其依赖 HarvestController 的直接 Wc3DefStore 引用也影响 `-s` 提前编译。这些代码在本轮之前已存在，未为通过测试而改变学习或经济规则。
- `selftest_ability_water_elemental.gd` 虽打印 PASS，但有 SelectableComponent 的 Wc3DefStore 提前编译错误及未入树节点坐标错误，因此不计为通过。
- 游戏编辑器全量导入遇到其他工作区 `.blend` 资产的 Blender 配置错误；新脚本已注册，插件独立空宿主导入用于单独验证安装。

测试日志在 `.cache/ability-system-tests/`；共享治疗日志为 `.cache/gas-healing.log`。插件独立测试只复制插件 scripts/tests，无 WC3 资产依赖，并将脚本错误、引擎错误和资源泄漏作为失败。

## 双仓维护

插件修改先形成子模块自己的本地提交，再由游戏仓库记录该 SHA。未自动推送远端。发布游戏引用前，必须先让插件提交在远端可获取，再提交/推送游戏引用；不可把只存在本机的插件 SHA 当作已发布依赖。

游戏适配只依赖插件公开的效果协议，通用插件代码没有反向引用 WC3 类。后续首先补可组合费用事务和来源授予句柄，再迁移装备及复杂施法；本轮不是完整能力系统替换。

[手动测试清单](../../test-cases/items/GAS_HEALING_TEST_CASES.md)
