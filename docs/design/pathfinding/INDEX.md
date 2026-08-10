# 寻路系统 · 设计索引

> 状态：**F-PATH-6 综合 selftest 5/5**（寻路 4 模块 + 1 集成）  
> 配合：[PATHFINDING_CHOICE.md](CHOICE.md)（主方案：WC3 离散网格 A*）  
> 最后更新：2026-08-10

---

## 0. 结论（先读）

**目标**：复刻 WC3 的寻路观感——"点哪走哪 + 群体散开 + 自动避让 + 凹角脱困"，**不**引入现代 RTS 的"鱼群 / RVO / 群体智能"算法（原作没做这些，做了反而失真）。

**主路径权威**：**WC3 离散网格 A\***（`Wc3PathingMap` / `PathQuery`），由 [PATHFINDING_CHOICE.md](CHOICE.md) 拍板。不引入 NavMesh 替代。

**寻路 + 移动分层**：
- **寻路 = Logic**：纯函数 / 可测 / 不碰场景树
- **移动 = Presentation**：消费路点 / 贴地 / 转向 / 动画
- **避障 = Logic 增强层**：在 A* 路径之上叠加，不替换路径

**F-PATH 范围（明早验收）**：
| 阶段 | 交付 | 状态 |
|------|------|------|
| **F-PATH-1** | 本设计文档 | ✅ |
| F-PATH-2 | `SteeringBehaviors`（seek/arrive/pursue/evade/wander） | ✅ |
| F-PATH-3 | `PathArc`（弧线转弯，不切直角） | ✅ |
| F-PATH-4 | `SlopeSpeed`（斜坡速度衰减） | ✅ |
| F-PATH-5 | `FormationFollow`（编队跟随） | ✅ |
| **F-PATH-6** | **selftest 5/5**（综合 4 模块 + 1 集成） | **✅** |

---

## 1. 现状（已落地）

### 1.1 寻路主路径（Logic · 网格 A*）

| 模块 | 职责 | 文件 |
|------|------|------|
| `Wc3PathingMap` | 4×4 字节 pathing 网格 + Heightfield | `scripts/map/data/wc3_pathing_map.gd` |
| `PathQuery` | A* / 弦拉直 / Catmull-Rom / 直线检测 / 落点 snap | `game/scripts/logic/pathing/path_query.gd` |
| `PathAgentProfile` | 净空 / 半径 / 移动类型（foot/horse/fly/float/amphibious） | `game/scripts/logic/pathing/path_agent_profile.gd` |
| `PathCellReservation` | 路径格预约（防叠） | `game/scripts/logic/pathing/path_cell_reservation.gd` |
| `UnitMoveSlots.assign_goals` | 落点散开（WC3 矿口 5 连连看） | `game/scripts/logic/pathing/unit_move_slots.gd` |
| `UnitCrowdQuery` | 群体 query（半径 / 邻居） | `game/scripts/logic/pathing/unit_crowd_query.gd` |
| `UnitSeparation` | soft separation（推开） | `game/scripts/logic/pathing/unit_separation.gd` |

### 1.2 移动执行器（Presentation）

| 模块 | 职责 | 文件 |
|------|------|------|
| `UnitNavigator` | 消费路点 + 贴地 + 转向 + soft 分离 + 凹角脱困 + 占格预约 | `game/scripts/presentation/unit_navigator.gd` |
| `PathDebugDraw` | 路径染色（编辑器 dev overlay） | `game/scripts/presentation/path_debug_draw.gd` |

### 1.3 集成测试

| 模块 | 文件 |
|------|------|
| `selftest_path_grid.gd` | `tests/integration/selftest_path_grid.gd` |

### 1.4 UnitNavigator 已实现的"局部修复"

```gdscript
# 1. 凹角脱困：起点卡在 pathTex 直角 → snap_to_open_walkable 弹到开阔格
func _unstuck_if_pocket(body, from_wc3, force=false)

# 2. 离墙推开：靠近 NO_WALK 时推开
func _with_separation(body, cur_wc3, desired_wc3, delta, is_last, dist_to_target)

# 3. 不可走回退：next 不可走 → fallback → keep
func _clamp_walkable(next, fallback, keep)

# 4. 卡死超时：moved < 0.75 持续 stall_abort_sec → 强制 finish
func _process(delta) → _stall_time
```

