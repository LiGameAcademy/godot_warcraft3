# 暴风雪（AHbz · Blizzard）

> **层别**：Game · Data / Logic / Present  
> **目标**：把大法师「暴风雪」从 SLK 数值 → 引导施法 → 多波伤害 → 落冰/命中特效整条链路写清，便于对照原作与继续抛光。  
> **代码锚点**：`blizzard_ability.gd` · `blizzard_zone.gd` · `blizzard_area_decal.gd` · `ability_ground_fx.gd` · `AbilityCastController`  
> **相关**：[ABILITY_SYSTEM.md](ABILITY_SYSTEM.md) · [ABILITY_REFACTOR_PLAN.md](ABILITY_REFACTOR_PLAN.md) · [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) · [PE2_GODOT.md](../asset-convert/PE2_GODOT.md)  
> 最后更新：2026-09-05

---

## 0. 一句话

暴风雪是**点地引导技能**：大法师原地吟唱（`Spell Channel`），在目标点半径 `Area` 内按 `DataA` 波次、每 `DataD` 秒造成 `DataB` 魔法伤害；表现上每波刷一次落冰模型（`BlizzardTarget`），命中单位刷霜冻附着（`FrostDamage`）。

---

## 1. 原作语义（对照）

| 项 | 原作 WC3 | 本仓库 as-built |
|----|----------|-----------------|
| 目标 | 点地（地面） | `TARGET_POINT` · order `blizzard` |
| 施法 | **引导**（移动/停止打断） | `AbilityBehaviorCatalog.channel=true` + `AbilityCastController.CHANNEL` |
| 波数 | AbilityData `DataA`（1/2/3 级：6/8/10） | `ab.data_a_at(lv)` |
| 每波伤害 | `DataB`（30/40/50） | `DamagePipeline` · `atk_type=spells` · `dmgplus=DataB` |
| 间隔 | `DataD`（0.5s） | `_interval` |
| 建筑系数 | `DataC`（常为 6 → 对建筑衰减） | 常量 `BUILDING_DAMAGE_FACTOR=0.5`（DataC 改作落冰柱数） |
| 半径 | `Area`（200） | `ab.area_at(lv)`；受害判定扣 `UnitBalance.collision` |
| 施法距离 | `Rng`（800） | 超距先 `APPROACH` 再引导（`AbilityCastController`） |
| 蓝耗 / CD | Cost 75 · Cool 6 | `AbilityCastRules.commit_cost`（**引导成功结束后**才扣） |
| 友伤 | 半径内**所有可受伤单位**（含友军、建筑） | `CombatQuery.units_blizzard_victims_in_radius` |
| 打断 | 移动、攻击、其它命令 | `_ability_channel_interrupt_check` + 清队列开场 |

`Cast1=1` 在 SLK 里**不是**「读条 1 秒再放」，而是与波次节奏并存的字段；引导总时长以 **`DataA × DataD`** 为准（1 级 ≈ 3.0s）。

---

## 2. 数据层（Data）

### 2.1 AbilityData（数值权威）

来源：`assets/slk-exported/Units/AbilityData.json` → `AbilityDataDef`（`alias=AHbz`）

| 字段 | Lv1 | Lv2 | Lv3 | 含义 |
|------|-----|-----|-----|------|
| `CostN` | 75 | 75 | 75 | 魔法 |
| `CoolN` | 6 | 6 | 6 | 冷却（秒） |
| `RngN` | 800 | 800 | 800 | 施法距离（WC3 坐标） |
| `AreaN` | 200 | 200 | 200 | 伤害/预览半径 |
| `DataAN` | 6 | 8 | 10 | **波数** |
| `DataBN` | 30 | 40 | 50 | **每波伤害** |
| `DataCN` | 6 | 7 | 10 | **每波落冰柱数**（本仓库约定；建筑半伤用 50% 常量） |
| `DataDN` | 0.5 | 0.5 | 0.5 | **波间隔（秒）** |
| `CastN` | 1 | 1 | 1 | 不单独驱动引导时长 |
| `reqLevel` | 1 | — | — | 英雄可学起始等级 |
| `levels` | 3 | — | — | 最大技能等级 |

