# 寻路 · 测试用例

> 状态：**F-PATH 6 步 + F3 4 步全 ✅，本用例文档覆盖完整。**  
> 配合：[PATHFINDING_INDEX.md](../../design/pathfinding/INDEX.md) / [GROUP_MOVE.md](../../design/pathfinding/GROUP_MOVE.md) / [PATHFINDING_CHOICE.md](../../design/pathfinding/CHOICE.md)  
> 最后更新：2026-08-10

---

## 0. 验收目标

复刻 WC3 经典寻路观感：**点哪走哪 + 散开 + 避让 + 凹角脱困 + 队形 + 斜坡速度**。

| 能力 | 状态 | 用例 |
|------|:---:|------|
| 单单位寻路 | ✅ | §4.1 |
| 群体落点散开 | ✅ | §4.2 |
| Shift+RMB 队形 | ✅ | §4.3 |
| 凹角脱困 | ✅ | §4.4 |
| 软分离（不叠模） | ✅ | §4.5 |
| 卡死超时 | ✅ | §4.6 |
| 斜坡速度衰减 | ✅ | §4.7 |
| 弧线转弯 | ⏳ | §4.8（F-PATH-3 模块就位，UnitNavigator 未接） |
| 行为 AI（追/逃/巡逻） | ⏳ | §4.9（F-PATH-2 模块就位，F4+ 触发） |

---

## 1. 准备（前置条件）

### 1.1 环境

- Godot 4.6.3 稳定版（`C:\Users\Administrator\Desktop\Godot_v4.6.3-stable_win64_console.exe`）
- WC3 1.30+（`D:\Program Files (x86)\Warcraft3`）
- 仓库根：`D:\GodotProject\laoli_gamedev_godot4_course\godot_warcraft3`
- 地图：`EchoIsles` 已 `bootstrap` 解析（`assets/map-parsed/echoisles/`）

### 1.2 跑 game

```powershell
cd D:\GodotProject\laoli_gamedev_godot4_course\godot_warcraft3
$env:WC3_PATH = "D:\Program Files (x86)\Warcraft3"
& "C:\Users\Administrator\Desktop\Godot_v4.6.3-stable_win64_console.exe" --path . res://game/scenes/game_main.tscn
```

### 1.3 准备 5 个 peasant

- F6 开局（默认 human race，random start location）→ 主城 + 5 peasant
- 或 F5 + 调试：单选 peasant → 复制 4 次（待支持）

---

## 2. headless 验收（selftest）

### 2.1 跑法

```powershell
# 寻路 4 模块 + 综合 + 群体移动
$env:WC3_PATH = "D:\Program Files (x86)\Warcraft3"
& "C:\Users\Administrator\Desktop\Godot_v4.6.3-stable_win64_console.exe" --headless --path . `
  -s res://tests/unit/selftest_steering.gd
