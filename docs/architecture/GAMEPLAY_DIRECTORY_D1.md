# D1 目录迁移实施记录

日期：2026-09-23。状态：已实施并通过回归。

对应 [重构策划](GAMEPLAY_REFACTOR_PLAN.md) 第 4 节前七项；策划基线提交为 `0e846be`。

## 变更

- GameDirector 移至 `game/app/`。
- GameSession 和原 `game/features/match/` 的三个模块移至 `game/match/`。
- MatchInputController、WorldPicker 移至 `game/features/interaction/input/`。
- UnitOrder、OrderQueue 移至 `game/entities/commands/`。
- 游戏场景、HUD 开发规则及相关当前文档使用新路径。历史审查和文件迁移映射保留旧路径作为历史证据。
- 新增 `game/README.md`，明确当前目录责任与尚待拆分的实现。

9 个脚本和对应 `.gd.uid` 均与迁移前逐字节一致；保留 class_name，不改变玩法、订单协议、更新频率或模块生命周期。不新增全局玩法 Autoload。

## 验证

使用 Godot 4.7.2 headless：

| 检查 | 结果 |
|---|---|
| 编辑器导入 | 无脚本解析错误 |
| 已跟踪非 Markdown 文件的旧路径检查 | 无本批旧路径残留 |
| 9 个脚本及 UID 与原提交内容比较 | 全部一致 |
| selftest_match_input | PASS，12 项 |
| selftest_interaction_module | PASS，16 项 |
| selftest_command_input_module | PASS，8 项 |
| selftest_command_card_module | PASS，9 项 |
| selftest_smart_command_module | PASS，5 项 |
| selftest_module_bindings_game | PASS，28 项 |
| selftest_match_end_game --restart | PASS，23 项 |

功能回归共 7 组 101 项。日志位于本地忽略目录 `tmp/d1-*.log`。

环境仍有系统证书读取、沙箱无法保存用户编辑器设置的提示；真实地图存在既有资产路径大小写警告。未发现脚本错误。本批未进行有渲染效果验证或性能改善验收。

## 边界

当前仍为单个 Godot 项目。D2 的移动/攻击协议试点及 D3–D5 内容快照、双产品发布与其他功能重构不属于本次纯目录变更。共享包边界未验证前，不直接移动全部资源至两个应用目录。
