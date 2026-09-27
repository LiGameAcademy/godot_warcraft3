# RTS Kernel — Godot 无关的内核抽象

> 状态：定稿 v1.0（design-only，待批准后实施）
> 关联：[GAMEPLAY_TARGET_ARCHITECTURE.md](GAMEPLAY_TARGET_ARCHITECTURE.md) · [GAMEPLAY_MODULE_BOUNDARIES.md](GAMEPLAY_MODULE_BOUNDARIES.md) · [LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md) · [ROADMAP.md](../roadmap/ROADMAP.md)

## 0. 目标与边界

**目标**：把 `packages/gameplay/` 中除表现层外的代码抽象成 **不依赖 Godot 引擎 API** 的 RTS 内核（用 GDScript 编写，只使用 `RefCounted` / `Signal` / `Callable` / 内置类型），通过**端口**与 Godot 适配层（`packages/gameplay/adapters/` 或 `apps/game/`）解耦。

**内核可见**：
- `RefCounted` / `Object`（GDScript 基础，但 Godot 引擎自带的，无 Node / Resource）
- `Signal`、`Callable`、`Dictionary`、`Array`、`String`、`int`、`float`、`Vector2`、`Vector3`（数值类型，仍允许）
- 数学运算 `min/max/abs/clamp/lerp`（基础库）

**内核不可见**（仅适配器可见）：
- `Node` / `Node3D` / `CanvasLayer` / `Control` 等场景树节点
- `Resource` / `Texture2D` / `PackedScene` 等资源类型
- `SceneTree` / `Viewport` / `Input` 等引擎运行时
- `preload("res://...")` 资源相对引用（内核只能用 `const Foo := preload(...)` 引用同包内的脚本——但脚本本身体只能声明 RefCounted 子类，**不能 extend Node/Resource**）

## 1. 已具备的纯内核

| 模块 | 现状 | 评估 |
|---|---|---|
| `PlayerStock` | `RefCounted`，仅 signal / 值字段 | ✅ 已内核 |
| `GameSession` | `RefCounted` + `signal match_finished` | ✅ 已内核 |
| `UnitOrder` | `RefCounted` 值对象 | ✅ 已内核 |
| `UnitLife` | `RefCounted`，但「挂在 Node3D meta 上」——外耦 | ⚠️ meta 改为 `EntityStore` 字典 |
| `EntityRegistry` | `node is Node3D` 检查 | ❌ 需端口化 |
| `EntityId` | int ID | ✅ 已内核 |

## 2. 内核改造目标

### 2.1 实体身份：EntityHandle

**核心抽象**：内核只见 `EntityHandle`（int），不见 `Node3D`。

```gdscript
class_name EntityHandle
extends RefCounted

## 内核级的实体身份。不持有 Node 引用——Node 由适配层维护在 EntityStore 里。
## 构造时可附带 owner / type / 列表等元数据；运行时不再变化。
var id: int
var owner_id: int = 0
var archetype: StringName = &""  ## 单位类型 / 建筑类型
var kind: int = Kind.UNIT

enum Kind { UNIT = 0, BUILDING = 1, ITEM = 2, RESOURCE_NODE = 3 }

static func unit(id: int, owner: int = 0) -> EntityHandle:
    return _build(id, owner, &"", Kind.UNIT)
# ...
```

### 2.2 实体仓库：EntityStore

```gdscript
class_name EntityStore
extends RefCounted

## 内核与适配层共享的实体仓库：handle ↔ 表现层 Node 引用。
## 内核**不读** node 字段；适配层**不写**内核数据（除了把变更同步过来）。
var _by_id: Dictionary = {}    ## int → EntityHandle
var _node: Dictionary = {}     ## int → Node3D（适配层独占读写）
var _positions: Dictionary = {} ## int → Vector3（适配层写、内核读）

func register(handle: EntityHandle, node: Node3D) -> void
func unregister(id: int) -> void
func get_handle(id: int) -> EntityHandle
func get_position(id: int) -> Vector3
func get_owner(id: int) -> int
func is_valid(id: int) -> bool
func list_by_owner(owner: int) -> Array[int]

# 适配层独占
func set_node(id: int, node: Node3D) -> void  ## @internal
func set_position(id: int, pos: Vector3) -> void  ## @internal
func attach_node(handle: EntityHandle, node: Node3D) -> void
func detach_node(id: int) -> void
```

