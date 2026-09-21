# 游戏功能模块

玩法代码逐步按功能聚合到此目录。每个功能内再按需要区分逻辑、表现和数据；没有实际文件时不创建空目录。

```text
game/features/
  production/
    production_module.gd           对局内生产生命周期
    logic/
      production_orders.gd         训练/研究校验、扣费与入队
      train_queue.gd               单建筑生产队列
      train_spawn.gd               出口与挤位计算
      building_rally.gd            集结点状态
    presentation/
      production_panel.gd          本地选择、生产反馈与建筑工作表现
  units/
    units_module.gd                对局内单位出生、AI/英雄装配与 CN 分配
  build/
    build_module.gd                对局内建造调度、工地注册表与放置视觉
  combat/
    combat_module.gd               对局内伤害管线、投射物、死亡与 AttackController
  abilities/
    abilities_module.gd            对局内技能 ctx / runtime / 瞄准 / 预览
  items/
    items_module.gd                对局内地面物品、背包操作与死亡掉落
  interaction/
    interaction_module.gd          互斥瞄准状态机 + 光标同步
    smart_command_module.gd        右键智能目标解析 / 闪选 / 文案
    command_input_module.gd        issue_*/begin_* 下发、瞄准点击与智能右键
  command_card/
    command_card_module.gd         命令卡刷卡、热键、二级菜单与 action 分发
  selection_hud/
    selection_hud_module.gd        肖像 vitals / buff / 选中详情
  match/
    match_bootstrap_module.gd      对局开局会话、本地/对手基地、镜头
    match_lifecycle_module.gd      胜负接线、结算屏、重开
    opponent_ai_module.gd          对手经营 / 军队 AI 挂接
  debug/
    path_debug_module.gd           选中单位寻路折线调试
    debug_tools_module.gd          GM 面板 / 性能叠层 / GM 动作
```

## 依赖约定

- `GameDirector` 是装配入口，创建模块、提供依赖并连接信号。模块不持有或查找 `GameDirector`。
- 功能模块是当前对局的 Node，随对局销毁；不注册为 Autoload。
- 状态就近持有：每座建筑的队列属于 `TrainQueue`，队列订阅属于 `ProductionModule`，单位出生与 AI/英雄装配属于 `UnitsModule`，玩家库存仍属于 `GameSession / PlayerStock`。
- 请求通过明确方法调用并返回结果；已发生的变化通过信号通知。暂不引入全局事件总线。
- 保留跨功能共享能力的原目录。功能拆分不等于一次性移动所有 `game/scripts`。
- 同时被多个功能使用的类不急于上提；先确定它的数据所有者和依赖方向。
- 移动 Godot 脚本时连同 `.gd.uid` 一起移动，保留 `class_name`，检查旧路径引用。
- 回归测试暂保留在 `tests/unit`、`tests/integration`，以功能前缀定位；各功能文档列出自己的验收入口。

当前生产与单位功能边界、兼容入口和后续批次见 [模块化重构计划](../../docs/architecture/FEATURE_MODULE_REFACTOR.md)。
