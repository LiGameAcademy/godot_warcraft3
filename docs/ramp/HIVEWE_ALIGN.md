# 斜坡层向 HivEWE 对齐的路线图

> **角色**：记录 `wc3_ramp_paint.gd` / `wc3_ramp_collect.gd` 当前与 HivEWE 的差异、
> 已对齐项、待重构项。**HivEWE 是行为权威**（来自 `D:\GameMaker\HiveWE\src\brush\terrain_operators.cpp`
> `CliffOperator::update_ramp` + `CliffOperator::check_ramp_direction` ~L406-463）；
> 本仓库扩展（HivEWE 没的）需有经典 WE 行为支撑，否则按 HivEWE 收窄。
> **本仓库主目标**（按老李）："实现过程可以不同但结果应该与游戏原作一致"——意味着
> HivEWE 行为**近似**经典 WE，但**不是**完整经典 WE。Lost Temple 数据没污染（已扫：750 ramp 旗
> 全 3 点直坡，0 孤立）。
> 最后更新：2026-07-31

---

## 1. 现状总览

| 维度 | 当前状态 | HivEWE 行为 | 待对齐？ |
|------|---------|-------------|---------|
| `update_ramp` bounds | `ix + 2*dir_x >= tp_w` | `i + 2*dir_x > width` | ✅ 老李更严格（HivEWE off-by-one）|
| 3 点 target_level | `_check_column` line 787-792 | `check_ramp_direction` L434-438 | ✅ 等价 |
| 侧邻高阻挡 | `_check_column` line 800-805 | `check_ramp_direction` L441-444 | ✅ 等价 |
| 紧贴对侧斜坡禁门 | `_check_column` line 808-826 | line 448-459 | ✅ 已加 1:1 等价（见 [§2.2]）|
| L 补心 | `fill_l_centers` 4 候选 | L509-535 独立 4 if 块 | ✅ 位置等价 |
| `_check_side_clearance` 3 例外 | 保留（`parallel_ok` / `_side_is_l_arm` / `completing_l`）| 无 | ⏸ 见 [§3.1] |
| `_is_l_recess_entrance` L 凹陷识别 | 保留 | 无 | ⏸ 见 [§3.2] |
| 外角未齐四旗碗 | 保留 | 无 | ⏸ 见 [§3.3] |
| `_ramp_cols_opposite` A/B 污染放宽 | 保留 | 严格 2 列反向 | ⏸ 见 [§3.4] |
| `extend_same_side` 死代码 | 已删 | 无 | ✅ |
| `soften_dirs` / `_infer_dirs` / `plan_from_pointer` | 保留 | 无 | ✅ UX 增强（保留）|

---

## 2. 已对齐项（已 commit）

### 2.1 `extend_same_side` 死代码删除

`@deprecated` 标了但永不调用——删除。

### 2.2 紧贴对侧斜坡禁门（HivEWE line 448-459）

HivEWE `check_ramp_direction` 的侧翼 ramp 不齐禁门（侧翼 corner 有 ramp + 沿主坡向延伸不齐 → 拒绝）——已 1:1 翻译到 `_check_column` line 808-826（Y 侧翼 + X 侧翼两个块）。

同时清掉老李之前误标的"反向延伸"注释（line 807-816 旧代码）——HivEWE 实际无此检查，是更老版本的"反向延伸"语义。

