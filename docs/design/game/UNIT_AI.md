# 单位 AI（Unit AI）：野怪对抗 · 闲置索敌 · 非 AI 玩家

> 状态：**U1+U2 已落地**（受击反击 + acquire 警戒）；下一刀 U3 Echo 手测 / 抛光  
> 前置：**战斗 C0–C3 已接线**，见 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) §0a  
> 相关：[GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) · [ROADMAP.md](ROADMAP.md) · [ARCHITECTURE.md](ARCHITECTURE.md)  
> 竖切目标：Echo Isles 上**野怪能与玩家单位互殴**（受击反击 + 警戒索敌）  
> 最后更新：2026-08-21

---

## 0. 结论（先读）

**做的是单位级微观 AI**，不是电脑玩家（Melee AI / 扩张 / 进攻波次）。

| 要做 | 不做 |
|------|------|
| 每个可战斗单位的「自主决策」：何时索敌、反击、追击、回营 | AI 玩家下矿、造兵、多线进攻 |
| 决策结果 = 发 **Attack / Stop / 回锚点 Move**，仍走现有 `AttackController` | 再写一套扣血 / 追击 / 冷却 |
| 野怪营（中立 owner≥12）P0 能打玩家 | 行为树引擎、完整 creep camp 表驱动（可后置） |

**一句话**：`UnitAI` 只负责「该不该打谁」；「怎么打」全部委托已落地的战斗管线。

```text
感知 / 受击事件
      │
      ▼
  UnitAI（决策表 / 小 FSM）  ──issue──►  AttackController / Navigator
      │                                      │
      │                                      ▼
      └── 禁止 set_life ──────────── DamagePipeline / CombatQuery
```

---

## 1. 现状缺口（对照战斗 as-built）

| 能力 | 今日 | 缺口 |
|------|------|------|
| 玩家 Attack / 攻移 / Hold | ✅ `CommandRouter` → `AttackController` | — |
| 野怪被打 | ✅ 可受伤、可死 | ❌ **不反击** |
| 野怪 idle 看见玩家走进 `acquire` | ❌ 无组件在 tick | ❌ 不主动接战 |
| Hold 索敌 | ✅ 仅出手射程内、不追 | 野怪警戒需要 **acquire 半径 + 可追** |
| `AttackController` 挂载 | 懒挂（有命令才 ensure） | 野怪入场就要能决策 → **入场 ensure** |
| 助攻 / 回营 leash | ❌ 助攻 / ✅ leash | 助攻仍 P1 |

`COMBAT_SYSTEM.md` §1.2 / §3.4 曾写「P0 中立不反击」——那是**战斗竖切**范围；本文件把它升级为**单位 AI 主线**。

---

## 2. 范围与非目标

### 2.1 本里程碑要做（U0–U3）

| ID | 玩法 | 最小交付 |
|----|------|----------|
| U0 | 文档 + 挂载点 | 本文；入场 `ensure_unit_ai`；可战斗单位 ensure `AttackController` |
| U1 | 受击反击 | 受伤且来源合法敌对 → 对来源 `start_attack`（打断闲置，不抢玩家显式命令优先级见 §5） |
| U2 | 警戒索敌 | 闲置时在 `acquire` 内 `find_acquire_target` → `start_attack` |
| U3 | Echo 验收 | 走近野怪营被拉；互殴致死；Stop/新命令可打断 AI 进攻 |
| U4 | Leash 归巢 | 追出 `leash_wc3` → 停攻回 `home_wc3`；归途不重开仇恨 |

### 2.2 明确不做（本分支实现，接口先留）

- AI 玩家（选点、科技树、多线）
- 完整行为树框架 / 通用 BT 编辑器
- 逃跑（低血 evade）、风筝、技能施放 AI
- ~~全图 camp 表、睡眠/苏醒、白天黑夜 aggro 修正~~ → **逻辑后置**；`UnitAI` 已留接口见 §4.5
- 联机确定性（沿用现有 `CombatRng` 口径）
- 把 AI 写进 `Map*Layer` / `Unit` 表现脚本

### 2.3 P1 / 后置（不挡 U0–U3 验收）

