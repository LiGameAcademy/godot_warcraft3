# 群体移动（F3）· 设计索引

> 状态：**F3-1 设计文档**  
> 配合：[PATHFINDING_INDEX.md](INDEX.md)（F-PATH-1~6 已 ✅）  
> 最后更新：2026-08-10

---

## 0. 结论（先读）

**目标**：复刻 WC3 经典群体移动——"点哪走哪 + 落点散开 + 队形（formation）排开"。

**两种群体落点范式并存**：
1. **落点散开**（右键默认）：`UnitMoveSlots.assign_goals` 黄金角螺旋（已就位 `469528d`）
2. **队形排开**（Shift+右键）：`FormationFollow.slot_positions` 按 formation 排（F3 新做）

**WC3 复刻口径**：follower **各自 A\*** 到自己的绝对 slot 目标（不是"leader 边走 follower 边跟"——原作没有；那是 SC2 行为）。

**F-PATH 4 模块集成**：
- `FormationFollow` ← F3-2 入口（Shift+右键）
- `SlopeSpeed` ← F3-3 UnitNavigator 默认开（WC3 真实斜坡观感）
- `SteeringBehaviors` ← F3-3 UnitNavigator 留 API 入口（默认关；追兵/逃兵/巡逻由 F4+ 接）
- `PathArc` ← **不接**（F3 范围外；弧线转弯观感锦上添花，留 future）

---

## 1. 现状（已落地）

| 模块 | 职责 | 文件 | 状态 |
|------|------|------|------|
| `_issue_move_command` | 右键下发 go_to | `game/scripts/game_director.gd:479` | ✅ 走 UnitMoveSlots |
| `UnitMoveSlots.assign_goals` | 黄金角螺旋落点散开 | `game/scripts/logic/pathing/unit_move_slots.gd` | ✅ |
| `FormationFollow.slot_positions` | 楔形/矩形/圆形 slot 算 | `game/scripts/logic/pathing/formation_follow.gd` | ✅（F-PATH-5） |
| `SlopeSpeed.apply` | 斜坡速度衰减 | `game/scripts/logic/pathing/slope_speed.gd` | ✅（F-PATH-4） |
| `SteeringBehaviors.seek/arrive/...` | 行为 AI | `game/scripts/logic/pathing/steering_behaviors.gd` | ✅（F-PATH-2） |
| `PathArc` | 弧线转弯 | `game/scripts/logic/pathing/path_arc.gd` | ✅（F-PATH-3）但 UnitNavigator 未接 |
| `UnitNavigator` | 移动执行器 | `game/scripts/presentation/unit_navigator.gd` | ✅ 缺 SlopeSpeed/Formation 入口 |

**关键缺口**：
- 群体移动没有 formation 入口
- UnitNavigator 还没接 SlopeSpeed（观感降级）
- UnitNavigator 还没有 `set_formation_slot` API（follower 标记 slot）

---

## 2. 缺口（WC3 复刻口径下）

| # | 项 | 必要性 | 用户感知 |
|---|------|--------|----------|
| **1** | **GameDirector 群体入口（Shift+右键）** | **高** | 玩家按 Shift+右键 → 队形排开 |
| **2** | **UnitNavigator 接 SlopeSpeed** | **高** | 上下坡真实感（默认开） |
| **3** | **UnitNavigator formation_slot 入口** | 中 | follower 标记自己的 slot，调试可视化用 |
| **4** | **selftest_group_move 5/5** | 必 | 综合 selftest |

---

## 3. 设计口径

### 3.1 触发器

| 输入 | 模式 | 走法 |
|------|------|------|
| RMB（不按 Shift） | 落点散开 | `UnitMoveSlots.assign_goals`（现状） |
| Shift+RMB | 队形排开 | `FormationFollow.slot_positions`（F3 新做） |
| RMB on minimap | 落点散开 | `UnitMoveSlots.assign_goals`（现状） |
| Shift+RMB on minimap | 队形排开 | `FormationFollow.slot_positions`（F3 新做） |

### 3.2 队形参数