**这些**已经覆盖了"局部路径修复"和"凹角脱困"——F-PATH 不需要再做。

---

## 2. 缺口（WC3 复刻口径下）

### 2.1 真"智能避障"已就位（不重做）

WC3 的"智能避障"是：
- **占格预约**（`PathCellReservation`）— ✅
- **落点散开**（`UnitMoveSlots.assign_goals`）— ✅
- **软分离推开**（`UnitSeparation`）— ✅
- **凹角脱困**（`_unstuck_if_pocket`）— ✅
- **离墙推开**（`_with_separation`）— ✅

**WC3 没有**：boids（alignment/cohesion）、RVO/ORCA（双向速度协商）、flow field（流向场）。**这些都不做**。

### 2.2 F-PATH 真正缺的 4 件事

| # | 项 | 必要性 | 用户感知 |
|---|------|--------|----------|
| **1** | **SteeringBehaviors**（seek/arrive/pursue/evade/wander） | **高** | 移动 AI（追兵、逃兵、巡逻） |
| **2** | **PathArc**（弧线转弯） | 中 | 高速单位不切直角 |
| **3** | **SlopeSpeed**（斜坡速度） | 中 | 上下坡真实感 |
| **4** | **FormationFollow**（编队跟随） | 中 | 群体移动保持队形 |

### 2.3 优先级

| 项 | 必要性 | 难度 | 依赖 |
|---|:---:|:---:|------|
| 1 SteeringBehaviors | **高** | 中 | 无 |
| 2 PathArc | 中 | 小 | F-PATH-2 |
| 3 SlopeSpeed | 中 | 小 | 无 |
| 4 FormationFollow | 中 | 中 | F-PATH-2 |
| 6 selftest 5/5 | **必** | 中 | F-PATH-2~5 |

---

## 3. 设计口径（WC3 复刻）

### 3.1 主路径仍 A*

不引入 NavMesh 替代（`PATHFINDING_CHOICE.md` 拍板）。

### 3.2 局部避障 = 占格 + 落点散开 + 软推开

**WC3 复刻的"避障" = 这 3 件事的组合**（已就位）：

1. **A\* 时**：`PathCellReservation` 排除他单位占的格
2. **落点时**：`UnitMoveSlots.assign_goals` 多单位散开
3. **运行时**：`UnitSeparation` + `_with_separation` 推开

**不**加 RVO（"协商速度"）——原作没这种行为。

### 3.3 不做 boids / RVO / flow field

理由：原作没做，加了反而失真。RTS 复刻口径下，**观感对齐 > 算法先进**。

### 3.4 steering behaviors 是必要的

WC3 实际上有 steering（虽然没理论化）：
- 农民追矿（pursue）
- 步兵追兵（pursue）
- 逃跑（flee / evade）
- 巡逻（wander / patrol）
- 抵达（arrive 减速）

这些**不**是"鱼群"，是"目标导向 + 缓速 + 行为切换"。

---

## 4. 架构

```text
┌─────────────────────────────────────────────────────────────┐
│  Application（GameDirector / CommandRouter / 状态机）         │
└────────────────────────┬────────────────────────────────────┘
                         │ 下达 MoveOrder / 智能右键
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Logic 寻路（PathQuery）                                      │
│    - 网格 A* / 弦拉直 / Catmull-Rom / 直线检测                │
│    - 凹角脱困 / 离墙推开 / 落点散开 / 占格预约               │
│    ← 读 Wc3PathingMap（只读）                                  │
└────────────────────────┬────────────────────────────────────┘
                         │ 路点列表（WC3 XY）
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Logic 移动 AI（F-PATH-2~5）                                  │
│    - SteeringBehaviors：seek / arrive / pursue / evade / wander│
│    - PathArc：弧线转弯（F-PATH-3）                            │
│    - SlopeSpeed：斜坡速度衰减（F-PATH-4）                     │
│    - FormationFollow：编队跟随（F-PATH-5）                   │
└────────────────────────┬────────────────────────────────────┘
                         │ 期望位移（WC3 XY / 秒）
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Presentation 移动执行（UnitNavigator）                       │
│    - 消费期望位移 + 软分离 + 离墙推 + 贴地 + 转向            │
│    - 贴不可走边缘 / 卡死超时                                  │
│    - 发 arrived / path_failed / locomotion_changed signal   │
└─────────────────────────────────────────────────────────────┘
```

