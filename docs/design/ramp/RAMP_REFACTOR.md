# 斜坡逻辑层重构方案

> 重构目标：**不改逻辑结果，只优化代码结构**
>
> 所有条件分支、门禁规则、变体判断保持完全一致。

---

## 问题一览

| # | 问题 | 严重度 | 位置 |
|---|------|--------|------|
| 1 | `extend_same_side` 死代码从未调用 | 低 | wc3_ramp_paint.gd |
| 2 | `plan()` 超长 ~140 行 | 高 | wc3_ramp_paint.gd |
| 3 | L 状态机 5 布尔量纠缠 | 中 | wc3_ramp_paint.gd |
| 4 | 变体→轴向映射矛盾（axis=D 但 variant=L） | 低 | wc3_ramp_paint.gd |
| 5 | `plan_from_pointer` fallback 成功静默覆盖 | 低 | wc3_ramp_paint.gd |
| 6 | `_check_column` 侧翼禁贴 ~35 行深嵌 | 中 | wc3_ramp_paint.gd |
| 7 | 入口判断逻辑重复（`is_entrance` vs 内部直接调用） | 中 | wc3_ramp_collect.gd |
| 8 | 低侧搜索半径硬编码 2，不可配置 | 低 | wc3_ramp_paint.gd |
| 9 | `_score_plan` 评分因子无注释，黑箱 | 低 | wc3_ramp_paint.gd |
| 10 | 无单元测试覆盖内部路径 | 中 | tests/unit/ |
| 11 | 文件头注释与实现不符（同侧扩展未实现） | 低 | wc3_ramp_paint.gd |
| 12 | `_ramp_cols_opposite` 放宽条件是否对称存疑 | 低 | wc3_ramp_collect.gd |

---

## 详细方案

---

### 问题 1 — `extend_same_side` 死代码

**现状**：函数已实现但 `plan()` 路由从未调用，无法实际生效。

**方案**：
- 文件头注释去掉「同侧扩展 → 增加斜坡宽度」描述
- 函数体保留（将来可能需要），在函数上方加 `@deprecated` 注释说明「当前路由未接入，待需要时启用」

**改动文件**：`wc3_ramp_paint.gd`

---

### 问题 2 — `plan()` 超长 ~140 行

**现状**：所有逻辑堆在一个函数里，难以维护。

**方案**：拆为 4 个阶段函数，主 `plan()` 变为纯调度：

```gdscript
## plan() 重构前 ~140 行 → 调度中心 ~30 行
static func plan(...) -> Dictionary:
    # Phase A：边界 + 层差 + 方向规范
    var ctx := _build_context(ix, iy, layers, flags, tp_w, tp_h, horizontal, vertical)
    if ctx.is_empty():
        return Wc3RampLogic.plan_fail(...)

    # Phase B：ramp 快照 + 三重门禁
    var gates := _run_gate_checks(ctx)
    if gates == null:
        return Wc3RampLogic.plan_fail(...)

    # Phase C：L 状态机
    var lst := _compute_l_state(ctx, gates)

    # Phase D：落旗 + 变体解析
    return _execute_mark_and_resolve(ctx, gates, lst)
```

每个阶段函数 ~15-25 行，职责单一。

**改动文件**：`wc3_ramp_paint.gd`

---

### 问题 3 — L 状态机 5 布尔量纠缠

**现状**：
```gdscript
var had_arm: bool = _origin_has_any_full_arm(...)
var has_h_arm: bool = ...
var has_v_arm: bool = ...
var l_ready: bool = has_h_arm and has_v_arm
var l_fill_only: bool = (
    not allow_h and not allow_v and not allow_d
    and _would_fill_l_center(...)
)
```

**方案**：替换为枚举 + 纯函数：

```gdscript
enum LRampState {
    NONE,       # 无臂
    HAS_H,      # 只有水平臂
    HAS_V,      # 只有竖直臂
    READY,      # 两臂齐（L 成型）
    FILL_ONLY,  # 列门禁全拒但能补 L 中心
}

static func _compute_l_state(ctx: Dictionary, gates: Dictionary) -> LRampState:
    var has_h := _has_full_ramp_arm(ctx.ix, ctx.iy, 1, 0, ctx.ramp, ctx.tp_w, ctx.tp_h) \
              or _has_full_ramp_arm(ctx.ix, ctx.iy, -1, 0, ctx.ramp, ctx.tp_w, ctx.tp_h)
    var has_v := _has_full_ramp_arm(ctx.ix, ctx.iy, 0, 1, ctx.ramp, ctx.tp_w, ctx.tp_h) \
              or _has_full_ramp_arm(ctx.ix, ctx.iy, 0, -1, ctx.ramp, ctx.tp_w, ctx.tp_h)
    if not has_h and not has_v:
        return LRampState.NONE
    if has_h and has_v:
        return LRampState.READY
    if not gates.allow_h and not gates.allow_v and not gates.allow_d:
        if _would_fill_l_center(...):
            return LRampState.FILL_ONLY
    return LRampState.HAS_H if has_h else LRampState.HAS_V
```

