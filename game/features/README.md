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
  harvest/
    harvest_module.gd             采集组件、树木注册、金矿生命周期
    logic/                        HarvestController / TreeRegistry / GoldMineRuntime
  navigation/
    navigation_module.gd          对局导航服务、Navigator 装配与动态寻路刷新
    logic/                        PathQuery / UnitCrowdQuery / PathCellReservation
    presentation/                 UnitNavigator
  units/
    units_module.gd                单位出生、AI/英雄装配与形态变化入口
    logic/                        UnitFormService / MilitiaController
    presentation/                 UnitModelPresenter
  build/
    build_module.gd                对局内建造调度、工地注册表与放置视觉
  combat/
    combat_module.gd               对局内伤害管线、投射物、死亡与 AttackController
    actions/                      AttackController / ProjectileService
    rules/                        CombatDamageTable / CombatRng
    logic/                        DamagePipeline / DeathService / CombatQuery
    presentation/                 CombatProjectileShell / DamageFloatText / UnitHitFlash
  abilities/
    abilities_module.gd            对局内技能 ctx / runtime / 瞄准 / 预览
  items/
    items_module.gd                对局内地面物品、背包操作与死亡掉落
  interaction/
    interaction_module.gd          互斥瞄准状态机 + 光标同步
    smart_command_module.gd        右键智能目标解析 / 闪选 / 文案
    command_input_module.gd        issue_*/begin_* 下发、瞄准点击与智能右键
    input/                        MatchInputController / WorldPicker
    presentation/                 InteractionFeedback
  command_card/
    command_card_module.gd         命令卡刷卡、热键、二级菜单与 action 分发
  selection_hud/
    selection_hud_module.gd        肖像 vitals / buff / 选中详情
  debug/
    path_debug_module.gd           选中单位寻路折线调试
    debug_tools_module.gd          GM 面板 / 性能叠层 / GM 动作
```

## 依赖约定

对局模块已迁至 `game/match/`，应用入口位于 `game/app/`；见 [游戏目录索引](../README.md)。历史批次记录中的旧路径保留用于说明迁移过程。

- `GameDirector` 是装配入口，创建模块、提供依赖并连接信号。模块不持有或查找 `GameDirector`。
- 功能模块是当前对局的 Node，随对局销毁；不注册为 Autoload。
- 状态就近持有：每座建筑的队列属于 `TrainQueue`，队列订阅属于 `ProductionModule`，单位出生与 AI/英雄装配属于 `UnitsModule`，玩家库存仍属于 `GameSession / PlayerStock`。
- 请求通过明确方法调用并返回结果；已发生的变化通过信号通知。暂不引入全局事件总线。
- 保留跨功能共享能力的原目录。功能拆分不等于一次性移动所有 `game/scripts`。
- 同时被多个功能使用的类不急于上提；先确定它的数据所有者和依赖方向。
- 移动 Godot 脚本时连同 `.gd.uid` 一起移动，保留 `class_name`，检查旧路径引用。
- 回归测试暂保留在 `tests/unit`、`tests/integration`，以功能前缀定位；各功能文档列出自己的验收入口。

当前生产与单位功能边界、兼容入口和后续批次见 [模块化重构计划](../../docs/architecture/FEATURE_MODULE_REFACTOR.md)。

## 2026-09-23：导航与状态归属收尾

- 导航模块只在地图就绪时初始化；普通获取不重装依赖。开局刷兵前建立服务，刷兵后同步动态脚印。销毁或重新初始化时停止已装配的导航组件、释放预约并断开信号。
- Director 的导航属性为只读转发，不再持有第二份服务状态。导航与动态寻路回调直接绑定 NavigationModule。
- BuildModule 是唯一工地注册表和 BuildSitesHost 所有者；玩家与 AI 路由器使用同一查询入口。失效或已取消工地不再返回给调用方。
- InteractionModule 独占瞄准状态和选择器启用状态；Director 不再复制普通命令/技能瞄准布尔值或技能 ID，CommandInputModule 不再请求总管同步镜像。
- 该批次之后的采集、单位形态和输入拆分现已完成，见下方四波次说明。

导航契约与回归入口见 [navigation/README.md](navigation/README.md)。

## 四波次后续实现

1. [采集](harvest/README.md)：采集组件与资源节点生命周期由 HarvestModule 持有。
2. [单位](units/README.md)：UnitFormService 负责变形/升级事务，UnitModelPresenter 负责模型及动画绑定。
3. [交互](interaction/README.md)：MatchInputController 接收显式事件入口，WorldPicker 和 InteractionFeedback 分别负责拾取与反馈。
4. 装配：Director 在 `_bind_match_modules()` 建立新对局依赖阶段；普通 `_ensure_*` 只在首次创建或绑定代次改变时构造依赖。更换 HUD、选择器、相机等引用后调用 `rebind_modules()`，旧 HUD/选择器信号断开，新信号仅连接一次。命令卡、选中 HUD 和生产面板保留廉价的身份检查以兼容局部替换测试。

`rebind_modules()` 不重建地图、会话、导航查询或预约，不重开正在运行的订单；更换整张地图应使用对局重开入口。各功能自己的 `_exit_tree` / `shutdown` 负责释放依赖和订阅。`module_binding_counts()` 返回绑定次数的副本，便于确认普通输入或每帧访问不会重新绑定。

按整个仓库的代码、场景和测试引用清理了 37 个无调用方的私有兼容转发；公共 GM 入口及仍被测试使用的适配保留。Director 仍有建造交互校验、HUD 协调、相机和场景配置，没有为了缩短文件将这些职责混入通用管理器。
