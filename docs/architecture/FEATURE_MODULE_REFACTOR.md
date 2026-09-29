# 功能模块与目录的渐进重构

日期：2026-09-13。基线：`03d3ec2`；开始本轮重构前，后续小地图差异、插件 UID 和资源忽略规则已分别提交，主仓库及插件子模块均无未提交差异。

## 目标与边界

教程按功能推进，目录也按功能组织。以 `game/features/<feature>/` 聚合一个功能的应用入口、规则和表现，内部按实际需要区分 `logic/`、`presentation/`、`data/`。地图、共享基础设施和资产管线保持原有边界。

`GameDirector` 最终只负责对局装配、启动与关闭。玩法模块使用对局内节点，跨场景资产访问和定义表沿用现有 Autoload。不要以全局单例替代显式依赖，也不要将总管作为万能上下文传给模块。

本文件描述当前迁移过程；旧架构文档中的历史设计不代表所有目标已经实现。

## 第一批：生产功能（已实现）

目录见 [game/features](../../packages/gameplay/features/README.md)。

### 运行路径

```text
玩家输入 → ProductionPanel → CommandRouter → ProductionOrders
电脑决策 ──────────────────→ CommandRouter → ProductionOrders
                                               ↓ 校验、扣费、入队
                                            TrainQueue
                                               ↓ 完工 / 取消
                                        ProductionModule
                                          ↓           ↓
                                 UnitsModule.spawn_trained
                                 UnitsModule.ensure_hero
                                          ↓
                                 信号 → ProductionPanel → HUD
```

- `ProductionOrders` 从 `CommandRouter` 迁出训练和研究校验、扣费及满队列回滚。每个命令路由器持有自己的实例，使用自己的命令玩家；路由器保留原公开 API 与通知信号。
- `ProductionModule` 接管训练/研究完工、复活事务和状态恢复、取消退款、生产终止与队列订阅。研究和退款按订单 owner 结算，不按本地玩家或建筑当前 owner 结算。
- `ProductionPanel` 接管选择相关的生产请求、可读的失败反馈、队列进度以及建筑工作表现。界面保留原有预检查，权威训练/研究校验仍在 `ProductionOrders`，复活事务在 `ProductionModule`。
- `TrainQueue`、`TrainSpawn`、`BuildingRally` 及其 UID 已迁入功能目录；类名不变。
- 模块初始化正常情况下在命令入口就绪后完成。旧测试或局部调用仍可通过总管的窄入口触发惰性装配。
- 每个队列只订阅一次，离树时移除订阅；模块退出或销毁时断开所有订阅并释放注入接口。对局退出不通过退款信号结算已卸载的会话。
- 复活入口明确拒绝无库存的命令玩家，并使用原订单玩家库存；无需 HUD 或选择器即可测试和调用。

### 第一批刻意保留的迁移接缝

- ~~单位创建、导航/AI/英雄组件装配、动态寻路刷新和训练后集结仍在总管~~ → 已由第二批 `UnitsModule` 接管；生产模块继续只拿 `spawn_trained` / `ensure_hero` 两个 Callable。
- 总管保留生产输入转发、命令卡生成及综合建造/生产选中面板协调。`_wire_train_queue`、`_apply_revived_hero_state` 等旧入口只转发，方便现有场景和测试逐步迁移。
- 训练与研究的界面预检查和权威检查仍有重复。后续可用带失败原因的结果类型合并；本批优先保持原有中文提示和行为。
- 不引入 ECS、通用模块框架、全局事件总线，也不增加玩法 Autoload。

### 验收入口