| 项 | 说明 | 接口落点 |
|----|------|----------|
| Leash / 回锚 | ✅ 默认 1000 WC3（营地 1200）；`RETURNING` 途中不索敌不反击 | `home_wc3` / `leash_wc3` / `State.RETURNING` |
| 营地助攻 | ✅ `TeamRegistry.notify_ally_engaged`；同 camp 全员可拉 | `team_registry.gd` · `TeamRegistry.notify_ally_engaged` |
| 玩家 team 盟友挨打 | ✅ `TeamRegistry.notify_ally_engaged` 对玩家 team 也走相同广播；仅当触发源 ENGAGED 才拉 | `Profile.TEAM_PLAYER` · `UnitAI.allows_ally_engage` |
| 全图 camp / team 注册表 | ✅ `TeamRegistry`：玩家按 owner，中立按距离聚类 | `TeamRegistry.cluster_and_bind` · `on_unit_gone` |
| 睡眠 / 苏醒 | 夜间睡、受击醒；读 `UnitData.canSleep` | `State.SLEEPING` · `set_asleep` · `notify_time_of_day` · `try_wake` |
| 昼夜 aggro | acquire 乘倍率（夜更警觉等） | `configure(..., aggro_range_mult)` · `effective_acquire_range_wc3()` |
| `OrderArbiter` | 从 Router `_abort_*` 抽薄壳 | 命令层 |

---

## 3. 分层落位

属 **Game Logic**，与 `AttackController` 同级组件。

```text
game/scripts/logic/
├── combat/                    # 已有：打法执行
│   ├── attack_controller.gd
│   ├── combat_query.gd
│   └── …
└── ai/                        # 新增：单位决策
    ├── unit_ai.gd             # 每单位组件（小 FSM + Profile）
    ├── unit_ai_profile.gd     # 枚举 / 静态参数（可先内联在 unit_ai）
    └── unit_ai_events.gd      # 可选：会话级把 damage_applied 扇出给受害者 AI
```

**禁止**：AI 内调用 `UnitLife.set_life`；AI 内播 Attack 动画；AI 里 `match type_id` 写死伤害。

---

## 4. 架构裁决

### 4.1 与战斗文档 §2.1-F 对齐

| 方案 | 裁决 |
|------|------|
| 玩家单位主路径用 BT | **不采用**（仍是命令驱动） |
| 野怪 / 闲置警戒用小型决策表或域内 FSM | **采用** |
| 决策产出 Order / `AttackController` API | **强制** |
| 单位级巨型 FSM（Idle/Attack/Harvest…） | **不采用** |

### 4.2 组件关系

`UnitAI` = 单位根上的**子节点**（`Node`，名 `UnitAI`），与 `AttackController` / `HarvestController` 同构。

| 谁挂 | 规则 |
|------|------|
| 可战斗中立野怪 | 挂；Profile=`CAMP_CREEP`（U0-2 ensure） |
| 可战斗玩家军事单位 | P0 挂 `PASSIVE`（占位）；P1 可改 `TEAM_PLAYER`（待补 idle 抢占边界后切） |
| 无武器 / 小动物 | **不挂**，或挂 `PASSIVE` 空转（优先不挂） |
| 农民 | **不靠 UnitAI 做采集**；采集见下「与 Harvest 边界」 |
| **防御塔 / 有武器建筑** | **算单位微观 AI，不是 AI 玩家**。P0 `ensure` 刻意跳过建筑（Echo 竖切先跑野怪）；P1 应对「有武器建筑」单独挂：`AttackController` + `UnitAI`（Profile 近 `CAMP_CREEP`/`GUARD`：acquire 内打、**通常不追出射程/锚点**） |

### 4.2c U1 受击反击 vs U2 警戒 vs Hold（勿混）

| 机制 | 触发 | 追击？ | 谁用 |
|------|------|--------|------|
| **U2 警戒索敌** | 敌对进入 **`acquire`** | 是 → 完整 `ATTACK`（可追到交战） | 野怪闲置主路径；「进圈就打」指这个 |
| **U1 受击反击** | **被打**且来源敌对 | 是 → `start_attack(来源)` | 补洞：远程风筝在 acquire 外先手、睡觉被打醒等；**不是** Hold |
| **Hold（玩家 H）** | 仅 **出手射程** 内索敌 | **不**追 | `AttackController.HOLD`；与 UnitAI 警戒不同 |
| **Leash / 追击上限** | 已接战后追出营/锚点半径 | 停攻回营 | **单位 AI（U4）**，不是电脑玩家 AI |

野怪「追到超出范围再回家」= **单位 AI + leash**，与 AI 玩家无关。

