# Gameplay 分层与项目目录重构实施策划

日期：2026-09-23。2026-09-24 更新：完整源码目录已迁入 apps/packages，根项目入口已退役；当前实施记录见 [双产品目录迁移验收](DIRECTORY_CUTOVER_2026_09_24.md)。下文保留原阶段策划与历史路径。

前置设计：[架构审查与双产品目标](GAMEPLAY_TARGET_ARCHITECTURE.md)。本文记录讨论后确定的四方面职责，并明确下一轮目录迁移的边界、批次和验收；已有四波次实现历史仍见 [FEATURE_MODULE_REFACTOR.md](FEATURE_MODULE_REFACTOR.md)。

## 1. 本轮决策

1. Gameplay 以输入、命令、单位状态、行动执行四方面组织职责；表现独立。状态是命令和行动共享的数据基础，不是串行调用链上的一步。
2. 目录优先按功能聚合，再按上述职责拆分。不会建立装下全部玩法的四个全局大目录。
3. 先在当前 Godot 项目中整理职责清晰的文件，再迁移到两个独立应用。目录整理可以先做，两个 project.godot 的正式切换仍以共享依赖、内容解析和发布验证就绪为前提。
4. 目录迁移不改玩法，不引入新的全局玩法 Autoload，不更换寻路算法或降低更新频率。
5. 一批目录移动对应一个可回退提交；混合职责文件先保留原位，另起行为重构提交。不要为了填满目录把不符合边界的文件改名后归入“纯逻辑”。

## 2. 四方面职责及表现边界

```text
玩家输入 / AI 决策 / 触发器
            ↓ CommandRequest
命令处理：权限与规则校验 → 接受 Order → 排队/替换/中断
            ↓
行动执行：跨帧推进，调用导航/伤害/资源等系统
            ↓ 结果 / 完成 / 失败 / 中断
       命令调度继续下一订单

命令和行动 → 通过所属接口读写单位状态
状态变化与行动事件 → 模型、动画、HUD、特效
```

| 职责 / 目录 | 包含 | 禁止 |
|---|---|---|
| `input/` | 玩家输入适配、拾取、选择、快捷键、请求构造 | 扣费、扣血、直接推进单位移动 |
| `commands/` | 命令请求/结果、接收校验、订单调度、替换与取消 | 读取 InputEvent，依赖 HUD 当前选中状态 |
| `state/` | 类型化运行态、只读视图、状态访问契约 | 文件加载、全局节点查找、另存一份可独立写入的镜像 |
| `actions/` | 移动、攻击、采集、施法等跨帧状态机 | 处理鼠标键盘、依据 HUD 决定业务结果 |
| `rules/` | 伤害计算、合法性判定等可独立测试的领域规则 | 访问 SceneTree、加载资源、创建特效 |
| `presentation/` | 动画、模型、HUD、特效、视觉预览 | 成为生命、费用、冷却等业务结果的权威 |
| `infrastructure/` | Godot/存储适配器、必要的外部实现 | 跨过命令入口替 UI 执行业务 |

这些是内部职责词汇，不要求每个功能都有全部目录。命令与行动属于应用执行机制，state/rules 属于领域，表现和基础设施保持独立；与前文 domain/application 分层并不冲突，实际目录采用本表命名，避免再嵌套两套同义层级。

### 请求、订单、行动必须区分

- 请求是尚未接受的意图，包含请求玩家、单位、目标、追加/替换方式，返回明确结果。
- 订单是已经接受、可排队的任务。现有 `UnitOrder` 混合了意图命名与订单用途，目录整理时保持接口，行为重构时再引入请求类型。
- 行动是执行进度，例如攻击订单中的追击、前摇、命中与后摇。一个订单可以推进多个行动，不需要输入层逐步驱动。
- 现有 `UnitOrder.target_id` 是 Godot instance_id；在 EntityId 契约落地前只作为对局内兼容字段，不能直接用作存档或 Mod API 身份。
- 每个行动应有开始、推进、中断、结束语义及退出清理责任；无需现在把所有控制器强制继承同一基类。通过适配器统一协议即可逐步迁移。
- 执行时重新校验可能变化的条件。费用何时扣除、何时可退款由各命令明确规定，不统一强制为“接受时扣费”。

## 3. 近期目录：保持单项目可运行

以下是迁移目标，不是当前文件清单。只在文件迁入时创建目录。