**关键**：
- **Logic 层是"输入位置 + 行为参数 → 输出期望位移"的纯函数**
- **Presentation 层是"消费期望位移 + 物理贴地"的执行器**
- **不混合** Logic 写 `body.global_position` / `body.rotation`

---

## 5. 关键决策

| # | 决策 | 理由 |
|---|------|------|
| **1** | **不做 boids** | 原作没做 |
| **2** | **不做 RVO/ORCA** | 原作没做；占格 + 落点散开 + 软推开已够 |
| **3** | **不做 flow field** | 远期；本作规模无需 |
| **4** | **做 steering behaviors** | 必要：移动 AI |
| **5** | **做弧线转弯** | 高速单位不切角 |
| **6** | **做斜坡速度** | 上下坡真实感 |
| **7** | **做编队跟随** | 群体保持队形 |
| **8** | **UnitNavigator 不动** | 已有凹角脱困 + 占格 + 软分离；只在外挂 steering / arc / slope |
| **9** | **Logic 纯函数** | 不碰 body；只返期望位移 |
| **10** | **数据驱动** | 速度 / 半径 / 权重走 PathAgentProfile |

---

## 6. 接口设计

### 6.1 `SteeringBehaviors`（F-PATH-2）

```gdscript
class_name SteeringBehaviors
extends RefCounted

## 纯函数：输入位置 + 目标 + 邻居，输出期望位移（WC3 XY / 秒）。
## 不碰场景树 / body。

## 朝目标直线移动（恒速）
static func seek(self_pos: Vector2, self_r: float, target: Vector2, max_speed: float) -> Vector2

## 朝目标但接近时减速（避免 overshoot）
static func arrive(self_pos: Vector2, self_r: float, target: Vector2, max_speed: float, slow_radius: float) -> Vector2

## 追移动目标（预测位置）
static func pursue(self_pos: Vector2, self_r: float, target_pos: Vector2, target_vel: Vector2, max_speed: float) -> Vector2

## 远离威胁
static func evade(self_pos: Vector2, self_r: float, threat: Vector2, threat_vel: Vector2, max_speed: float) -> Vector2

## 随机游走（Wander circle）
static func wander(self_pos: Vector2, wander_angle: float, wander_radius: float, max_speed: float) -> Vector2
```

### 6.2 `PathArc`（F-PATH-3）

```gdscript
class_name PathArc
extends RefCounted

## 路点转角处的弧线插值（不切直角）。
## 输入：当前路点 + 下一路点 + 速度；输出：弧线采样点（frame-rate independent）。

static func arc_samples(
    cur: Vector2, nxt: Vector2, turn_rate_rad: float, speed_wc3: float, fps: int
) -> PackedVector2Array
```

### 6.3 `SlopeSpeed`（F-PATH-4）

```gdscript
class_name SlopeSpeed
extends RefCounted

## 按坡度衰减速度：上坡减速 / 下坡限速（防滑）。
## 输入：当前位置 + 上一帧位置 + 基础速度；输出：衰减后速度。

const UPHILL_FACTOR := 0.6  # 上坡 60% 速度
const DOWNHILL_FACTOR := 0.85  # 下坡 85% 速度
const MAX_SLOPE_DEG := 30.0  # 30° 以内生效

static func apply(self_pos: Vector2, prev_pos: Vector2, base_speed: float) -> float
```

### 6.4 `FormationFollow`（F-PATH-5）

```gdscript
class_name FormationFollow
extends RefCounted

## 编队跟随：leader 走 path，follower 按 slot 偏移。
## slot 布局：楔形 / 矩形 / 圆形（选 preset）。

const FORMATION_WEDGE := "wedge"
const FORMATION_RECT := "rect"
const FORMATION_CIRCLE := "circle"

static func slot_positions(
    leader_pos: Vector2, leader_heading: float, count: int, formation: String, spacing: float
) -> PackedVector2Array
```