门面：`AbilityCatalog.data("AHbz")` · `level_for(caster, "AHbz")`。

引导时长计算（与 selftest 一致）：

```text
channel_sec ≈ DataA × DataD          # Lv1: 6×0.5 = 3.0
controller 保险余量 +0.75s
```

实现：`AbilityCastCatalog.channel_duration_sec` · `AbilityCastController._begin_channel`。

### 2.2 HumanAbilityFunc / Strings（图标 · order · 特效路径）

文件：`assets/slk-exported/Units/HumanAbilityFunc.txt`（Strings 同目录 `HumanAbilityStrings.txt`）

```ini
[AHbz]
Art=ReplaceableTextures\CommandButtons\BTNBlizzard.blp
Researchart=ReplaceableTextures\CommandButtons\BTNBlizzard.blp
Buttonpos=0,2
Researchbuttonpos=0,0
Casterart=                    ; 施法者无额外附着
Order=blizzard

[BHbd]                        ; Buff / 命中行（非 AHbz 本体）
Buffart=ReplaceableTextures\CommandButtons\BTNBlizzard.blp
Targetart=Abilities\Spells\Other\FrostDamage\FrostDamage.mdl

[XHbz]                        ; 扩展行：区域落冰 + 音效键
Effectart=Abilities\Spells\Human\Blizzard\BlizzardTarget.mdl
Effectsoundlooped=BlizzardLoop
Effectsound=BlizzardWave
```

Catalog 解析：

| 用途 | 读法 | 代码 |
|------|------|------|
| 命令卡图标 | `AHbz.Art` | `CommandButtonCatalog` |
| 落冰模型 | `XHbz.Effectart`（fallback 写死同路径） | `AbilityFxCatalog.ground_effect_art("AHbz")` |
| 命中附着 | fallback → `FrostDamage.mdl` | `AbilityFxCatalog.hit_effect_art("AHbz")` |
| 施法动作 | order→`Spell Channel` | `AbilityCastCatalog.spell_sequence_for` |

### 2.3 Behavior 注册

`AbilityBehaviorCatalog`：

```text
order "blizzard" →
  behavior: channel_aoe_damage
  target: POINT
  channel: true
  abil: AHbz
```

---

## 3. 逻辑层（Logic）管线

```text
HUD / 热键
  → GameDirector / AbilityTargetingService.begin_targeting("AHbz")
  → 左键地面 → issue_at_screen
       │
       ▼
AbilityCastController.begin_cast
  · can_cast_point（蓝/CD/距离/等级）
  · clear_caster_orders + 停步          ← 防残留 MOVE 首帧打断
  · CHANNEL：播放 Spell Channel
  · BlizzardAbility.begin_channel
       │
       ▼
BlizzardZone（挂在 map_root）
  · 每 DataD：_apply_wave
      - 随机点 spawn BlizzardTarget（Present）
      - 半径内 victims → DamagePipeline（magic）
      - 命中 → SpellHitFx(FrostDamage)
  · 波次用尽 → finished(true)
       │
       ▼
AbilityCastController._on_zone_finished
  · commit_cost（成功才扣蓝/CD）
  · AbilityCastPresenter.end
  · cast_resolved → HUD
```

### 3.1 关键脚本

| 脚本 | 职责 |
|------|------|
| `blizzard_ability.gd` | `begin_channel`：校验 + new Zone + configure |
| `blizzard_zone.gd` | 波次时钟、伤害、每波落冰、区域贴花生命周期 |
| `ability_cast_controller.gd` | CHANNEL 态机、打断、成功扣费 |
| `ability_cast_rules.gd` | 蓝/CD/距离 |
| `combat_query.gd` | `units_blizzard_victims_in_radius` |
| `damage_pipeline` | 魔法伤害结算 |

### 3.2 打断规则

开场：`clear_caster_orders` 清空队列，避免旧 MOVE 被当成打断。

