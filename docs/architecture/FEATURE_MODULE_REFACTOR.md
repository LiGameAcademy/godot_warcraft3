# 功能模块与目录的渐进重构

日期：2026-09-13。基线：`03d3ec2`；开始本轮重构前，后续小地图差异、插件 UID 和资源忽略规则已分别提交，主仓库及插件子模块均无未提交差异。

## 目标与边界

教程按功能推进，目录也按功能组织。以 `game/features/<feature>/` 聚合一个功能的应用入口、规则和表现，内部按实际需要区分 `logic/`、`presentation/`、`data/`。地图、共享基础设施和资产管线保持原有边界。

`GameDirector` 最终只负责对局装配、启动与关闭。玩法模块使用对局内节点，跨场景资产访问和定义表沿用现有 Autoload。不要以全局单例替代显式依赖，也不要将总管作为万能上下文传给模块。

本文件描述当前迁移过程；旧架构文档中的历史设计不代表所有目标已经实现。

## 第一批：生产功能（已实现）

目录见 [game/features](../../game/features/README.md)。

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

## 后续批次（尚未实施）

1. **战斗模块**：集中伤害、投射物和死亡的协调；单位死亡、尸体表现和库存释放分别明确所有者。
2. **技能、物品模块**：收敛运行时注册、效果执行、背包事务和表现接线；通过适配层接入已有技能插件 Autoload。
3. **交互与 HUD 装配**：统一互斥瞄准模式、选择订阅及命令卡协调，清理第一批留下的转发入口。
4. **单位出生来源补齐**：召唤、建造、复活统一走 `UnitsModule`，保留各来源差异配置。

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

每批先确认工作区状态，再迁移一个可独立验收的功能；通过相关回归后单独提交。目录移动、类型变化和行为变化尽量避免在同一批同时扩大范围。
