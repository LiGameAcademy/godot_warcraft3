# 技能系统（Ability · as-built + 重构备忘）

> **层别**：Game · data / logic / present  
> **状态**：F10 大法师 + 山丘 + P0 支援单位（Ahea/Ainf/Aslo + autocast）已完成；**重构计划**见 [ABILITY_REFACTOR_PLAN.md](ABILITY_REFACTOR_PLAN.md)。  
> **最后更新**：2026-09-05（单位自然回血/回蓝 `UnitRegen`；AHbz 玩法收口）

## 1. 设计原则（已定）

| 原则 | 说明 |
|------|------|
| 不引入 godot_ability_system（现阶段） | 原生 thin 层：`Order + Cooldown + Mana + 具体 Behavior` |
| 权威数据来自 WC3 Def | `AbilityDataDef`（数值）、`UnitAbilitiesDef`（列表）、`HumanAbilityFunc.txt`（order/图标/特效路径） |
| 分层 | **Data** 查表 → **Logic** 效果 → **Present** 模型/粒子/贴地 |
| 插件决策门 | 见 [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) §F10；P0 四技跑通后再评估是否迁插件 |

## 2. 当前模块地图

```text
assets/slk-exported/Units/
  AbilityData.json          ← 数值（Cost/Cool/Area/Rng/DataA…）
  HumanAbilityFunc.txt      ← order、Art、Casterart/Targetart/Effectart…
        │
        ▼
game/scripts/data/
  ability_catalog.gd        ← SLK 数值门面（target/supported 委托 BehaviorCatalog）
  ability_behavior_catalog.gd ← order/behavior/target/passive 唯一注册表（Phase A）
  ability_fx_catalog.gd        ← Func 特效路径 + fallback（Phase B）
  ability_cast_catalog.gd      ← order→Sequence、channel 时长
  command_button_catalog.gd ← Func+Strings → HUD 槽位/图标
        │
        ├─ Logic
        │    ability_cast_rules.gd      冷却/蓝/距离校验 + commit_cost
        │    ability_cast_controller.gd 即时 Cast / 引导 Channel
        │    point_target_ability.gd    点地 order 分发
        │    ability_autocast.gd / ability_autocast_runner.gd
        │    heal_ability.gd / inner_fire_*.gd / slow_ability.gd
        │    ability_executor.gd        按 target_kind + behavior 路由
        │    summon_unit_ability.gd       AHwe
        │    blizzard_ability.gd          AHbz（+ blizzard_zone.gd）
        │    mass_teleport_ability.gd     AHmt
        │    storm_bolt_ability.gd        AHtb
        │    thunder_clap_ability.gd      AHtc
        │    avatar_ability.gd            AHav（+ avatar_controller.gd）
        │    bash_controller.gd           AHbh（被动 proc）
        │    unit_status_effects.gd       门面 → BuffHost
        │    logic/buff/                  BuffHost · BuffCatalog · BuffQuery
        │    brilliance_aura_controller.gd  AHab（被动光环 → BuffHost brilliance）
        │    unit_mana.gd / unit_life.gd / unit_regen.gd  蓝/血权威 + 自然回复（含光环 bonus）
        │    ability_cooldowns.gd
        │
        └─ Present
             ability_cast_presenter.gd   朝向 + Spell Sequence + 地面 FX
             ability_ground_fx.gd
             blizzard_area_decal.gd / spell_hit_fx.gd
             ability_attach_fx_presenter.gd  通用单位附着 FX
             brilliance_aura_presenter.gd    薄封装 → AttachFxPresenter
        │
game/scripts/game_director.gd
  瞄准 → AbilityCastController.begin_cast → cast_resolved
  _ability_cast_context() 注入 map_root / unit_host / pipeline…
```

## 3. 三类技能在代码里的分界（勿混用）

| 概念 | 判定来源 | UI（命令卡） | Logic |
|------|----------|--------------|-------|
| **主动点目标** | Func 有 `Order`，`target_kind=POINT` | `ability:AHxx`，点地瞄准 | `AbilityExecutor` → `PointTargetAbility` / 具体 `*Ability` |
| **主动点单位（敌）** | order 如 `thunderbolt` / `slow` | 点敌军瞄准 | `StormBoltAbility` / `SlowAbility` |
| **主动点单位（友）** | order 如 `heal` / `innerfire` | 点友军瞄准 | `HealAbility` / `InnerFireAbility` |
| **主动自身** | order 如 `thunderclap` / `avatar` | 点按钮即施 | `ThunderClapAbility` / `AvatarAbility` |
| **引导型** | order ∈ `_CHANNEL_ORDERS` | 同上 | `AbilityCastController` CHANNEL + zone |
| **被动技能** | Func **无** Order | 当前 `passive:AHxx`（不可点） | 学会即挂 Controller（光环 / proc） |

