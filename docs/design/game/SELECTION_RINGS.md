# 选中环与目标环（Selection / Target Rings）

> 对齐 WC3：己方选中 **绿环**；中立金矿左键可选 **黄环**（树**不可**左键选中，只右键伐木）。  
> 所属层：场景 `scenes/selection/`（环 / UnitSelector）+ 脚本 `scripts/shared/selection/`（组件 / 框选）；游戏与编辑器共用。  
> 相关：[GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [TREE_INTERACT.md](TREE_INTERACT.md) · [HUD.md](HUD.md) · [SELECTION_FIX.md](SELECTION_FIX.md)  
> 最后更新：2026-10-01（拾取几何与输入所有权定稿）

---

## 1. 组件拆分

```text
scenes/selection/          # 带场景的节点
  selection_ring.tscn/.gd
  unit_selector.tscn/.gd

scripts/shared/selection/  # 纯脚本组件
  selectable / interactable / interaction_setup
  marquee_selection / marquee_overlay

InteractionSetup.attach(host)   # 刷单位 / promote / 悬停懒挂
  ├── SelectionRing（tscn 子节点，默认隐藏）
  ├── SelectableComponent（注入 ring）
  └── InteractableComponent（注入 ring + selectable）

UnitSelector（中央：输入 / 2D 脚底圆 / 框选 / 悬停）
  └── 只调 Selectable.show_selected / show_hover / hide_*
```

| 组件 | 职责 | 不负责 |
|------|------|--------|
| `SelectionRing` | 选中 / 悬停 / 交互闪；脚底 `Y_BIAS` 抬高 | 按节点名查找、静态工厂 |
| `SelectableComponent` | 拾取半径、环径、选中/悬停态 | 自行 new 环 |
| `InteractableComponent` | `flash()` | SmartTarget 裁决 |
| `InteractionSetup` | 装配并注入依赖 | 输入 |

树木未 promote 前无 Node：仍由 `TreeRegistry` 拾取；promote 后 `InteractionSetup.attach(..., TREE)`。**悬停不显示树环。**

---

## 2. 拾取管线（点选 / 框选靠什么）

**不依赖** `.scn` 里的 `CollisionShape` / 物理射线。

| 步骤 | 做法 |
|------|------|
| 点选 | 相机射线 ∩ 单位脚底水平面 → 世界 XZ 距 ≤ `pick_radius_world` |
| 框选 | 脚底投影落在框内，或脚底圆与屏幕框相交 |
| 候选集 | `unit_host` 下带 `unit_data` 的 Node3D（树木走 `TreeRegistry`，不进左键选中） |

为何不用物理：会先打到单位网格/选中环，目标变成「自己脚下」（见 `GameDirector` 地面点注释）。

**拾取半径**（世界单位）：`UnitBalance.collision × WORLD_SCALE` → 否则 `UnitUI.scale` → 再与 mesh XZ 有限混合；有上下限。  
这是 **SLK / 配置数据**（碰撞半径），**不是** `.scn` collision mesh。

**选中环直径**：`Wc3IdCatalog.selection_diameter_wc3` — 优先 `path_tex` 脚印格、再 `collision×2`、`UnitUI` Selection Scale；单位再乘系数并与 mesh 混合。同样是配置/Catalog，不是 scn。

**应否依赖 scn collision？** **否。** 保持脚底 2D 圆：与 WC3 脚底选框一致、与网格复杂度解耦、避免环/贴花干扰射线。

**模型表面优先**（2026-09-25 修复）：`UnitPickVolume` 在 `_pick_at` 中先对每个候选做 AABB 初筛，再对可见 MeshInstance3D 的三角面求最近命中。身体命中 > 单位脚底圆 > 建筑脚底圆。包围盒只做粗筛，命中点必须在模型**实际可见的三角形**上。详见 [SELECTION_FIX.md](SELECTION_FIX.md)。

**脚底容错兜底**（仅在没有表面命中时）：
- 单位 `FOOT_FALLBACK_UNIT_PX ≈ 10`
- 建筑 `FOOT_FALLBACK_BUILDING_PX ≈ 8`
- 同点多圆重叠：建筑半径有 `BUILDING_RADIUS_SCORE_MUL = 0.35` 惩罚，避免大圆抢走小单位

**骨骼 / 形态网格**：CPU 端用当前骨骼姿态刷新候选网格，结果每帧缓存，避免悬停时反复从 GPU 读回。BlendShape 走 `bake_mesh_from_current_blend_shape_mix`。

---

## 3. 环色与悬停

| 情形 | 环 | 说明 |
|------|-----|------|
| 选中己方 | 绿、不透明 | primary 多选时可略亮，非 primary 淡 |
| 选中中立金矿 | 黄 | 可点选、不可框选 |
| 悬停单位/建筑（未选中） | 同色系、`HOVER_ALPHA≈0.42` | 树木不显示 |
| 树木 | — | 不可左键选中；右键伐木用闪环 |
| 移动确认 FX | 另套贴花 | 不是脚底选中环 |

`Y_BIAS ≈ 0.16`：环略高于地面 UberSplat，减轻被建筑底图遮挡 / 地形穿插。

---

## 4. 分层

| 层 | 职责 |
|----|------|
| Logic / Session | `RingKind`、owner、是否可框选 |
| Presentation | `SelectionRing` 贴图 + modulate + Y_BIAS |
| Catalog / DefStore | collision、path_tex、Selection Scale → 半径/直径 |
| Data | 不存环；金矿在 `unit_data`，树在 doodad |

禁止：在 Layer 里写「点了谁算黄」；颜色决策在 `SelectableComponent.ring_kind` / selector。

---

## 5. 验收

- [ ] 点选/框选不依赖物理 collision。  
- [ ] 选中己方绿环；金矿黄环；树左键无环。  
- [ ] 悬停单位/建筑：半透明环；移开消失；已选中不再叠悬停。  
- [ ] 悬停树木：无环。  
- [ ] 建筑底图贴花下选中环仍可见（略抬高）。  

---

## 6. 相关代码

| 路径 | 角色 |
|------|------|
| `scenes/selection/` | SelectionRing、UnitSelector |
| `scripts/shared/selection/` | Selectable / Interactable / InteractionSetup、框选 |
| `scripts/map/catalog/wc3_id_catalog.gd` | `selection_diameter_wc3` |
| `game/app/game_director.gd` | `_setup_selector`、装配 |
| `game/scripts/logic/selection_info_builder.gd` | HUD 选中信息 |
| `game/scripts/presentation/target_flash_fx.gd` | 右键目标闪 |
| `game/scripts/presentation/move_confirm_fx.gd` | 命令确认（勿混） |

---

## 7. 输入所有权与按下即选中

**只有 `MatchInputController` 拥有左键世界点击。**

- `UnitSelector` 默认 `set_process_input(false)`，独立场景可通过 `set_external_input(false)` 恢复自身 `_input`
- `MatchInputController.configure({selector, ...})` 把新 selector 的 `_external_input = true`（停用自身 `_input`）；旧实例同样置 `true`，避免它被替换后还继续抢事件
- 顺序：背包点击 → 命令/技能瞄准 → UnitSelector 点选/框选 → 其余

**按下即选中**（修复 #3）：
- 按下立刻 `_pick_at` 并 `_set_selection([hit])`，HUD 当帧就能拿到主选
- 拖动阈值 = `click_slop_px`（默认 8 px），手抖不会变框选
- 松开时若仍在阈值内 → 保留按下命中；若拖出框 → 执行 `_select_in_rect`
- 重复点同一单位不再重建命令卡 / 详情 / 肖像 / 集结反馈

**HUD 阻挡**：移除「屏幕底部 22% 整条屏蔽」，改为按 `world_input_blockers` 组里的实际可见 Control 矩形判定；读取 `gui_get_hovered_control()` 时再校验事件当前位置。框选进行中**不**调 `_hud_blocks_screen`，确保松开事件不被底栏吞掉。

---

## 8. 选中集合与状态

`UnitSelector` 是「当前选中」唯一权威：

```
_primary: Node3D       # 主选（命令卡 / 肖像跟随）
_selected: Array[Node3D]  # 选中集合（无原作 12 人上限）
```

- 对外：`get_primary()` / `get_selected()` / `select_node()` / `clear_selection()` / `deselect_unit()` / `set_primary()` / `cycle_primary()`
- 信号：`selection_changed(primary, selected)` —— 命令卡 / HUD / SelectionPresenter / InteractionModule 都订此信号
- 入树：`setup(camera, unit_host)` 由 `GameDirector._setup_selector` 注入；失败时 `_try_autobind` 自救但应走 `setup`

**环显示**：选区变化 → `_refresh_rings` 只对旧/新差集 set 状态，重复点同一集合不重画。`InteractionSetup.attach` 只在 `show_*` 真正需要时才装，地图装配不批量实例化选中组件。

**世界在场**：`WorldMembership.is_in_world(n) == false`（进矿 / 工地 / 训练中）的单位既不点选也不框选。

---

## 9. 当前边界 / 待办

- 拾取是 CPU 模型表面 + 脚底圆兜底，**不是**完整 GPU picking 管线
- 没有地形 / 其他场景物体的全局遮挡（地形穿越也算命中），战争迷雾独立层处理
- 未知自定义 ShaderMaterial 按不透明表面处理；当前队色材质符合此规则
- `SelectableComponent.RingKind` 仍有 ENEMY/ALLY 枚举值，但 `ring_kind()` 实际只返 OWN/NEUTRAL —— 若要严谨可收窄枚举
- `UnitSelector` 仍偏胖：输入层 / HUD 阻挡 / 拾取裁决 / 环刷新挤在一个 Node —— 后续可按职责再拆
- `_try_autobind` 是 Director 失败时的自救，正式路径应只靠 `setup`

---

## 10. `UnitSelector` 拆分方案（待落地）

当前 `UnitSelector` ≈ 735 行，混了 4 件事。下面是按职责组合、**不强抽接口**的拆分草案；落地前仍要 review。

### 10.1 拆分目标

```
UnitSelector（瘦）                Node    选区状态机 + 信号
  ├─ SelectionPicker             Node    拾取 + 框选命中（挂 UnitSelector 下）
  ├─ SelectorInputGate            Node    透明 Control + HUD 阻挡查询
  └─ SelectorOverlayLayer        Node    框选矩形绘制（现状 MarqueeOverlay 升级）

外部静态 / RefCounted（不动）：
  ├── UnitPickVolume                      AABB + 三角面拾取
  ├── MarqueeSelection / MarqueeOverlay   框选矩形状态与绘制
  └── InteractionSetup / Selectable / Interactable / SelectionRing  环组件（已正分层）
```

### 10.2 各模块职责边界

| 模块 | 职责 | 不负责 |
|------|------|--------|
| `UnitSelector` | `_primary` / `_selected` / `select_node` / `cycle_primary` / `set_primary` / `deselect_unit` / `selection_changed`；委托 `SelectionPicker` / `SelectorInputGate` | 拾取计算、HUD 判定、自身 `_input` 接管 |
| `SelectionPicker` | `_iter_unit_nodes` / `_pick_at` / `_ray_foot_plane_hit` / `_footprint_in_marquee` / `_pick_in_rect`；暴露 `pick_at(screen)` / `pick_in_rect(rect)` | 选中集合、HUD 判定、信号 |
| `SelectorInputGate` | `_input_root` / `_hud_blocks_screen` / `_is_ui_control_blocking`；维护自身 blocker 列表 + 与 `world_input_blockers` 组并轨 | 选中状态、拾取 |
| `SelectorOverlayLayer` | 框选矩形 + 后续选中信息 VM | 拾取、HUD 阻挡 |

### 10.3 接口（草案）

```gdscript
class_name SelectionPicker extends Node
func bind(camera: Camera3D, unit_host: Node) -> void
func pick_at(screen_pos: Vector2) -> Node3D
func pick_in_rect(rect: Rect2) -> Array[Node3D]
func iter_unit_nodes() -> Array[Node3D]   # 给 SelectableComponent.attach 用
```

```gdscript
class_name SelectorInputGate extends Node
signal blocker_changed()                  # 用于 HUD 调试
func bind(viewport: Viewport) -> void
func is_blocked_at(screen_pos: Vector2) -> bool
func add_blocker(ctrl: Control) -> void   # HUD 模块主动注册（推荐）
func remove_blocker(ctrl: Control) -> void
func ensure_input_layer(canvas_layer: int) -> Control  # 给 UnitSelector 创建透明层
## 兼容旧 API：仍扫描 world_input_blockers 组。add/remove 是补充，不是替代。
```

```gdscript
class_name UnitSelector extends Node          # 瘦版
@export var input_layer: SelectorInputLayer  # 由 GameMain 注入；亦可 @export 默认场景
@export var overlay_layer: SelectorOverlayLayer
var picker: SelectionPicker
var gate: SelectorInputGate

func setup(camera: Camera3D, unit_host: Node) -> void  # 内部实例化 children
func handle_pointer_event(event: InputEvent) -> bool  # 转发给 gate + picker + self
func set_external_input(value: bool) -> void
func select_node(node: Node3D) -> void
func deselect_unit(node: Node3D) -> void
func clear_selection() -> void
func set_primary(node: Node3D) -> bool
func cycle_primary(step: int = 1) -> bool
func get_primary() -> Node3D
func get_selected() -> Array[Node3D]
signal selection_changed(primary: Node3D, selected: Array)
```

```gdscript
class_name SelectorInputLayer extends CanvasLayer
## 透明世界点击层。仅转发 gui_input，不处理业务。
signal gui_input_received(event: InputEvent)
func _on_world_gui_input(event: InputEvent) -> void:
    gui_input_received.emit(event)
```

```gdscript
class_name SelectorOverlayLayer extends CanvasLayer
## 高图层（layer=100）。绑 MarqueeSelection 状态，画框选矩形。
func bind_marquee(marquee: MarqueeSelection) -> void
```

### 10.3.1 子场景形态

```text
selector_input_layer.tscn
  SelectorInputLayer (CanvasLayer, layer=5)
    └─ WorldInput (Control, mouse_filter=Ignore, gui_input→ SelectorInputLayer._on_world_gui_input)

selector_overlay_layer.tscn
  SelectorOverlayLayer (CanvasLayer, layer=100)
    └─ OverlayRoot (Control, full rect, mouse_filter=Ignore)
         └─ MarqueeOverlay (绑 marquee)
```

`GameMain.tscn` 把这两个子场景作为平级子节点挂上，通过 `game_main.gd._setup_unit_selector` 注入到 `UnitSelector.input_layer` / `UnitSelector.overlay_layer`。这样：

- 子场景结构可在编辑器里直接看到/调整
- 选择器不创建子节点，只绑定外部引用
- HUD 模块可独立访问 `SelectorInputLayer` 做调试/改造

### 10.4 迁移路径（步骤）

1. **新增 `SelectionPicker`（Node，挂在 `UnitSelector` 下）**：把 `_iter_unit_nodes` / `_pick_at` / `_ray_foot_plane_hit` / `_footprint_in_marquee` / `_pick_radius_of` / `_select_in_rect` 全搬过去。`UnitSelector` 保留 `picker.pick_at(...)` / `picker.pick_in_rect(rect)` 调用。无外部行为变化。
2. **新增 `SelectorInputGate`**：搬 `_hud_blocks_screen` / `_is_ui_control_blocking` / `_ensure_input_layer` / `_input_root`。`UnitSelector.handle_pointer_event` 改成 `if gate.is_blocked_at(pos): return false`，其余逻辑保持。
3. **overlay 升 `SelectorOverlayLayer`**：现有 `_ensure_overlay` 逻辑搬走，挂在 UnitSelector 下。
4. **删除 `_try_autobind` 的选择器自救**（独立场景走 `set_external_input(false)` + 自有 setup；正式对局由 `GameDirector._setup_selector` 注入）。
5. **删除旧的 `RingKind` / 旧兼容入口**（已完成 2026-10-01）。

### 10.5 迁移前后对照

| 现有方法 | 迁移后归属 | 调用方是否变 |
|---|---|---|
| `_pick_at` / `_select_in_rect` | `SelectionPicker.pick_at` / `pick_in_rect` | 否）`UnitSelector` 内部调用） |
| `_iter_unit_nodes` / `_pick_radius_of` / `_node_is_building` / `_type_id_of` / `_owner_of` / `_allows_marquee` | `SelectionPicker`（部分改 `static`，因为它们不依赖相机） | 否 |
| `_hud_blocks_screen` / `_is_ui_control_blocking` / `_ensure_input_layer` | `SelectorInputGate` | 否 |
| `_ensure_overlay` / `MarqueeOverlay.bind` | `SelectorOverlayLayer` | 否 |
| `_update_hover` / `_clear_hover` / `_refresh_rings` | 留在 `UnitSelector`（选中状态机部分） | 否 |
| `select_node` / `deselect_unit` / `set_primary` / `cycle_primary` / `_set_selection` / `_refresh_rings` | 留在 `UnitSelector` | 否 |
| `_input` / `_on_world_gui_input` / `_process` 兜底 | 留在 `UnitSelector`（独立嵌入场景） | 否）已默认关） |
| `MatchInputController.configure` / `GameDirector._setup_selector` | 不变 | — |
| HUD / 命令卡 / InteractionModule / SelectionPresenter 订阅 `selection_changed` | 不变 | — |

### 10.6 边界与风险

- **`SelectionPicker` 选 Node**：随选择器同生共死，省心；候选集索引不需额外存。如果未来要做「多选择器实例」或多视口选择器，可加重构。
- **`world_input_blockers` 保留**：HUD 侧需跟着调用 `gate.add_blocker` 才能真正阻断，不依赖选择器接错顺序。
- **`handle_pointer_event` 仍由 `UnitSelector` 持有**：作为薄壳：事件 → Gate 拦截 → Picker 选人 → `set_selection`。中央路由不需改。
- **独立嵌入场景**：selftest / 预览场景仍可 `set_external_input(false)` 启用自身 `_input`；挑选器默认走中央路由。
- **不动 `InteractionSetup` / `Selectable` / `Interactable` / `SelectionRing`**，它们已经是正确分层。
- **不动测试**：`selftest_unit_selection.tscn` / `selftest_match_input.tscn` 等不需改。

### 10.7 验收

- [ ] `UnitSelector` 文件 ≤ 400 行；不依赖 `get_viewport().gui_get_hovered_control()` / `get_tree().get_nodes_in_group(...)`
- [ ] `SelectionPicker` / `SelectorInputGate` 可在测试中独立挂载
- [ ] `world_input_blockers` 行为不变（中央路由转发后仍是同一组查询）
- [ ] HUD 模块可选调用 `add_blocker` 主动注册
- [ ] `tests/unit/selftest_unit_selection.tscn` 33 项、媒体测试 21 项继续通过

---

## 10. 已知变更

- 2026-09-25 [SELECTION_FIX.md](SELECTION_FIX.md)：包围盒粗筛 → 模型表面 + 透明孔洞继续向后；骨骼姿态 CPU 缓存；按下即选中；HUD 按可见矩形分组；`MatchInputController` 独占输入。
- 2026-10-01 清理 `UnitSelector.RingKind` 旧枚举与未引用入口（`ring_kind_for` / `selection_ring_diameter_for`）；环颜色与直径只走 `SelectableComponent` / `SelectionRing`。
