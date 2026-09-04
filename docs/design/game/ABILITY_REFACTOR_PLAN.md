# 技能系统重构计划（Ability Refactor Plan）

> **层别**：Game · data / logic / present / orchestration  
> **状态**：Phase A–E 完成（Effect 原子 + Director 技能外提）  
> **原则**：数据驱动、模块化、**组合优于继承**、Effect 可复用、Buff 独立统一体系  
> **最后更新**：2026-09-04

## 0. 为何重构

F10 大法师 + 山丘 + P0 支援单位竖切后，每增一技需改 **4+ 处**：

```text
AbilityCatalog.SUPPORTED_ORDERS
AbilityCatalog.TARGET_KIND_BY_ORDER
PointTargetAbility.match order
AbilityExecutor.match order
ability_cast_catalog.gd 硬编码路径
```

Buff 状态分散在 `UnitStatusEffects` meta、`InnerFireController`、`AvatarController`、`BrillianceAuraController`（Phase C 门面已立，Controller 迁移后置）。  
Orchestration 已抽出：`AbilityTargetingService` · `AbilityRuntimeRegistry` · `AbilityHudFeedback` · `AbilityCastContextFactory`。

**核心目标**：

| 目标 | 含义 |
|------|------|
| **数据驱动** | SLK + Func 为权威；代码只注册 behavior / fallback |
| **模块化** | Data 查表 · Logic 效果 · Present 特效 · Orchestration 输入 |
| **组合优于继承** | 技能 = `CastRules` + `Effect[]` + 可选 `BuffSpec`；不堆 `*Ability extends BaseAbility` |
| **Effect 可复用** | 治疗 / 伤害 / 附着 FX / 召唤 等为独立原子，多技能拼装 |
| **Buff 统一体系** | 独立 `BuffSystem`：施加 / 查询 / tick / 驱散 / 叠加 |

## 1. 目标架构（四层）

```text
┌─────────────────────────────────────────────────────────────┐
│  Orchestration（薄 Director + Services）                   │
│  AbilityTargetingService · AbilityRuntimeRegistry · HUD 回调  │
└───────────────────────────┬─────────────────────────────────┘
                            │ ctx + orders
┌───────────────────────────▼─────────────────────────────────┐
│  Logic                                                       │
│  AbilityCastController → AbilityExecutor → EffectRunner      │
│  BuffSystem（UnitBuffHost + BuffInstance + BuffQuery）        │
│  AuraController / ProcController（被动 tick，读 Catalog）       │
└───────────────────────────┬─────────────────────────────────┘
                            │ 读 behavior / fx / buff spec
┌───────────────────────────▼─────────────────────────────────┐
│  Data                                                        │
│  AbilityBehaviorCatalog  ← 唯一 behavior / target / passive  │
│  AbilityFxCatalog        ← Func Casterart/Targetart/…        │
│  AbilityCatalog            ← SLK 数值门面（薄）                  │
│  CommandButtonCatalog      ← order / Art / Unart               │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  Present                                                     │
│  AbilityCastPresenter · AbilityAttachFxPresenter · SpellHitFx │
└─────────────────────────────────────────────────────────────┘
```

## 2. 分阶段落地（严格顺序）

| Phase | 名称 | 产出 | 验收 |
|-------|------|------|------|
| **A** | Behavior 注册表 | `AbilityBehaviorCatalog` | ✅ 现有 selftest 全绿 |
| **B** | FX 数据化 | `AbilityFxCatalog` + `AbilityAttachFxPresenter` | ✅ fallback + 附着迁移 |
| **C** | Buff 统一体系 | `BuffHost` + `BuffCatalog` + `BuffQuery` + HUD strip | ✅ 门面 + dispel + Avatar；见 [BUFF_SYSTEM.md](BUFF_SYSTEM.md) |
| **D** | Effect 组合 | `logic/effect/*`；Heal/Clap/… 变薄 | ✅ 原子可复用；*Ability 调 Effect |
| **E** | Director 瘦身 | Targeting / Runtime / Hud / CtxFactory | ✅ Director 转发；见 §7 |