> **Tech debt**：`passive:` 表示「被动技能」，不是「光环」。`PASSIVE_AURAS` / `is_passive_aura()` 命名过窄——暴击、闪避等 passive 将来也会走 `passive:` 前缀，但 Logic 不是 aura。

## 4. 表现层：现状 vs 应然

### 4.1 WC3 已提供的特效字段（`HumanAbilityFunc.txt`）

| 段 | 典型字段 | 用途 |
|----|----------|------|
| `[AHxx]` | `Casterart` / `Targetart` / `Areaeffectart` / `Specialart` | 施法者 / 附着 / 地面 / 单位闪现 |
| `[BHxx]` | `Targetart` | buff 受益单位附着（如 GeneralAuraTarget） |
| `[XHxx]` | `Effectart` | 扩展地面特效（暴风雪落点） |

示例（大法师）：

```text
[AHmt]  Areaeffectart=…MassTeleportTo.mdl  Casterart=…MassTeleportCaster.mdl
[AHab]  Targetart=…Brilliance.mdl
[BHab]  Targetart=…GeneralAuraTarget.mdl
[XHbz]  Effectart=…BlizzardTarget.mdl
```

### 4.2 当前实现

| 技能 | Present 来源 |
|------|----------------|
| AHwe | `AbilityCastPresenter` + order→Sequence |
| AHbz | Catalog 硬编码 ground/hit + `BlizzardAreaDecal` / `SpellHitFx`；波次伤害 → `EffectDamageAoe.run_all_victims` |
| AHmt | `MassTeleportPresenter`：Caster / Target 脚印 / To 落点 + Decal 落点圈 |
| AHab | `BrillianceAuraPresenter` ← `AbilityFxCatalog`（AHab Targetart=Brilliance / BHab=GeneralAuraTarget）；`on_entity_root` 防 MODEL_SCALE 缩没 |

### 4.3 重构目标（部分完成）

1. **`AbilityFxCatalog`（data）** — ✅ 已有  
   - 优先 `CommandButtonCatalog.get_ability(abil_id)` 读 `casterart/targetart/effectart/areaeffectart`  
   - Buff 受益：`buff_row_id` + `buff_beneficiary_art`（AHab→BHab；例外表 + fallback）

2. **`AbilityAttachFxPresenter`（present，通用）** — ✅ 通用挂点已有；per-skill Presenter 仍保留薄封装  
   - `sync_attach` / `sync_buff_beneficiaries_for_abil` / `on_entity_root`  
   - `BrillianceAuraPresenter` 等仅做 Catalog→Presenter 接线（可再删薄壳）

3. **`AbilityCastCatalog` 收敛** — 未做  
   - 仅保留 order→Sequence、channel 标记、无法从 Func 推断的 fallback

**Logic 仍按行为类型分**（无法纯数据驱动）：

| Behavior | 参数 | 实现 |
|----------|------|------|
| `summon_point` | abil_id | `SummonUnitAbility` |
| `channel_aoe_damage` | abil_id | `BlizzardAbility` + zone |
| `mass_teleport` | abil_id | `MassTeleportAbility` |
| `aura_regen_mana` | abil_id | 泛化 `AuraController`（今 `BrillianceAuraController`） |

注册表建议：`AbilityBehaviorCatalog` 替代散落的 `SUPPORTED_ORDERS` + `PASSIVE_AURAS` + `PointTargetAbility.match`。

## 5. 施法链路（主动技）

```text
命令卡 ability:AHmt
  → Director._begin_ability_targeting
  → 点地 _issue_ability_at_screen
  → AbilityCastController.begin_cast
       Cast1>0 → CAST_DELAY → PointTargetAbility.try_cast
       channel → CHANNEL → *Ability.begin_channel
  → cast_resolved → HUD / 刷路径
```

**资源**：引导完整结束才 `commit_cost`；即时/前摇在 `try_cast` 内 commit（AHwe/AHmt）。

## 6. 大法师四技能速查

| ID | Order | Cast | 机制 | Logic 类 |
|----|-------|------|------|----------|
| AHwe | waterelemental | 0 | 点地召唤 hwat | `SummonUnitAbility` + `SummonLifetime`→`DeathService.kill` |
| AHbz | blizzard | 引导 DataA×DataD | 区域多段伤害 | `BlizzardAbility` |
| AHab | （无） | — | 被动 Area → 有蓝友军 brilliance Buff + 回蓝 | `BrillianceAuraController` → `BuffHost` / `UnitRegen` |
| AHmt | massteleport | DataB≈3s 读条（Cast=0） | 自身 Area 友军→点地 | `MassTeleportAbility` + `MassTeleportPresenter` |

## 7. 山丘之王四技能速查（Hmkg）