- **默认 formation**：`rect`（WC3 经典 3 列居中）
- **可选 formation**：`wedge` / `circle`（F3 范围内不暴露 UI 切换；硬编码 rect，future 加 UI）
- **spacing**：默认 64（WC3 单位）

### 3.3 leader 选取

- `_issue_group_move_command` 取 `unit_selector.get_primary()`（已存在）
- 1 个单位：等价于落点散开
- N 个单位：leader = `_primary`，follower = `_selected[1:]`

### 3.4 slot 计算

- `FormationFollow.slot_positions(leader_pos, leader_heading, count, formation, spacing)`
- leader_heading 默认 0（+X），**不**根据右键方向算（WC3 不算，是 leader 朝向）
- 头一回 slot 锁定；中途换目标 → 重新算

### 3.5 follower 寻路

- **各自 A\*** 到自己的 slot 目标（与 UnitMoveSlots 一致）
- **不做**"leader 边走 follower 边跟"（WC3 复刻口径）
- **不做** slot 冲突动态 fallback（formation 内部 row/col 排序已保证不重叠）

### 3.6 F-PATH 4 模块集成

| 模块 | 集成方式 | 触发 |
|------|---------|------|
| `FormationFollow` | `GameDirector._issue_group_move_command` 调 | Shift+RMB |
| `SlopeSpeed` | `UnitNavigator._process` 默认开，每帧调 | 永续 |
| `SteeringBehaviors` | `UnitNavigator` 留 `apply_steering_override()` 入口，默认 null | F4+ 触发 |
| `PathArc` | **不接**（F3 范围外） | — |

---

## 4. 架构

```text
┌─────────────────────────────────────────────────────────────┐
│  Application（GameDirector）                                  │
│    - RMB → _issue_move_command → UnitMoveSlots.assign_goals │
│    - Shift+RMB → _issue_group_move_command →                │
│                  FormationFollow.slot_positions             │
└────────────────────────┬────────────────────────────────────┘
                         │ per-unit slot 目标（WC3 XY）
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Presentation 移动执行（UnitNavigator）                       │
│    - A* 到 slot 目标（已有）                                 │
│    - SlopeSpeed 调速（F3-3 默认开）                          │
│    - soft 分离 + 离墙推 + 贴地 + 转向（已有）               │
│    - 凹角脱困（已有）                                       │
│    - set_formation_slot 入口（F3-3 follower 标记）           │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. 关键决策

1. **触发器**：Shift+RMB（不污染主键位，经典 RTS 习惯）
2. **formation 默认**：rect（WC3 经典）
3. **leader_heading**：默认 0，**不**根据右键方向算
4. **leader 选取**：`get_primary()`（已存在）
5. **follower 寻路**：各自 A* 到 slot（WC3 复刻）
6. **SlopeSpeed 默认开**：WC3 真实斜坡观感是必须
7. **SteeringBehaviors 留 API 不接**：F4+ 触发（追兵/逃兵/巡逻）
8. **PathArc 不接**：F3 范围外，future
9. **不做 leader 边走 follower 边跟**：WC3 复刻口径
10. **不暴露 formation UI 切换**：F3 硬编码 rect，future 加 UI

---

## 6. 接口

### 6.1 GameDirector（新增）

```gdscript
## Shift+RMB 入口：队形排开群体移动
func _issue_group_move_command(screen_pos: Vector2, formation: String) -> bool
    # 1. 取 primary leader + selected followers
    # 2. leader_pos = primary 当前位置（WC3 XY）
    # 3. leader_heading = 0（默认 +X）
    # 4. FormationFollow.slot_positions(leader_pos, 0, count, formation, spacing)
    # 5. 头一个 slot 走 leader（go_to_wc3(goal_center)）
    # 6. 余下 slot 走各 follower（go_to_wc3(slot[i])）
    # 7. 收 success 计数 → 状态
```

### 6.2 UnitNavigator（新增）

```gdscript
## F3-3: 标记 follower 在 formation 中的 slot（调试用，F3 不强依赖）
func set_formation_slot(slot: int, formation: String, spacing: float) -> void
    # 存 _formation_slot / _formation_name / _formation_spacing
    # 不影响 _process（follower 自己 A* 到 slot 目标）

