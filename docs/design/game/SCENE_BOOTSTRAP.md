# GameMain — 场景根与依赖编排

> 状态：定稿 v1.3（强类型 setup 签名）
> 目标：消除 `game_main.tscn` 内子节点之间的字符串硬编码依赖查找，统一由场景根脚本注入。

## 0. 命名约定

- **场景根节点**：`GameMain`（`game_main.tscn` 中已存在，类型 `Node3D`，承载环境/光照）
- **根脚本**：`class_name GameMain`，路径 `apps/game/scenes/game_main.gd`
- **节点名 ≡ 类名**：`GameMain`（节点名）、`GameMain`（脚本类名）
- **子节点初始化约定**：所有子节点暴露 `setup(...)` 强类型签名方法；`game_main.gd` 按拓扑顺序调用，**不**依赖任何 `_ready` 自动装配

## 1. 背景

`game_main.tscn` 当前包含 8 个子节点，它们之间存在大量隐式耦合：

| 文件 | 反模式 |
|---|---|
| `game_loading_screen.gd._resolve_refs` | `get_parent().get_node_or_null("MapRoot"/...)` ← 已修复为 `setup()` 注入 |
| `game_director.gd._resolve_exports` | `get_node_or_null("../MapRoot"/...)` ← 本轮消除 |
| HUD / UnitSelector / HealthBarManager | 各自 `get_node_or_null` 字符串协议 |

任何新增子节点都必须在多处同步修改 `string-based` 路径，违反单一事实来源（SSOT）。

## 2. 设计决策（v1.3）

| 维度 | 选型 |
|---|---|
| Scope | 全部子节点 |
| 装配 API | **统一 `setup(...)`** 强类型签名（不用 Dictionary） |
| 装配点 | `game_main.gd._ready` 中按拓扑顺序调 `_setup_*` |
| 子节点内部 `_ready` | 仅做轻量日志 / 检查 `setup()` 是否已调；**禁止**依赖别的节点 |
| GameDirector `_resolve_exports` | **现在删除**（不留 fallback） |
| `_setup_*` 顺序 | 手工 toposort（game_main.gd 内） |

## 3. 拓扑顺序

```
1. _setup_unit_selector(unit_selector, deps)        # 最先：选择器只读 Camera/MapUnitLayer
2. _setup_game_cursor(game_cursor, deps)             # 鼠标：只读 UnitSelector（局部耦合）
3. _setup_health_bar_manager(health_bar_manager, deps)  # 血条：读 unit_selector + map_root
4. _setup_rts_camera(rts_camera, deps)               # 相机：读 map_root（高度场）
5. _setup_game_hud(game_hud, deps)                   # HUD：读 unit_selector + game_director（弱耦合）
6. _setup_game_director(game_director, deps)         # 主协调：依赖前面所有
7. _setup_game_loading_screen(game_loading_screen, deps)  # Loading：最后装配（订阅 session_ready）
```

**为什么 GameLoadingScreen 最后**：它订阅 `session_ready`，必须在 GameDirector 已经 setup 之后才能注册；反过来它对其他人没有依赖。

## 4. `setup(...)` 接口约定

每个子节点暴露**强类型签名**的 setup，形参直接列出需要的依赖（不用 Dictionary，避免 key 拼写错误 / 无类型检查）：

```gdscript
## 由 GameMain._ready 调用。依赖未注入前不应执行任何业务逻辑。
func setup(
    map_root: MapLoader,
    rts_camera: RtsCamera,
    game_hud: GameHud,
    unit_selector: Node,
    game_cursor: Node,
    health_bar_manager: HealthBarManager,
    game_loading_screen: Node
) -> void:
    self.map_root = map_root
    self.rts_camera = rts_camera
    ...
```

**为什么不用 Dictionary**：
- 形参类型在编辑期 / 编译期校验，缺参立即报错
- `game_main.gd` 一眼看清每个子节点要什么依赖
- selftest 可传 stub 节点，类型严格
- 与 `game_main.gd:17-23` 的 `game_loading_screen.map_root = map_root` 风格一致——直接逐字段赋值，不用 dict 中转