### 2.3 命令路由：CommandRouter 改造

现状：`32KB`，60+ 处 `Node3D` 入参，所有命令方法都接 `Array[Node3D]`。

目标：所有方法接 `Array[int]`（EntityHandle id）。UnitNavigator / HarvestController / BuildController 注入改为 `Callable` 形式（已经是 Callable 风格）。

```gdscript
## 改造前
func issue_move_to_wc3(units: Array[Node3D], goal: Vector2, source: int) -> int:
    var n: Node3D = units[0]
    var nav := UnitNavigator.of(n)
    nav.move_to_wc3(goal)

## 改造后
func issue_move_to_wc3(unit_ids: Array[int], goal: Vector2, source: int) -> int:
    var id: int = unit_ids[0]
    var nav_getter: Callable = _navigator_getter
    var nav = nav_getter.call(id)  ## 适配层：返回 UnitNavigator（Node）
    nav.move_to_wc3(goal)
```

迁移步骤：
1. 把所有 `Array[Node3D]` 入参改为 `Array[int]`（entity ids）。
2. `_navigator_getter`、`_harvester_getter` 等保留为 `Callable`；适配层实现该 Callable：内部用 `EntityStore.get_node(id)` 拿到 Node → 转回 Navigator。
3. 内核方法签名脱 Node 化。

### 2.4 战斗查询：CombatQuery 改造

现状：`static func in_attack_range(attacker: Node3D, target: Node3D, ...)` 大量 Node3D 入参。

目标：所有静态方法改 `int` 入参 + `EntityStore` 静态访问。

```gdscript
## 内核顶层持有一个 EntityStore（外部注入）
static var _store: EntityStore

func configure(store: EntityStore) -> void:
    _store = store

static func in_attack_range(attacker_id: int, target_id: int, hysteresis: float = 0.0) -> bool:
    if _store == null or not _store.is_valid(target_id):
        return false
    var a := _store.get_position(attacker_id)
    var b := _store.get_position(target_id)
    return a.distance_to(b) <= range_wc3(attacker_id, target_id) + hysteresis
```

### 2.5 端口（Callable 注入）清单

下列 Callable 是适配层向内核暴露的端口。每条都「内核只声明 + 适配层实现」：

| 端口（Callable 字段） | 内核用途 | 适配层实现 |
|---|---|---|
| `_navigator_of(id) -> Node` | 拿到 UnitNavigator（执行移动） | `EntityStore.get_node(id).get_node("UnitNavigator")` |
| `_harvester_of(id) -> Node` | 拿到 HarvestController | 同模式 |
| `_builder_of(id) -> Node` | 拿到 BuildController | 同模式 |
| `_attacker_of(id) -> Node` | 拿到 AttackController | 同模式 |
| `_unit_data(id) -> Dictionary` | 读 unit_data meta | `EntityStore.get_node(id).get_meta("unit_data")` |
| `_unit_life(id) -> UnitLife` | 读生命 | 同模式 |
| `_ability_host(id) -> Node` | 拿 AbilityRuntimeRegistry 宿主 | 同模式 |
| `_damage_pipeline() -> DamagePipeline` | 单例伤害管道 | `app/damage_pipeline.gd` |
| `_projectile_service() -> ProjectileService` | 单例弹道服务 | `app/projectile_service.gd` |
| `_path_query() -> PathQuery` | 寻路查询 | `app/path_query.gd` |
| `_is_pathable(wc3_xy) -> bool` | 可走性 | `MapRoot.get_pathing().is_pathable_at_wc3(...)` |
| `_world_position(id) -> Vector3` | 实体位置（CombatQuery 重） | `EntityStore.get_position(id)` |

### 2.6 适配层位置

新增 `packages/gameplay/adapters/` 子树（按依赖包划分）：

```text
packages/gameplay/adapters/
├── godot/
│   ├── godot_entity_store.gd       ## EntityStore 适配：EntityStore ↔ Node3D
│   ├── godot_node_port.gd          ## 节点访问 Callable 集合（navigator_of / harvester_of …）
│   ├── godot_visual_port.gd        ## 视觉 Callable（play_animation / fx_spawn …）
│   └── godot_collision_port.gd     ## 碰撞 / 视野 / 射线 Callable
├── world/
│   └── godot_world_adapter.gd      ## 把 Godot 寻路 / 高度图包装成 Callable
└── presentation/
    ├── unit_model_adapter.gd       ## Wc3ModelScene 包装为 EntityVisualPort
    ├── attack_fx_adapter.gd        ## AttackController 包装为 AttackPort
    └── nav_adapter.gd              ## UnitNavigator 包装为 NavigatorPort
```