```text
game/
  app/                          # GameDirector、场景装配、本地视图协调
  scenes/                       # 保留现有应用场景位置
  config/                       # 游戏应用配置
  match/                        # 对局运行、开局、结束、GameSession
  entities/
    commands/                   # 订单协议、队列、通用路由门面
    state/                      # EntityId、状态访问；按实际迁移引入
  features/
    interaction/
      input/                    # 输入路由、拾取、智能右键意图
      presentation/             # 光标、移动/集结反馈
    navigation/
      actions/                  # 移动推进与巡逻执行
      rules/                    # 只在脱离场景依赖后放入纯规则
      infrastructure/           # 场景/地图访问适配
    combat/
      commands/
      state/
      actions/
      rules/
      presentation/
    abilities/                  # 同类内部职责，按需要创建
    production/
    build/
    harvest/
    units/                      # 出生、变形、能力装配
    items/
    ai/                         # 决策产生请求，不另建执行链
    command_card/               # 本地交互/UI；后续随客户端迁移
    selection_hud/
    debug/
  scripts/                      # 过渡目录：未完成职责拆分的旧实现
```

不把 `scripts/` 改名为 `legacy/` 后长期保留；逐批清空已迁移职责，最后删除空目录。当前 Unit 同时承担元数据宿主和动画/尸体表现，应先保持兼容，再拆状态与表现，不能整体迁入 entities/state。

现有 feature 根的 `*_module.gd` 可继续作为功能门面，既不强制搬进 commands，也不一律改成 manager。`game/app` 不得成为承接所有混合职责的杂物目录。

## 4. 首批文件映射与暂缓项

路径均相对仓库根。目标路径为策划，移动前逐项检查代码、场景与测试引用。

| 当前位置 | 目标位置 / 处理 |
|---|---|
| `game/scripts/game_director.gd` | `game/app/game_director.gd`；仅移动与更新引用，保留 class_name 和 UID |
| `game/scripts/session/game_session.gd` | `game/match/game_session.gd` |
| `game/features/match/` | `game/match/`；保留各模块原文件名 |
| `game/features/interaction/match_input_controller.gd` | `game/features/interaction/input/match_input_controller.gd` |
| `game/features/interaction/logic/world_picker.gd` | `game/features/interaction/input/world_picker.gd`；这是 Godot 拾取适配，不是领域规则 |
| `game/scripts/logic/command/unit_order.gd` | `game/entities/commands/unit_order.gd`；本批不改变身份字段和请求语义 |
| `game/scripts/logic/command/order_queue.gd` | `game/entities/commands/order_queue.gd`；保留原状态所有者，不复制队列 |
| `game/scripts/logic/command/command_router.gd` | 先保留；拆出各功能命令处理后，再迁通用门面至 entities/commands |
| `game/scripts/logic/combat/attack_controller.gd` | 目标 combat/actions；先审查表现调用，再决定直接移动还是先加适配 |
| `game/features/navigation/presentation/unit_navigator.gd` | 目标 navigation/actions；需先核对移动逻辑和表现边界，不能因旧路径认定它仅做表现 |
| `game/scripts/unit/unit.gd` | 先保留；分离实体状态门面和动画/尸体表现后分别归位 |
| `game/scripts/data/ability_catalog.gd` | 先保留；区分内容定义解析和 Gameplay 行为规则，禁止整体塞入 shared |
| `scripts/auto/`、`scripts/definitions/`、`scripts/map/catalog/` | 内容来源统一后分别归 content 的适配或定义目录，不按旧目录机械合并 |
| `scripts/map/infra/runtime_assets.gd`、`map_model_cache.gd` | 先保留门面；拆存储/解码与地图视觉处理后分别归 content/map |

首批只采用已明确归属的前七项；每项仍需独立引用核对。AI 模块与 HUD 的最终归属不因暂时处于 match/features 而固定，双产品迁移前重新核对依赖。

## 5. 最终目录：两个产品、单一共享源码

```text
apps/
  game/
    project.godot
    app/                        # 游戏启动与装配
    client/                     # 玩家输入、HUD、相机、命令卡、选择
    scenes/
    config/
    packages/*/               # 工具同步生成，不手工编辑
  map_editor/
    project.godot
    app/
    documents/
    tools/
    ui/
    scenes/
    packages/*/               # 工具同步生成
packages/
  gameplay/
    match/
    entities/
    features/                   # 命令/状态/行动/规则及可复用世界表现
  map/                          # 地图数据、查询、地形表现
  content/                      # 定义、清单、解析、存储/加载与缓存契约
  foundation/                   # 少量被明确证明共享的基础类型
content/
  builtin/
  samples/
tools/
  workspace/                    # 同步、依赖锁定、双项目导入/导出
  content_pipeline/             # 离线转换
tests/
  contracts/
  architecture/
  integration/
  performance/
docs/
```