这些测试是场景，必须以场景参数运行，不使用 `-s`：

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_production_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_production_owners.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_hero_life_game.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_player_army_game.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_match_end_game.tscn -- --restart
```

独立模块测试覆盖生成接口、重复接线只结算一次、卸载后不再结算、重新装配会话隔离、队列离树清理，以及非本地玩家复活扣费/取消/资金不足。既有测试保护生产归属、退款、研究授予、建筑终止、英雄状态、电脑完整场景和重开行为。

## 第二批：单位模块（已实现）

目录：`game/features/units/units_module.gd`。

### 职责

- 训练出生：`spawn_trained`（出口/挤位、`UnitLife`、战斗 AI、英雄装配、动态寻路刷新、集结派遣）。
- 组件装配：`ensure_combat_ai`、`ensure_hero`、`wire_existing`（地图单位批量挂 AI/英雄 + `TeamRegistry` 营地聚类）。
- 运行时编号：`alloc_creation_number`（建造半成品等也经总管转发共用）。
- 坐标：`teleport_wc3`。

### 依赖方向

总管装配并注入 `MapLoader` / 高度场 / 寻路查询 / `CommandRouter` / 血条，以及导航、攻击控制器、单位宿主、背包变更、英雄被动等 Callable。`UnitsModule` 不依赖 `GameDirector` 类型。`ProductionModule` 只接收模块上的两个方法引用。

### 刻意未迁

- 召唤、建造完工入图、复活刷回仍可走总管窄入口；后续批次再统一到单位模块并保留来源差异配置。
- `AttackController` 仍由总管创建，经 Callable 注入。
- 建造工地 / 战斗伤害 / 技能物品运行时另批处理。

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_units_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_production_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_production_owners.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_hero_life_game.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_player_army_game.tscn
```

## 第三批：建造模块（已实现）

目录：`game/features/build/build_module.gd`。

### 职责

- 工地注册表：`register_site` / `unregister_site` / `find_site` / `find_site_for_node`（`%s_x_y` 编码）。
- 半成品设备：`on_construction_started` / `on_construction_completed` / `on_construction_cancelled`，内部维护 `_active_construction`。
- 放置视觉：`begin_placement` / `update_placement_screen` / `commit_placement` / `cancel_placement`（与 `BuildPlacementController` + `BuildPlacementGhost` 协同）。
- 工地钉住幽灵：`pin_site_ghost` / `clear_pinned_ghost`。
- HUD 工地绑定：`sync_hud_for_selection` / `bind_hud_site` / `unbind_hud_site`；运行进度走 `progress_changed`。

### 依赖方向

`MapLoader` / 高度场 / 寻路查询 / `CommandRouter` / `GameSession` / 血条 / HUD 等经 `configure(Dictionary)` 注入；查找动画玩家、单位视觉、`UnitLife.set_ratio` 等以 Callable 注入。`BuildModule` 不依赖 `GameDirector` 类型。

### 刻意未迁

- 召唤完工、复活刷回未迁移（仍经 Director / UnitsModule 接口进入地图）。
- `BuildController` 仍由 Director 装配；信号转发到 BuildModule 的 `on_construction_*`。

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_build_module.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_build_module_game.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_hero_life_game.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_player_army_game.tscn
```

## 第四批：战斗模块（已实现）

目录：`game/features/combat/combat_module.gd`。

### 职责

- 服务所有权：`DamagePipeline` / `DeathService` / `ProjectileService` 在模块内创建并接线。
- `ensure_attack_controller`：挂/刷新单位 `AttackController`。
- `kill` / `tick`：死亡入口与弹道步进。
- 表现：弹道壳、伤害飘字、技能命中 FX、尸体 linger / `remove_unit_instance`。
- 死亡横切：Buff / 物品准备 / 库存清空 / 控制器停机；食物释放与生产终止经 Callable 注入。

### 依赖方向

总管注入 `MapLoader`、血条，以及导航、单位视觉、食物、生产终止、物品死亡准备、选中清理、HUD 刷新等 Callable。`CombatModule` 不依赖 `GameDirector` 类型。`UnitsModule` 仍经总管 `ensure_attack_controller` 转发接入。

### 刻意未迁

- `DamagePipeline` / `DeathService` / `ProjectileService` / `AttackController` 脚本仍在 `game/scripts/logic/combat/`（本批只抽装配与协调）。
- 技能瞄准 / 命令卡 / 物品 HUD 仍在总管；下一批再收敛。
- `_release_unit_food` 仍属会话库存，留在总管。

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_combat_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_death_once.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_hero_life_game.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_player_army_game.tscn
```

