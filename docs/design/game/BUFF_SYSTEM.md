# Buff 系统（as-built）

> **层别**：Game · Logic（`buff_host` / `buff_query` / `buff_catalog`）+ Present（`UnitBuffStrip`）  
> **状态**：Phase C 落地（2026-08-23）；辉煌光环 Buff 化（2026-09-05）  
> **相关**：[ABILITY_REFACTOR_PLAN.md](ABILITY_REFACTOR_PLAN.md) §5 · [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) · [HUD.md](HUD.md)

## 1. 目标

将分散在 `UnitStatusEffects` meta、`InnerFireController`、`AvatarController` 等的**可查询状态**收敛到统一 Buff 容器；战斗 / 导航 / AI 通过 `BuffQuery` 只读；详情面板底部展示当前 Buff 图标。

**Phase C 范围**（已完成）：

| 能力 | 状态 |
|------|------|
| `BuffHost` 施加 / tick / 驱散 / 查询 | ✅ |
| `BuffCatalog` 静态 id、可驱散、展示映射 | ✅ |
| `UnitStatusEffects` → `BuffQuery` 委托 | ✅ |
| Inner Fire → `BuffHost.apply(ID_INNER_FIRE)` | ✅ |
| Avatar → `BuffHost.apply(ID_AVATAR)` | ✅ |
| Brilliance → `BuffHost.apply(ID_BRILLIANCE)`（光环续期） | ✅ |
| Brilliance Present：Caster Brilliance + 受益 GeneralAuraTarget（`on_entity_root`） | ✅ |
| HUD `UnitBuffStrip` + tooltip | ✅ |
| Modifier 原子类 / 全 SLK 驱动 BuffSpec | ❌ Phase D 后 |

## 2. 模块图

```text
┌──────────────────────────────────────────────────────────────┐
│ Present                                                      │
│  UnitBuffStrip (game/hud/unit_buff_strip.tscn)                 │
│  GameHud.update_buff_strip ← SelectionInfoBuilder.buffs      │
└────────────────────────────┬─────────────────────────────────┘
                             │ hud_entries()
┌────────────────────────────▼─────────────────────────────────┐
│ Logic · BuffQuery（静态门面）                                  │
│  is_stunned / bonus_armor / move_speed_mul / hud_entries …     │
└────────────────────────────┬─────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────┐
│ Logic · BuffHost（单位子节点 BuffHost）                        │
│  apply / remove / tick / dispel_magic / list_active          │
└────────────────────────────┬─────────────────────────────────┘
                             │ 读定义
┌────────────────────────────▼─────────────────────────────────┐
│ Data · BuffCatalog                                           │
│  buff_id、DISPELLABLE、DISPLAY_ABIL、tooltip_text、icon_path   │
└──────────────────────────────────────────────────────────────┘

兼容层：UnitStatusEffects.* → BuffQuery（旧调用方暂不改）
来源层：InnerFireController / AvatarController / BrillianceAuraController 施放或光环 tick 时 apply；被驱散时 controller 同步 deactivate
```

## 3. Buff id 表（当前）

| id | 中文名 | 可驱散 | 展示图标来源 | 主要参数 |
|----|--------|--------|--------------|----------|
| `stun` | 眩晕 | 否 | AHtb | — |
| `slow` | 减速 | 是 | Aslo | `move_mul`, `attack_mul` |
| `inner_fire` | 心灵之火 | 是 | Ainf | `armor`, `dmg_mul` |
| `bonus_armor` | 护甲加成 | 否 | AHav | `amount` |
| `avatar` | 天神下凡 | 否 | AHav | `armor`, `bonus_hp` |
| `brilliance` | 辉煌光环 | 否 | AHab | `mana_regen`, `aura`, `source_id` |

光环（Brilliance）：`BrillianceAuraController` 在范围内对 **有魔法值** 的友军 `BuffHost.apply` 续期，离范围 `remove`；回蓝由 `UnitRegen` 读 `BuffQuery.mana_regen_bonus`。HUD `left=-1`（不闪烁）。脚兵等无蓝单位不挂 Buff / 受益特效。
## 4. 对外 API

### 4.1 施加与查询（Logic）

```gdscript
var bh := BuffHost.ensure_on(unit)
bh.apply(BuffCatalog.ID_SLOW, 5.0, {"move_mul": 0.5, "attack_mul": 0.25})
bh.tick(delta)
bh.dispel_magic()  # 移除可驱散 Buff

BuffQuery.is_stunned(unit)
BuffQuery.bonus_armor(unit)
BuffQuery.hud_entries(unit)  # → [{id, icon, tooltip, short, left}]
```