参考：[RAMP_WE.md §4.2 #4](RAMP_WE.md)

### 2.3 bounds check 严格度

老李 `ix + 2 * dir_x >= tp_w` 比 HivEWE `i + 2 * dir_x > width` 严格（HivEWE 在 `i = width - 2, dir_x = 1` 时算 `width > width = false` 而允许——`i+2 = width` 越界）。**保留老李严格版**。

---

## 3. 待对齐项（HivEWE 严格但当前放宽）

### 3.1 `_check_side_clearance` 3 例外（白名单放宽）

**位置**：`wc3_ramp_paint.gd:678-720` + `_side_is_l_arm` 助手

老李 HivEWE 没的白名单放宽：
- `parallel_ok`（邻列平行加宽：侧邻沿本坡向有完整臂）
- `_side_is_l_arm`（L 转角邻臂：侧邻是从原点出发的垂直完整臂）
- `completing_l`（补 L 第二臂时邻列异向坡）

**保留原因**：Lost Temple 邻列加宽 + L 转角补心常见 case 在老李代码下能跑通。HivEWE 严格禁门**会拒**。

**待验证（手测经典 WE）**：
- 在 Lost Temple 已有 3 点坡 A→B→C，在 C 的正下方/正上方/正左/正右一格 corner 起点再点刷一条 3 点坡——WE 接受还是拒绝？
- 答案决定 §3.1 是否删 3 例外

**影响（删 3 例外后）**：
- 9 个 logic 测试 case 改 `expect reject`（见 [§4.2]）
- 4 个 present 测试 case 改 `expect reject`（见 [§4.3]）
- Lost Temple 加载**不受影响**（line 448-459 只在 paint 路径）
- **用户**邻列加宽 / L 转角补心 paint 会被拒——同 HivEWE 行为

### 3.2 L 凹陷识别（`_is_l_recess_entrance` + 7 助手）

**位置**：`wc3_ramp_collect.gd:90-142`（主函数）+ `_l_recess_*` 系列助手

HivEWE 没"L 凹陷入口"概念——`is_corner_ramp_entrance` 只认经典 4 旗齐 + 对角层差不平。

老李扩展：识别"恰一角最低 + 邻边两角有旗"为入口 → undig + 低角 +0.5。L 补心时高角常无旗——经典 WE 实际可能处理这个 case。

**待验证（手测经典 WE Lost Temple）**：
- L 转角补心 case 在经典 WE 视觉是否对——如果 L 凹陷处"内角平底"显示错位，保留扩展；否则按 HivEWE 收窄。

**影响（删扩展后）**：
- 4 个 present 测试 case 删（L 凹陷识别 / 外角识别 / L 转角 CT / 无 CT 留地面 case 失效）
- `is_entrance` 等价于 `_is_classic_entrance`
- `plan_dig_mask` / `plan_entrance_tiles` / `plan_entrance_height_boost` 简化（删 L 碗 + 外角路径）
- 内角下凹坡视觉——按 HivEWE 简单处理

### 3.3 外角未齐四旗碗（`_is_outer_corner_ramp_tile` + 6 助手）

**位置**：`wc3_ramp_collect.gd:276-408`

HivEWE 没"3 低 1 高 + 高台支撑 + 邻列坡旗"识别。

老李扩展：识别后强制 undig，藏直崖。

**保留原因**：与 [§3.2] L 凹陷同类——L 转角邻臂 L 补心时常见 case。

**待验证**：同 [§3.2]。

### 3.4 `_ramp_cols_opposite` A/B 污染放宽

**位置**：`wc3_ramp_collect.gd:819-828`

老李放宽：1 列完整 + 1 列中格被另一臂污染 = 接受为合法 CliffTrans 匹配。
HivEWE 严格：只接受 2 列完全反向。

**保留原因**：L 补心时 1 列被另一臂中格污染是常见——A/B 污染放宽让 LABH/BALH 匹配。

**影响（收紧后）**：
- `_test_ramp_cols_opposite` A/B 污染 case 改 `expect false`
- L 补心 CliffTrans 匹配可能不认——视觉走"有旗无模"灰缝
- Lost Temple 是否受影响需 collect_placements 实测

---

## 4. 测试状态

### 4.1 `selftest_ramp_data.gd` — ✅ PASS

Lost Temple 解析正常（58 placements / 116 romp 非零）。
HivEWE line 448-459 严格禁门**不破坏** Lost Temple 加载（禁门只在 paint 路径，Lost Temple 旗直接 load 不检查）。

### 4.2 `selftest_ramp_logic.gd` — 9 个 case 失败

`selftest_ramp_logic.gd` 有 1 个 parse bug（line 862 之前有重复定义 `_test_soften_dirs`）已修。

剩余 9 个失败**全符合 HivEWE 严格行为预期**：

| # | 测试 | 行 | HivEWE 行为 | 老李扩展行为 |
|---|------|---|-------------|-------------|
| 1 | `_test_allow_opposite_face_ramp` | 368 | 拒 -Y 反向 paint | allow |
| 2 | `_test_l_then_complete_with_center` | 402 | 拒 L 第二臂 paint | allow |
| 3 | `_test_single_axis_keeps_straight_second_arm` | 445 | 拒 L 第二臂 paint | allow |
| 4 | `_test_dual_arms_se_plus_l_fill` | 517 | 拒 L 第二臂 paint | allow |
| 5 | `_test_bend_low_side_not_auto_diagonal` | 677 | 拒低侧拐弯 paint | allow |
| 6 | `_test_l_corner_from_low_side_correct_origin` | 743 | 拒 L 邻臂 paint | allow |
| 7 | `_test_l_then_dual_axis_expands_to_diagonal` | 807 | 拒 L 第二臂 paint | allow |
| 8 | `_test_side_is_l_arm` | 939 | 拒 L 邻臂 paint | allow |
| 9 | `_test_ramp_cols_opposite` | 968 | A/B 污染 false | true（放宽）|

### 4.3 `selftest_ramp_present.gd` — 4 个 case 失败

| # | 测试 | 行 | HivEWE 行为 | 老李扩展行为 |
|---|------|---|-------------|-------------|
| 1 | `_test_l_recess_entrance` | 187 | 拒 L 凹陷 paint | allow |
| 2 | `_test_l_recess_not_fake_diagonal` | 238 | 拒 L 凹陷 paint | allow |
| 3 | `_test_l_corner_clifftrans` | 417 | 拒 L 转角 paint | allow |
| 4 | `_test_no_clifftrans_keeps_ground` | 468 | 拒 L 转角 paint | allow |

### 4.4 决策路径

- **A 向 HivEWE 靠拢**：删 [§3.1-§3.4] 全部扩展 + 改 9+4 case 期望（`expect reject`）
- **B 保留老李扩展**：改 9+4 case 期望（`expect reject` 在 HivEWE 严格禁门下）——但代码放宽会通过——**矛盾**！

实际只有 **A** 路径一致：删扩展 + 改测试。

---

## 5. 实施步骤

按 A 路线：

1. **手测经典 WE Lost Temple**（[§3.1] [§3.2] 决策点）：
   - L 转角邻臂 paint（接受 / 拒绝？）
   - 反向 paint（接受 / 拒绝？）
   - L 凹陷视觉（内角平底 / 凹陷坡？）
2. **手测结果**决定 [§3.1-§3.4] 是否全删
3. 如全删（A 路线）：
   - 改 9 logic + 4 present case 期望（`expect reject`）
   - 改 [RAMP_WE.md §6.1 §6.2 §4.2](RAMP_WE.md) 同步（HivEWE 严格行为记录）
   - 跑全测试通过 → 一次性 commit
4. 如部分删：
   - 按 §3.1-§3.4 各自决定
   - 删的 case 改 `expect reject` 或删 case
   - 留的 case 保留扩展

---

## 6. 源码索引

| 主题 | HivEWE 文件 | HivEWE 符号 | 本仓库符号 |
|------|------------|------------|------------|
| 落旗 | `terrain_operators.cpp` | `update_ramp` ~L406 | `Wc3RampPaint.plan` |
| 方向门禁 | `terrain_operators.cpp` | `check_ramp_direction` ~L427 | `Wc3RampPaint._check_column` ~L769 |
| 紧贴对侧禁门 | `terrain_operators.cpp` | line 448-459 | `Wc3RampPaint._check_column` line 808-826 |
| L 补心 | `terrain_operators.cpp` | L509-535 | `Wc3RampPaint.fill_l_centers` ~L116 |
| CliffTrans 匹配 | `terrain.ixx` | `update_cliff_meshes` ~L1047 | `Wc3RampCollect._try_vertical` / `_try_horizontal` |
| 入口 | `terrain.ixx` | `is_corner_ramp_entrance` ~L819 | `Wc3RampCollect._is_classic_entrance` + `_is_l_recess_entrance` |
| +0.5 boost | `terrain.ixx` | `update_ground_heights` ~L912-946 | `Wc3RampCollect.plan_entrance_height_boost` |

---

## 7. 相关文档

- [RAMP_WE.md](RAMP_WE.md) — 领域权威（WE 怎么想、怎么算）
- [RAMP_REFACTOR.md](RAMP_REFACTOR.md) — 重构历史
- [README.md](README.md) — 斜坡模块入口
- HivEWE 源码：`D:\GameMaker\HiveWE\src\brush\terrain_operators.cpp` + `src\base\terrain.ixx`