## 第五批：技能与物品模块（已实现）

目录：
- `game/features/abilities/abilities_module.gd`
- `game/features/items/items_module.gd`

### 职责（AbilitiesModule）

- 持有 `AbilityCastContextFactory` / `AbilityHudFeedback` / `AbilityRuntimeRegistry` / `AbilityTargetingService`
- `ensure_unit` / `ensure_hero_passives` / `ui_state_for` / `cast_context`
- 瞄准：`begin_targeting` / `issue_*` / `set_targeting` / `cancel_targeting`
- 引导：`clear_caster_orders` / `channel_interrupt_check` / `interrupt_channels`
- 预览：`update_preview` / `clear_preview`（AHbz / AHmt）

### 职责（ItemsModule）

- 创建 `GroundItems` 宿主与 `ItemService`
- `use_slot` / `drop_slot` / `swap_slots` / `prepare_hero_death`
- 订阅 `CombatModule.connect_unit_died`；地面生成接 `GroundItemVisual`

### 依赖方向

技能模块注入战斗管线与选择/命令回调；物品模块注入 Combat + 高度场。二者都不依赖 `GameDirector` 类型。总管保留输入互斥、命令卡分发、英雄学习菜单与 GM 入口转发。

### 刻意未迁

- `logic/ability/*`、`logic/item/*` 脚本仍留在原目录（本批只抽装配协调）。
- SmartTarget 拾取射线、命令卡总调度仍在总管（交互瞄准已抽到 InteractionModule；命令卡仍待收敛）。

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_abilities_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_items_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_item_system.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_hero_life_game.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_player_army_game.tscn
```

## 第六批：交互模块（已实现）

目录：`game/features/interaction/interaction_module.gd`。

### 职责

- 互斥瞄准状态机：`MOVE / ATTACK / PATROL / HARVEST / RALLY / ABILITY / BUILD`。
- 光标同步：`apply_aim_cursor` / `end_aim_cursor`；友方技能 → `ALLY`，集结/建造 → `SELECT`。
- `flash_move_confirm`：先退出瞄准再闪箭头，避免 `set_move_targeting(false)` 掐死 flash。
- `adopt_external_aim` / `acknowledge_external_end`：对接 Abilities/Build 模块的自管瞄准生命周期。
- 选中变化 / Esc：`cancel_aim` 统一清态（含 ability↔build 互斥）。

### 光标修复要点

- `Wc3GameCursor` 增加 `apply_aim_cursor` / `end_aim_cursor` / `set_ally_targeting` / `set_select_targeting`。
- 退出 MOVE sticky 时不误杀紧随其后的 `flash_move`。
- 建造 commit 后用 `acknowledge_external_end`，避免再 `cancel_placement` 清掉钉住幽灵。

### 刻意未迁

- 命令卡按钮生成、热键绑定、二级建造/英雄技能菜单仍在 `GameDirector`。
- 悬停 INVALID 光标本批不做。

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_interaction_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_abilities_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_build_module.tscn
```

## 第七批：命令卡模块（已实现）

目录：`game/features/command_card/command_card_module.gd`。

### 职责

- 刷卡：`refresh` / `refresh_move_executing_ui` / `apply_building_train_card`
- 热键表 + `try_hotkey`；二级建造/英雄菜单 + `handle_submenu_escape`
- Action 分发：`dispatch_action` / `dispatch_action_rclick`（执行经 Callable）
- 选中命令卡分支：`on_selection_changed`（金矿/敌方/训练/移动者）

### 刻意未迁

- `CommandCard` 数据组装仍在 `game/scripts/logic/command/`
- 选中详情 / 肖像 / buff 条仍在总管
- `_issue_*` / `_begin_*_targeting` 命令执行仍在总管

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_command_card_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_interaction_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_abilities_module.tscn
```

## 第八批：选中 HUD 模块（已实现）

目录：`game/features/selection_hud/selection_hud_module.gd`。

### 职责

- 肖像：`setup_portrait` / `refresh_portrait_vitals` / `refresh_portrait_timed_life_bar`
- Buff / 攻甲芯片：`refresh_buff_strip`
- 选中详情：`apply_selection_info` / `sync_panel` / `bind_inventory_for`
- 帧 tick：保留轮询（TODO：改信号驱动）

### 刻意未迁

- `_sync_build_hud_for_selection` / 训练队列 HUD 仍在总管（经 Callable 注入 sync）
- ~~`path_debug`、GM 面板~~ → 第十 / 十二批已迁出

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_selection_hud_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_command_card_module.tscn
```

