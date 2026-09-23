# 玩法功能组件

按功能聚合：abilities、ai、build、combat、economy、harvest、heroes、interaction、items、navigation、production、technology、units。

各功能只创建需要的 commands/state/actions/rules/presentation 等职责目录；仍含场景访问的既有服务继续标为 logic，避免误称纯规则。

带 HUD、输入或本地生命周期协调的模块位于 `apps/game/app` 和 `apps/game/client`。本包组件通过显式参数、Callable 与信号协作，不依赖 GameDirector 或游戏 HUD 类型。

共享内容读取来自 content，地图查询/表现来自 map，基础设施来自 foundation。见 [包目录说明](../FEATURE_LAYOUT.md)。