**不做（现阶段）**：引入 godot_ability_system；纯数据驱动 channel/proc 全部逻辑；动地图 Ground 主线；`effects: []` 全表驱动（仍 dedicated class + Effect）。

---

## 3. Phase A — `AbilityBehaviorCatalog`（Data）

### 3.1 职责

**唯一**注册表：`order → entry`，`abil_id → passive entry`。

```gdscript
# entry 字段（order 级）
{
  "behavior": "ally_instant_heal",   # Executor 路由键
  "target_kind": 3,                  # TARGET_ALLY
  "channel": false,
  "autocast_eligible": true,         # 可与 UnitAbilities.auto 配合
}
```

`AbilityCatalog.is_supported()` / `target_kind()` / `is_passive_ability()` **委托** Catalog，删除散落字典。

### 3.2 Behavior 键（Logic 仍保留实现类，仅收敛路由）

| behavior | 实现 | 示例 order |
|----------|------|------------|
| `summon_point` | `SummonUnitAbility` | waterelemental |
| `channel_aoe_damage` | `BlizzardAbility` | blizzard |
| `mass_teleport` | `MassTeleportAbility` | massteleport |
| `hostile_unit_spell` | `StormBoltAbility` / `SlowAbility` | thunderbolt / slow |
| `ally_instant_heal` | `HealAbility` | heal |
| `ally_buff` | `InnerFireAbility` | innerfire |
| `self_aoe` | `ThunderClapAbility` | thunderclap |
| `self_buff` | `AvatarAbility` | avatar |
| `aura_regen_mana` | `BrillianceAuraController` | （被动 AHab） |
| `proc_bash` | `BashController` | （被动 AHbh） |

### 3.3 Executor 路由

```text
AbilityExecutor.try_cast
  → target_kind 分流（point / unit hostile / unit ally / self）
  → behavior 键 → 具体 *Ability / Effect 组合（Phase C 后逐步替换 *Ability）
```

`PointTargetAbility` 仅处理 `target_kind == POINT` 的 behavior 子集。

---

## 4. Phase B — FX 数据化（Present）

### 4.1 `AbilityFxCatalog`

优先读 `CommandButtonCatalog.get_ability(abil_id)`：

| Func 字段 | 用途 |
|-----------|------|
| `casterart` | 施法者附着 |
| `targetart` | 目标命中 / 附着 |
| `effectart` / `areaeffectart` | 地面 / 区域 |
| `[BHxx].targetart` | Buff 受益单位（GeneralAuraTarget 等） |

**Fallback 小表**：AHbz→BHbd、XHbz 等非规则 id 映射；`AbilityCastCatalog` 仅保留 order→Sequence、无法推断项。

### 4.2 `AbilityAttachFxPresenter`（通用）

```gdscript
sync_caster(unit, abil_id, active, cache)
sync_buff_beneficiaries(caster, allies, buff_id, cache, state_dict)
clear_attach(state_dict)
```

删除 / 收敛：`BrillianceAuraPresenter` 硬编码；各 Controller 内重复 spawn。

---

## 5. Phase C — Buff 统一体系（Logic · 独立模块）

### 5.1 设计原则

- **Buff 是一等公民**：与「技能施法」解耦；技能只是 Buff 的一种来源（`source_abil_id` + `caster`）。
- **组合**：一个 Buff = `BuffSpec`（数据）+ 运行时 `BuffInstance`；效果由 **Modifier 列表** 组合，非继承树。

### 5.2 模块划分

```text
game/scripts/logic/buff/
  buff_spec.gd           # 静态定义：id, duration, modifiers[], dispellable, stack_rule
  buff_instance.gd       # 运行时：left, stacks, source, level
  buff_host.gd           # 挂单位 Node：apply / remove / tick / query
  buff_query.gd          # 静态查询：damage_mul, bonus_armor, is_stunned, move_mul…
  buff_catalog.gd        # abil_id / buff_id → BuffSpec（读 SLK + 小表）
  modifiers/
    mod_damage_mul.gd
    mod_armor_flat.gd
    mod_move_speed_mul.gd
    mod_attack_speed_mul.gd
    mod_stun.gd
    mod_mana_regen_aura.gd   # 光环类 tick modifier
```

