# GameMain — 场景根与依赖编排

> 状态：定稿 v1.4（独立 Loading 场景 + 异步加载）
> 目标：消除 `game_main.tscn` 内子节点之间的字符串硬编码依赖查找，统一由场景根脚本注入；
> Loading 屏与主场景解耦为并列 peer scene，由 `boot.gd` 编排异步加载。

## 0. 命名约定

- **场景根节点**：`GameMain`（`game_main.tscn` 中已存在，类型 `Node3D`，承载环境/光照）
- **根脚本**：`class_name GameMain`，路径 `apps/game/scenes/game_main.gd`
- **节点名 ≡ 类名**：`GameMain`（节点名）、`GameMain`（脚本类名）
- **子节点初始化约定**：所有子节点暴露 `setup(...)` 强类型签名方法；`game_main.gd` 按拓扑顺序调用，**不**依赖任何 `_ready` 自动装配
- **Loading 场景**（v1.4）：`game_loading_screen.tscn` 与 `game_main.tscn` **并列**，由 `boot.gd` 先实例化

## 1. 背景

`game_main.tscn` 当前包含 7 个子节点，它们之间存在大量隐式耦合（已消除）：

| 文件 | 反模式 |
|---|---|
| `game_loading_screen.gd` | 纯 View：`begin` / `set_progress` / `finish`；业务订阅在 `boot.gd` |
| `game_director.gd._resolve_exports` | `get_node_or_null("../MapRoot"/...)` ← 已删除 |
| HUD / UnitSelector / HealthBarManager | 各自 `get_node_or_null` 字符串协议 ← 已改 setup 注入 |

任何新增子节点都必须在多处同步修改 `string-based` 路径，违反单一事实来源（SSOT）。

## 2. 设计决策（v1.4）

| 维度 | 选型 |
|---|---|
| Scope | GameMain 内全部子节点 + 独立 Loading peer |
| 装配 API | **统一 `setup(...)`** 强类型签名（不用 Dictionary） |
| 装配点 | `game_main.gd._ready` 中按拓扑顺序调 `_setup_*` |
| 子节点内部 `_ready` | 仅做轻量日志 / 检查 `setup()` 是否已调；**禁止**依赖别的节点 |
| GameDirector `_resolve_exports` | **已删除**（不留 fallback） |
| `_setup_*` 顺序 | 手工 toposort（game_main.gd 内） |
| Loading 生命周期 | **独立 peer scene**，由 `boot.gd` 经 `ResourceLoader.load_threaded_request` 异步加载主场景 |

## 3. 拓扑顺序（GameMain 内部）

```
1. _setup_unit_selector(...)        # 最先：选择器只读 Camera/MapUnitLayer
2. _setup_game_cursor(...)          # 鼠标：只读 UnitSelector
3. _setup_health_bar_manager(...)   # 血条：读 camera + map_root
4. _setup_rts_camera(...)           # 相机：读 map_root
5. _setup_game_hud(...)             # HUD：缓存 selector / director / hpbar
6. _setup_game_director(...)        # 主协调：依赖前面所有（6 参，不含 loading）
```

**v1.4 变更**：`GameLoadingScreen` 不再进入本拓扑。它由 `boot.gd` 在主场景之外独立持有。

## 4. `setup(...)` 接口约定

每个子节点暴露**强类型签名**的 setup，形参直接列出需要的依赖（不用 Dictionary）：

**每个子节点的签名**：
- `UnitSelector.setup(camera: Camera3D, unit_host: Node)` — 2 参
- `GameCursor.setup(unit_selector: Node)` — 1 参
- `HealthBarManager.setup(camera: Camera3D, map_root: MapLoader)` — 2 参
- `RtsCamera.setup(map_root: MapLoader)` — 1 参
- `GameHud.setup(unit_selector: Node, game_director: GameDirector, health_bar_manager: HealthBarManager)` — 3 参
- `GameDirector.setup(map_root: MapLoader, rts_camera: RtsCamera, game_hud: GameHud, unit_selector: Node, game_cursor: Node, health_bar_manager: HealthBarManager)` — **6 参**（v1.4 去掉 loading）
- `GameLoadingScreen.begin(title)` / `set_progress(stage, p)` / `finish()` — **纯 View**；由 `boot.gd` 订阅业务信号后推送

**约定**：
- `setup()` 应是**幂等**的：重复调用不抛 warning 也不重复连接（用 `is_connected` 守卫）。
- GameMain 仅调一次。
- 形参顺序**先入先调**（上游 → 下游），与拓扑顺序一致。
- 可选依赖形参允许 `null`；子节点内部对 null 短路即可。

## 5. GameDirector 改造

### 5.1 删除

- `_resolve_exports()` 函数（整段）
- `@export var game_loading_screen: Node`（v1.4：Loading 不再由 Director 持有）

### 5.2 `_ready` 改造

```gdscript
func _ready() -> void:
    # ... AssetProvider / RNG / AppLog ...
    if map_root == null:
        await get_tree().process_frame  # 等 GameMain._ready 完成 setup
        if map_root == null:
            push_warning("GameDirector: setup() 未注入")
            return
    _boot_match()
```