### 6.5 挂到 UnitNavigator

```gdscript
# UnitNavigator 新增（不破坏现有 API）
var _steering: int = SteeringBehaviors.SEEK  # 默认行为
var _steering_target: Vector2 = Vector2.INF
var _steering_max_speed: float = 0.0

func set_steering(kind: int, target: Vector2, max_speed: float) -> void
```

**UnitNavigator 已有逻辑不变**（凹角脱困 / 占格 / 软分离），steering 只是"期望速度"的来源。

---

## 7. 数据契约

### 7.1 Profile 字段

| 字段 | 用途 | 默认 |
|------|------|------|
| `move_speed_wc3` | 基础速度 | 270（WC3 农民） |
| `turn_rate_rps` | 转向率（圈/秒） | 0.5 |
| `collision_radius_wc3` | 碰撞半径 | 16 |
| `clearance_cells` | 路径净空 | 0（单格通道） |
| `steering_weight_seek` | seek 权重 | 1.0 |
| `steering_weight_arrive` | arrive 权重 | 1.0 |
| `steering_weight_pursue` | pursue 权重 | 0.7 |
| `steering_weight_evade` | evade 权重 | 1.5 |
| `steering_slow_radius` | arrive 减速半径 | 80 |
| `slope_uphill_factor` | 上坡速度因子 | 0.6 |
| `slope_downhill_factor` | 下坡速度因子 | 0.85 |
| `slope_max_deg` | 生效坡度上限 | 30° |

### 7.2 决策记录字段

| 字段 | 用途 |
|------|------|
| `formation_preset` | 楔形 / 矩形 / 圆形 |
| `formation_spacing` | 单位间距 |
| `arc_turn_rate_factor` | 弧线弯曲系数（1.0 = 原 turn_rate） |

---

## 8. 测试契约

| # | 用例 | 断言 |
|---|------|------|
| **1** | **seek 直线** | self → target 方向 = target - self，max_speed 限速 |
| **2** | **arrive 减速** | 接近 slow_radius → 速度线性下降到 0；overshoot 距离 < slow_radius × 0.1 |
| **3** | **pursue 预测** | target 速度 v，追击者选 target + v·τ，τ = dist / self.max_speed |
| **4** | **evade 反向** | self + threat 之间方向 = threat - self 反向（远离） |
| **5** | **wander 角变化** | 5 帧内 wander_angle 偏移 < 30°（避免急转） |

### 8.1 集成 selftest（5/5）

| # | 用例 | 断言 |
|---|------|------|
| **1** | steering 影响期望速度 | 5 农民 + seek 同点 → 5 个期望速度方向互不重合（散开） |
| **2** | arrive 减速闭环 | 农民从 100 wc3 外走 5 秒 → 末 1 秒速度 < max_speed × 0.3 |
| **3** | arc 转弯不切角 | 90° 转弯中点 3 帧：arctan 增量 < 45° / 帧 |
| **4** | slope 衰减 | 30° 坡上 5 帧：实际位移 = 基础 × 0.6 ± 5% |
| **5** | formation 跟随 | 5 单位 formation=wedge，leader 移 100 wc3，follower 各自 offset 在 ±10 wc3 内 |

---

## 9. 实施分期

| # | 阶段 | 交付 | 估时 | 关注点 |
|---|------|------|------|--------|
| **1** | **F-PATH-1** | 本设计文档 | 已完成 | 设计驱动 |
| **2** | **F-PATH-2** | `SteeringBehaviors` + 5 单测 + 集成 1 | 中 | 移动 AI 基础 |
| **3** | **F-PATH-3** | `PathArc` + 集成 3 | 小 | 弧线转弯 |
| **4** | **F-PATH-4** | `SlopeSpeed` + 集成 4 | 小 | 斜坡速度 |
| **5** | **F-PATH-5** | `FormationFollow` + 集成 5 | 中 | 编队跟随 |
| **6** | **F-PATH-6** | UnitNavigator 集成 steering/arc/slope/formation 入口 | 中 | 接线 |
| **7** | **F-PATH-7** | selftest 5/5（steering 单测 + 集成） | 中 | 验收 |