```text
Unit (Node3D)
├── UnitNavigator
├── AttackController          # 战斗执行层（已有）
├── UnitAI?                   # 战斗自主决策（无武器可不挂）
├── HarvestController?        # 采集执行层（仅工人；已有）
└── …
```

共享服务仍挂在 Session / Director：

- `DamagePipeline.damage_applied` → Director 转发给**受害单位**的 `UnitAI.notify_damaged`
- `CombatQuery` 静态查询照旧

### 4.2b 与采集 / 建造的架构边界（农民「AI」）

**不要**把伐木/挖金塞进 `UnitAI`。仓库已是「域内小 FSM」：

| 层 | 战斗 | 采集 |
|----|------|------|
| 玩家/智能命令 | `CommandRouter` → Attack Order | → Harvest Order |
| **自主决策**（无命令时谁主动） | **`UnitAI`**（警戒/反击） | 电脑玩家宏观才需要；工人 P0 **无** |
| **订单执行**（有命令后怎么循环） | `AttackController` | **`HarvestController`**（矿↔交货自动循环） |

农民右键金矿后的「一直采」是 **HarvestController 订单 AI**，不是单位级战斗 AI。若将来 AI 玩家要自动派农民，应是 **Melee/Player AI 发 Harvest Order**，仍进 `HarvestController`，不扩 `UnitAI.Profile`。

### 4.3 UnitAI 状态（刻意少）

```text
enum State {
  IDLE = 0,       # 可索敌 / 可听受击
  ENGAGED = 1,    # 已把进攻交给 AttackController（AI 持有「意图」）
  RETURNING = 2,  # P1：回锚点
  SLEEPING = 3,   # 后置：夜间睡觉（`sleep_rules_enabled` 前不会进入）
}
```

- `ENGAGED`：**不**复制追击逻辑；每帧只检查「目标是否仍有效 / 是否被更高优先级命令抢走 / 是否超 leash」
- 玩家下 Move / Attack / Harvest / Build / Stop → AI `yield_to_player()`：清意图，必要时 `AttackController.cancel` 已由 Router 做
- `SLEEPING`：`wants_idle_acquire()==false`；受击走 `try_wake()` 再反击

### 4.5 后置扩展接口（已挂在 UnitAI，勿绕开另起炉灶）

| 能力 | API | 当前行为 |
|------|-----|----------|
| 营地归属 | `camp_id` / `bind_camp` / `clear_camp` / `has_camp` / `camp_bound` | 只存 id；无 Registry |
| 营友助攻 | `notify_camp_ally_engaged(target)` | no-op |
| 睡眠 | `set_asleep` / `is_asleep` / `can_sleep_by_data` / `try_wake` / `sleep_changed` | 可手动设；默认不睡 |
| 昼夜驱动睡眠 | `notify_time_of_day(is_day)` + `sleep_rules_enabled` | flag 默认 false → no-op |
| 昼夜 aggro | `configure(..., aggro_range_mult)` / `effective_acquire_range_wc3()` | 倍率缺省 1.0 |

会话侧后置建议：

```text
CreepCampRegistry          # camp_id → { home, members, assist_radius }
DayNightClock / Environment  → UnitAI.notify_time_of_day / aggro_range_mult
```

U2 索敌必须用 `effective_acquire_range_wc3()`，不要直接裸读 `CombatQuery.acquire_range_wc3`，以免昼夜修正接不上。

### 4.4 Profile（竖切三种）

| Profile | 谁用 | idle 索敌 | 受击反击 | 盟友挨打可参战 | leash |
|---------|------|-----------|----------|----------------|-------|
| `PASSIVE` | 小动物等（可选） | 无 | 可选逃跑后置 | — | — |
| `CAMP_CREEP` | Echo 野怪默认 | ✅ | ✅ | ✅（同 camp 全员可拉） | ✅ |
| `TEAM_PLAYER` | 玩家军事单位（暂未默认） | ✅ | ✅ | ✅（同 team 有人已 ENGAGED 才拉） | —（跟玩家命令） |
| `REACTIVE` | 玩家辅助单位（默认） | ✘ | ✅ | ✅ | — |

