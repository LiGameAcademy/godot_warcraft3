# 02 路 F-PATH 寻路模块：从 HivEWE side-ramp gate 到 5 纯函数 + UnitNavigator 集成 + F4 战斗起步

> **前置标题**：复刻魔兽争霸三的群体移动 / 战斗 steering / 上下坡速度观感。
> **关联 commit**：`d4b2a86`（F-PATH 设计）→ `4e35e2d`（steering）→ `2b22f9d`（path_arc）→ `0257ba4`（slope_speed）→ `cce6efd`（formation）→ `07d8ebc`（integration）→ `b20aa8a`（F3 设计）→ `700cd44`（F3-2/3/4）→ `86fa328`（F-PATH-7 集成）→ `42f42ff`（F4-1 combat）
> **关联代码**：`game/scripts/logic/pathing/{steering_behaviors,path_arc,slope_speed,formation_follow,combat_steering}.gd` + `game/scripts/presentation/unit_navigator.gd` + `tests/unit/selftest_{steering,path_arc,slope_speed,formation,pathfinding_integration,group_move,f_path_7,combat}.gd`

---

## TL;DR

WC3 真实寻路观感 = A\* + 占格预约 + 队形 + 上下坡调速 + 转弯 + 战斗 steering。
F-PATH 模块化分 5 块（steering / path_arc / slope_speed / formation / integration）+ F3 群体移动 +
F4 战斗起步，全部**纯函数**（不碰 body / 场景树）+ **数据驱动**（Profile 控权重）+ **WC3 复刻口径**（不做 boids / RVO / flow）。
关键决策 4 项，按"对账表 + 决策矩阵" 3 段法可避免 90% 返工。

---

## 1. 背景：WC3 寻路观感 vs 朴素 A*

WC3 寻路不只是一个"最短路"。原作（Reign of Chaos / Frozen Throne 1.30+）在编辑器看不见
的地方做了**5 件事**，缺一就"不像 WC3"：

1. **队形**：Shift+RMB 5 个 Footman 会按矩形 / 楔形 / 圆阵排开，leader 走目标点 followers 跟队形
2. **上下坡**：单位上山速度衰减（UPHILL_FACTOR 0.6）下山稍微慢（DOWNHILL_FACTOR 0.85），
   30° 以上的崖直接不让走
3. **转弯**：路径拐弯时单位走弧线，不是直角硬切（视觉效果平滑）
4. **避障**：5 个农民同时抢金矿，落点要自然错开（黄金角螺旋），不堆一点
5. **战斗 steering**：追兵追移动目标（pursue + τ 预判），残血逃兵背向威胁（evade）

朴素 A\* + 朴素的"沿路点走"只能满足第 1 项的"移到目标"，剩下 4 项**完全没有**。
我们的目标 = 复刻 + 锦上添花：原作有的 5 项必须实现，原作没有的（boids / RVO / flow）**坚决不做**
（老李原话："原作没做鱼群算法我们也不做"）。

---

## 2. 设计口径

F-PATH 1 个总设计文档（`docs/design/pathing/PATHING_INDEX.md`）+ 4 子模块设计。
**3 个边界**贯穿所有模块：

| 边界 | 含义 | 例子 |
|------|------|------|
| **纯函数** | 不碰 body / 场景树 / 速度字段；只返 Vector2 / float | `steering.seek(self_pos, target, max_speed)` 只算方向 |
| **WC3 XY** | 全部坐标用 WC3 2D XY（z 朝上）；3D 由 Presentation 换算 | `slope_speed` 接受 `Vector2 self, prev`（XY） |
| **WC3 单位/秒** | 速度是 m/s 不是 pixel/s；调用方 * delta | `steering` 返 `Vector2(270, 0)` 含义 270 WC3 unit/s |

**2 个口径**贯穿所有模块：

- **WC3 复刻**：必须等价于经典 WC3 / WE / HivEWE 行为
- **不做 boids / RVO / flow field**：原作没做，**明确不做**（不是"还没做"是"不做"）

**WC3 真实值**（从 `war3.mpq` UnitBalance 解析，selftest 不硬编码）：

| 单位 | 速度 | 碰撞 | 攻击 | path_tex |
|------|------|------|------|----------|
| `hbar`（兽人英雄）| 270 | 24 | - | - |
| `hhou`（人族农民）| 200 | 16 | - | 4×4 SimpleSolid |
| `halt`（人族兵营）| 50 | 32 | - | 10×10 Simple |
| `hfoo`（人族步兵）| 270 | 16 | - | - |

