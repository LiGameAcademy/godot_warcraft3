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
                                 单位生成接口      原订单玩家库存
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

- 单位创建、导航/AI/英雄组件装配、动态寻路刷新和训练后集结仍在总管，生产模块通过两个有限接口访问：`spawn_unit(type_id, position, owner, building)` 和 `ensure_hero(unit)`。第二批将把它们交给单位模块。
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

## 后续批次（尚未实施）

1. **单位模块**：统一单位出生与组件装配；先接管训练出生，再接入召唤、建造和复活，替换本批的总管接口。保留各出生来源的差异配置。
2. **建造模块**：集中工地表、施工生命周期、动态占地和取消；放置预览与指针输入分开。
3. **战斗模块**：集中伤害、投射物和死亡的协调；单位死亡、尸体表现和库存释放分别明确所有者。
4. **技能、物品模块**：收敛运行时注册、效果执行、背包事务和表现接线；通过适配层接入已有技能插件 Autoload。
5. **交互与 HUD 装配**：统一互斥瞄准模式、选择订阅及命令卡协调，清理第一批留下的转发入口。

每批先确认工作区状态，再迁移一个可独立验收的功能；通过相关回归后单独提交。目录移动、类型变化和行为变化尽量避免在同一批同时扩大范围。
