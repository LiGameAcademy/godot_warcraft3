# Gameplay 源码归属

共享玩法源码已完整迁入本包；游戏应用入口和客户端位于 `apps/game`，编辑器位于 `apps/map_editor`。

| 目录 | 职责 |
|---|---|
| `match/` | 对局会话、玩家库存、开局规则、胜负规则 |
| `entities/commands/` | 请求、订单、队列与命令路由 |
| `entities/state/` | 实体身份、注册表、生命状态 |
| `entities/actions/` | 单位回复推进 |
| `entities/presentation/` | Unit 模型/姿态门面及现有实体宿主 |
| `features/` | 技能、战斗、导航、建造、生产、采集、物品、单位、AI、英雄、经济、科技与交互组件 |
| `catalog/` | 玩法使用的定义解析与数据查询门面 |
| `integration/` | GAS 等外部框架适配 |
| `presentation/` | 可复用世界表现与现有视觉组件 |

游戏应用的 `app/` 管理模块装配；`client/` 管理输入、命令卡、HUD、相机和本地调试。现有部分 logic 与表现调用仍待行为重构，目录迁移不代表所有组件已纯领域化。不得把应用类重新引用回本包。

详见 完整迁移记录（开发资料，公开版待审阅）。