> **当前默认**：中立可战 → `CAMP_CREEP`；玩家可战 → `REACTIVE`（受击反击 + 盟友广播可拉；不主动 idle acquire，避免抢玩家命令）。
> `TEAM_PLAYER` 代码已就位（盟友挨打广播 / `allows_ally_engage`），但 `wants_idle_acquire` 一开会跟玩家命令争抢 `set_current` 序列，**待 P1 补「玩家显式命令时压制 idle acquire」边界后再切默认**。
> P1 路线：`default_profile_for` 玩家单位改回 `TEAM_PLAYER`，并加 selftest 兜住「move 后 6Hz 内不被偷打」。

P0 实现：地图中立 + `has_weapon` → `CAMP_CREEP`；玩家可战 → `REACTIVE`；其余不挂或 `PASSIVE`。

> **别名**：`PLAYER_MILITARY = TEAM_PLAYER`，保留供旧引用；新代码统一用 `TEAM_PLAYER`。

### 4.5 仇恨表（ThreatTable）+ Sticky Target（U5）

**问题**：旧 `_issue_ai_attack` 每次都「按距离最近」选目标，野怪 / 玩家单位会在多个敌人之间来回横跳，仇恨完全不稳定。

**解法**：每个 `UnitAI` 维护一张仇恨表，叠加「sticky 锁定」+「切目标冷却」，让目标选择有记忆。

#### 数据结构

| 字段 | 含义 |
|------|------|
| `_threat: Dictionary[id → float]` | 仇恨值表；写入：受击 `add_threat(attacker, dmg × 1.0)` + idle acquire 候选基础值 0.1 |
| `_swap_cd: float` | 切目标冷却（0.25s）；受击强制清零 |
| `_locked_target: Node3D` | sticky 锁定目标；hold 窗口 1.5s 内不重新 acquire |
| `_locked_at_msec: int` | 锁定时间戳 |

#### 衰减

- 每秒 `THREAT_DECAY_PER_SEC = 0.3`（WC3 经典值）；≤0 即从表移除
- 死亡 / 脱敌对 / 脱离 acquire 半径 → 立即移除并清 sticky 锁

#### 选目标（`_pick_target`）

```text
1) sticky: _locked_target 存活 + 敌对 + 在 acquire 半径内 + 锁未超 1.5s → 保留
   ↓ 否则清锁 / 清仇恨
2) top_threat: 仇恨表按值排序，过滤死亡 / 失效 / 脱敌对 → 取最大
   ↓ 仍空
3) 兜底: CombatQuery.find_acquire_target（最近敌对）
```

#### 触发写入 / 重读

| 时机 | 动作 |
|------|------|
| `notify_damaged` | `add_threat(attacker, dmg)` + 清 `_swap_cd`（保证攻击者必中） |
| `try_engage` 成功 | `_locked_target = target`；`_swap_cd = 0.25`；`_threat[id] = max(_, 0.1)` |
| `_process` 节流（6Hz） | `_decay_threat(delta)` + `_swap_cd -= delta`；到 0 才让 `_tick_idle_acquire` 重新选 |
| `_on_combat_ended` | 走 `_pick_target`（不再直接 `find_acquire_target`） |

#### AttackController 切目标防卡刀

```gdscript
# 切目标时保留原冷却余量 + 最小 0.05s 切换间隔（_MIN_SWAP_COOLDOWN）
_cooldown_left = maxf(_cooldown_left, _MIN_SWAP_COOLDOWN)
```

避免「同一帧在 A/B 之间反复切」造成卡刀刷伤 / 攻击动画抽筋。

#### 与原 Profile 矩阵的兼容性

| Profile | idle acquire | 受击反击 | 盟友挨打可拉 | 应用 |
|---------|-------------|----------|--------------|------|
| `CAMP_CREEP` | ✅ | ✅ | ✅ | Echo 野怪 |
| `TEAM_PLAYER` | ✅ | ✅ | ✅ | 玩家军事（P1 切默认） |
| `REACTIVE` | ✘ | ✅ | ✅ | 玩家辅助（当前默认） |
| `PASSIVE` | ✘ | ✘ | ✘ | 小动物 |

#### 验证

`tests/unit/selftest_threat_table.gd`（10 用例）：`threat_add_and_top` / `threat_decay_removes_when_zero` / `threat_filters_dead_and_neutral` / `sticky_holds_through_tiny_window` / `sticky_drops_when_target_out_of_range` / `swap_cooldown_blocks_extra_pick` / `swap_cooldown_cleared_by_damage` / `reactive_does_not_idle_acquire` / `reactive_does_ally_engage` / `pick_target_prefers_higher_threat_over_closer`。

