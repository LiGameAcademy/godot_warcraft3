# 游戏 UI 框架：UiManager 与解耦契约

> 日期：2026-09-27 · 状态：**设计已落骨架，迁移进行中**  
> 配套：[HUD.md](HUD.md) · [HUD_WIDGET_CATALOG.md](HUD_WIDGET_CATALOG.md) · [HUD_LAYOUT_REDESIGN.md](HUD_LAYOUT_REDESIGN.md) · [模块边界](../../architecture/GAMEPLAY_MODULE_BOUNDARIES.md)

## 1. 目标

把 **HUD / 面板 / 模态** 从 `GameDirector` 直调里抽出来：

| 现在 | 目标 |
|------|------|
| Director `_wire_hud` + 多处 `game_hud.set_*` | Director 只绑 **玩法会话**；UI 经 `UiManager` 注册与推送 |
| 面板信号散落到 Director | 统一 **意图总线**（`UiIntent`），再由适配器转发命令 |
| 视图知道 `GameSession` / `TrainQueue` | 视图只吃 **展示快照 / ViewModel** |
| 无全局 UI 入口 | Autoload **`UiManager`**：壳、路由、生命周期；**不是**玩法总管 |

与旧文档「不创建万能 UIManager」不冲突：禁止的是 **包办命令合法性 / 持有权威状态** 的上帝对象；本框架的 `UiManager` 只做 **壳 + 路由 + Presenter 挂载点**。

## 2. 分层

```text
┌─────────────────────────────────────────────────────────────┐
│  UiManager（Autoload）                                        │
│  · 注册 Surface（MatchHud / Loading / Modal）                 │
│  · 推送展示快照 / 转发意图信号                                  │
│  · 挂载 Presenter 宿主（会话级 Node）                          │
└───────────────┬─────────────────────────────┬───────────────┘
                │ push ViewModel              │ UiIntent
┌───────────────▼─────────────┐   ┌───────────▼───────────────┐
│  View（GameHud + panels）    │   │  UiGameplayBridge          │
│  只展示 / 发意图，不查玩法表   │   │  （会话节点，非 Autoload）   │
└─────────────────────────────┘   │  → CommandRouter / Modules │
                                  └─────────────▲─────────────┘
                                                │ 只读快照 / signal
                                  ┌─────────────┴─────────────┐
                                  │  Gameplay（权威）            │
                                  │  Stock · Selector · Queue… │
                                  └───────────────────────────┘
```

| 角色 | 职责 | 禁止 |
|------|------|------|
| **UiManager** | Surface 注册、顶层 tip/modal、意图 fan-out、Presenter 宿主 | 扣费、寻路、改 `unit_data`、持有 `GameSession` 可写引用 |
| **Surface** | 一块完整 UI 壳（对局 HUD、加载屏）实现 `UiSurface` | 跨 Surface 互相 `$` 找节点 |
| **Presenter** | 订 gameplay signal → 组 ViewModel → `UiManager.push_*` | 直接改世界；在 `_process` 无节流刷整卡 |
| **View / Panel** | 渲染 ViewModel；发出 `UiIntent` | `preload` 玩法 Catalog 做合法性（图标路径由 VM 带入） |
| **UiGameplayBridge** | 会话内把意图译成 `CommandRouter` / Module API | 反向依赖具体 Panel 类型 |

## 3. UiManager API（契约）

路径：`apps/game/client/ui/ui_manager.gd` · Autoload 名 **`UiManager`**。

```text
# Surface
register_surface(id: StringName, surface: UiSurface) -> void
unregister_surface(id: StringName) -> void
get_surface(id: StringName) -> UiSurface
set_active_surface(id: StringName) -> void   # 对局 HUD / 菜单互斥时可扩展

# 展示（下行）— 先覆盖高频入口，面板细化仍可走 Surface 强类型 API
push_resources(vm: Dictionary) -> void
push_selection(vm: Dictionary) -> void
push_command_card(entries: Array) -> void
push_status(text: String) -> void
show_tip(text: String) -> void              # 命令飘字等

# 意图（上行）
signal intent(intent_id: StringName, payload: Dictionary)
emit_intent(intent_id: StringName, payload: Dictionary = {}) -> void

# 会话
bind_session(bridge: Node) -> void          # 通常为 UiGameplayBridge
unbind_session() -> void
```

约定：

- `StringName` 意图 id 集中在 `UiIntent`（`command` / `train_cancel` / `item_use` …），禁止魔法字符串散落。
- `payload` 只带 **稳定身份**（`unit_instance_id`、`task_id`、`action_id`、槽位），不传活 `Node3D` 给 View。
- 对局未 `bind_session` 时，意图可丢弃或打开发日志，不崩溃。

## 4. Surface：MatchHud

