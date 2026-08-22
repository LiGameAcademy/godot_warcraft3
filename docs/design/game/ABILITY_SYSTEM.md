# 技能系统（Ability · as-built + 重构备忘）

> **层别**：Game · data / logic / present  
> **状态**：F10 大法师四技能竖切已完成（AHwe / AHbz / AHab / AHmt）；本文记录**当前实现**与**计划中的抽象化**，供后续重构对照。  
> **最后更新**：2026-08-22

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
  ability_catalog.gd        ← SLK 门面 + SUPPORTED_ORDERS + 被动注册
  ability_cast_catalog.gd   ← 施法动画 / 地面&命中特效（部分硬编码）
  command_button_catalog.gd ← Func+Strings → HUD 槽位/图标
        │
        ├─ Logic
        │    ability_cast_rules.gd      冷却/蓝/距离校验 + commit_cost
        │    ability_cast_controller.gd 即时 Cast / 引导 Channel
        │    point_target_ability.gd    按 order 分发
        │    summon_unit_ability.gd       AHwe
        │    blizzard_ability.gd          AHbz（+ blizzard_zone.gd）
        │    mass_teleport_ability.gd     AHmt
        │    brilliance_aura_controller.gd  AHab（被动光环 tick）
        │    unit_mana.gd / ability_cooldowns.gd
        │
        └─ Present
             ability_cast_presenter.gd   朝向 + Spell Sequence + 地面 FX
             ability_ground_fx.gd
             blizzard_area_decal.gd / spell_hit_fx.gd
             brilliance_aura_presenter.gd  ← 待收敛（见 §4）
        │
game/scripts/game_director.gd
  瞄准 → AbilityCastController.begin_cast → cast_resolved
  _ability_cast_context() 注入 map_root / unit_host / pipeline…
```

## 3. 三类技能在代码里的分界（勿混用）

| 概念 | 判定来源 | UI（命令卡） | Logic |
|------|----------|--------------|-------|
| **主动点目标** | Func 有 `Order` | `ability:AHxx`，可点击瞄准 | `PointTargetAbility` → 具体 `*Ability` |
| **引导型** | order ∈ `_CHANNEL_ORDERS` | 同上 | `AbilityCastController` CHANNEL + zone |
| **被动技能** | Func **无** Order | 当前 `passive:AHxx`（不可点） | 学会即挂 Controller（如光环） |

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
| AHbz | Catalog 硬编码 ground/hit + `BlizzardAreaDecal` / `SpellHitFx` |
| AHmt | Catalog 硬编码 `MassTeleportTo` 落点 |
| AHab | **`BrillianceAuraPresenter` 硬编码路径**（应读 Func） |

### 4.3 重构目标（未做）

1. **`AbilityFxCatalog`（data）**  
   - 优先 `CommandButtonCatalog.get_ability(abil_id)` 读 `casterart/targetart/effectart/areaeffectart`  
   - Buff 受益：`get_ability("B" + suffix)` 或 AbilityData 里的 buff 链接（AHbz→BHbd 等非规则 id 需小表 fallback）

2. **`AbilityAttachFxPresenter`（present，通用）**  
   - `sync_caster(abil_id)` / `sync_beneficiaries(buff_row)`  
   - 删除 per-skill Presenter（`BrillianceAuraPresenter` 等）

3. **`AbilityCastCatalog` 收敛**  
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
| AHab | （无） | — | 被动 Area 回蓝 | `BrillianceAuraController` |
| AHmt | massteleport | 0 | 自身 Area 友军→点地 | `MassTeleportAbility` |

### AHmt 数值（AbilityData）

| 字段 | Lv1 |
|------|-----|
| reqLevel | 6 |
| Cost / Cool | 100 / 15s |
| Area | 700（**以施法者**为圆心选人） |
| Rng | 99999（落点全图） |
| DataA | 24（最多单位） |
| Cast1 | 0（即时） |

P0 简化：不传送建筑；传送前 `halt` 移动/采集/攻击；落点用 `TrainSpawn.resolve_with_displace` 挤位。

## 7. 测试

```bash
godot --headless --path . -s res://tests/unit/selftest_ability_water_elemental.gd
godot --headless --path . -s res://tests/unit/selftest_ability_blizzard.gd
godot --headless --path . -s res://tests/unit/selftest_ability_brilliance.gd
godot --headless --path . -s res://tests/unit/selftest_ability_mass_teleport.gd
godot --headless --path . -s res://tests/unit/selftest_summon_lifetime.gd
godot --headless --path . -s res://tests/unit/selftest_militia.gd
```

### 时限行为

| 对象 | 时长来源 | 到期行为 |
|------|----------|----------|
| 水元素 hwat | AHwe `Dur1`（60s） | `SummonLifetime` → `DeathService.kill`（Death 动画 + 尸体 linger） |
| 民兵 hmil | Amil `Dur1`（~45s） | `MilitiaController._process` → `_revert_now()` 变回 hpea |

## 8. 重构检查清单（将来 PR 用）

- [ ] `is_passive_ability()` + 重命名 `passive:` 注释
- [ ] `AbilityFxCatalog` 读 Func；删除 Presenter 硬编码
- [ ] `AbilityBehaviorCatalog` 统一 order/behavior 注册
- [ ] `AuraController(abil_id)` 泛化 AHab/AHad…
- [ ] `AbilityCastController` 与 channel 行为解耦（非仅 Blizzard）
- [ ] 文档同步 GAMEPLAY_VERTICAL §F10 决策记录

## 9. 相关文档

- [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) §F10 — 竖切范围与验收  
- [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) — 伤害管线（暴风雪）  
- [HUD.md](HUD.md) — 命令卡组装  
- [docs/data/WC3_ASSET_PATHS.md](../../data/WC3_ASSET_PATHS.md) — SLK 路径
