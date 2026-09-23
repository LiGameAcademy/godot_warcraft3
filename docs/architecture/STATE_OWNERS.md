# D0 契约基线：状态所有者

日期：2026-09-23。批次：**D0**。配套：[GAMEPLAY_TARGET_ARCHITECTURE.md](GAMEPLAY_TARGET_ARCHITECTURE.md)、[GAMEPLAY_REFACTOR_PLAN.md](GAMEPLAY_REFACTOR_PLAN.md)。

本文记录**当前**写入权威，不是目标终态。迁移时先改本文再改代码；禁止双写。

## 三类数据

| 类别 | 含义 | 可变性 |
|------|------|--------|
| ContentDefinition | 单位/技能/物品/科技/模型引用等定义 | 导入校验后冻结；改动需新 ContentSnapshot |
| MatchState | 对局运行态 | 各系统唯一写入者 |
| ViewState | 选中、HUD、动画、特效 | 可由前两者重建；不得成为业务权威 |

## MatchState 所有者（当前）

| 状态 | 写入所有者 | 读取方 | 存储位置 | 迁移备注 |
|------|------------|--------|----------|----------|
| 玩家库存（金/木/食物/科技） | `GameSession` / `PlayerStock` | 生产、建造、HUD、AI | `game/match/game_session.gd` → `stocks` | 保持 Session |
| 胜负结算 | `GameSession.evaluate_match` | 生命周期模块、HUD | Session 内 `_match_result` | 保持 |
| 单位身份 typeId/owner | 出生/变形路径（UnitsModule、UnitFormService） | 全系统 | 节点 `unit_data` meta | D5 → EntityRegistry |
| creationNumber | UnitsModule.alloc_creation_number | 树/集结/调试 | unit_data / 注册表 | 候选 EntityId 输入 |
| 生命/最大生命 | UnitLife / 伤害管线 | HUD、战斗、AI | UnitLife meta 或组件 | D5 Health 组件 |
| 法力/技能等级 | AbilityRuntimeRegistry | 技能、HUD | 节点 meta / runtime | D5 |
| 订单队列 | OrderQueue（经 CommandRouter） | 导航、攻击、采集 | 节点 meta `order_queue` | 已在 entities/commands |
| 当前位置 | UnitNavigator / 节点 transform | 寻路、拾取、AI | Node3D | 保持节点；查询走端口 |
| 采集负重 | HarvestController | 命令、HUD | 控制器状态 | harvest feature |
| 生产队列 | TrainQueue | ProductionModule、面板 | 建筑关联队列 | production feature |
| 集结点 | BuildingRally | 出生派遣、旗标 | 建筑 meta | production |
| 进矿/施工在场性 | WorldMembership 契约 | 命令合法性 | 见 WORLD_MEMBERSHIP | 必须延续 |
| 死亡权威 | CombatModule / DeathService | 命令、AI、选中清理 | 领域死亡 ≠ 尸体动画 | 命令入口须查死亡 |

## ViewState（非权威）

| 状态 | 持有 | 说明 |
|------|------|------|
| 当前选中 | UnitSelector | 命令校验不得依赖选中；输入层构造请求时可读 |
| 瞄准态 | InteractionModule | 仅本地交互 |
| 命令卡/肖像 | CommandCard / SelectionHud | 只读视图 |
| 光标/移动确认 FX | Interaction feedback | 表现 |

## ContentDefinition（当前读路径）

| 定义 | 加载入口 | 问题 |
|------|----------|------|
| SLK 表行 | `Wc3DefStore` ← `RuntimeAssets.slk_path` | **未走 AssetProvider overlay**（P1） |
| 模型/贴图 | AssetProvider.resolve → MapModelCache | overlay 有效；换包缓存未统一作废 |

D3 起：定义与资源均经 ContentSnapshot；缓存键含快照版本。