第一块 Surface = 今日 `GameHud`（`scenes/game_hud.tscn`）。

| 步骤 | 动作 |
|------|------|
| 1 | `GameHud` 实现 `UiSurface`（`surface_id = &"match_hud"`） |
| 2 | `_ready`：`UiManager.register_surface(...)`；`tree_exiting` 注销 |
| 3 | 现有 `command_action` 等信号改为 `UiManager.emit_intent(UiIntent.COMMAND, {action_id})`（过渡期可双发） |
| 4 | Director 去掉逐条 `game_hud.xxx.connect`，改为 Bridge 订 `UiManager.intent` |

面板（ResourceBar / CommandPanel / …）**不**直接注册到 Autoload；只挂在 Surface 下。

## 5. Presenter 清单（从 Director 迁出）

| Presenter | 现有落点 | 订阅 | 推送 |
|-----------|----------|------|------|
| ResourcePresenter | MatchBootstrap `bind_stock` | `PlayerStock` 变化 | `push_resources` |
| SelectionPresenter | `SelectionHudModule` | Selector / Life / Buff | `push_selection` |
| CommandPresenter | `CommandCardModule` | 选中 + 冷却 | `push_command_card` |
| ProductionPresenter | `ProductionPanel` | TrainQueue | 队列 VM + tip |
| MinimapPresenter | Director 相机/地图 | 镜头/单位点 | Surface 小地图 API |

Presenter 挂在 **UiManager 子节点或 Bridge 子节点**（会话生命周期），随 `unbind_session` 释放，避免 Autoload 堆积对局引用。

## 6. 意图表（初版）

| `UiIntent` | payload 关键字段 | Bridge 转发 |
|------------|------------------|-------------|
| `COMMAND` | `action_id`, `source` | CommandCardModule.dispatch |
| `COMMAND_RCLICK` | `action_id` | dispatch_rclick |
| `TRAIN_CANCEL` | `slot` / `task_id` | ProductionPanel.cancel |
| `ITEM_USE` / `ITEM_DROP` / `ITEM_SWAP` | `slot`, `slot_b` | ItemsModule |
| `MULTI_SELECT` | `instance_id` | UnitSelector |
| `MINIMAP_CLICK` | `uv` | 相机（非单位命令） |
| `TIP_ACK` | （可选） | 仅 UI |

扩展新按钮 = 加意图常量 + Bridge 一处 `match`，不改 `UiManager` 内核。

## 7. 目录

```text
apps/game/client/ui/
  ui_manager.gd          # Autoload
  ui_intent.gd           # StringName 常量
  ui_surface.gd          # 接口（可 extends RefCounted / 约定方法）
  ui_gameplay_bridge.gd  # 会话适配器（后续从 Director 长出）
  presenters/            # 迁入后的 Presenter（可先空）

apps/game/client/hud/    # View：GameHud + panels（保持）
```

共享 Theme / 无玩法基础控件若编辑器也要用，再上提 `packages/`；**Match HUD 与 Bridge 留在 `apps/game`**。

## 8. 迁移阶段

| 阶段 | 交付 | 验收 |
|------|------|------|
| **M0** | 本文档 + `UiManager` Autoload + `UiIntent` / `UiSurface` 骨架 | 工程可启动；无行为回归 |
| **M1** | `GameHud` 注册为 `match_hud`；`show_tip` / `set_status` 走 UiManager | 训兵资源飘字仍可见 |
| **M2** | 命令/背包/取消等意图改 `emit_intent`；Bridge 订阅 | 命令卡全路径自测绿 |
| **M3** | Selection / Command / Resource Presenter 迁出 Director 直调 | Director 不再 `game_hud.set_selection_info` 散落 |
| **M4** | 删除过渡双发；补 selftest：意图路由、未 bind 不崩 | `selftest_ui_manager` |

**不做：** 第一期把编辑器 HUD 并进同一 Autoload；不做跨对局缓存单位 Node。

## 9. 与现有文档对齐

- [HUD_WIDGET_CATALOG.md](HUD_WIDGET_CATALOG.md)：控件四级不变；增加「经 UiManager 推送 / 意图」一句。
- [HUD_LAYOUT_REDESIGN.md](HUD_LAYOUT_REDESIGN.md) §9：将「不创建万能 UIManager」改为「允许壳单例，禁止玩法上帝对象」并链本文。
- 信号驱动规则（`.cursor/rules/hud-signal-driven.mdc`）仍然有效：Presenter 订 signal，禁止无脑每帧全量刷卡。

## 10. 非目标

- 用 UiManager 替代 `GameDirector` 开局/胜负。
- 在 Autoload 里 `load` SLK / 判 Requires。
- 为「目录整齐」预建空 Presenter 文件而不接线。