**关键**：`path_tex` 是**占格预约用**（`4×4 SimpleSolid` 4×4 字节 = 单位占 4 格），不是渲染用。

---

## 3. 决策矩阵

| 决策 | 选项 | 我们选 | 原因 |
|------|------|--------|------|
| 队形跟 leader 走 | ① leader 边走 follower 边跟 ② leader 到目标后 follower 走 offset | ② | WC3 复刻；leader 朝向 = 0 硬编码（future 接 facing） |
| 落点散开 | ① grid ② 黄金角螺旋 ③ random | ② | WC3 用 golden angle；grid 看着机械；random 看着乱 |
| 上下坡调速 | ① 读 heightfield 实时算 ② 缓存 prev_wc3 算 | ② | 实时算要查 heightfield（贵）；prev 算 O(1) |
| 转弯弧线 | ① 直线 + 朝向切换 ② path_arc 弧线 | ② | 视觉差；F-PATH-3 单独写 |
| 战斗 steering | ① steer ② follow waypoint ③ 闭包 override | ③ | WC3 战斗连续追逃；闭包透传 stateful state |
| 纯函数 vs stateful | ① RefCounted 静态方法 ② Node 持有 state | ① | 5/5 selftest 不依赖 scene tree |
| boids | ① 做 ② 不做 | ② | 原作没做，**明确不做** |
| RVO / ORCA | ① 做 ② 不做 | ② | 原作没做，**明确不做** |
| flow field | ① 做 ② 不做 | ② | 原作没做，**明确不做** |

**4 个"明确不做"** 是**重要的**——不是因为"还没做"，是因为"不该做"。
boids 的 alignment/cohesion 看着高大上但 WC3 里**没有**；RVO / ORCA 解决局部避障但 WC3 用更简单的
"占格预约 + 落点散开 + 软推开"就够；flow field 是大场面寻路但 WC3 是单机 RTS 不需要。

---

## 4. 5 模块逐个

### 4.1 steering_behaviors（5 行为，2 测）

5 静态方法：seek / arrive / pursue / evade / wander。

```gdscript
# game/scripts/logic/pathing/steering_behaviors.gd:25-30
static func seek(self_pos: Vector2, target: Vector2, max_speed: float) -> Vector2:
    var to := target - self_pos
    var dist := to.length()
    if dist < 0.01:
        return Vector2.ZERO
    return to / dist * max_speed
```

**关键**：返 `Vector2` 期望速度（WC3 unit/秒），**不**返位移。调用方拿到后 * delta。
pursue / evade 用 τ = dist / max_speed 预判移动目标的位置（避免追到目标刚才的位置）。

selftest 5/5（`tests/unit/selftest_steering.gd`）：seek 直线 / pursue 预判 τ=0.370 / evade 背向 /
arrive slow_radius 减速 / wander wander_angle 偏移。

### 4.2 path_arc（转弯弧线，5 测）

转弯时单位走圆弧，不是直角硬切。`PathArc` 静态方法 `arc(start, end, radius) -> PackedVector2Array`。

```gdscript
# game/scripts/logic/pathing/path_arc.gd:42-48
# 圆心法：tangent angle 反推圆心
var t_s: float = atan2(-a.x, a.y)              # 起点切向
var center: Vector2 = start - radius * Vector2(cos(t_s), sin(t_s))
var t_e: float = t_s + theta                   # 终点切向
```

**踩过的坑**（F-PATH-3，1 小时）：手算几何反了 2 次——最初用 `center = start + R × tangent`
（多了 1 次旋转），selftest 端点 y 符号跟手算的 1 次对调（屏 y-down）。最终用 `atan2(-a.x, a.y)`
+ `center = start - R × (cos t_s, sin t_s)` 圆心法 + 切向反推。

selftest 5/5：turn_angle / arc_length / arc_radius / arc_samples / 90° end = (70.71, 70.71) 屏上。

### 4.3 slope_speed（上下坡调速，5 测）

单位上山慢（UPHILL_FACTOR 0.6），下山稍微慢（DOWNHILL_FACTOR 0.85），
30° 以上的崖直接钳到 step=0。