适配层**只引用内核的端口签名**，不反向依赖内核具体实现。内核对适配层一无所知。

### 2.7 表现层端口

`kernel-also-presentation` 这部分目标是：**AI/逻辑层不再直接调用动画/特效/Mesh**，而是通过"表现端口"Callable 触发：

```gdscript
## 内核侧声明（CombatQuery 装饰等）
var _play_attack_anim: Callable = Callable()       ## (entity_id: int) -> void
var _play_hit_fx: Callable = Callable()             ## (entity_id: int) -> void
var _spawn_muzzle_flash: Callable = Callable()      ## (entity_id: int) -> void
var _attach_buff_icon: Callable = Callable()        ## (entity_id: int, buff_id: String) -> void
```

适配层 `godot_visual_port.gd` 实现：

```gdscript
func _play_attack_anim(entity_id: int) -> void:
    var node: Node3D = _store.get_node(entity_id)
    if node and node.has_node("Model"):
        var model := node.get_node("Model")
        if model.has_method("play_anim"):
            model.call("play_anim", "Attack")

func attach_to(kernel: CombatQuery) -> void:
    kernel._play_attack_anim = Callable(self, "_play_attack_anim")
```

## 3. 路径：表现层也脱耦的具体子目录

| 子目录 | 当前耦合 | 内核化方案 |
|---|---|---|
| `features/navigation/presentation/unit_navigator.gd` | `extends Node`，挂在 Unit 子节点 | 内核只声明 `NavigatorPort` Callable；适配层仍是 Node 子节点 |
| `features/combat/actions/attack_controller.gd` | `extends Node`，state machine 持有 Node3D 引用 | state machine 持有 entity id；Node3D 通过 `EntityStore.get_node(id)` 拿 |
| `features/build/logic/build_controller.gd` | `extends Node`，操作 BuildSite（Node3D） | 持有 build site id；BuildSite 元数据走 EntityStore |
| `features/harvest/logic/harvest_controller.gd` | `extends Node`，peasant + gold mine Node3D | 持有 peasant id + mine id |
| `presentation/health_bar_manager.gd` | `CanvasLayer`，订阅 Node3D set_selection | 订阅 `GameSession.stocks.changed` + EntityStore 内 entity_id 列表 |
| `entities/presentation/unit.gd` | `extends Node3D`，所有元数据宿主 | 元数据迁到 EntityStore；Unit 仅剩视觉/输入适配 |

## 4. 边界：什么**不**内核化

| 模块 | 原因 |
|---|---|
| `MapLoader` (`extends Node3D`) | 表现层场景入口 |
| `MapRoot` 场景树 | 表现层 |
| 所有 `Layer` (`extends Node3D`) | 表现层 |
| `HealthBarManager` (`extends CanvasLayer`) | 表现层 |
| `Wc3ModelScene` / `Wc3AnimPlayer` | 表现层 |
| `WorldMembership` (`extends Node`) | 接近 Node，但本质是 EntityStore 的早期形态，可保留为 Node 子节点代理 |

表现层**不**进入内核。它们在 `apps/game/client/`、`packages/map/presentation/` 等位置存在。

## 5. 迁移路线图（5 个批次）

### Batch 1：内核边界划定（无功能改动）

- 新增 `packages/gameplay/kernel/` 子树：
  - `kernel/entity_handle.gd`
  - `kernel/entity_store.gd`
  - `kernel/ports.gd`（Callable 字段集合 / 端口契约）
- 现有 `PlayerStock` / `GameSession` / `UnitOrder` / `UnitLife` **不动**（已经是 RefCounted）。
- 写 `selftest_entity_kernel.gd` 验证 EntityHandle/Store 的注册/查询。

### Batch 2：EntityStore 适配层 + Unit 元数据迁移

- 新增 `packages/gameplay/adapters/godot/godot_entity_store.gd`。
- Unit / Building Node3D 在 `attach` 时往 EntityStore 写 handle + node + position + unit_data meta。
- `unit_data` meta **保留**（向后兼容），但 EntityStore 是权威。