**每个子节点的签名**：
- `UnitSelector.setup(camera: Camera3D, map_root: MapLoader)` — 2 参
- `GameCursor.setup(unit_selector: Node)` — 1 参
- `HealthBarManager.setup(unit_selector: Node, camera: Camera3D, map_root: MapLoader)` — 3 参
- `RtsCamera.setup(map_root: MapLoader)` — 1 参
- `GameHud.setup(unit_selector: Node, game_director: GameDirector, health_bar_manager: HealthBarManager)` — 3 参
- `GameDirector.setup(map_root: MapLoader, rts_camera: RtsCamera, game_hud: GameHud, unit_selector: Node, game_cursor: Node, health_bar_manager: HealthBarManager, game_loading_screen: Node)` — 7 参
- `GameLoadingScreen.setup(map_root: MapLoader, game_director: GameDirector, game_hud: CanvasLayer, health_bar_manager: CanvasLayer)` — 4 参

**约定**：
- `setup()` 应是**幂等**的：重复调用不抛 warning 也不重复连接（用 `is_connected` 守卫）。
- GameMain 仅调一次。
- 形参顺序**先入先调**（上游 → 下游），与拓扑顺序一致。
- 可选依赖形参允许 `null`；子节点内部对 null 短路即可。
- 类型为 `Node`（弱类型）的字段避免 class_name 缓存依赖。

## 5. GameDirector 改造

### 5.1 删除

- `_resolve_exports()` 函数（整段）
- `@export var game_loading_screen: Node`（改为 setup 注入）

### 5.2 `_ready` 改造

```gdscript
func _ready() -> void:
    var assets := get_node_or_null("/root/AssetProvider")
    if assets != null:
        assets.seal_runtime_content()
    _rng.randomize()
    AppLog.reload_config()
    if map_root == null:
        push_warning("GameDirector._ready: setup() 尚未被调用；game_main.gd 应在 _ready 中按拓扑顺序调 setup(...)")
        return
    _boot_match()  ## 把原 _ready 后续逻辑搬过来
```

### 5.3 `setup(...)` 新增

```gdscript
func setup(
    p_map_root: MapLoader,
    p_rts_camera: RtsCamera,
    p_game_hud: GameHud,
    p_unit_selector: Node,
    p_game_cursor: Node,
    p_health_bar_manager: HealthBarManager,
    p_game_loading_screen: Node
) -> void:
    map_root = p_map_root
    rts_camera = p_rts_camera
    game_hud = p_game_hud
    unit_selector = p_unit_selector
    game_cursor = p_game_cursor
    health_bar_manager = p_health_bar_manager
    game_loading_screen = p_game_loading_screen
    # 节点引用就绪后再触发 _boot_match（仅触发一次）
    if _boot_match_done:
        return
    _boot_match()
    _boot_match_done = true
```

### 5.4 `_boot_match()` 新增

把原 `_ready` 后半段、`_configure_map_root`、`_wire_hud`、`_setup_selector`、`_load_camera_bounds`、`_configure_camera`、`_bind_ui_bridge`、`_inject_loading_screen` 都搬入此函数。

## 6. 子节点 setup 模板

```gdscript
## 例：UnitSelector
func setup(p_camera: Camera3D, p_map_root: MapLoader) -> void:
    if p_camera == null or p_map_root == null:
        push_warning("UnitSelector.setup: 缺关键依赖")
        return
    # 调用原本 _setup_selector 的逻辑
    _setup_internal(p_camera, p_map_root)
```

`_setup_internal` 等私有函数照旧，但**不再**在 `_ready` 内被调。

## 7. `game_main.gd` 终态