& "..." --headless --path . -s res://tests/unit/selftest_path_arc.gd
& "..." --headless --path . -s res://tests/unit/selftest_slope_speed.gd
& "..." --headless --path . -s res://tests/unit/selftest_formation.gd
& "..." --headless --path . -s res://tests/unit/selftest_pathfinding_integration.gd
& "..." --headless --path . -s res://tests/unit/selftest_group_move.gd
```

### 2.2 期望输出

每个 selftest 末尾输出 `selftest_<name>: PASS`，**5/5 PASS**。

```
selftest_steering: PASS
selftest_path_arc: PASS
selftest_slope_speed: PASS
selftest_formation: PASS
selftest_pathfinding_integration: PASS
selftest_group_move: PASS
```

任一 FAIL → 回归，对照 commit `4e35e2d` (F-PATH-2) / `2b22f9d` (F-PATH-3) / `0257ba4` (F-PATH-4) / `cce6efd` (F-PATH-5) / `07d8ebc` (F-PATH-6) / `700cd44` (F3-2/3/4) 排查。

---

## 3. 模块验收（库层）

### 3.1 F-PATH-2 · SteeringBehaviors（5/5 PASS）

| 用例 | 输入 | 期望 |
|------|------|------|
| seek 轴向 | self=(0,0), target=(100,0), max=50 | vel=(50, 0) |
| seek 斜向 | self=(0,0), target=(50,50), max=50 | vel=(50/√2, 50/√2) ≈ (35.36, 35.36) |
| arrive 缓速 | slow_radius 内 | vel 线性减速到 0 |
| pursue 预测 | target 有速度 | vel 朝 τ=dist/max_speed 后的位置 |
| evade 背向 | threat 在前 | vel 朝远离 threat 方向 |
| wander 抖动 | wander_angle 偏移 | 圆心 + 半径 + 角度 |

### 3.2 F-PATH-3 · PathArc（5/5 PASS）

| 用例 | 输入 | 期望 |
|------|------|------|
| 90° 转弯 | chord=100, theta=π/2 | 端点 (70.71, 70.71) 屏上（圆心法+切向反推） |
| 0° 直线 | theta=0 | n+1 = 2 points，走直线 |
| 180° U-turn | theta=π | 端点 (0, 100) 屏下 |
| arc_radius | chord=100, theta=π/2 | R = 100 / (2 sin(π/4)) ≈ 70.71 |
| arc_length | speed=100, turn_rate=0.5 圈/秒 | 弧长 = 100 / 0.5 = 200 |

### 3.3 F-PATH-4 · SlopeSpeed（5/5 PASS）

| 用例 | 输入 | 期望 |
|------|------|------|
| 平地 | dy=0, dx≠0 | speed 不变（factor=1.0） |
| 上坡 | dy<0 (屏上) | 减速，30° 钳到 UPHILL_FACTOR 0.6 |
| 下坡 | dy>0 (屏下) | 减速，30° 钳到 DOWNHILL_FACTOR 0.85 |
| 30° 陡坡 | slope_deg=30 | factor = UPHILL/DOWNHILL |
| 80° 极陡 | slope_deg=80 | 钳到 30° 计算（不超 factor） |

**WC3 屏 y-down 约定**：
- `self.y < prev.y` → 上坡（屏向上）→ UPHILL_FACTOR
- `self.y > prev.y` → 下坡（屏向下）→ DOWNHILL_FACTOR

### 3.4 F-PATH-5 · FormationFollow（5/5 PASS）

| 用例 | 输入 | 期望 |
|------|------|------|
| wedge 5 | leader=(100,100), heading=0, spacing=64 | 5 slot：leader (100,100) + 4 followers (-X 后方 + ±Y 交替) |
| rect 9 | 9 单位 rect，cols=3 | 9 slot：leader (0,0) + 8 followers（3 列居中，行 y=-64/-128/-192） |
| circle 8 | 8 单位 circle，radius=64 | 8 slot：leader 中心 + 7 followers 等分圆周（首位 (64,0)） |
| heading 90° 旋转 | local (-64,-64) | world (64,-64) + leader → (164, 36) |
| count 1 | 1 单位 | 1 slot = leader 位置 |

### 3.5 F-PATH-6 · 综合 selftest（5/5 PASS）

`selftest_pathfinding_integration.gd` 串起 4 模块 + 1 集成：
1. steering seek（轴向 + 斜向）
2. path arc 90° 转弯
3. slope speed 上坡 + 平地
4. formation wedge 5
5. 集成（formation offset + steering seek + slope 调速）

### 3.6 F3 · 群体移动（5/5 PASS）

`selftest_group_move.gd`：
1. rect 5 OK
2. wedge 3 OK
3. shift routing OK（leader goal=center, followers=offset）
4. slope speed integration OK（162 < 270 in uphill）
5. fallback to scatter OK（count 1 → goal=center）

---

## 4. 手动验收（前台）

### 4.1 单单位寻路

**准备**：F6 开局，单选 1 个 peasant。
**操作**：右键到远处空地（黄金矿点附近）。
**期望**：
- peasant 立即朝目标走
- 途中自动绕过建筑/悬崖（不穿模）
- 抵达后停下来（Walk → Stand）

**观察点**：
- F9 切换路径调试（黄色折线）— A* 路径应绕障碍
- 路径应贴近地形（不走 NO_WALK 区）
- 抵达后 peasant 转身 Stand 动画

### 4.2 群体落点散开（RMB）

**准备**：F6 开局，框选 5 个 peasant。
**操作**：右键到空地（远离任何单位/建筑）。
**期望**：
- 5 个 peasant **同时**开始走
- 落点散开（黄金角螺旋）— 5 个落点不在同一点
- 各自 A*，途中不互相穿过
- 全部抵达后停下

**观察点**：
- 落点散开半径 ≈ 5 × collision_radius_wc3
- 5 个落点呈螺旋分布
- 没有重叠（软分离生效）

### 4.3 Shift+RMB 队形排开（F3）

**准备**：F6 开局，框选 5 个 peasant。
**操作**：**按住 Shift + 右键**到空地。
**期望**：
- 5 个 peasant 按 **rect formation** 排开
- leader slot 0 = 右键落点（goal_center）
- follower 1-4 在 leader 后方（屏上 = -X），3 列居中
- 各自 A* 到 slot 目标

**观察点**：
- 落点呈 3×2 矩形（leader 在前排中央）
- 5 个落点 spacing=64（WC3 单位）
- HUD 状态栏显示「队形移动 [rect] → (x, y) · 5 单位」

**对照**：
- 不按 Shift = §4.2 散开（黄金角螺旋）
- 按 Shift = §4.3 队形（rect 矩形）
- 两种模式落点分布不同，但都能抵达

### 4.4 凹角脱困

**准备**：把 1 个 peasant 拖到 pathTex 直角格（建筑直角内凹）。
**操作**：右键到远处。
**期望**：
- peasant 立即弹到开阔格（不卡死在墙缝）
- 之后正常 A* 到目标

**观察点**：
- 看 F9 路径调试 — 起点是 snap 后的开阔格，不是原始凹角
- 用 `PathQuery.snap_to_open_walkable` 验证（参考 `unit_navigator.gd:_unstuck_if_pocket`）

### 4.5 软分离（不叠模）

**准备**：2 个 peasant 起点相邻（< 32 WC3 单位）。
**操作**：同时右键到同一点。
**期望**：
- 2 个 peasant **不**叠在一起
- 走的过程中互相推开（soft push）
- 落点散开（§4.2 算法）

**观察点**：
- 看 F9 路径 + 单位视觉 — 不应穿模
- 接近时路径自动偏移（侧移避让）

### 4.6 卡死超时

**准备**：把 1 个 peasant 卡在 NO_WALK 边缘（贴墙到不可走格旁）。
**操作**：右键到不可走区对侧（path 过不去）。
**期望**：
- peasant 走 0.4 秒（stall_abort_sec）后停下来
- 不死循环（不卡死）
- 控制台打印「stall → finish」

**观察点**：
- peasant 不会原地抖
- 不报「无法到达」（虽然实际没到）

### 4.7 斜坡速度衰减

**准备**：5 个 peasant 在斜坡底。
**操作**：右键到斜坡顶。
**期望**：
- 上坡时 peasant 速度 ≈ base × 0.6（UPHILL_FACTOR）
- 下坡时 ≈ base × 0.85（DOWNHILL_FACTOR，防滑）
- 平地不变
- 30° 陡坡钳到 factor

**观察点**：
- 视觉上坡时比平地慢（约 60%）
- 下坡不会冲得太快（约 85%）
- 30° 以上和 30° 一样（钳到 30°）

**调试**：F9 路径 + 控制台 `print(speed_wc3)` 实时值。

### 4.8 弧线转弯（未集成，仅模块 PASS）

**状态**：F-PATH-3 `PathArc` 模块就位（`selftest_path_arc.gd` 5/5 PASS），但 `UnitNavigator` 未接。
**手动验收**：暂不可见（`UnitNavigator._process` 走直线，不走弧线）。
**future**：F-PATH-7 UnitNavigator 集成时手动可观察。

### 4.9 行为 AI（未集成，仅模块 PASS）

**状态**：F-PATH-2 `SteeringBehaviors` 模块就位（`selftest_steering.gd` 5/5 PASS），`UnitNavigator.apply_steering_override()` 留 API 但默认 null。
**手动验收**：暂不可见（UnitNavigator 走纯 waypoint + soft 分离）。
**future**：F4+ 战斗（追兵 pursue / 逃兵 evade）时接 `apply_steering_override`。

---

## 5. 边界 / 已知失败

### 5.1 已知限制

- **headless selftest 无法跑 game_director**：`_issue_group_move_command` 强依赖 `unit_selector` / `path_query` 注入；selftest 只能测纯算法（formation slot 计算 + shift routing 逻辑）
- **F9 路径调试**：默认开；F9 切换；不影响功能
- **stall_abort_sec=0.4**：贴墙/卡死时 0.4s 后强制 finish；不报 path_failed

### 5.2 已知失败

- **大群体（30+ 单位）性能**：待 F2+ 修；当前 A* 每次寻路是单线程
- **F-PATH-8/9 暂未集成**：弧线转弯 / 行为 AI 留 future

### 5.3 复刻偏差

- **leader_heading 硬编码 0**（F3）：WC3 实际是 leader 朝向；F3 范围内硬编码，future 接 leader facing
- **不接 leader 边走 follower 边跟**（F3）：WC3 复刻口径；follower 各自 A* 到 slot 目标

---

## 6. 性能基准

### 6.1 当前 baseline

| 场景 | 单位数 | 期望 FPS |
|------|:---:|:---:|
| 单单位长距 | 1 | > 60 |
| 群体（5 单位） | 5 | > 60 |
| 群体（12 单位） | 12 | > 60 |
| 群体（30 单位） | 30 | > 45（**待优化**） |

### 6.2 测量方法

- F6 开局 → 复制 peasant 到 N 个
- 全员同时右键到地图对角
- 记录 30 秒内平均 FPS

### 6.3 已知瓶颈

- A* 单线程（30+ 单位群体走时 CPU 单核吃满）
- soft 分离每帧 O(N²) 邻居查询（30+ 单位时 O(900)）
- 未来优化：JPS 跳点 / hierarchical path / spatial hash 邻居

---

## 7. 验收 checklist

- [ ] headless 6 个 selftest 全 PASS（steering/path_arc/slope_speed/formation/pathfinding_integration/group_move）
- [ ] §4.1 单单位寻路
- [ ] §4.2 群体落点散开（RMB）
- [ ] §4.3 Shift+RMB 队形（rect 默认）
- [ ] §4.4 凹角脱困
- [ ] §4.5 软分离
- [ ] §4.6 卡死超时
- [ ] §4.7 斜坡速度
- [ ] F9 路径调试开关正常
- [ ] 5 个 peasant 落点呈 3 列矩形（Shift+RMB 模式）

---

## 8. 失败排查

| 现象 | 排查点 |
|------|--------|
| headless selftest FAIL | 看错误信息 → 对照 commit 找原因 |
| 单单位不走路 | 检查 `_path_query` 注入 / `UnitNavigator.configure` |
| 群体走但叠在一起 | `_crowd_query` 注入 / `enable_separation` 开关 |
| 队形落点 = 落点散开 | 检查 `mb.shift_pressed` 分流 / `FORMATION_RECT` 字串 |
| 卡死不 finish | `_stall_time` 是否累加 / `stall_abort_sec` 默认 0.4 |
| 斜坡不减速 | `_prev_wc3` 是否记录 / `enable_slope_speed` 默认开 |