## 第九批：单位出生来源补齐（部分实现）

扩展：`game/features/units/units_module.gd`。

### 新增

- `build_building_entry` / `build_unit_entry` / `spawn_entry` / `spawn_near`
- `find_owned_unit_by_types`
- 开发刷兵、GM 野怪、建造 entry 经总管薄转发接入

### 刻意未迁

- ~~`EffectSpawnSummon` 仍直接 `add_unit_instance`~~ → 第十批已接入 `spawn_summon`
- ~~`_bootstrap_melee` / `_spawn_opponent_base` 仍属会话开局~~ → 第十一批已迁入 MatchBootstrapModule

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_units_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_build_module.tscn
```

## 第十批：召唤接入 + 路径调试（已实现）

### 召唤

- `UnitsModule.spawn_summon`：Birth / InteractionSetup / SummonLifetime
- `EffectSpawnSummon` 优先 `ctx.spawn_summon`；无注入时回退直刷
- Abilities ctx 工厂注入 `spawn_summon`

### 路径调试

目录：`game/features/debug/path_debug_module.gd`。

- 持有 `PathDebugDraw`；`ensure_draw` / `tick` / `set_enabled`
- 总管 F9 与 `_process` 只转发

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_units_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_path_debug_module.tscn
& $env:GODOT --headless --path . res://tests/unit/selftest_abilities_module.tscn
```

## 第十一批：对局开局（已实现）

目录：`game/features/match/match_bootstrap_module.gd`。

### 职责

- `bootstrap_melee`：创建 `GameSession`、选 sloc、本地基地刷兵、镜头落点、对手基地、动态 pathing 刷新
- `spawn_opponent_base`：双人开局对手库存注册（总管保留薄兼容入口供集成测试）

### 刻意未迁

- ~~`_setup_match_end` / `_restart_match` / OpponentEconomy 装配仍在总管~~ → 第十三批已迁出结束/重开；第十四批已迁出 OpponentEconomy
- ~~GM / Perf 面板装配仍在总管~~ → 第十二批已迁入 DebugToolsModule
- `MeleeBootstrap` / `MeleeRacePreview` 静态规则类位置不变

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_match_bootstrap_module.tscn
& $env:GODOT --headless --path . res://tests/integration/selftest_two_player_start.tscn
```

## 第十二批：调试工具（已实现）

目录：`game/features/debug/debug_tools_module.gd`。

### 职责

- GM 面板 / 性能叠层：`ensure_gm_panel` / `toggle_gm_panel` / `ensure_perf_overlay` / `toggle_perf_overlay`
- 英雄 GM：`hero_level_up` / `hero_max_level` / `hero_learn_one_point` / `hero_unlock_all_skills`
- 物品 GM：`item_test_kit` / `item_test_vitals` / `item_test_death` / `item_test_creep`
- 总管保留 `gm_*` 公开薄转发（`GmDebugPanel` 与集成测试仍调总管）

### 刻意未迁

- `GmDebugPanel` / `PerfOverlay` 表现类仍在 `game/scripts/presentation/`
- ~~对局结束 / 重开仍在总管~~ → 第十三批已迁出

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_debug_tools_module.tscn
```

## 第十三批：对局结束 / 重开（已实现）

目录：`game/features/match/match_lifecycle_module.gd`。

### 职责

- `setup_match_end`：武装 `GameSession.arm_match` 并连接 `match_finished`
- 结算屏挂接与退出；`restart_match` 复制导出设置并排队 `MatchRestart`
- `_process` 内 `evaluate_match` 仍由总管轮询（触发会话信号）

### 刻意未迁

