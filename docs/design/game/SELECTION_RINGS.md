# 选中环与目标环（Selection / Target Rings）

> 对齐 WC3：己方选中 **绿环**；中立金矿左键可选 **黄环**（树**不可**左键选中，只右键伐木）。  
> 所属层：场景 `scenes/selection/`（环 / UnitSelector）+ 脚本 `scripts/shared/selection/`（组件 / 框选）；游戏与编辑器共用。  
> 相关：[GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [TREE_INTERACT.md](TREE_INTERACT.md) · [HUD.md](HUD.md)  
> 最后更新：2026-08-22

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
| `game/scripts/game_director.gd` | `_setup_selector`、装配 |
| `game/scripts/logic/selection_info_builder.gd` | HUD 选中信息 |
| `game/scripts/presentation/target_flash_fx.gd` | 右键目标闪 |
| `game/scripts/presentation/move_confirm_fx.gd` | 命令确认（勿混） |