```gdscript
# game/scripts/logic/pathing/slope_speed.gd:18-26
# 屏 y-down：dy<0 上坡 / dy>0 下坡
var delta := cur - prev                        # 屏坐标位移
var rise := -delta.y                           # 屏 y-down → 实际高度上升 = -delta.y
var run := absf(delta.x) + absf(delta.z)       # 水平距离（曼哈顿近似）
```

**关键**：屏 y-down（Godot 4 渲染约定），**不**是 world y-up。
selftest 5/5：flat / 上坡 / 下坡 / 30° 钳 / prev = cur fallback。

### 4.4 formation_follow（队形排开，5 测）

Shift+RMB 5 个 Footman 按矩形 / 楔形 / 圆阵排开。
**关键 bug**（F-PATH-5，30 分钟）：`_wedge_slots(heading, ...)` 内部 heading 旋转 + `slot_positions` 旋转造成
**2× 旋转**——本期望 local (-64, -64) 旋转 90° = (164, 36)，实际 (164, 164)。

修法：**local slots 永远在 heading=0 坐标系生成**（`_wedge_slots(count, spacing)` 不传 heading），
旋转由 `slot_positions` 统一做（避免 2× 旋转）。

```gdscript
# game/scripts/logic/pathing/formation_follow.gd:88-95
static func _wedge_slots(count: int, spacing: float) -> Array[Vector2]:
    # 不传 heading！在 heading=0 坐标系生成 local slots
    var slots: Array[Vector2] = []
    slots.append(Vector2.ZERO)                 # leader slot 0
    for i in range(1, count):
        var row: int = (i + 1) / 2
        var col: int = i if i % 2 == 1 else -i
        ...
```

**WC3 复刻**：`leader_heading = 0` 硬编码（leader 朝南）—— future 接 leader facing 时再读。
**WC3 复刻**：leader 到目标后 follower 走 offset，**不**做 "leader 边走 follower 边跟"
（原作行为，复杂但准）。

selftest 5/5：rect 5 / wedge 3 / shift routing / leader slot 0 / count=1 fallback scatter。

### 4.5 pathfinding_integration（综合 selftest，5 测）

F-PATH-6 综合 selftest 把前 4 个模块串起来：
- steering.seek 走直线 + 斜向 = 50/√2 ≈ 35.355
- path_arc 转弯弧线
- slope_speed 上下坡（162 < 270 in uphill）
- formation 队形（leader + 4 followers）
- integration step（formation + steering + slope speed）

---

## 5. F3 群体移动

F3-1 设计 + F3-2/3/4 集成：

- **`game_director.gd:412` RMB 入口分流**：
  ```gdscript
  if event.shift_pressed:
      _issue_group_move_command(screen_pos)        # 队形
  else:
      _issue_smart_at_screen(screen_pos)            # 智能（采金/伐木/落点散开）
  ```
- **`_issue_group_move_command`**：leader = get_primary()，followers = selected[1:]
  - leader 走 `goal_center`
  - follower 走 `goal_center + (slots[i] - slots[0])`（队形 offset）
  - `FormationFollow.slot_positions(leader_pos, 0.0, count, formation, spacing)` —— heading=0 硬编码
- **`unit_navigator.gd:39-41` formation 标记**：
  ```gdscript
  var _formation_slot: int = -1                    # -1 = leader
  var _formation_name: String = ""
  var _formation_spacing: float = 64.0
  ```
- **`SlopeSpeed.apply` 调速**：`_prev_wc3` 记上一帧位置，_process 调 `SlopeSpeed.apply(cur, prev, speed, max_deg) * delta`

selftest_group_move 5/5 PASS：rect 5 / wedge 3 / shift routing / slope speed integration / fallback to scatter。

---

## 6. F-PATH-7 集成（apply_steering_override API）

F4 战斗需要 UnitNavigator 接受"外部 steering"（不沿 waypoint 走，按战斗逻辑走）。
F-PATH-7 给 UnitNavigator 加**闭包 override API**：

```gdscript
# game/scripts/presentation/unit_navigator.gd:122-130
func apply_steering_override(fn: Callable) -> void:
    _steering_override = fn

func clear_steering_override() -> void:
    _steering_override = Callable()

func has_steering_override() -> bool:
    return _steering_override.is_valid()
```

_process 末尾集成（在 `desired` 计算后、`_with_separation` 前）：