- ~~OpponentEconomy / OpponentArmy 装配仍在总管~~ → 第十四批已迁入 OpponentAiModule
- `MatchResultScreen` / `match_restart.gd` 类位置不变

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_match_lifecycle_module.tscn
```

## 第十四批：对手电脑挂接（已实现）

目录：`game/features/match/opponent_ai_module.gd`。

### 职责

- `setup`：为对手玩家创建独立 `CommandRouter` + `OpponentEconomy`，可选 `OpponentArmy`
- `observe_enemies`：全图可见敌方单位（迷雾前占位）
- 节点仍挂在总管下，集成测试路径 `get_node("OpponentEconomy")` 不变
- 总管保留 `_setup_opponent_economy` 薄转发

### 刻意未迁

- `player_economy_ai.gd` / `player_army_ai.gd` 决策实现仍在原目录
- 迷雾 / 真实视野观察接口未做

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_opponent_ai_module.tscn
```

## 第十五批：智能右键（已实现）

目录：`game/features/interaction/smart_command_module.gd`。

### 职责

- `resolve_smart_target`：道具 / 矿 / 树 / 交货 / 工地 / 敌方 / 地面优先级解析
- 交互闪选：`flash_smart_interact_target` / `flash_tree_target`
- `format_smart_status`：HUD 状态文案

### 刻意未迁

- `_ground_at_screen` 拾取仍在总管（经 Callable 注入）

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_smart_command_module.tscn
```

## 第十六批：命令输入下发（已实现）

目录：`game/features/interaction/command_input_module.gd`。

### 职责

- `issue_*` / `begin_*`：停步、保持、攻击、巡逻、智能右键、集结、移动、队形、采集、送回、顶盾
- `try_handle_aim_input`：移动/攻击/巡逻/采集/集结瞄准态的鼠标确认与取消
- `try_handle_smart_rmb`：右键智能 / Shift+RMB 队形
- 瞄准态仍由 `InteractionModule` 持有；`SmartTarget` 仍由 `SmartCommandModule` 解析

### 刻意未迁

- `_ground_at_screen` / 光标闪选 / 移动确认特效仍在总管（Callable 注入）
- 技能瞄准、建造瞄准、命令卡 action 分发仍在各自模块 / 总管薄转发

### 验收入口

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_command_input_module.tscn
# 再跑 game_main 冒烟：移动 / A / 右键智能 / Shift+RMB
```

## 后续批次（尚未实施）

总管装配面已明显变薄。后续可按需收敛：建造瞄准细节、或继续把仍留在总管的薄转发改为测试直调模块。

每批先确认工作区状态，再迁移一个可独立验收的功能；通过相关回归后单独提交。目录移动、类型变化和行为变化尽量避免在同一批同时扩大范围。


## 2026-09-23：导航模块与既有模块收尾

本批实现以 `game/features/README.md` 和 `navigation/README.md` 为当前边界说明：

1. `NavigationModule` 接管导航服务生命周期、导航组件创建/配置、移动参数和动态寻路刷新。Director 只保留只读服务转发和少量兼容入口；消费者的导航回调直接绑定模块。
2. 删除 Director 的工地宿主和注册表，玩家与 AI 的命令路由器直接查询 `BuildModule`。查询过滤已取消/释放工地。
3. 删除 Director 的普通命令/技能瞄准镜像及同步回调；`InteractionModule` 统一控制选择器启用状态。技能具体数据仍在技能模块。
4. 四个导航脚本连同 UID 迁入功能目录；没有改动寻路算法或增加玩法 Autoload。

后续批次仍是采集生命周期、单位形态/模型表现、交互拾取与反馈，以及最后的对局装配整理。本批没有把这些剩余职责搬入新的通用管理器。

验收包括导航模块重绑/释放、工地注册表与真实路由器一致性、瞄准/命令卡/路径调试、群体移动、寻路组合、上一轮性能回归，以及真实双人对局重开。上述均为无渲染功能验证，不代表长期卡顿已解决，也不换算为游戏 FPS。


本批验证结果（Godot 4.7.2）：