---

## 5. 命令优先级（必须钉死）

从高到低：

1. **玩家显式命令**（含智能右键、A/H/P、采集、建造）  
2. **UnitAI 受击反击**（目标 = 伤害来源）  
3. **UnitAI idle 警戒索敌**  
4. 真正发呆

规则：

- AI 只能在「当前无玩家订单占用」或「当前订单就是 AI 自己发起的 Attack」时发令。  
- 判定「玩家占用」P0 可用：`CommandRouter` / 单位上已有 `UnitOrder` 队列 `current` 的 `source == PLAYER`（或 meta `player_ordered`）；若现有 Source 枚举不够，**补 `UnitOrder.Source.UNIT_AI`**。  
- 玩家 Stop：清 AI 意图 + cancel Attack。  
- AI 发起的 Attack：`source = UNIT_AI`，便于被玩家命令干净替换。

---

## 6. 关键算法（可直接照写）

### 6.0 营地 / 队伍注册（TeamRegistry）—— 已落地

会话级单例 `game/scripts/logic/ai/team_registry.gd`：

- **玩家 owner 索引**：owner<12 全部入 `p<owner>` team（player 0/1/...）。
- **中立野怪聚类**：owner≥12 且可战斗者两两距离 ≤ `CAMP_CLUSTER_RADIUS_WC3 = 900` 视为同营地（`c<n>`）。
- **营地 home**：成员位置几何中心；成员死亡 / 离场后 `on_unit_gone` 重算（最后一个存活成员的位置兜底）。
- **营地 leash**：`CAMP_LEASH_WC3 = 1200`；player team **不** leash（玩家命令优先）。

入场 `Director._wire_all_unit_ai` 末尾调 `TeamRegistry.attach(self).cluster_and_bind(host)`；单位死亡走 `DeathService.kill` → `TeamRegistry.on_unit_gone`。

### 6.1 盟友挨打自动参战（与 U1 受击反击并列，已落地）

`TeamRegistry.notify_ally_engaged(source, attacker, radius_wc3)`：

```text
gid = group_of(source)
if 是玩家 team（gid = "p<owner>"）：
  仅当 source.is_engaged() == true 时才拉（玩家闲站不自动接战）
else（gid = "c<n>" 营地）：
  全部存活成员都可拉
for m in members_of(gid):
  if 距 source ≤ radius_wc3（默认 900）：
    if m.allows_ally_engage()（未睡 / 未 RETURNING / 未玩家占用 / Profile ∈ {CAMP_CREEP, TEAM_PLAYER}）：
      if CombatQuery.is_auto_acquire_target(m, attacker)：
        m.try_engage(attacker)    # 走 AttackController，source = UNIT_AI
```

触发点：
- 玩家单位受击：`UnitAI.notify_damaged` → 反击 → `notify_camp_ally_engaged(attacker)` → 同 team 拉人。
- 营地成员受击：同上，同 camp 全员可拉。

返回成功参战人数；UI / 自测可观察。

### 6.2 入场（U0）

### 6.1 入场（U0）

在地图单位生成 / 训练出生与 Director 现有 `InteractionSetup.attach` 同路径：

```text
if CombatQuery.has_weapon(unit):
    ensure_attack_controller(unit)   # 已有
    ensure_unit_ai(unit)             # 新增；按 owner 选 Profile
```

中立判定：`CombatQuery.is_neutral_owner(owner_of(unit))`。

锚点：`home_wc3 = godot_to_wc3_xy(unit.global_position)`（生成时记一次）。

### 6.2 受击反击（U1）

订阅点（二选一，推荐 A）：

- **A.** `GameDirector` 已接 `_damage_pipeline.damage_applied` → 除飘字外调用 `UnitAI.notify_damaged`  
- **B.** 会话级 `UnitAiEvents` 再扇出（单位多时再拆）

```text
notify_damaged(self, result):
  if profile 不反击: return
  if 正在被玩家订单占用: return
  attacker = result.attacker
  if not CombatQuery.is_auto_acquire_target(self, attacker): return
  if AttackController 已在打同一目标: return
  ensure AttackController
  start_attack(attacker)
  state = ENGAGED
  mark order source = UNIT_AI
```