**改动文件**：`wc3_ramp_paint.gd`

---

### 问题 4 — 变体→轴向映射矛盾

**现状**：`allow_h && allow_v` 时 `axis=AXIS_D` 但 `variant=VARIANT_L`。

**方案**：在 `plan()` 的变体解析注释中明确说明：

```gdscript
## L 变体使用 AXIS_D：L 本质是两臂交汇的角点，
## 与对角共享「角轴」语义；后续 footprint 判断只用 H/V，
## D 轴仅作标记用途，不影响 Present 建模。
```

不做代码逻辑改动，仅加文档说明。

---

### 问题 5 — fallback 成功静默覆盖

**现状**：`plan_from_pointer` 低侧解析成功时无任何提示。

**方案**：在 fallback 成功路径加一行 debug 日志：

```gdscript
## plan_from_pointer 内
if bool(resolved.get("ok", false)):
    AppLogScript.debug(AppLogScript.Layer.LOGIC, "RampPaint",
        "low_side_fallback ok @(cx=%d,cy=%d) → origin=(%d,%d)"
        % [resolved.get("sx"), resolved.get("sy"), resolved.get("sx"), resolved.get("sy")])
    return resolved
```

**改动文件**：`wc3_ramp_paint.gd`

---

### 问题 6 — `_check_column` 侧翼禁贴 ~35 行深嵌

**现状**：侧翼检查逻辑（平行扩宽豁免 / L 臂豁免 / completing_l 豁免）全部写在 `_check_column` 内部。

**方案**：提取为独立函数：

```gdscript
## 检查侧邻有 ramp 时是否「合法」
## 返回 true = 允许（豁免），false = 禁止
static func _side_ramp_compatible(
    ix: int, iy: int,
    dir_x: int, dir_y: int,     # 坡向
    sx: int, sy: int,           # 侧邻坐标
    completing_l: bool,
    ramp: PackedByteArray,
    tp_w: int, tp_h: int
) -> bool:
    if not _has_ramp(ramp, tp_w, tp_h, sx, sy):
        return true  # 无旗，跳过
    # 平行扩宽豁免
    if _has_full_ramp_arm(sx - ix + sx, sy - iy + sy, dir_x, dir_y, ramp, tp_w, tp_h):
        return true
    # L 臂豁免
    if _side_is_l_arm(ix, iy, sx, sy, ramp, tp_w, tp_h):
        return true
    # completing_l 豁免
    if completing_l:
        return true
    return false
```

原 `_check_column` 内遍历侧邻的循环简化为：

```gdscript
for side in [-1, 1]:
    var sx := ix + side * (-dir_y)
    var sy := iy + side * dir_x
    if not _in_bounds(sx, sy, tp_w, tp_h):
        continue
    if not _side_ramp_compatible(ix, iy, dir_x, dir_y, sx, sy, completing_l, ramp, tp_w, tp_h):
        return false
```

**改动文件**：`wc3_ramp_paint.gd`

---

### 问题 7 — 入口判断逻辑重复

**现状**：`plan_entrance_tiles()` 内部直接调用 `_is_classic_entrance` / `_is_l_recess_entrance`，与对外 `is_entrance()` 入口重复。

**方案**：`plan_entrance_tiles()` 改用 `is_entrance()` 配合类型过滤：

```gdscript
## plan_entrance_tiles 内，重构后
for iy in range(map_h):
    for ix in range(map_w):
        if not is_entrance(flags, layers, tp_w, tp_h, ix, iy):
            continue
        # 区分类型走不同路径
        if _is_l_recess_entrance(flags, layers, tp_w, ix, iy):
            # L 碗处理...
        elif _is_outer_corner_ramp_tile(...)
            # 外角碗处理...
        elif _is_classic_entrance(...):
            # 经典入口处理...
```

**改动文件**：`wc3_ramp_collect.gd`

---

### 问题 8 — 低侧搜索半径硬编码 2

**方案**：提取为模块级常量：

```gdscript
## wc3_ramp_paint.gd 顶部常量区
const LOW_SIDE_SEARCH_RADIUS := 2
```

`_resolve_from_low_side` 中的 `range(click_y - 2, click_y + 3)` 改为 `range(click_y - LOW_SIDE_SEARCH_RADIUS, click_y + LOW_SIDE_SEARCH_RADIUS + 1)`。

**改动文件**：`wc3_ramp_paint.gd`

---

### 问题 9 — `_score_plan` 评分因子黑箱

**方案**：在函数开头加结构化注释：

```gdscript
## 评分因子说明：
##   标记点距离 click 越近分越高：d=0 → +100, d=1 → +40, d=2 → +8
##   原点距 click 越近分越高：max(|dx|,|dy|) ≤ 5，每少 1 格 +4
##   click 落在「沿本笔坡向的轴上」→ +60（真·转角原点）
##   变体偏好：
##     单轴 pref 时：diagonal -80, L +10, n>3 单列 -40, 单列 +25
##     双轴 pref 时：diagonal +20, L +15
static func _score_plan(...) -> int:
```