```gdscript
class_name GameMain
extends Node3D

@onready var world_environment: WorldEnvironment = %WorldEnvironment
@onready var sun: DirectionalLight3D = %Sun
@onready var map_root: MapLoader = %MapRoot
@onready var rts_camera: RtsCamera = %RtsCamera
@onready var game_hud: GameHud = %GameHud
@onready var health_bar_manager: HealthBarManager = %HealthBarManager
@onready var unit_selector: UnitSelector = %UnitSelector
@onready var game_director: GameDirector = %GameDirector
@onready var game_cursor: Wc3GameCursor = %GameCursor
@onready var game_loading_screen: GameLoadingScreen = %GameLoadingScreen

func _ready() -> void:
    _boot_scene()

func _boot_scene() -> void:
    # 拓扑顺序：上游依赖先 setup；下游后 setup
    var camera := rts_camera.get_camera() if rts_camera else null
    _setup_unit_selector(camera, map_root)
    _setup_game_cursor(unit_selector)
    _setup_health_bar_manager(unit_selector, camera, map_root)
    _setup_rts_camera(map_root)
    _setup_game_hud(unit_selector, game_director, health_bar_manager)
    _setup_game_director(
        map_root, rts_camera, game_hud,
        unit_selector, game_cursor, health_bar_manager, game_loading_screen
    )
    _setup_game_loading_screen(map_root, game_director, game_hud, health_bar_manager)

func _setup_unit_selector(p_camera: Camera3D, p_map_root: MapLoader) -> void:
    unit_selector.setup(p_camera, p_map_root)

func _setup_game_cursor(p_unit_selector: Node) -> void:
    game_cursor.setup(p_unit_selector)

func _setup_health_bar_manager(p_unit_selector: Node, p_camera: Camera3D, p_map_root: MapLoader) -> void:
    health_bar_manager.setup(p_unit_selector, p_camera, p_map_root)

func _setup_rts_camera(p_map_root: MapLoader) -> void:
    rts_camera.setup(p_map_root)

func _setup_game_hud(p_unit_selector: Node, p_game_director: GameDirector, p_health_bar_manager: HealthBarManager) -> void:
    game_hud.setup(p_unit_selector, p_game_director, p_health_bar_manager)

func _setup_game_director(
    p_map_root: MapLoader, p_rts_camera: RtsCamera, p_game_hud: GameHud,
    p_unit_selector: Node, p_game_cursor: Node, p_health_bar_manager: HealthBarManager,
    p_game_loading_screen: Node
) -> void:
    game_director.setup(
        p_map_root, p_rts_camera, p_game_hud,
        p_unit_selector, p_game_cursor, p_health_bar_manager, p_game_loading_screen
    )

func _setup_game_loading_screen(
    p_map_root: MapLoader, p_game_director: GameDirector,
    p_game_hud: CanvasLayer, p_health_bar_manager: CanvasLayer
) -> void:
    game_loading_screen.setup(p_map_root, p_game_director, p_game_hud, p_health_bar_manager)
```

## 8. 关键约束

- `game_main.gd` 是**唯一**负责节点引用装配的地方
- 子节点**不得**调 `get_node_or_null("Xxx")` 字符串协议（除 `$Root`、`%InternalUi` 等 Godot 标准 UI 引用）
- 子节点 `_ready` **不**访问 game_main 子节点；只对自身 `@onready` 子控件做初始化
- `_setup_*` 顺序必须保证 deps 全部就绪后才调 setup

## 9. 验收清单

- [ ] grep `get_node_or_null` 在 `apps/game/client/`、`apps/game/app/game_director.gd` 仅剩 game_main.gd
- [ ] GameDirector `_resolve_exports` 已删除
- [ ] 启动主对局：loading → 进局 → 命令卡 / 小地图 / 血条 / 单位选择 / 相机 全部正常
- [ ] `selftest_*` 全部 PASS（GameDirector 仍可在 selftest 中手动 `GameDirector.new()` + `setup()`，不依赖 game_main.tscn）
- [ ] 移除 `_resolve_exports` 后无其他脚本继续隐式依赖其副作用（如 `AppLog.info("GameDirector", "bind ...")` 可删）