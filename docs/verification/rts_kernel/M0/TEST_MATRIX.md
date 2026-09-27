# M0 测试映射

日期：2026-09-27。状态：初版。`目标测试` 是计划名称，创建后替换为真实路径。

| 功能契约 | 现有证据 | 目标测试阶段 |
|---|---|---|
| 命令格式、错误玩家、追加拒绝、非法参数 | `selftest_command_request.tscn` | M1 CommandEnvelope；M2 订单 |
| 实体释放、替换、离树、身份 | `selftest_entity_behavior.tscn` | M1 EntityId/lifecycle |
| 内容冻结与失败原子性 | `selftest_content_snapshot.tscn` | M1 frozen definitions；M5 ability JSON |
| 弹道飞行与命中 | `selftest_c_combat_projectile.gd` | M3 projectile + snapshot |
| 战斗模块装配 | `selftest_combat_module.tscn` | M3 combat host adapter |
| 胜负、退出、重开隔离 | `selftest_match_end_game.tscn -- --restart` | M6 full match/restart |
| 移动、预约、分离、群体落点 | `selftest_navigation_module.tscn`、pathfinding 专项 | M2 navigation contracts |
| 建造、生产与退款 | `selftest_build_flow.gd`、`selftest_build_module.tscn` | M4 economy/build/production |
| 技能与自动施法 | ability 系列 selftest | M5 per-ability contracts |
| 物品与统一治疗 | `selftest_item_system.tscn`、`selftest_gas_healing.tscn` | M5 items/effects |
| Godot 启动装配 | `selftest_boot_flow.gd`、`--smoke-test` | 每个里程碑宿主回归 |

每个迁移工作包必须注明现有测试是继续保留为表现/接入测试，还是由 .NET 模拟测试接管。删除旧测试前，测试映射必须指向覆盖同一失败模式的新证据。