| ID | Order | 目标 | 机制 | Logic 类 |
|----|-------|------|------|----------|
| AHtb | thunderbolt | 单位 | 魔法弹道 + 伤害 + 眩晕 | `StormBoltAbility` + `ProjectileService.fire_spell` |
| AHtc | thunderclap | 自身 | 范围魔法伤害 + 减速 | `ThunderClapAbility` + `UnitStatusEffects` |
| AHbh | （无） | — | 攻击概率眩晕 + 额外伤害 | `BashController`（监听 `damage_applied`） |
| AHav | avatar | 自身 | 限时 +HP / +护甲 | `AvatarAbility` + `AvatarController` |

Director 按 `AbilityCatalog.target_kind()` 分流：点地 / 点敌军 / 点友军 / 点按钮即 `_issue_self_ability`。

## 7.1 支援单位技能（P0）

| ID | 单位 | Order | 目标 | 机制 |
|----|------|-------|------|------|
| Ahea | hmpr | heal | 友军 | 即时治疗 DataA（20） |
| Ainf | hmpr | innerfire | 友军 | 60s +10% 伤 / +5 甲 |
| Aslo | hsor | slow | 敌军 | 60s 移速×0.6 / 攻速×0.25 |

**自动/手动**：`UnitAbilities.auto` 为默认开启项；Func 有 `Unart` 的技能可右键切换。UI：`auto_cast` 金边 + `Art`，手动 `Unart` 关图标。

### AHmt 数值（AbilityData）

| 字段 | Lv1 |
|------|-----|
| reqLevel | 6 |
| Cost / Cool | 100 / 15s |
| Area | 700（**以施法者**为圆心选人） |
| Rng | 99999（落点全图） |
| DataA | 24（最多单位） |
| Cast1 | 0（SLK；玩法读条用 DataB） |
| DataB | 3（读条秒；`AbilityCastCatalog.cast_time_sec`） |

P0 简化：不传送建筑；传送前 `halt` 移动/采集/攻击；落点用 `TrainSpawn.resolve_with_displace` 挤位。
读条期：`MassTeleportPresenter` 挂 Caster 光环（**实体根**，避免 MODEL_SCALE 二次缩小）+ 落点 Decal；打断不扣蓝；结算时旧坐标脚印（Target）→ 瞬移 → 落点 To + 音效。

## 8. 测试

```bash
godot --headless --path . -s res://tests/unit/selftest_ability_fx_catalog.gd
godot --headless --path . -s res://tests/unit/selftest_buff_system.gd
godot --headless --path . -s res://tests/unit/selftest_ability_water_elemental.gd
godot --headless --path . -s res://tests/unit/selftest_ability_blizzard.gd
godot --headless --path . -s res://tests/unit/selftest_ability_brilliance.gd
godot --headless --path . -s res://tests/unit/selftest_ability_mass_teleport.gd
godot --headless --path . -s res://tests/unit/selftest_ability_mountain_king.gd
godot --headless --path . -s res://tests/unit/selftest_ability_support_units.gd
godot --headless --path . -s res://tests/unit/selftest_ability_autocast.gd
godot --headless --path . -s res://tests/unit/selftest_summon_lifetime.gd
godot --headless --path . -s res://tests/unit/selftest_militia.gd
```

### 时限行为

| 对象 | 时长来源 | 到期行为 |
|------|----------|----------|
| 水元素 hwat | AHwe `Dur1`（60s） | `SummonLifetime` → `DeathService.kill`（Death 动画 + 尸体 linger） |
| 民兵 hmil | Amil `Dur1`（~45s） | `MilitiaController._process` → `_revert_now()` 变回 hpea |

## 9. 重构检查清单

> 完整分阶段设计与 Director 瘦身方案：[ABILITY_REFACTOR_PLAN.md](ABILITY_REFACTOR_PLAN.md)

- [x] `AbilityBehaviorCatalog` 统一 order/behavior 注册（Phase A）
- [x] `AbilityFxCatalog` + `AbilityAttachFxPresenter`（Phase B）
- [x] `BuffHost` / `BuffCatalog` / `BuffQuery` 统一 Buff（Phase C 骨架）
- [ ] Effect 原子 + `*Ability` 变薄（Phase D）
- [ ] `AbilityTargetingService` + Director 瘦身（Phase E）
- [ ] `is_passive_aura()` 调用方改 `is_passive_ability()`（随 Phase A 清理）

## 10. 相关文档

- [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) §F10 — 竖切范围与验收  
- [BLIZZARD.md](BLIZZARD.md) — **暴风雪专项**：引导/多波/落冰资产与缺口  
- [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) — 伤害管线（暴风雪）  
- [HUD.md](HUD.md) — 命令卡组装  
- [docs/data/WC3_ASSET_PATHS.md](../../data/WC3_ASSET_PATHS.md) — SLK 路径
