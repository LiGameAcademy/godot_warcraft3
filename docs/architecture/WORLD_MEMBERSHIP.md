# WorldMembership — 「在世界成员资格」抽象

> 适用范围：游戏运行时单位 / 实体（不含地图静态地形 / 装饰）。
> 状态：F2 已落地（Gold Mine / BuildSite），未来 TrainQueue / Death / AirTransport 沿用。

---

## 为什么单独抽

WC3 中很多机制会让单位"暂时不在场"：

| 行为 | 所属系统 | 表现层视觉 | 工程语义 |
|---|---|---|---|
| 农民进金矿 | Harvest | 隐形 | 离场 |
| 农民到位 → 工地 | Build | 隐形 | 离场 |
| 工地幼体建造中 | BuildSite | 工地模型 | 离场 |
| 训练中模型 | Train | 半透（计划）| 离场 |
| 死亡（尸体 / 灵魂）| Combat | 尸体 / 半透 | 离场 |
| 空运中途 | Transport | 隐形 | 离场 |

此前用 `visible = false` + `selection_blocked` meta 强行做 "隐身"，导致：

1. **语义混淆**：视觉"隐身"（隐身披风 / 隐刀）和机制"离场"被混在同一个字段。
2. **多状态并列**：未来要做"灵魂状态"时，`visible` 已被占用。
3. **漏点**：每个查询点（选择 / 寻路裁剪 / 镜头裁剪）都得各自加判断。

把"在场性"独立为 **`WorldMembership`**，上面叠 `visible` 表现层，互不干扰。

---

## API（已实现）

文件：`scripts/shared/world/world_membership.gd`

```
class_name WorldMembership
extends RefCounted

const META_IN_WORLD := "world_member_in_world"

static func exit(node: Node3D) -> void
static func enter(node: Node3D) -> void
static func is_in_world(node: Node) -> bool
```

### `exit(node)`

把节点移出游戏世界。一组原子副作用：

1. `node.set_meta(META_IN_WORLD, false)` — 状态标签。
2. `node.visible = false` — 视觉离场（如果调用方还要半透 / 半隐，自行覆盖）。
3. 若节点在 `UnitSelector` 当前选中里，自动 `deselect_unit(node)`。
4. **幂等**：已离场再调用不会重复改 `visible`，避免出现"hide 两次导致恢复时模型错位"。

### `enter(node)`

把节点加回游戏世界：

1. `set_meta(META_IN_WORLD, true)`。
2. `node.visible = true`。
3. **首次 enter 不操作**（无 meta 视为"默认在场"，避免误把任意可见节点当作离场恢复）。

### `is_in_world(node)`

无 meta → 默认在场（`true`）。其它读 meta。

---

## 已接入的查询点

| 位置 | 之前 | 现在 |
|---|---|---|
| `UnitSelector._collect_children`（点选 + 框选） | `not n.visible` | `not WorldMembership.is_in_world(n)` |
| `GameMinimap` 单位过滤 | `not n.visible` | `not WorldMembership.is_in_world(n)` |
| `UnitCrowdQuery.neighbors_of`（寻路裁剪 / 占位）| `not n.visible` | `not WorldMembership.is_in_world(n)` |

---

## 已替换的调用点

| 文件 | 入口 | 行为 |
|---|---|---|
| `HarvestController._begin_inside_mine` | 农民进矿 | `WorldMembership.exit(body)`（替代 `visible=false` + `selection_blocked` + `entered_unselectable`） |
| `HarvestController._exit_mine_with_gold` / `_cut_tree_done` / `_return_idle` | 农民出矿 / 砍完 | `WorldMembership.enter(body)` |
| `BuildController._on_arrived` | 农民到位进入工地 | `WorldMembership.exit(_peasant)` |
| `BuildController._on_site_completed` | 完工 | `WorldMembership.enter(_peasant)`（精灵由 Director 后续替换 peasant → 古树，不在此 enter） |

旧的 signal `entered_unselectable` 与 `deselect_unit` 外部连接全部清理掉。

---

## 与表现层的关系

| 视觉需求 | 走向 |
|---|---|
| 完全不可见（进矿 / 工地幼体 / 训练中）| `WorldMembership.exit` → 自动 `visible=false` |
| 半透（训练中、灵魂）| `exit()` 后调用方再 `modulate.a = 0.5` |
| 隐刀 / 隐身披风（仍在场）| **不**调 exit；走 Combat 单独的 stealth 系统 |
| 镜头 cull | 未来：`Camera3D.cull_mask` 在 is_in_world==false 时排除 |

> 重点：`WorldMembership` 是「在场性」，不是「视觉隐身」。

---

## 迁移指南（后续系统接入）

任何需要让单位"暂时不算在场"的功能，按这个套路：

1. 在事件入口调用 `WorldMembership.exit(node)`。
2. 在恢复点调用 `WorldMembership.enter(node)`（保证 enter 之前 exit 过）。
3. **不要**直接改 `node.visible`，除非另有视觉需求（覆盖即可）。
4. **不要**直接操作 `selection_blocked` meta，已删除。

## 未来扩展点

- `set_layer_exit(node, layer_id)` / `set_layer_enter`：分层离场（寻路裁剪但仍可见 = 鬼影；仅镜头裁剪但不退寻路…）。当前不需要，等真有需求再拆。
- 一个 `entity_set: Dictionary[int, Node3D]` 缓存（目前只靠 meta，没集合视图）。等节点量大再补。