### Batch 3：CommandRouter 脱 Node

- `CommandRouter` 所有入参改 `Array[int]`。
- 内核内的 NavigatorOf/HarvesterOf/BuilderOf 改为 Callable（已 Callable，加类型）。
- 适配层 `godot_node_port.gd` 实现 Callable。

### Batch 4：CombatQuery / Harvest / Build 脱 Node

- 这三个是 80KB+ 的逻辑类；逐个方法改 `int` 入参。
- 适配层补 NavAdapter / AttackAdapter / BuildAdapter。

### Batch 5：表现层 Callable 端口

- Combat 攻击动画/弹道壳 → `_play_attack_anim` / `_spawn_missile` 等 Callable。
- HealthBarManager 订阅 EntityStore 的 `selection_changed` 而非 Unit Node3D 信号。
- Unit 脚本瘦身到只剩视觉 / 输入。

## 6. 验收标准

每个 Batch 完成后必须验证：

- [ ] `selftest_entity_kernel.tscn` 全绿（内核纯 RefCounted，无 Node 引用）
- [ ] `selftest_command_router.gd` 跑通（用 Callable stub，验证路由逻辑不依赖 Node）
- [ ] `selftest_combat_query.gd` 跑通（EntityHandle 入参，验证距离/范围算法正确）
- [ ] 启动主对局，所有原有 selftest（含 `selftest_tower_defense`、`selftest_unit_selection` 等）保持 PASS
- [ ] Godot 进程**没有**新增 Node 子节点做端口实现（除适配层专门设计的 godot 节点）
- [ ] `grep -rn "extends Node" packages/gameplay/` 在 Batch 5 后**仅**剩适配层 + 视觉层

## 7. 不在本轮范围

- 不引入 C# / Rust / 其他语言内核（用户选择 GDScript）
- 不拆 EntityStore 的并发模型（GDScript 单线程）
- 不做 undo/redo 系统
- 不做 Mod API 边界（与 Mod 系统的接缝留到下次架构迭代）

## 8. 风险

| 风险 | 缓解 |
|---|---|
| `Callable` 注入端口太多，每个内核类都带 10+ Callable 字段 | 引入 `PortSet` 聚合类，把相关 Callable 打包成单一对象 |
| 调试时栈轨迹被 Callable 截断，难追踪 | 适配层 Callable 内部打 `AppLog.debug` 记录 caller |
| 现有 `selftest_*` 大量直接构造 Node3D / Unit 测战斗；改成 EntityHandle 后要大改 | 渐进迁移：先 `EntityHandle` + `EntityStore` 双轨；旧 selftest 走 Node 路径直到 Batch 5 收尾 |
| 玩家经济 AI (`player_economy_ai.gd`) 大量 Node 引用 | 推到 Batch 4 后处理，本轮**不**触及 PlayerEconomyAI / UnitAI |
| Godot 4 `class_name` 全局缓存：批量新增 `class_name` 可能让 `class_name` 解析失败 | 每次新增 `class_name` 后用 `tools/workspace/sync_packages.py` 同步，强制 Godot 重新扫描；不要绕过 |

## 9. 后续可选方向（不在本轮）

- 把内核 `.gd` 抽取成独立 Godot 项目 `packages/gameplay_kernel/`，仅靠 GDScript 标准库即可编译；用作单元测试子项目。
- 用 GDScript-to-Rust / -C# 转换，把热路径（如寻路）落地到 C#/.NET（C# 程序集本项目已配置 `project/assembly_name="godot_warcraft3"`）。
- 用同样的内核写一个 CLI 跑回放（headless replay viewer），用 Godot 进程但**只**依赖适配层 stub。

## 10. 总结

本轮设计把 RTS 内核从 Godot 引擎 API 解耦，方法签名用 `EntityHandle` (int) 替代 `Node3D`，通过 `Callable` 端口与适配层通讯。`PlayerStock` / `GameSession` / `UnitOrder` / `UnitLife` 已经具备内核形态；剩余工作是把 `CommandRouter` / `CombatQuery` / `HarvestController` / `BuildController` / `AttackController` 等"系统集成层"从 Node3D 切换到 `int + Callable`。

5 个批次渐进迁移；每批次独立可发布（现有 selftest 保持 PASS）。