引导中：玩家新下达 MOVE / STOP / HOLD / ATTACK / ATTACK_MOVE / PATROL / 采集 / BUILD / **其它** ABILITY → 打断。  
同源技能残留单不打断。AI 来源命令不打断。

### 3.3 友伤与过滤

`units_blizzard_victims_in_radius`：**不分敌我**，凡 `_attack_target_basics` 通过的单位（含建筑）都吃伤害。与原作一致，可误伤农民/友军英雄。

---

## 4. 表现层（Present）

### 4.1 时间轴（期望）

```text
t=0     瞄准预览圈跟随鼠标（Area 半径）
t=0     确认：大法师 Spell Channel；区域贴花落下
t≈0.35  第 1 波：随机点 BlizzardTarget Birth + PE2；命中 FrostDamage
t≈0.85  第 2 波 …
…       共 DataA 波
结束    停 Channel；贴花淡出；扣蓝进入 CD
打断    Zone.cancel；拆贴花；不扣蓝（或按规则回滚——当前成功才 commit）
```

### 4.2 组件对照

| 表现 | 原作资产 | Godot 实现 | 状态 |
|------|----------|------------|------|
| 瞄准范围预览 | UI 选区 / 技能指示器 | `SpellAreaOfEffect` → **Godot Decal** 投地形 + 范围内 `UnitSpellTint` | ✅ |
| 施法中区域指示 | 同上或持续圈 | `BlizzardAreaDecal.spawn` | ✅ |
| 每波落冰 | `BlizzardTarget.mdx` | 每波 `DataC` 次 `AbilityGroundFx` 随机点 | ✅ |
| 命中霜冻 | `FrostDamage.mdx` | `SpellHitFx` + `UnitHitFlash`（经 Effect） | ✅ |
| 施法者特效 | （Func `Casterart` 空） | 无 | ✅ 对齐 |
| 音效 | `BlizzardLoop` / `BlizzardWave` | 代码已接线；**音频管线后置** | ⏸ 延期 |
| 大法师动作 | Spell Channel | `Unit.play_spell_cast` | ✅ |

### 4.3 瞄准预览

代码：`GameDirector._update_ability_preview` → `BlizzardAreaDecal`（**Decal** 投影到 `RENDER_LAYER_TERRAIN`，避免 PlaneMesh 穿坡）+ 圈内单位/建筑染色；**禁止**预览期刷落冰。

曾用水平 `PlaneMesh` 单点采样高度，坡地/悬崖会穿帮；现与建筑 `Wc3UberSplat` 同套路：`cull_mask=TERRAIN`、投影深度约 4 Godot 单位。

---

## 5. 资产路径详表

> 运行时只读 `assets/asset-converted/`（视觉车道）。MPQ 逻辑路径与下表「WC3 路径」一致。

### 5.1 模型 / 场景

| 角色 | WC3 路径（.mdl） | 转换产物（相对 `asset-converted/`） |
|------|-----------------|-------------------------------------|
| 落冰主模型 | `Abilities/Spells/Human/Blizzard/BlizzardTarget.mdl` | `Abilities/Spells/Human/Blizzard/BlizzardTarget.{gltf,bin,scn,pe2.json,geosetvis.json}` |
| 命中附着 | `Abilities/Spells/Other/FrostDamage/FrostDamage.mdl` | `Abilities/Spells/Other/FrostDamage/FrostDamage.{gltf,scn,pe2.json,geosetvis.json}` |

Bake：`BlizzardTarget.scn` / `FrostDamage.scn`（优先实例化 `.scn`，缺则 GLTF）。

### 5.2 PE2 粒子（BlizzardTarget）

源：`BlizzardTarget.pe2.json` · `source: .../BlizzardTarget.mdx`  
唯一 Sequence：**Birth**（frame 约 33→3333，≈ 3.3s 轨；**每波实例只播短生命周期**，由 `AbilityGroundFx` 的 lifetime≈1.15s 回收）。