| 测试 | 结果 |
|---|---|
| NavigationModule | PASS，14 项 |
| BuildModule / 真实地图建造 | PASS，17 / 13 项 |
| InteractionModule / CommandInputModule | PASS，16 / 8 项 |
| CommandCardModule / PathDebugModule | PASS，9 / 3 项 |
| 第二轮热点回归 | PASS，1098 项 |
| 群体移动 / 寻路组合 / steering override | 三组 PASS |
| 对战结束及重开 | PASS，23 项 |

共 12 组无渲染测试通过，最终日志无 GDScript 解析或运行错误。编辑器导入成功注册新类；沙箱下仍有用户目录日志/编辑器设置写入权限和系统证书读取提示，另有既有资源路径大小写警告。没有在本批重新执行有渲染或 30 分钟性能验收。

GameDirector 从 2949 行降至 2708 行。剩余体积主要来自尚未迁移的采集/形态/输入表现逻辑、兼容入口和模块装配，后续继续按功能边界迁移。


## 2026-09-23：四波次后续实现与验收

在 `e5e21e2` 基线上继续按功能拆分，每波回归后提交：

| 波次 | 结果 |
|---|---|
| 1：采集（28ec0e7） | HarvestModule 统一采集装配、树木和金矿生命周期；保留会话资源账本，接入变化信号 |
| 2：单位（0688dae） | UnitFormService 处理民兵/升级事务；UnitModelPresenter 处理模型与动画重绑 |
| 3：交互（28feb73） | MatchInputController、WorldPicker、InteractionFeedback 分别负责输入、拾取和反馈 |
| 4：装配（本提交） | 对局启动与显式重绑形成依赖阶段，普通获取不再构造依赖字典；清理 37 个无调用方的私有适配 |

当前目录与接口以 `game/features/README.md` 及各功能 README 为准。模块仍随对局销毁，没有新增玩法 Autoload、全局事件总线或服务定位容器。

### 行为与边界

- 金矿信号用同一个带参数 Callable 查重；组件跟踪随节点退出释放，旧对局的延迟倒塌回调不能作用于新绑定。
- 民兵查询本单位 owner 的主城；单位变形保留节点、creationNumber 和生命比例。主城升级仍使用原有升级规则与资源归属。
- 事件入口只由 Director 调用一次，保留背包 GUI → 瞄准 → 选择器/热键的处理顺序。
- `rebind_modules()` 更新替换后的依赖和 HUD/选择器信号，保留导航查询、预约、单位服务和瞄准状态。更换整张地图走原重开入口。
- 命令卡、选中 HUD、生产面板另保留廉价身份比较，兼容现有局部依赖替换入口。
- 没有改变寻路算法、AI 更新频率或画质。

### 最终验证（Godot 4.7.2，无渲染）

21 组功能回归通过，最终日志无 GDScript 解析/运行错误：

| 测试 | 结果 |
|---|---|
| navigation_module / harvest_module | PASS，14 / 10 项 |
| gold_mine_depleted / militia | PASS |
| units_module / production_module / production_owners | PASS，13 / 14 / 45 项 |
| match_input / interaction_module / command_input_module | PASS，12 / 16 / 8 项 |
| command_card_module / path_debug_module | PASS，9 / 3 项 |
| match_round2 / match_hotpath_cache / economy_supply | PASS，1098 / 77 / 7 项 |
| group_move / pathfinding_integration | PASS |
| build_module_game / unit_forms_game | PASS，13 / 27 项 |
| module_bindings_game | PASS，28 项；100 次获取不重绑，替换选择器后每模块仅重绑一次 |
| match_end_game --restart | PASS，23 项 |

额外完成默认地图 60 秒实时 AI 对战冒烟检查（4548 帧），无脚本错误。此项仅验证模块接入，不作为优化前后性能对比；本批没有重跑有渲染或 30 分钟性能验收。沙箱日志仍有用户目录写入、系统证书读取提示，以及既有资产大小写警告。

GameDirector 从本轮开始的 2708 行降至 2151 行。仍保留场景配置、相机、建造交互校验与部分 HUD 协调；没有为追求行数把剩余业务整体搬进另一个总管。
