# 游戏层架构设计

> 状态：**设计文档**（`feature/game-scene-echoisles`）。实现顺序以 [ROADMAP.md](ROADMAP.md) 为准。  
> 原则：游戏是 **Application 层**，消费 `scripts/map/*`；不污染 Editor；触发器是可插拔运行时，不是开局阻塞项。  
> 最后更新：2026-08-03

---

## 1. 分层位置

现有五层（Data → Catalog → Logic → Presentation → Editor）描述的是**地图与编辑**。  
游戏在其上增加对称的 **Game 应用层**：

```text
┌──────────────────────────────────────────────────────────┐
│  Game（应用）  GameDirector / Session / Melee / Trigger   │
│  开局、玩家、规则、输入；不组地形 Mesh、不写 Heightfield   │
└────────────────────────────┬─────────────────────────────┘
                             │ 读地图态 · 调 MapLoader API
┌────────────────────────────▼─────────────────────────────┐
│  Presentation  MapLoader + Layers（共用 map_root.tscn）   │
└─────────────┬──────────────────────────────┬─────────────┘
              │                              │
     Data / Catalog / Logic（scripts/map/）   │
              │                              │
┌─────────────▼──────────────┐   ┌───────────▼─────────────┐
│  Editor（可选同时存在）      │   │  离线资产 / map-parsed   │
└────────────────────────────┘   └─────────────────────────┘
```

| 层 | 游戏侧职责 | 禁止 |
|----|------------|------|
| Game | 生命周期、玩家、对战引导、输入命令、（远期）触发器调度 | 拼 GLB 路径、改 cliff flags |
| map/Presentation | 显示地形/单位/路径/栅格 | 决定「该不该刷农民」 |
| map/Logic | 寻路查询、放置合法性等纯规则 | 持有「当前是第几秒」 |
| map/Data | Heightfield、PathingMap、UnitList 只读视图 | Godot 节点 |

---

## 2. 目录与场景树（目标）

```text
game/
├── scenes/
│   └── game_main.tscn              # 游戏壳
└── scripts/
    ├── game_director.gd            # 总管（对标 MapEditor）
    ├── session/
    │   └── game_session.gd         # 地图路径、玩家、资源、胜负标志
    ├── logic/
    │   ├── melee/
    │   │   └── melee_bootstrap.gd  # 对战初始化（原生动作表）
    │   ├── command/                # 选中、移动命令（阶段 D）
    │   └── trigger/                # 远期：VM / 事件总线
    ├── data/
    │   └── (远期) trigger_def.gd   # wtg 解析后的图数据结构
    └── presentation/
        ├── rts_camera.gd
        └── hud/                    # 简陋资源条等
```

目标场景树：

```text
GameMain (Node3D)                         # 薄壳：环境光 / 灯光（无玩法脚本）
├── MapRoot (instance map_root.tscn)      # 共用 Present（MapLoader）
├── GameDirector (Node)                   # @export map_root / rts_camera / game_hud
├── RtsCamera (instance rts_camera.tscn)
├── GameHud (instance game_hud.tscn)      # 人族 Console UI
├── GameCursor                          # Wc3GameCursor：按种族切 *Cursor.png
└── (可选) WorldEnvironment / Sun
```

**相机取舍（相对 godot_simple_rts / editor）：**

| 采用 | 不采用 |
|------|--------|
| 边缘滚动、WASD/方向键、中键旋转、滚轮缩放、`focus_on_position` | `CharacterBody3D` + `move_and_slide`（地图相机无需物理） |
| 编辑器同款 `Node3D → Pivot → Camera3D` 距离缩放 | `SpringArm3D`（无碰撞拉近需求；距离直接改 camera.z） |
| 右键留给命令（不抢相机） | simple_rts 里过重的全局 Autoload 输入网 |
| 可选地图边界夹紧 | 每单位一个完整 tscn Prefab 作为唯一真相（本项目走 Catalog + Factory） |

**为何不把脚本挂在 GameMain 根上？**  
可以，效果上等价于「根节点 = Director」。拆成子节点是为了与 `MapEditor` 一致：根只负责场景构图（WorldEnvironment / 灯光 / 子场景），**总管**用 `@export` 注入依赖，后续 Session、Melee、输入路由可挂在 Director 下而不污染 Node3D 根。`game_main.gd` 当根脚本也可以，只要 `class_name` 仍是应用控制器、别把逻辑写进 MapLoader。

**与 `scenes/main.tscn`：** 旧预览可保留；新玩法一律走 `game_main`，避免再往 preview 堆业务。

---

## 3. 运行时数据流（阶段 A–C）

```text
启动
  → GameDirector._ready
  → 配置 MapLoader.map_dir = echoisles
  → MapLoader 加载 heightfield / doodads / units（可分帧）
  → 注入 / 合成 Wc3PathingMap → PathingLayer + DebugGrid（开发开关）
  → GameSession.from_parsed(map_dir, units, info)
  → MeleeBootstrap.run(session)          # 阶段 C
       · 清野、刷主城/工人、设资源
  → 相机对准本地 sloc
  → 进入可交互循环（阶段 D）
```

### 3.1 开发期可视化（硬需求）

| 开关 | API | 默认（开发） |
|------|-----|--------------|
| 最小栅格 | `MapLoader.set_view_grid_level(3)` | 开（PATHING_CELL=32） |
| 路径-地面 | `MapLoader.set_show_pathing_ground(true)` | 开 |