### 5.3 BuffSpec 示例（数据驱动）

```gdscript
# Ainf → spec from AbilityData DataA/DataB/Dur
{
  "buff_id": "Binf",
  "modifiers": [
    { "type": "damage_mul", "data": "data_a_pct" },
    { "type": "armor_flat", "data": "data_b" },
  ],
  "duration": "duration",
  "dispellable": true,
  "present": { "attach_art": "from_func_targetart" },
}
```

### 5.4 迁移路径

| 现状 | 迁移后 |
|------|--------|
| `UnitStatusEffects` meta（stun/slow） | `BuffHost` + `mod_stun` / `mod_move_speed_mul` |
| `InnerFireController` | `BuffHost.apply(spec)`；Present 由 FxCatalog |
| `AvatarController` | 限时 self_buff spec |
| `BrillianceAuraController` | 光环不占用 BuffInstance 槽，用 `AuraModifier` tick；受益可选 BHxx attach |

**对外 API 不变期**：`UnitStatusEffects.damage_mul()` 等先 **委托** `BuffQuery`，再删旧 meta。

### 5.5 驱散（P1 Adis）接口

```gdscript
BuffHost.dispel(unit, filter: DispelFilter) -> int  # 返回移除数量
DispelFilter: magic | positive | negative
```

---

## 6. Phase D — Effect 组合 & `*Ability` 变薄

### 6.1 Effect 原子（Logic · 可复用）

```text
game/scripts/logic/effect/
  effect_context.gd      # caster, target, goal, ctx, abil_id, level
  effect_heal.gd
  effect_damage_aoe.gd
  effect_apply_buff.gd
  effect_spawn_summon.gd
  effect_teleport_area.gd
  effect_play_present.gd  # 调 Present 层，Logic 不直接 new 粒子
```

### 6.2 技能 = Effect 管道

```gdscript
# HealAbility 变薄为：
static func try_cast(...) -> Dictionary:
  var ec := EffectContext.from_cast(...)
  if not AbilityCastRules.validate_unit(ec): return ec.fail()
  EffectHeal.run(ec, "data_a")
  EffectPlayPresent.hit_target(ec)
  AbilityCastRules.commit_cost(...)
  return ec.ok({"heal_amount": ...})
```

**组合优于继承**：新技能优先在 `AbilityBehaviorCatalog` 挂 `effects: ["damage_aoe", "apply_buff"]`（远期）；P0 竖切期仍可用 dedicated class，但内部调用 Effect。

---

## 7. Phase E — `game_director.gd` 瘦身（完整设计 · 实施前必读）

> **约束**：Phase E **必须在 A–C 稳定后**实施；本文先定接口与迁移清单，避免边重构边改 Director 行为。

### 7.1 现状职责（技能相关 ~350 行）

| 区域 | 函数 | 行数级 |
|------|------|--------|
| 瞄准 | `_begin_ability_targeting`, `_set_ability_targeting` | ~50 |
| 施法入口 | `_issue_self_ability`, `_issue_ability_at_unit_screen`, `_issue_ability_at_screen` | ~130 |
| 回调 | `_on_ability_cast_resolved`, `_ability_cast_context` | ~50 |
| UI 状态 | `_ability_ui_state_for` | ~40 |
| Tick | `_tick_autocast`, `_tick_status_effects`, `_tick_ability_cooldowns_on_map` | ~40 |
| Runtime | `_ensure_caster_runtime`, `_ensure_hero_runtime`, `_ensure_bash/brilliance/avatar` | ~80 |
| 打断 | `_ability_channel_interrupt_check` | ~20 |

### 7.2 目标：Director 只做编排

```text
玩家输入 / AI 命令
  → GameDirector._route_command
  → AbilityTargetingService（瞄准态机）
  → AbilityCastController.begin_cast
  → cast_resolved → GameDirector._on_ability_cast_resolved（仅 HUD + pathing）
```

### 7.3 新服务

#### `AbilityTargetingService`（Logic 或 game/services）