注意：`DamagePipeline` 在击杀时也会 emit；死者 AI 不应再动（`WorldMembership` / life≤0 早退）。

### 6.3 警戒索敌（U2）

`UnitAI._process`（可 5–10Hz 节流，避免全图每帧扫）：

```text
if state != IDLE: 维护 ENGAGED 见下；return
if 玩家订单占用: return
if not has_weapon: return
target = CombatQuery.find_acquire_target(body, unit_host, effective_acquire_range_wc3())
if target == null: return
start_attack(target)
state = ENGAGED
source = UNIT_AI
```

> 索敌半径必须走 `effective_acquire_range_wc3()`（含昼夜倍率钩子），禁止裸用 `acquire_range_wc3`。
`ENGAGED` 维护：

```text
if AttackController 已 IDLE 且 mode NONE:
  # 目标死光或被 cancel
  state = IDLE
  # 若超 leash → RETURNING
```

### 6.4 与 Hold / Attack-Move 的边界

| 机制 | 谁用 | 区别 |
|------|------|------|
| `AttackController.HOLD` | 玩家 H | 只打**出手射程**，不追 |
| `UnitAI` 警戒 | 野怪 / 日后闲置兵 | `acquire` 拉人后走完整 `ATTACK`（可追） |
| `ATTACK_MOVE` | 玩家 A 地面 | 有终点；清场后续走 |

**不要**让野怪 `start_hold()` 冒充警戒——半径与追击语义都不对。

### 6.5 Leash（U4）

```text
leash_wc3 = UnitAI.leash_wc3（默认 1000）
if ENGAGED and distance(home, self) > leash:
  AttackController.cancel()
  Navigator.go_to_wc3(home)
  state = RETURNING
# 回到 home 附近 → IDLE；RETURNING 期间忽略 idle 索敌与受击重开打
```

---

## 7. Director / Router 改动清单（最小）

| 位置 | 改动 |
|------|------|
| `GameDirector` 单位入场 | `ensure_unit_ai`；中立有武器默认 `CAMP_CREEP` |
| `GameDirector._on_damage_applied_present` | 改名或旁路：飘字 + `notify_unit_ai_damaged` |
| `CommandRouter` 各 `issue_*` | 已有 abort Attack；增加「标记玩家 source / 通知 UnitAI.yield」 |
| `UnitOrder.Source` | 增加 `UNIT_AI`（若尚无） |
| `DeathService` / 死亡 | 已有 cancel Attack；AI `queue_free` 随单位即可 |

不改：`DamagePipeline` 公式、`CombatQuery.is_hostile`（中立 vs 玩家已是敌对）。

---

## 8. 文件与单测

### 8.1 新增

```text
game/scripts/logic/ai/unit_ai.gd
game/scripts/logic/ai/unit_ai.gd.uid
tests/unit/selftest_unit_ai_retaliate.gd
tests/unit/selftest_unit_ai_acquire.gd
```

### 8.2 单测建议（无场景树也可测决策）

| 用例 | 断言 |
|------|------|
| 中立受伤 + 来源敌对 | `notify_damaged` 后 AttackController mode=ATTACK 且 target=来源 |
| 玩家 Move 占用中受伤 | **不**改写为 Attack（或仅记 pending，P0 直接忽略） |
| idle + 敌对进入 acquire | 调用索敌后 start_attack |
| 无武器单位 | 不挂 AI 或 AI 空转 |
| 两中立互伤 | `is_hostile` 为 false → 不互打 |

可用桩：`Node3D` + meta `unit_data` + 假 `AttackController` 记录 `start_attack` 调用。

---

## 9. 实现顺序（1 关注点 / 1 commit）

| # | 关注点 | 产物 | 验收 |
|---|--------|------|------|
| **U0-0** | 文档 | 本文 + `COMBAT_SYSTEM` / `README` 互链 | 人读得懂边界 |
| **U0-1** | `UnitAI` 骨架 + Profile + yield API | `unit_ai.gd` + `Source.UNIT_AI` | ✅ 组件可挂、yield/notify 空转不报错 |
| **U0-2** | 入场 ensure（地图单位 + 训练单位） | Director 接线 | ✅ 野怪/有武器单位挂 `UnitAI`+`AttackController` |
| **U1** | `damage_applied` → 反击 | Director 扇出 + `notify_damaged` | ✅ |
| **U2** | idle acquire 节流索敌 | `UnitAI._process` | ✅ |
| **U3** | Echo 剧本 + 自测 | selftest + 手测清单 | `selftest_unit_ai` 已加；Echo 手测待验 |
| **U4** | leash 归巢 | ✅ `RETURNING`；助攻仍后置 | 不挡 U3 合并 |