发布/「像游戏」配置可再关；逻辑不依赖 overlay 可见性。

### 3.2 权威状态

| 状态 | 权威位置 | 说明 |
|------|----------|------|
| 地形/装饰静态 | 磁盘 JSON → MapLoader 内部缓存 | 游戏阶段 A 只读 |
| 路径 | `Wc3PathingMap`（挂在 Session 或 MapLoader） | 合成或 pathing.json |
| 运行时单位 | **GameSession 单位表**（阶段 C 起）；节点目标为 **Unit 实体根**（子节点才是模型） | 见 [WC3_MODEL_SCENE.md](../presentation/WC3_MODEL_SCENE.md) §2.0 |
| 资源/科技 | GameSession | Bootstrap 写入 |

阶段 A 可暂用「Present 即真相」（MapLoader 已放置的单位节点）；C 起应显式 Session，避免触发器/命令无处落笔。

---

## 4. 触发器架构（远期设计 · 本阶段不实现）

### 4.1 WE 模型（要对齐的语义）

```text
Trigger
  ├─ Events      地图初始化 / 单位死亡 / 时间周期 …
  ├─ Conditions  布尔树
  └─ Actions     有序列表（可含 Wait、If、Loop）
```

常规对战图自带 **Melee Initialization**：Event = 地图初始化；Actions = 上表 8 条「对战游戏 - …」。

本项目中：**同一语义先由 `MeleeBootstrap` 提供原生实现**；触发器 VM 成熟后改为：

- 解析图内 wtg → 得到等价 Trigger 图，或  
- 若图无自定义触发器，则挂「内置 Melee 模板」Trigger  

### 4.2 建议子系统

```text
TriggerRuntime
  ├─ EventBus          引擎事件 → 触发器事件（MapInit、UnitDeath…）
  ├─ ConditionEval     纯函数，读 Session / 地图查询
  ├─ ActionExecutor    动作 ID → 原生处理器（与 MeleeBootstrap 共用实现）
  ├─ TriggerScheduler  Wait / 队列 / 每帧额度（防卡死）
  └─ TriggerStore      当前地图已加载的 Trigger 列表
```

| 组件 | 职责 | 首批动作来源 |
|------|------|----------------|
| ActionExecutor | `MeleeSetResources`、`MeleeCreateStartingUnits`… | **从 MeleeBootstrap 抽接口** |
| EventBus | `map_initialized.emit()` | GameDirector 开局发一次 |
| TriggerStore | 内存图；日后 wtg 填入 | 先手写「内置 Melee」一条 |

### 4.3 数据管线（远期）

```text
war3map.wtg / war3map.j
  → tools/map-parse 增 parsers/wtg.js（或 j 子集）
  → assets/map-parsed/<map>/triggers.json
  → game/data 反序列化 → TriggerStore
```

Echo Isles 的 `summary.json` 已列出 archive 含 `war3map.wtg` / `war3map.j`，但**当前未解析**——符合「先 Bootstrap」策略。

### 4.4 与编辑器的边界

| 能力 | 归属 | 说明 |
|------|------|------|
| 触发器编辑 GUI | `editor/` 远期 | 改 triggers.json / 导出 wtg |
| 触发器执行 | `game/logic/trigger/` | 只在游戏运行 |
| 物体数据 | Catalog + 日后 ObjectEditor | 触发器只读 |

禁止：在 `Map*Layer` 里写「如果是对战就刷农民」。

### 4.5 风险与门禁

- **Wait / 阻塞动作**：必须协程或状态机，禁止 `OS.delay`。  
- **每帧动作预算**：大地图自定义图可能上百触发器。  
- **动作覆盖率**：只实现 Melee + 玩法所需子集；未知动作 log + skip。  
- **确定性**（日后联机）：随机源注入 Session。  

---

## 5. MeleeBootstrap 与触发器的演进关系

```text
阶段 C                         阶段 E
────────                       ────────
MeleeBootstrap.run()    →      ActionExecutor 注册同一批 Handler
  create_starting_units          Trigger「地图初始化」调用相同 Handler
  set_resources
  clear_creeps_near_sloc
```

**不变式：**「创建对战初始单位」只有一份实现；Bootstrap 与 Trigger 都是调用方。

---

## 6. 与现有分层文档的衔接

| 文档 | 关系 |
|------|------|
| [LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) | Game 为第六应用层；map 五层契约不变 |
| [MAP_ARCHITECTURE.md](../../architecture/MAP_ARCHITECTURE.md) | MapRoot 节点树继续是 Present 唯一入口 |
| [editor/EDITOR.md](../editor/EDITOR.md) | 编辑器不负责开局刷兵 |
| [roadmap/ROADMAP.md](../../roadmap/ROADMAP.md) | 地图模块 ①–⑫；玩法见本目录 ROADMAP |

---

## 7. 决策记录

| 日期 | 决策 |
|------|------|
| 2026-08-03 | 开分支 `feature/game-scene-echoisles`；默认图 Echo Isles |
| 2026-08-03 | 开发期默认显示最小栅格 + 路径-地面 |
| 2026-08-03 | **暂缓**完整触发器 VM；先 MeleeBootstrap + 游戏场景壳 |
| 2026-08-03 | 触发器与 Bootstrap 共用 Action Handler，避免双实现 |
| 2026-08-05 | 玩法主线转入人族游玩竖切 F0–F10，见 [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) |
| 2026-08-17 | F0–F6 后插入战斗主线 C0–C3；契约见 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) |