### 4.2 兼容门面

`UnitStatusEffects.apply_stun / apply_slow / set_inner_fire / set_bonus_armor` 等仍可用，内部委托 `BuffHost` + `BuffQuery`。

### 4.3 HUD 契约

`SelectionInfoBuilder.build()` 在 `info["buffs"]` 填入 `BuffQuery.hud_entries(primary)`。

`GameHud.set_selection_info` 刷新 strip；`GameDirector._process` 每帧 `update_buff_strip` 更新 tooltip 剩余时间（图标组成不变时只改 tooltip）。

## 5. 详情面板 · Buff 条（Present）

- **场景**：`res://game/hud/unit_buff_strip.tscn`（`UnitBuffStrip`）
- **挂载**：`game_hud.tscn` → `InfoFrame/CenterPanel` 底部（**常驻预留高度 28px**，有无 Buff 不改变面板高度）
- **布局**：`HBoxContainer`，图标 28×28，`separation = 4`
- **图标**：优先读 Buff 行 `Buffart`（如 `Binf`→`BTNInnerFire`），**不用**命令卡 `BTN*On`（带自动施法角标）
- **交互**：`Button`（flat）+ `tooltip_text`
- **即将结束**：剩余 ≤10s 时图标 alpha 闪烁（对齐原作）

## 6. InfoFrame / StatusLabel

| 控件 | 决策 |
|------|------|
| `UnitBuffStrip` | 详情正式控件；常驻高度 |
| `DebugStatusLabel` | **已移出** `CenterPanel`；挂在 HUD Root 底栏旁，仅 `show_dev_hint` 时显示开发态文案 |
| 整包拆 `InfoFrame` | 暂不；见下文 |

**结论：暂不整包拆分 `InfoFrame`；Buff 条已按子组件拆场景。**

| 因素 | 分析 |
|------|------|
| `InfoFrame` 内容 | 左肖像 + 中 `CenterPanel`（攻防芯片、建造条、训练队列、Buff 条） |
| 生命周期 | 建造 / 训练由 `GameDirector` 与 `BuildController` 分散驱动 |
| 已有模式 | `unit_combat_stat_chip` / `unit_portrait_view` / `unit_buff_strip` 已子场景化 |
| 推荐演进 | 中栏再膨胀时抽 `unit_info_panel.tscn`（肖像 + 详情 + Buff） |

## 7. 驱散与 Controller 同步

- `BuffHost.dispel_magic()` 按 `BuffCatalog.DISPELLABLE` 过滤。
- `InnerFireController` / `AvatarController` 在 `_process` 中检测 `has_buff`；若 Buff 被驱散则 `_deactivate()`。
- 心灵之火 Present：`Targetattach=overhead` → `Wc3ModelScene.overhead_anchor()` 挂 OverHead Ref（无则 AABB）；scale≈0.45
- 辉煌光环 Present：`BrillianceAuraPresenter` ← Catalog（AHab Brilliance / BHab GeneralAuraTarget），`AbilityAttachFxPresenter.on_entity_root` 挂实体根（防 MODEL_SCALE≈0.01 缩没）
- 详情攻/甲：`SelectionInfoBuilder` 读 `BuffQuery.damage_mul` / `bonus_armor`；`GameDirector` 与 Buff 条同频刷新芯片
- 血条：同走 `overhead_anchor()`（`HealthBarManager`）

## 8. 测试

```bash
godot --headless --path . -s res://tests/unit/selftest_buff_system.gd
```

覆盖：stun/slow、inner fire、dispel、`UnitStatusEffects` 门面、`BuffQuery.hud_entries`。  
辉煌光环 Buff 化：`selftest_ability_brilliance.gd`（范围内 apply / HUD / 离范围 remove / mana_regen_bonus）。

## 9. 后续（Phase D+）

- `EffectApplyBuff` 原子 + SLK `BuffSpec` 数据化
- `DispelFilter`（magic / positive / negative）供 Adis
- 更多被动 Buff 从 Controller 迁入 `BuffHost`
- 命令卡自动施法：见 [HUD.md §4.1](HUD.md)（`AutocastButtonOverlay`；远期可嵌 `UI-ModalButtonOn.scn`）