```gdscript
begin_targeting(abil_id, source, hud) -> void
issue_at_screen(screen_pos) -> bool
issue_at_unit(screen_pos) -> bool
issue_self(abil_id, source) -> bool
cancel() -> void
is_targeting() -> bool
pending_abil_id() -> String
```

- 内含：`target_kind` 分流、友军/敌军校验、`AbilityCastRules` 预检。
- Director 保留：`unit_selector` / `_ground_at_screen` 通过 **注入 Callable** 传入。

#### `AbilityRuntimeRegistry`（Logic）

```gdscript
ensure_unit(unit, ctx) -> void          # Mana, AutoCast defaults
ensure_hero_passives(unit, ctx) -> void # 读 BehaviorCatalog passive → 挂 Controller
tick_all_units(host, delta, ctx) -> void # autocast + buff tick + cd tick
```

- 替代 `_ensure_caster_runtime` / `_ensure_hero_runtime` / 分散 `_ensure_*`。
- passive 挂载 **读 Catalog**，不再在 Director 写死 AHab/AHbh。

#### `AbilityCastContextFactory`（game 或 logic）

```gdscript
build(director) -> Dictionary  # 现 _ability_cast_context 字段
```

Director 仅持 factory 引用，ctx 字段变更在一处。

#### `AbilityHudFeedback`（Present 或 game/presentation）

```gdscript
on_cast_resolved(result, abil_id) -> void
on_targeting_begin(abil_id, aim_hint) -> void
build_command_card_state(primary) -> Dictionary  # 现 _ability_ui_state_for
```

### 7.4 迁移步骤（Phase E 执行时）

1. 抽出 `_ability_cast_context` → Factory；单测 mock ctx。
2. 抽出 `_ability_ui_state_for` → `AbilityHudFeedback`；CommandCard 不变。
3. 瞄准三入口 + `_begin_ability_targeting` → `AbilityTargetingService`；Director 转发。
4. `_tick_autocast` + status/cd tick → `AbilityRuntimeRegistry.tick_all_units`。
5. `_ensure_*` → Registry；删除 Director 内 hero passive 硬编码。
6. 回归：全部 ability selftest + 手动 F6 施法/自动施法/引导打断。

### 7.5 Director 技能相关目标形态（伪代码）

```gdscript
var _ability_targeting: AbilityTargetingService
var _ability_runtime: AbilityRuntimeRegistry

func _process(delta):
  _ability_runtime.tick_all_units(_unit_host(), delta, _cast_ctx_factory.build(self))

func _on_command_ability(abil_id, source):
  if AbilityCatalog.target_kind(abil_id) == TARGET_SELF:
    _ability_targeting.issue_self(abil_id, source)
  else:
    _ability_targeting.begin_targeting(abil_id, source)
```

---

## 8. 测试策略

每 Phase 合并前：

```bash
godot --headless --path . -s res://tests/unit/selftest_ability_*.gd
```

Phase C 新增：

- `selftest_buff_system.gd` — apply / tick / expire / stack / dispel
- `selftest_buff_query_compat.gd` — `UnitStatusEffects` 委托一致性

Phase E 新增：

- `selftest_ability_targeting_service.gd` — 瞄准态机无 Director

---

## 9. 与 ROADMAP 的关系

| 功能竖切 | 依赖 Phase |
|----------|------------|
| P1 Adis 驱散 | **C** 必须 |
| P1 变形 / 隐形 | A + C |
| 新英雄技能 | **A** 起每技受益 |
| 更多种族 Func | **B** FX 数据化 |

**建议节奏**：A（本次）→ 并行 B → C → P1 功能 → E Director 瘦身。

---

## 10. 相关文档

- [ABILITY_SYSTEM.md](ABILITY_SYSTEM.md) — as-built 模块图与速查表  
- [BUFF_SYSTEM.md](BUFF_SYSTEM.md) — BuffHost / HUD strip as-built  
- [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) — 伤害管线与 Buff 查询挂点  
- [HUD.md](HUD.md) — 命令卡 / autocast UI  
- [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) — F10 竖切验收
