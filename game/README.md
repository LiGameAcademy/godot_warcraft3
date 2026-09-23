# 游戏代码目录

当前仍是一个 Godot 项目；双产品目录是后续目标。迁移步骤见 [实施策划](../docs/architecture/GAMEPLAY_REFACTOR_PLAN.md)。

首批目录迁移已完成，详见 [D1 实施与验证记录](../docs/architecture/GAMEPLAY_DIRECTORY_D1.md)。

| 目录 | 当前职责 |
|---|---|
| `app/` | GameDirector：场景引用、模块装配及尚待拆分的应用协调 |
| `match/` | GameSession、开局、对局结束/重开、对手 AI 装配 |
| `entities/commands/` | UnitOrder 和 OrderQueue；保留原有协议与队列语义 |
| `features/` | 按功能聚合的模块；输入适配位于 interaction/input |
| `scenes/` | 游戏场景 |
| `scripts/` | 尚未完成边界拆分的既有实现，逐批迁移 |

目录不等于已经完成分层：CommandRouter、Unit、导航和战斗控制器仍保留既有实现。新增代码按功能和实际职责归位，不向总管或通用状态字典继续堆业务。

请求通过明确方法调用，结果通过信号通知。对局模块不持有 GameDirector；目录迁移保持 class_name 与脚本 UID，不增加全局玩法 Autoload。