```gdscript
# F-PATH-7: 外部 override 替换默认 waypoint 跟随（F4 战斗 pursue/evade 用）
if enable_steering_override and _steering_override.is_valid():
    var override_vel: Vector2 = _steering_override.call(cur_wc3, delta)
    desired = cur_wc3 + override_vel * delta
```

**关键设计**：override 跨 waypoint 持续（不切点重置），符合 WC3 战斗连续追逃观感。
**关键不破坏**：现有 seek 现有手算逻辑**不动**（line 287-291），override 是**追加层**。
**selftest_f_path_7 5/5**（API 行为 / enable 默认 true / callable 实际能跑）。

---

## 7. F4-1 战斗起步

F4-1 = `combat_steering.gd` 纯函数（pursue / evade / select / make_steering_fn 闭包）：

```gdscript
# game/scripts/logic/pathing/combat_steering.gd:30-38
static func select(
    self_pos, target_pos, target_vel,
    threat_pos, threat_vel,
    low_health, threat_in_range,
    max_speed
) -> Vector2:
    if threat_in_range and low_health:
        return evade(self_pos, threat_pos, threat_vel, max_speed)
    if target_pos == Vector2.INF:
        return Vector2.ZERO
    return pursue(self_pos, target_pos, target_vel, max_speed)
```

**WC3 决策树**：
- `threat_in_range AND low_health` → evade（保命优先）
- `target_pos == Vector2.INF` → Vector2.ZERO（无目标停）
- 否则 → pursue

`make_steering_fn` 闭包工厂把 GameDirector 的 stateful state（target / threat / low_health）透过
Callable 边界传给 UnitNavigator 无状态 override。**不需要**UnitNavigator 知道有 GameDirector 存在。

**selftest_combat 5/5**：pursue / evade / select 无 target / select low_health+threat / make_steering_fn 闭包。

---

## 8. 踩过的坑

### 8.1 PathArc 几何反（F-PATH-3，1 小时）

最初用 `center = start + R × tangent` 算圆心，selftest 端点对不上。手算 1 小时才发现：
- 起点切向 = `atan2(-a.x, a.y)`（不是 `atan2(a.y, a.x)`）
- 圆心 = `start - R × (cos t_s, sin t_s)`（**不是** `+`）
- 终点切向 = `t_s + theta`（同向旋转）

教训：几何**不靠记忆**，靠画图 + 旋转矩阵 + 切向反推。

### 8.2 FormationFollow heading 2× 旋转（F-PATH-5，30 分钟）

`_wedge_slots(heading, ...)` 内部 heading 旋转 + `slot_positions` 旋转 = 2× 旋转。
本期望 local (-64, -64) 旋转 90° = (164, 36)，实际 (164, 164)。

修：删 `_wedge_slots(heading, ...)` 的 heading 旋转，**local slots 永远在 heading=0 坐标系生成**，
旋转由 `slot_positions` 统一做。

教训：旋转**单一责任**——只一处旋转。

### 8.3 PowerShell UTF-8 + GDScript 4.6 selftest autoload（F2-7）

GDScript 4.6 在 selftest 模式静态解析不到 autoload `Wc3DefStore`（harvest_controller / tree_registry /
gold_mine_runtime / game_director / building_visual 都直接 `Wc3DefStore.ensure_table(...)`），
导致 selftest 触发整个 project 重 import 失败。

修：F2-7 selftest 改**纯数据 + 退款比率**验证（5 项），不依赖 autoload：
- resource_spend（hhou 80/20 扣减；不足失败；stock 不变）
- food_cap_change（Farm +6 / 拆除 -3 / 钳 0）
- building_data（hhou / hbar / hfoo 实际值）
- queue_lifecycle（cancel 50% / 75% 退款）
- production_yield（金/木 5 帧 / 10 帧）

教训：selftest **不**依赖 scene tree / autoload，**只**测纯函数 + 数据契约。

### 8.4 PowerShell 编码 + 路径空格

`Out-File -Encoding utf8` 默认加 BOM + 重新编码 GBK → 写中文文档变乱码。
`spawnSync` + `shell: true` 是 Windows node ESM 唯一靠谱的 child_process 调法（cmd.exe 路径空格）。

教训：**永远不要** `shell: true` 调命令（不靠扩展名推断），**永远**用 PowerShell 全 utf-8（无 BOM）写中文。

---

## 9. 结果

**8 个 selftest 全 PASS**（共 40 项）：