建议分支策略：U0–U4（含 leash）可同分支；营地助攻另切片。

---

## 10. Echo Isles 手测清单

**捷径（无需兵营）：** 选农民 → 命令卡 **战斗号召**（Amil）→ 变民兵 `hmil`（约 45s 或再点收回）→ A 键/右键打野怪，验收 UnitAI。

1. 开局到人族开始点，训 `hfoo`（或用现成兵）靠近最近野怪营 **不开火** → 进入 acquire 后野怪主动接战。  
2. 远程先手打一发 → 目标野怪反击；邻怪 P0 **可不**助攻。  
3. 互殴至一方死亡 → 死亡方不可选、胜方若无新目标回 idle（或继续打下一目标若仍在 acquire）。  
4. 战斗中对己方单位下 Move / Stop → 立即脱离 AI 进攻，服从玩家。  
5. 对野怪下 Attack → 行为与今日一致（玩家命令优先，AI 不抢）。  
6. `hrif` 远程 kite：野怪会追（ATTACK）；不要用 Hold 语义冒充。

---

## 11. 风险与门禁

| 风险 | 门禁 |
|------|------|
| AI 与玩家命令打架 | Source 优先级 §5；Router issue 必 `yield` AI |
| 全图每帧 `find_acquire_target` | AI tick 节流；或空间哈希后置 |
| Director 再膨胀 | 扇出一行 + `UnitAI` 内聚；禁止在 Director 写索敌循环 |
| 双套战斗 | AI **只**调 `AttackController.start_*` / `cancel` |
| 中立互啄 | 保持 `CombatQuery.is_hostile` 中立互不为敌 |
| 小动物被拉 | Profile：无武器或不挂 `CAMP_CREEP` |

---

## 12. 决策记录

| 日期 | 决策 |
|------|------|
| 2026-08-21 | 单独立 `UNIT_AI.md`；范围=单位微观 AI，不含 AI 玩家 |
| 2026-08-21 | 复用 `AttackController`；不新增扣血路径 |
| 2026-08-21 | P0 = 受击反击 + acquire 警戒；leash/助攻 P1 |
| 2026-08-21 | 野怪不用 Hold 冒充警戒；闲置索敌在 UnitAI |
| 2026-08-21 | 决策表 / 小 FSM，不上 BT；BT 留给未来电脑玩家 |
| 2026-08-21 | 战斗文档 §0a 记 as-built；原「野怪不反击」从战斗竖切移出，改由本文件交付 |
| 2026-08-21 | **U0-1**：`UnitAI` 子节点骨架；`UnitOrder.Source.UNIT_AI`；采集仍归 `HarvestController` |
| 2026-08-21 | **接口预留**：`camp_id` / 睡眠态 / `notify_time_of_day` / `effective_acquire_range_wc3`（实现后置） |
| 2026-08-21 | **U0-2**：`_wire_all_unit_ai` + 训练刷兵 ensure；Router 玩家令 `yield_to_player` |
| 2026-08-22 | **U4 leash**：`CAMP_CREEP` 超 `leash_wc3` 停攻回 `home_wc3`；归途不重开仇恨 |

---

## 13. 实现前检查清单

- [ ] 读过 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) §0a 与本文 §0–§6  
- [ ] 确认 Echo 野怪 `unit_data.owner` ≥ 12 且 `CombatQuery.has_weapon` 为真  
- [x] `UnitOrder.Source.UNIT_AI` 已加  
- [x] `game/scripts/logic/ai/unit_ai.gd`（U0-1）  
- [x] 入场 ensure（U0-2：地图扫描 + 训练刷兵）  
- [x] U1 受击反击 + U2 acquire 警戒  
- [x] U4 leash / 营地 home 中心点（TeamRegistry 重算）  
- [x] `TeamRegistry`：玩家 team + 中立营地聚类 + 盟友挨打广播（U0+ 增强）  
- [x] `tests/unit/selftest_team_registry.gd` PASS（聚类 / home 重算 / 玩家 team 仅 ENGAGED 才拉 / 营地全员拉）  
- [ ] Echo §10 手测验收  
