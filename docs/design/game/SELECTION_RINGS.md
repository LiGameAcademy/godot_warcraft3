# 选中环与目标环（Selection / Target Rings）

> 对齐 WC3：己方选中 **绿环**；中立金矿左键可选 **黄环**（树**不可**左键选中，只右键伐木）。  
> 所属层：场景 `scenes/selection/`（环 / UnitSelector）+ 脚本 `scripts/shared/selection/`（组件 / 框选）；游戏与编辑器共用。  
> 相关：[GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [TREE_INTERACT.md](TREE_INTERACT.md) · [HUD.md](HUD.md)  
> 最后更新：2026-08-16

---

## 1. 组件拆分

```text
scenes/selection/          # 带场景的节点
  selection_ring.tscn/.gd
  unit_selector.tscn/.gd

scripts/shared/selection/  # 纯脚本组件
  selectable / interactable / interaction_setup
  marquee_selection / marquee_overlay

InteractionSetup.attach(host)   # 刷单位 / promote 时
  ├── SelectionRing（tscn 子节点，默认隐藏）
  ├── SelectableComponent（注入 ring）
  └── InteractableComponent（注入 ring + selectable）

UnitSelector（中央：输入 / 2D 脚底圆 / 框选）
  └── 只调 Selectable.show_selected / hide_selected
```

| 组件 | 职责 | 不负责 |
|------|------|--------|
| `SelectionRing` | 实例方法：选中显示 / 隐藏 / 交互闪 | 按节点名查找、静态工厂 |
| `SelectableComponent` | 半径、环色、选中态 | 自行 new 环 |
| `InteractableComponent` | `flash()` | SmartTarget 裁决 |
| `InteractionSetup` | 装配并注入依赖 | 输入 |

树木未 promote 前无 Node：仍由 `TreeRegistry` 拾取；promote 后 `InteractionSetup.attach(..., TREE)`。

---

## 1. 问题

现状 `UnitSelector` 己方绿环 / 中立黄环已分色。  
框选：`marquee_owner = local_player` → **不可多选**中立/敌对（点选金矿仍可）。

原作观感（人族竖切最小集）：

| 情形 | 环色 | 说明 |
|------|------|------|
| 选中己方单位 / 建筑 | **绿** | 当前已有 |
| 选中中立金矿 `ngol` | **黄** | 左键**点选**可选；**不可框选** |
| 可伐树木 | — | **不可左键选中**（与原作一致）；右键下令伐木 |
| 选中敌方（远期） | **红** | 点选信息可后置；**不可框选** |
| 选中友军（远期） | **蓝** | 本竖切可后置 |
| 移动 / 攻击地面确认 FX | 另套贴花 | 已有 `move_confirm_fx`，**不是**脚底选中环 |

本文件只定 **脚底选中环** 契约；命令确认 FX 不混入。

---

## 2. 目标与非目标

**目标**

- 左键选中：己方 → 绿；中立金矿 → 黄 + HUD 储量。  
- 树木：**不**进左键拾取；promote 仅由伐木/伤害触发。  
- 环尺寸仍读 Catalog / 碰撞近似（与现 `UnitSelector` 一致）。  
- API 可扩展敌/友色，但 P0 只落地绿 + 黄。  
- **多选当前选中（primary）**：环可对 primary 更高亮、其余略淡（与 [HUD.md](HUD.md) §4 联动；Tab 切主选）。  
- **框选人数**：不设原作 12 上限。

- 右键交互目标（金矿 / 送回建筑 / 工地 / 树）：`TargetFlashFx` 黄环闪一下表示收到指令；不进左键选中集合。

**非目标（P0）**

- 鼠标悬停预览环（hover）。  
- 多选混合颜色规则的精细化（多选中立时全黄即可）。  
- 编辑器 doodad 笔刷环改色（可继续用绿作编辑提示）。

---

## 3. 分层

| 层 | 职责 |
|----|------|
| Logic / Session | 判定 `RingKind`：owner、是否中立可交互、是否建筑 |
| Presentation | `SelectionRing` 贴图 + modulate；挂到目标 Node3D 脚下 |
| Catalog | 环贴图路径（可先共用 `SelectionCircleMed.png`）；可选 scale |
| Data | 不存环；金矿在 `unit_data`，树在 doodad `creationNumber` |

禁止：在 Layer 里写「点了谁算黄」；颜色决策集中在 selector / 一处 `ring_kind_for(node)`。

---

## 4. API 草案

```gdscript
enum RingKind {
	NONE = 0,
	OWN = 1,       ## 己方 → 绿
	NEUTRAL = 2,   ## 中立可交互 → 黄
	ENEMY = 3,     ## 远期红
	ALLY = 4,      ## 远期蓝
}

## 根据节点 meta / owner 解析环种类（唯一决策点）
func ring_kind_for(node: Node3D) -> int

## 创建或更新脚下环；color 由 kind 映射，禁止调用方直接传随意色（除调试）
func ensure_ring(node: Node3D, kind: int) -> void
```

颜色常量（起步值，可微调对齐截图）：

```text
OWN     ≈ Color(0.15, 1.0, 0.25)   ## 现有绿
NEUTRAL ≈ Color(1.0, 0.92, 0.15)  ## 黄
ENEMY   ≈ Color(1.0, 0.15, 0.12)  ## 预留
ALLY    ≈ Color(0.25, 0.55, 1.0)  ## 预留
```

**金矿**：`typeId == ngol`（或 owner 中立 + 可采）→ `NEUTRAL`。  
**树**：promote 节点带 `doodad_data` / `tree_runtime` meta，且可选 → `NEUTRAL`。  
**己方农民 / 主城**：`OWN`。

---

## 5. 拾取范围

| 目标 | 拾取 | 环挂载 |
|------|------|--------|
| 单位 / 建筑（含 ngol） | `UnitSelector`：**脚底水平面 2D 圆**（非 3D 胶囊）；框选同圆/脚底 | 单位 Node |
| 树木 | `TreeRegistry` 同款脚底圆；**不**对 MultiMesh GPU 拾取 | promote Node |

左键选中树时：若仍为 MultiMesh，**先 promote 再挂黄环**（与受伤入口可共用 promote，见树文档 §4）。

---

## 6. 实现步骤（建议）

1. `UnitSelector`：抽出 `RingKind` + `ring_kind_for`；`_make_ring` / `_update_ring` 吃 kind。  
2. 金矿选中验收：点 ngol → 黄环；点农民 → 绿环。  
3. 树：等 `TreeInteract.promote` 可用后，selector 增加 doodad 拾取分支 + 黄环。  
4. ✅ 环 / UnitSelector 在 `scenes/selection/`；组件与框选在 `scripts/shared/selection/`。

---

## 7. 验收

- [ ] 选中己方农民 / 主城：绿环。  
- [ ] 选中中立金矿：黄环（不再绿）。  
- [ ] 左键点树：无选中、无黄环（仍可右键伐木）。  
- [ ] 取消选中：环移除，无残留 Node。  
- [ ] 多选仅己方：全绿；选中金矿：黄环 + 储量 status。

---

## 8. 相关代码

| 路径 | 角色 |
|------|------|
| `scenes/selection/` | SelectionRing、UnitSelector（场景 + 脚本） |
| `scripts/shared/selection/` | Selectable / Interactable / InteractionSetup、框选 |
| `game/scripts/game_director.gd` | `_setup_selector`、装配调用 |
| `game/scripts/logic/selection_info_builder.gd` | HUD 选中信息（游戏侧，留在 game/） |
| `game/scripts/presentation/target_flash_fx.gd` | 目标闪反馈（游戏侧） |
| `game/scripts/presentation/move_confirm_fx.gd` | 命令确认（勿混） |
| `editor/scripts/tools/doodad_brush.gd` | 编辑器 doodad 环（可暂保持绿） |
