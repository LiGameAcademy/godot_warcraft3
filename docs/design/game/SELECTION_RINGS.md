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

**HUD 阻挡**：移除「屏幕底部 22% 整条屏蔽」，改为按 `world_input_blockers` 组里的实际可见 Control 矩形判定；读取 `gui_get_hovered_control()` 时再校验事件当前位置。框选进行中**不**调 `is_blocked_at`，确保松开事件不被底栏吞掉。

---

## 8. 选中集合与状态

`UnitSelector` 是「当前选中」唯一权威：

```
_primary: Node3D       # 主选（命令卡 / 肖像跟随）
_selected: Array[Node3D]  # 选中集合（无原作 12 人上限）
```

- 对外：`get_primary()` / `get_selected()` / `select_node()` / `clear_selection()` / `deselect_unit()` / `set_primary()` / `cycle_primary()`
- 信号：`selection_changed(primary, selected)` —— 命令卡 / HUD / SelectionPresenter / InteractionModule 都订此信号
- 入树：`setup(camera, unit_host)` 由 `GameMain` / `GameDirector._setup_selector` 注入（无自救反查）

**环显示**：选区变化 → `_refresh_rings` 只对旧/新差集 set 状态，重复点同一集合不重画。`InteractionSetup.attach` 只在 `show_*` 真正需要时才装，地图装配不批量实例化选中组件。

**世界在场**：`WorldMembership.is_in_world(n) == false`（进矿 / 工地 / 训练中）的单位既不点选也不框选。

---

## 9. 当前边界 / 待办

- 拾取是 CPU 模型表面 + 脚底圆兜底，**不是**完整 GPU picking 管线
- 没有地形 / 其他场景物体的全局遮挡（地形穿越也算命中），战争迷雾独立层处理
- 未知自定义 ShaderMaterial 按不透明表面处理；当前队色材质符合此规则
- `SelectableComponent.RingKind` 仍有 ENEMY/ALLY 枚举值，但 `ring_kind()` 实际只返 OWN/NEUTRAL —— 若要严谨可收窄枚举
- HUD 阻挡依赖 `world_input_blockers` 组 + `gui_get_hovered_control` 兜底（逻辑在 `SelectorInputGate`，不在 UnitSelector）

---

## 10. `UnitSelector` 拆分（已落地）

`UnitSelector` ≈ **320–430 行**：选区状态机 + LMB 手势；拾取 / HUD / 绿框绘制已外提。

### 10.1 结构

```
UnitSelector（瘦）                Node    选区状态机 + 信号 + 手势
  ├─ SelectionPicker             Node    拾取 + 框选命中
  └─ SelectorInputGate            Node    HUD 阻挡（world_input_blockers 组）

GameMain 平级：
  ├─ SelectorInputLayer          CanvasLayer=5  WorldInput 壳（正式对局不订 gui_input）
  └─ SelectorOverlayLayer        CanvasLayer=100 → MarqueeOverlay

外部静态 / RefCounted：
  ├── UnitPickVolume
  ├── MarqueeSelection / MarqueeOverlay
  └── InteractionSetup / Selectable / Interactable / SelectionRing
```

### 10.2 职责边界

| 模块 | 职责 | 不负责 |
|------|------|--------|
| `UnitSelector` | `_primary` / `_selected` / 手势 / hover / 环刷新 / `selection_changed` / `is_blocked_at` | 几何命中细节、组扫描细节 |
| `SelectionPicker` | `pick_at` / `pick_in_rect` / `iter_unit_nodes`；半径走 `SelectableComponent` | 选中集合 |
| `SelectorInputGate` | `is_blocked_at`（组 + hovered）；`set_exempt_controls` | 输入事件、选中态 |
| `SelectorInputLayer` | 提供 `world_input()` Control | 业务信号转发 |
| `SelectorOverlayLayer` | `bind_marquee` → 绿框绘制 | 拾取 |

### 10.3 注入与输入

- `UnitSelector.input_layer_path` / `overlay_layer_path`：`NodePath`（场景里写相对路径）；独立 selftest 可留空。
- `GameDirector.unit_selector: UnitSelector`；`_setup_selector` 调 `setup(cam, layer)`（无哑参数）。
- 正式对局：`MatchInputController` → `handle_pointer_event`（`set_external_input(true)`）。
- 独立嵌入：`set_external_input(false)`，可订 `WorldInput.gui_input`。

### 10.4 迁移清单

1. `SelectionPicker`：✅
2. `SelectorInputGate`：✅（仅组扫描；已删未用的 `add_blocker`）
3. overlay / input 外部子场景：✅
4. 删除 `_try_autobind` + 输入合一 + `is_blocked_at`：✅
5. 拾取半径：`SelectableComponent.estimate_pick_radius_world` 单一来源：✅

### 10.5 验收

- [x] `UnitSelector` 不再自建 CanvasLayer；不直接扫 `world_input_blockers`
- [x] 拾取半径共享 `SelectableComponent.estimate_pick_radius_world`
- [x] `tests/unit/selftest_unit_selection.tscn` 33 项继续通过
- [ ] 媒体测试 21 项（按需跑）

---

## 11. 已知变更

- 2026-09-25 [SELECTION_FIX.md](SELECTION_FIX.md)：包围盒粗筛 → 模型表面 + 透明孔洞继续向后；骨骼姿态 CPU 缓存；按下即选中；HUD 按可见矩形分组；`MatchInputController` 独占输入。
- 2026-10-01 清理 `UnitSelector.RingKind` 旧枚举与未引用入口；环颜色与直径只走 `SelectableComponent` / `SelectionRing`。
- 2026-10-01 瘦身 UnitSelector（去自救/重复输入）；删 `assets/visuals`；InputLayer 去死信号；Gate 单轨；半径估计上收。