### 5.3 `setup(...)`（6 参）

```gdscript
func setup(
    p_map_root: MapLoader,
    p_rts_camera: RtsCamera,
    p_game_hud: GameHud,
    p_unit_selector: Node,
    p_game_cursor: Node,
    p_health_bar_manager: HealthBarManager,
) -> void:
    map_root = p_map_root
    rts_camera = p_rts_camera
    game_hud = p_game_hud
    unit_selector = p_unit_selector
    game_cursor = p_game_cursor
    health_bar_manager = p_health_bar_manager
    if _bootstrapped:
        return
    _boot_match()
```

## 6. `game_main.gd` 终态（v1.4）

```gdscript
class_name GameMain
extends Node3D

@onready var map_root: MapLoader = %MapRoot
@onready var rts_camera: RtsCamera = %RtsCamera
@onready var game_hud: GameHud = %GameHud
@onready var health_bar_manager: HealthBarManager = %HealthBarManager
@onready var unit_selector: UnitSelector = %UnitSelector
@onready var game_director: GameDirector = %GameDirector
@onready var game_cursor: Wc3GameCursor = %GameCursor
# v1.4：不再持有 game_loading_screen

func _ready() -> void:
    _boot_scene()

func _boot_scene() -> void:
    _setup_unit_selector(rts_camera.get_camera() if rts_camera else null, map_root)
    _setup_game_cursor(unit_selector)
    _setup_health_bar_manager(rts_camera.get_camera() if rts_camera else null, map_root)
    _setup_rts_camera(map_root)
    _setup_game_hud(unit_selector, game_director, health_bar_manager)
    _setup_game_director(map_root, rts_camera, game_hud, unit_selector, game_cursor, health_bar_manager)
```

## 7. 关键约束

- `game_main.gd` 是**唯一**负责 GameMain 子节点引用装配的地方
- 子节点**不得**调 `get_node_or_null("Xxx")` 字符串协议（除 `$Root`、`%InternalUi` 等 Godot 标准 UI 引用）
- 子节点 `_ready` **不**访问 game_main 子节点；只对自身 `@onready` 子控件做初始化
- `_setup_*` 顺序必须保证 deps 全部就绪后才调 setup

## 8. 验收清单

- [x] GameDirector `_resolve_exports` 已删除
- [x] GameDirector.setup 6 参（无 loading）
- [x] `game_main.tscn` 不再挂载 `GameLoadingScreen`
- [x] `boot.gd` 独立实例化 Loading + `load_threaded_request` 异步加载主场景
- [x] 启动主对局：loading → 进局 → 命令卡 / 小地图 / 血条 / 单位选择 / 相机 全部正常
- [x] `--smoke-test` PASS

---

## 10. Boot 流程（v1.4 新增）

```
boot.tscn (_ready)
  │
  ├─[--smoke-test]──► instantiate GameMain
  │                     configure_match({spawn_opponent_base})
  │                     add_child → is_session_ready / has_playable_match → quit 0
  │
  └─[正常]──► instantiate game_loading_screen.tscn
                │  begin("Echo Isles")
                │  load_threaded_request(game_main.tscn)
                │  poll → set_progress(…, 0..GameMain.RESOURCE_END)
                ▼
              THREAD_LOAD_LOADED
                │  instantiate GameMain
                │  订 preparation_progress / session_ready
                │  wire_external_hooks()  （入树前；内部转接 Map/Director，藏 HUD）
                │  add_child(GameMain)
                ▼
              session_ready → loading.finish() → fade → queue_free
                │
              boot.queue_free()
```

### Loading 屏 API（纯 View）

| 方法 | 调用方 | 作用 |
|---|---|---|
| `begin(title)` | `boot.gd` add_child 后 | 立刻显示 UI，进度 0 |
| `set_progress(stage, p)` | `boot.gd` | 推送**绝对**总进度 0–1（只升不降） |
| `finish()` | `boot.gd` 订 `GameMain.session_ready` | 最短展示后淡出 `queue_free` |

### GameMain Facade（对外窄接口）

| API | 作用 |
|---|---|
| `wire_external_hooks()` | 入树前：转接进度/就绪、隐藏玩法 UI |
| `configure_match(settings)` | 入树前写入 GameDirector 配置 |
| `set_gameplay_ui_visible(v)` | 显隐 HUD / 血条 |
| `is_session_ready()` / `has_playable_match()` | 等待与冒烟验收 |
| `signal preparation_progress(stage, p)` | 已映射绝对进度（地图+对局段） |
| `signal session_ready` | 对局就绪（并恢复玩法 UI） |

`boot.gd` **不** `get_node` MapRoot / GameDirector / GameHud / HealthBarManager。

### 进度分段

| 阶段 | 进度区间 | 驱动源 |
|---|---|---|
| 资源异步加载 | 0.0 – 0.30 | boot × `GameMain.RESOURCE_END` |
| 地图装配 | 0.30 – 0.85 | GameMain 转发 `MapRoot.load_progress` |
| 对局准备 | 0.85 – 0.99 | GameMain 转发 `session_preparation_progress` |
| 就绪 | 1.0 | GameMain `session_ready` → `finish()` |