玩家输入与 HUD 属于游戏客户端，不进入 Gameplay 核心；可复用的单位视觉适配可以随 gameplay 发布。编辑器普通地图预览只依赖 map/content；试玩先调用独立游戏程序，传入地图与内容锁定信息。

共享包同步到两个 Godot 项目内的固定路径，解决两个 `res://` 根的实际可见性。脚本/资源路径在此阶段统一到 `res://packages/<package>/...`。保留 UID、构建清单与哈希，排除重复 class_name；检查 `.gdignore` 不误屏蔽需要导入的共享代码。生成目录仅一份，不同时扫描 packages 源码与同步副本。

各应用独立管理 Autoload 和发布配置。第三方 addons 按实际依赖分发，先审计再搬迁，不在目录整理中修改插件实现或子模块。大量转换资产、缓存、日志和 node_modules 不属于共享源码包；依照现有资产管线处理，不顺带删除或搬运。

## 6. 分批落地与提交策略

| 批次 | 内容 | 验收与提交边界 |
|---|---|---|
| D0 | 本文及架构索引、关联文档一致性 | 目标/现状区分明确；文档独立提交 |
| D1 | 第 4 节前七项目录整理 | UID/class_name 不变；旧运行引用清零；干净导入和相关对局回归通过；纯移动提交 |
| D2 | 移动/攻击纵向试点：输入→请求→订单→行动→状态→表现 | 移动、停止、追加、攻击、目标死亡、中断、预约释放、重开均通过；协议与逻辑变更独立提交 |
| D3 | 定义与资源统一解析、内容快照和示例 Mod | 编辑器/游戏解析一致；基础包回退、冲突、失败缓存和重开通过；内容链路提交 |
| D4 | 清理共享层产品依赖，建立共享包同步和两个项目 | 两项目干净导入；独立导出制品启动；不存在开发机器路径依赖；工具与目录移动分开提交 |
| D5 | 采集、建造、生产、技能等逐功能推广 | 每个功能有状态所有者、命令入口、行动退出协议和针对性回归；一功能一波 |

本表是目录与四层主线的执行顺序，细化并调整前一篇的波次：允许 D1 先做低风险归位、D2 先验证命令边界；双产品切换仍在内容契约之后。不能把前文与本文两组批次当成两套并行实施清单。

### 每次目录迁移的操作清单

1. 记录工作区和当前基线，保留用户修改；只暂存本批已审查文件，不使用无差别提交。
2. 搜索 preload/load、场景资源引用、ProjectSettings/Autoload、字符串路径、测试和工具配置。历史记录可保留旧路径并标明历史，活跃入口必须更新。
3. 移动脚本与对应 `.gd.uid`；移动场景/资源时保留身份并核对内嵌引用。使用 Git 可识别的移动，不复制后同时保留两个 class_name。
4. 先做 headless 编辑器导入，再跑相关功能与对局启动/重开回归；路径相关缓存测试按涉及范围执行。
5. 检查意外生成文件、旧路径残留及 git diff；纯目录批次不应混入 gameplay 行为改动。
6. 验收通过后提交，记录文件归属与验证结果。失败留在当前批次修复，不继续扩大移动范围。

D1 不需要以 30 分钟性能测试替代路径和功能检查；D2 及后续执行机制变化需要同场景性能对比。正式双产品发布必须测导出制品，不能只测 Godot 编辑器内运行。

## 7. 教程与文档维护

以“移动请求如何成为实际移动”和“攻击如何被中断”作为前两个教程切片；每个示例展示完整链路和唯一状态所有者。教程链接到稳定入口与功能 README，避免依赖私有总管方法。

每批更新目录索引、实现状态和测试入口。

### 实施状态（对照仓库）

| 批次 | 状态 |
|------|------|
| D0 | 契约文档 + `tests/architecture` 门禁 |
| D1 | 前七项目录归位已落地（`game/app`、`game/match`、`entities/commands`、`interaction/input`） |
| D2 | `CommandRequest`/`CommandResult` + `CommandRouter.submit_request`；停止/移动经请求入口 |
| D3 | `ContentSnapshot`/`ContentRegistry`；DefStore 经 AssetProvider overlay；`content/samples/demo_mod` |
| D4 | `apps/game`、`apps/map_editor` 壳 + `tools/workspace/Sync-Packages.ps1` |
| D5 | `EntityId`/`EntityRegistry`/`BehaviorRegistry`；UnitsModule 可注入注册表 |
