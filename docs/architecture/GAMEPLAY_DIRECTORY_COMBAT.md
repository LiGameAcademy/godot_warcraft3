# 战斗功能目录归位

日期：2026-09-24。基线：`a3706db`。

## 范围

这一批实现当前单项目内的战斗功能聚合，不切换根项目入口，不移动共享包或第三方插件。10 个脚本及其 `.gd.uid` 成对迁移；脚本内容、class_name、UID、信号和玩法语义不变。弹道场景更新脚本资源路径。

| 原位置 | 新位置（均相对 game/） |
|---|---|
| `scripts/logic/combat/attack_controller.gd` | `features/combat/actions/attack_controller.gd` |
| `scripts/logic/combat/projectile_service.gd` | `features/combat/actions/projectile_service.gd` |
| `scripts/logic/combat/combat_rng.gd` | `features/combat/rules/combat_rng.gd` |
| `scripts/data/combat_damage_table.gd` | `features/combat/rules/combat_damage_table.gd` |
| `scripts/logic/combat/{combat_query,damage_pipeline,death_service}.gd` | `features/combat/logic/` 下同名脚本 |
| `scripts/presentation/{combat_projectile_shell,damage_float_text,unit_hit_flash}.gd` | `features/combat/presentation/` 下同名脚本 |

## 边界与后续

`actions` 标识跨帧执行职责，`rules` 放无需场景查询的计算与随机数封装。依赖场景的服务留在 `logic`，不误标为纯规则。AttackController 的动画调用、DeathService 的尸体显示操作仍需另批通过状态/表现接口拆分。详见 [战斗模块职责](../../packages/gameplay/features/combat/README.md)。

本次没有完成 `apps/game`、`apps/map_editor` 与 `packages` 的最终源码切换。原拟整体迁移约 761 个文件并移除根项目入口，后续接线被自动审批拦截；已按迁移记录与 Git 基线逐文件核验并撤回，改为本批可独立验证的单功能归位。

后续按导航、建造、物品、技能分别审查和迁移；混合职责先拆分。共享地图层目前仍依赖 Unit/UnitLife，必须解决此依赖后再验证编辑器独立发布，不能把当前应用壳的导入测试等同于双产品发布验收。

## 验证

- 引擎：Godot 4.7.2 Mono；headless 编辑器导入通过。恢复整体迁移后的首次导入发现旧 UID 缓存路径，重新扫描后的第二次导入无脚本编译或 Autoload 加载错误。
- 10 个脚本与 10 个 UID 对比基线内容一致；Git 识别为 100% 相似度重命名。除架构门禁中的禁止路径外，活跃源码、场景、测试与工具未发现旧战斗脚本路径。
- 11 组回归通过：`selftest_c_combat_damage`、`selftest_c_combat_projectile`、`selftest_c_combat_attack_resolve`、`selftest_combat_module`、`selftest_attack_chase_facing`、`selftest_building_attack_range`、`selftest_hero_combat_stats`、`selftest_command_request`、`selftest_dependency_bounds`、`selftest_module_bindings_game`、`selftest_match_end_game --restart`。
- `Test-Apps.ps1` 对 game / map_editor 各同步 1727 个运行文件，两个应用的导入与 runtime package smoke 均 PASS。此测试覆盖应用壳及 GameSession，不覆盖完整编辑器交互或独立导出。
- 日志仍包含本机根证书、编辑器设置写入和已有资产路径大小写诊断；上述通过不表示日志完全无警告，也不表示跨平台资产路径已修复。
- `git diff --cached --check` 通过。本批不改变算法或更新频率，不声称有性能改善。

本批后 `game/scripts` 仍有 127 个脚本；四个 `packages` 目录仍无运行脚本。此数量用于明确剩余迁移规模，不能将本批描述为整个目录规划已经落地。