**改动文件**：`wc3_ramp_paint.gd`

---

### 问题 10 — 无单元测试覆盖内部路径

**方案**：在 `tests/unit/selftest_ramp_logic.gd` 尾部追加 5 个新测试函数：

```gdscript
func _test_soften_dirs() -> void:
    # 同现有 selftest_ramp_logic.gd 第 129 行
    # 补充边界：ax==ay, ax>2*ay, ay>2*ax

func _test_check_column_gate() -> void:
    # 构造纯层差地形（无侧邻干扰），验证 _check_column 单轴门禁

func _test_check_diagonal_box_gate() -> void:
    # 构造 origin=高层、8邻=低层的对角地形，验证 _check_diagonal_box

func _test_side_is_l_arm() -> void:
    # 验证侧邻是否构成 L 的一肢

func _test_ramp_cols_opposite() -> void:
    # 验证严格模式 + 放宽模式（污染中格）的所有组合
```

**改动文件**：`tests/unit/selftest_ramp_logic.gd`

---

### 问题 11 — 文件头注释与实现不符

**方案**：更新 `wc3_ramp_paint.gd` 文件头注释：

```gdscript
## 三层架构：
##   Step 1 — 单列斜坡：沿方向标注连续 3 个顶点
##   Step 2 — 方向变体：
##     邻侧扩展 → 对角斜坡，3×3 box（9点）
##     同侧扩展 → 增加斜坡宽度（多列，暂未接入路由 @deprecated）
##   Step 3 — 路由：根据顶点信息 + 门禁校验，决定落哪种变体
```

---

### 问题 12 — `_ramp_cols_opposite` 放宽条件对称性存疑

**分析结论**：三种情况已覆盖所有合法组合（严格相反 + A 列污染 + B 列污染），逻辑对称。加注释：

```gdscript
## 两列 ramp 是否构成合法坡列组合：
##   1. 严格：列内全同，列间相反
##   2. A 污染：A 完整，B 仅中格被污染（两端仍相反）
##   3. B 污染：B 完整，A 仅中格被污染（两端仍相反）
## 注意：两端有旗中格无旗的「双向各污染」不属于合法组合（无法判断 base 层）
```

**改动文件**：`wc3_ramp_collect.gd`

---

## 重构前后对比

| 文件 | 重构前 | 重构后 |
|------|--------|--------|
| `wc3_ramp_paint.gd` | ~770 行，plan() ~140 行 | ~750 行，plan() ~30 行调度 + 4 个 ~20 行阶段函数 |
| `wc3_ramp_collect.gd` | `plan_entrance_tiles` 直接调内部函数 | 统一经 `is_entrance()` 过滤后分支 |
| `selftest_ramp_logic.gd` | ~317 行，9 个高层测试 | ~420 行，14 个测试（含内部路径） |

---

## 测试验证计划

### 验证原则

**所有已有测试必须通过**，且行为完全一致。重构只改代码组织，不改任何条件分支。

### 验证步骤

```
1. 现有测试回归
   godot --headless --path . -s res://tests/unit/selftest_ramp_logic.gd
   godot --headless --path . -s res://tests/unit/selftest_ramp_data.gd
   → 必须全部 PASS，零 FAIL

2. 新增内部路径测试
   → 覆盖 soften_dirs / _check_column / _check_diagonal_box / _side_is_l_arm / _ramp_cols_opposite

3. 逻辑等价性抽检（人工）
   - 四种对角方向（hx/hy 符号组合）刷坡验证 3×3 box 范围
   - 低侧 fallback 路径验证 origin 解析正确
   - L 补心路径验证中心点只补一个
   - 幂等测试（重复刷同一位置不变）
```

### 风险控制

- **问题 3（枚举替换布尔）**：枚举值数量与原布尔组合数严格对应，状态转换逻辑一一对应
- **问题 6（提取侧翼函数）**：原 `_check_column` 内所有判断条件原样保留，只移动代码位置
- **问题 7（统一入口）**：`plan_entrance_tiles` 内部三个分支条件与原完全相同，仅增加一层分发

---

## 执行顺序

建议按以下顺序逐步推进，每步完成后运行测试验证：

1. **问题 8**（常量提取）— 最简单，无风险
2. **问题 11**（注释修正）— 仅文档
3. **问题 12**（加注释）— 仅注释
4. **问题 5**（加日志）— 仅加一行
5. **问题 9**（加注释）— 仅注释
6. **问题 4**（加注释）— 仅文档
7. **问题 1**（标记 deprecated）— 仅注释
8. **问题 6**（提取侧翼函数）— 逻辑不变，结构优化
9. **问题 7**（统一入口）— 逻辑不变，结构优化
10. **问题 10**（新增测试）— 增加覆盖
11. **问题 3**（枚举替换布尔）— 核心重构
12. **问题 2**（拆分 plan）— 最后执行，依赖问题 3 的结果