| Emitter | 纹理（PE2 `texture`） | 转换后常见落点 | 说明 |
|---------|----------------------|----------------|------|
| BlizParticle02 | `Textures/Frost3.png` | `Textures/Frost3.png` | 霜柱/主粒子 |
| BlizParticle03 | `Textures/Frost3.png` | 同上 | |
| BlizParticle01 | `Textures/snowflake2.png` | `Textures/snowflake2.png` | 雪花 |
| BlizParticle01x | `Textures/Dust5A.png` | `Textures/Dust5A.png` | 尘/雾 |
| BlizParticle01x01 | `abilities/Spells/Human/Blizzard/Frost3test.png` | **常缺** | 旁路纹理，缺则该 emitter 弱/白 |

`filter_mode=1` → 转换/运行时需按双面/加色规则处理（参见牧师 `_fm1`、水元素软混合经验）。

### 5.3 PE2 粒子（FrostDamage）

Sequences：`Birth` / `Stand` / `Death`  

| Emitter | 纹理 |
|---------|------|
| BlizParticle03 | `Textures/snowflake.png` |
| BlizParticle04 | `Textures/star2_32.png` |

命中 FX 由 `SpellHitFx` 挂到单位；应优先 Birth，避免误切 Stand 熄粒子（与地面 FX 相同纪律）。

### 5.4 UI 图标

| 用途 | 路径 |
|------|------|
| 命令按钮 | `ReplaceableTextures/CommandButtons/BTNBlizzard.blp` → `.png` |
| 禁用 | `ReplaceableTextures/CommandButtonsDisabled/DISBTNBlizzard.png` |
| 学习菜单 | `Researchart` 同 BTNBlizzard |
| Buff 图标 | `BHbd.Buffart` 同 BTNBlizzard |

### 5.5 区域贴花 + 瞄准提示

| 项 | 路径 / 脚本 |
|----|-------------|
| AOE 圈贴图 | `ReplaceableTextures/Selection/SpellAreaOfEffect.png` |
| 投影方式 | Godot `Decal` · `cull_mask=Wc3Coords.RENDER_LAYER_TERRAIN` · `size.y≈4` |
| 脚本 | `game/scripts/presentation/blizzard_area_decal.gd` |
| 范围内染色 | `UnitSpellTint`（`material_overlay` 霜蓝）；瞄准期由 Director 刷新，受击闪 `UnitHitFlash` |
| 瞄准期禁令 | **不得**刷 `BlizzardTarget`（落冰仅引导波次） |

### 5.6 音效（⏸ 延期 · 无音频管线）

| 键 | 用途 | 状态 |
|----|------|------|
| `BlizzardWave` | 每波触发 | `AbilitySfx` 已调；**wav / 管线后置** → [TODO.md](../../roadmap/TODO.md) |
| `BlizzardLoop` | 引导循环 | 同上 |

---

## 6. 坐标与尺寸

| 量 | WC3 | Godot |
|----|-----|-------|
| 半径 Area | 200 | 平面直径 `400 × WORLD_SCALE`；受害距离扣 collision |
| 施法距离 | 800 | 超距 → APPROACH 走近再引导 |
| 落冰随机 | 半径内均匀盘 | `r = Area × 0.72 × sqrt(rand)`，角 `rand*TAU` |
| 贴地高度 | — | `heightfield.interpolated_height` + 小偏移（GroundFx / Decal） |

常量：`Wc3Coords.WORLD_SCALE` · `TILE_SIZE`。

---

## 7. 代码索引（改哪里）