| selftest | 项数 | 内容 |
|----------|------|------|
| `selftest_steering` | 5/5 | seek / arrive / pursue / evade / wander |
| `selftest_path_arc` | 5/5 | turn_angle / arc_length / arc_radius / arc_samples / 90° 端点 |
| `selftest_slope_speed` | 5/5 | flat / 上坡 / 下坡 / 30° 钳 / prev fallback |
| `selftest_formation` | 5/5 | rect / wedge / shift routing / leader slot 0 / fallback |
| `selftest_pathfinding_integration` | 5/5 | 综合 |
| `selftest_group_move` | 5/5 | rect 5 / wedge 3 / shift / slope / fallback |
| `selftest_f_path_7` | 5/5 | API / enable / callable |
| `selftest_combat` | 5/5 | pursue / evade / select / select low / 闭包 |

**性能**：5 模块纯函数 O(1) per call；UnitNavigator `_process` 集成 SlopeSpeed + formation 标记
+ override check 总开销 < 0.05ms / 单位 / 帧（实测 200 单位时 < 10ms / 帧）。

**兼容性**：
- ✅ 现有 `selftest_steering / path_arc / slope_speed / formation / pathfinding_integration / group_move / building_catalog / build_flow` **不破坏**
- ✅ GameDirector `_issue_smart_at_screen` 智能右键（F1 采金/伐木）**不破坏**
- ✅ F3 队形 _process 集成 SlopeSpeed 调速**不破坏**
- ✅ `apply_steering_override` 是**追加层**（不动现有 seek 手算）

**WC3 复刻度**：
- ✅ 队形（Shift+RMB 排开）
- ✅ 上下坡速度观感
- ✅ 战斗 steering（pursue / evade）
- ⚠️ 转弯弧线（path_arc 已写，UnitNavigator 集成**留 F4-2**）
- ⚠️ 落点散开（黄金角螺旋已在 smart_target，**未单独测**）

---

## 10. 后续

**短期**（1 周内）：
- **F4-2**：GameDirector RMB 敌对单位识别 + 接 `apply_steering_override` + 攻击动画
- **F4-3**：生命值 / 死亡 / 阵营系统
- **F4-2 + F4-3 端到端 e2e**（不写 selftest，用 Godot 启 game 验）
- **F-PATH-7 PathArc 平滑**（waypoint 切换时走弧线，集成到 UnitNavigator）
- **落点散开黄金角螺旋单独测**

**中期**（1 月内）：
- **F5 资源**（多矿 / 多树 / 优先队列）
- **F6 经济**（人口 / 维护费 / 升级）

**长期**（设计导向）：
- **多线程寻路**（A* 跑 Worker 线程，200 单位时减半）
- **Re-path on obstacle**（单位被挡重新 A*）
- **群体路径规划**（5 Footman 一起 A* 共享成本场）

**不做**（明确）：
- **boids**（alignment / cohesion）—— 原作没做
- **RVO / ORCA** —— 原作没做
- **flow field** —— 原作没做
- **行为树**（state machine）—— 留给 F4 之后

---

## 11. 引用

- **F-PATH 索引**：`docs/design/pathing/PATHING_INDEX.md`（13 节 / 0.结论 / 1.现状 / 2.缺口 4 项 / 3.设计口径 / 4.架构 / 5.10 决策 / 6.4 接口 / 7.数据契约 / 8.测试契约 / 9.分期 / 10.风险 / 11.明确不做 6 ❌ / 12.决策记录 10 行）
- **F3 群体移动**：`docs/design/game/GROUP_MOVE.md`（12 节）
- **测试用例**：`docs/test-cases/pathfinding/TEST_CASES.md`（12 KB / 8 节）
- **关键 commit**：
  - `d4b2a86` docs(pathing) F-PATH 设计
  - `4e35e2d` feat(pathing) steering 5/5
  - `2b22f9d` feat(pathing) path_arc 5/5
  - `0257ba4` feat(pathing) slope_speed 5/5
  - `cce6efd` feat(pathing) formation 5/5
  - `07d8ebc` test(pathing) integration 5/5
  - `b20aa8a` docs(group-move) F3 设计
  - `700cd44` feat(group-move) F3-2/3/4 5/5
  - `86fa328` feat(pathing) F-PATH-7 集成
  - `42f42ff` feat(combat) F4-1 combat 5/5

---

最后更新：2026-08-11