### 9.1 F-PATH-2 详细拆

```text
game/scripts/logic/pathing/
├── steering_behaviors.gd       # 新（F-PATH-2）
└── ...

tests/unit/
├── selftest_steering.gd         # 新（F-PATH-2 5/5 单测）
└── ...

tests/integration/
└── selftest_steering_flow.gd   # 新（F-PATH-2 集成：5 农民 + seek）
```

---

## 10. 风险与缓解

| 风险 | 缓解 |
|------|------|
| `SteeringBehaviors` 调用频率高 → 性能 | 纯函数 + 静态；只算期望速度，不每帧重算 profile |
| `PathArc` 弧线过长 | max arc length + 弦距离 < 阈值时退回直走 |
| `SlopeSpeed` 噪声（Heightfield 精度） | 滑动平均 prev_pos / self_pos |
| `FormationFollow` slot 抖动 | 一次性算 slot 后**不每帧**重算（leader 移动时更新） |
| UnitNavigator 集成复杂 | 现有 logic 不动；只加"期望速度来源"（seek vs arrive） |
| selftest 静态解析不过（autoload 静态名） | 改用 `_get_def_store()` helper（参考之前 F2-7 修法） |

---

## 11. 明确不做（本阶段）

- ❌ **boids**（alignment/cohesion/separation 三规则）— 原作没做
- ❌ **RVO / ORCA**（双向速度协商）— 原作没做；占格 + 落点散开 + 软推开已够
- ❌ **flow field**（流向场）— 远期；本作规模无需
- ❌ **飞行层 / 两栖 / 动态障碍物**（开关闸门 / 传送门）— 远期
- ❌ **替 UnitNavigator 重写** — 已有凹角脱困 + 占格 + 软分离
- ❌ **替 PathQuery** — A* + 弦拉直 + Catmull-Rom 已就位

---

## 12. 决策记录

| 日期 | 决策 | 理由 |
|------|------|------|
| 2026-08-05 | 主方案 A（WC3 离散网格 A*） | PATHFINDING_CHOICE.md 拍板 |
| 2026-08-10 | **不**做 boids / RVO / flow field | 老李确认"原作没鱼群我们也不做" |
| 2026-08-10 | **做** steering behaviors（seek/arrive/pursue/evade/wander） | WC3 实际有，只是没理论化 |
| 2026-08-10 | **做** 弧线转弯 / 斜坡速度 / 编队跟随 | RTS 观感必要 |
| 2026-08-10 | UnitNavigator 不重写 | 现有 logic 覆盖 90% 缺口 |
| 2026-08-10 | Logic 纯函数（不碰 body） | 可测 / 接线简单 |
| 2026-08-10 | Steering 数据驱动（profile 控权重） | 不同兵种行为不同 |

---

## 13. 下一步（明早验收清单）

1. F-PATH-2：`SteeringBehaviors`（seek/arrive/pursue/evade/wander） + 5 单测
2. F-PATH-3：`PathArc`（弧线转弯）
3. F-PATH-4：`SlopeSpeed`（斜坡速度衰减）
4. F-PATH-5：`FormationFollow`（编队跟随）
5. F-PATH-6：UnitNavigator 集成入口（不改逻辑，只加来源）
6. F-PATH-7：selftest 5/5（单测 + 集成）

**预计 commit 序列**（1 关注点 / 1 commit）：
```
docs(pathing): F-PATH 寻路索引 + 缺口 + 决策                    ← F-PATH-1（本文）
test(pathing): selftest_steering 5/5 PASS（seek/arrive/pursue/evade/wander）  ← F-PATH-2 测试
feat(pathing): SteeringBehaviors（5 行为 + 1 集成）             ← F-PATH-2 实现
feat(pathing): PathArc（弧线转弯）                              ← F-PATH-3
feat(pathing): SlopeSpeed（斜坡速度衰减）                        ← F-PATH-4
feat(pathing): FormationFollow（楔形/矩形/圆形）                 ← F-PATH-5
feat(present): UnitNavigator 集成 steering/arc/slope/formation ← F-PATH-6
test(pathing): selftest_steering_flow 5/5 集成 PASS              ← F-PATH-7
```