## F3-3: SlopeSpeed 默认开关
@export var enable_slope_speed: bool = true
    # _process 中每帧调 SlopeSpeed.apply(self_pos, prev_pos, base_speed)
    # 调速只影响 step = speed * delta；不影响路点切换
```

---

## 7. 数据契约

- 群体移动触发：`InputEventMouseButton.button_index == MOUSE_BUTTON_RIGHT` + `event.shift_pressed`
- leader 选取：`unit_selector.get_primary()` 返首个选中的 Node3D
- followers 列表：`unit_selector.get_selected()[1:]`
- formation 字符串：`"rect"` / `"wedge"` / `"circle"`
- slot 数组：`PackedVector2Array`（count 个；leader 在 slot 0）

---

## 8. 测试契约

`tests/unit/selftest_group_move.gd` 5/5：

1. **slot_assignment_basic**：5 单位 rect formation → 5 个 slot，leader slot 0 = leader 位置
2. **slot_assignment_wedge**：3 单位 wedge → 3 个 slot，leader 前方，左右排开
3. **shift_routing**：模拟 Shift+RMB → GameDirector 调 `_issue_group_move_command` → 各 follower 收到不同 slot
4. **slope_speed_integration**：UnitNavigator `_process` 中 SlopeSpeed 调速生效（上坡 step 减少）
5. **fallback_to_scatter**：formation 模式下 1 单位 → 等价于落点散开（用 primary 目标点）

---

## 9. 实施分期

| 阶段 | 交付 | 状态 |
|------|------|------|
| **F3-1** | 本设计文档 | ✅ |
| F3-2 | `GameDirector._issue_group_move_command`（Shift+RMB → FormationFollow） | 待办 |
| F3-3 | `UnitNavigator` 接 SlopeSpeed + `set_formation_slot` API | 待办 |
| F3-4 | `selftest_group_move` 5/5 | 待办 |

---

## 10. 风险与缓解

| 风险 | 缓解 |
|------|------|
| Shift 按下后未释放就触发多次移动 | 每次 RMB 按下就立刻发命令，不缓存 Shift 状态 |
| follower 收到 slot 但路不通 | A* 自身返回 ok=false；_process 走 path_failed（已有） |
| formation slot 跨过不可走区 | slot 算在 leader 坐标系（WC3 XY），不直接 A* 到 slot；A* 自带不可走回退 |
| SlopeSpeed 误把"非坡度"判定为坡 | SlopeSpeed 已用 |dy| > |dx| 0.5 才算坡，且 30° 钳（已有） |
| leader_heading=0 让队形永远朝 +X | F3 范围内硬编码 0；future 改 leader 朝向（朝向 = leader 当前 facing） |

---

## 11. 明确不做（6 ❌）

- ❌ Leader 边走 follower 边跟（WC3 复刻口径）
- ❌ Formation UI 切换按钮（F3 硬编码 rect）
- ❌ PathArc 弧线转弯 UnitNavigator 集成（future）
- ❌ SteeringBehaviors 触发（追兵/逃兵/巡逻留 F4+）
- ❌ Slot 冲突动态 fallback（formation 内部 row/col 排序已保证）
- ❌ Leader heading 跟随右键方向（F3 硬编码 0）

---

## 12. 决策记录

- 2026-08-10：F3 触发器 = Shift+RMB（不污染主键位）
- 2026-08-10：formation 默认 = rect（WC3 经典）
- 2026-08-10：SlopeSpeed 默认开（WC3 真实斜坡观感）
- 2026-08-10：follower 各自 A* 到 slot（WC3 复刻）
- 2026-08-10：Steering 留 API 不接（F4+ 触发）
- 2026-08-10：PathArc 不接（F3 范围外）
- 2026-08-10：leader_heading=0 硬编码（future 接 leader facing）
- 2026-08-10：不做 leader 边走 follower 边跟（WC3 复刻口径）