```text
Data
  scripts/definitions/units/ability_data_def.gd
  game/scripts/data/ability_catalog.gd
  game/scripts/data/ability_behavior_catalog.gd   # blizzard channel
  game/scripts/data/ability_fx_catalog.gd         # ground/hit art
  game/scripts/data/ability_cast_catalog.gd       # Spell Channel / duration

Logic
  game/scripts/logic/ability/blizzard_ability.gd
  game/scripts/logic/ability/blizzard_zone.gd     # 波次编排；伤害委托 Effect
  game/scripts/logic/effect/effect_damage_aoe.gd # run_all_victims（友伤 AOE）
  game/scripts/logic/ability/ability_cast_controller.gd  # APPROACH / CHANNEL
  game/scripts/logic/ability/ability_targeting_service.gd
  game/scripts/logic/combat/combat_query.gd       # victims + collision
  game/scripts/logic/combat/damage_pipeline.gd    # spell AOE 友伤

Present
  game/scripts/presentation/blizzard_area_decal.gd
  game/scripts/presentation/ability_ground_fx.gd
  game/scripts/presentation/spell_hit_fx.gd
  game/scripts/presentation/unit_spell_tint.gd
  game/scripts/presentation/unit_hit_flash.gd
  game/scripts/presentation/ability_cast_presenter.gd

Orchestration
  game/scripts/game_director.gd                   # preview 圈/染色 / clear_orders / interrupt
```

自测：

```bash
godot --headless --path . -s res://tests/unit/selftest_ability_blizzard.gd
```

---

## 8. 已知缺口 / 抛光清单

| 优先级 | 项 | 状态 | 说明 |
|--------|-----|------|------|
| P0 | **瞄准预览观感** | ✅ | `SpellAreaOfEffect.png`；无预览落冰 |
| P0 | **范围内染色** | ✅ | `UnitSpellTint` |
| P0 | **每波落冰可见** | ✅ | 每波 `DataC` 柱（2–6） |
| P0 | **FrostDamage + 闪色** | ✅ | 经 `EffectDamageAoe.run_all_victims` |
| P0 | **超距先移动** | ✅ | `AbilityCastController.APPROACH` |
| P0 | **建筑伤害** | ✅ | collision + `spells` + 半伤常量 |
| P1 | Effect 抽波次伤害 | ✅ | Zone 编排；伤害原子复用 |
| P1 | `DataC` 用法 | ✅ | 落冰柱数；建筑半伤常量 `0.5` |
| P1 | 音效 Wave/Loop | ⏸ | **音频管线后置**；代码占位保留 |
| P1 | 飘字 | ✅ | 魔法青飘字 |
| P2 | `Frost3test.png` 缺文件 | 仍缺 | 重转旁路或忽略该 emitter |
| P2 | 性能 | 可跟 | 同屏多场时再池化 |

> **玩法结论（2026-09-05）**：AHbz 竖切可玩验收通过；音效不挡下一技能。

---

## 9. 验收剧本（人工）

1. 大法师学满暴风雪（或 GM 全技能）  
2. 点技能 → **SpellAreaOfEffect 贴图圈**；圈内单位/建筑霜蓝染色；**无**落冰模型  
3. 超距点地 → 大法师先跑近再引导  
4. 点敌群/建筑：多波落冰；建筑掉血 + 青飘字；单位霜冻 + 闪色  
5. 引导中右键移动 → 立即停、不扣蓝（未完成则不 commit）  
6. 完整放完 → 扣 75 蓝、进 6s CD  
7. 音效可静默（管线后置）  

---

## 10. 与技能系统总文档的关系

- 总览与分层：[ABILITY_SYSTEM.md](ABILITY_SYSTEM.md)  
- Effect / Director 瘦身：[ABILITY_REFACTOR_PLAN.md](ABILITY_REFACTOR_PLAN.md)  
- 本文只深挖 **AHbz**；其它引导技可复用 `CHANNEL` + Zone + `EffectDamageAoe.run_all_victims`。

### 建议下一技能（竖切已接线之外的抛光 / 扩展）

| 候选 | 理由 |
|------|------|
| **AHmt 群体传送** | ✅ 读条 DataB≈3s + `MassTeleportPresenter` + 落点 Decal；见 [ABILITY_SYSTEM.md](ABILITY_SYSTEM.md) §AHmt |
| 光环 / Buff 再抽 | Brilliance / InnerFire 迁满 BuffHost（非新技能） |
| N1 闭环项 | 祭坛复活 / Keep / 铁匠（非技能，见 [NEXT.md](../../roadmap/NEXT.md)） |
