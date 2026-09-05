# 游戏 HUD

> 场景：`game/scenes/game_hud.tscn` · 脚本：`game/scripts/presentation/game_hud.gd`  
> 选中权威：`scenes/selection/unit_selector.gd`  
> 命令卡：`game/scripts/logic/command/command_card.gd`  
> 最后更新：2026-08-22

## 1. 目标与原则

现代底栏三分栏（AOE4 向布局），**不**复刻 WC3 Console 贴图外壳；语义对齐原作：

| 区 | 职责 |
|----|------|
| **左** 小地图 | 战场概览、镜头跳转 |
| **中** 信息面板 | 当前选中单位的肖像 + 生命/魔法条 + 详情；多选时头像队列 |
| **右** 命令卡 | 移动/技能/建造子菜单等（跟 **当前选中**） |
| **顶** 资源条 | 金 / 木 / 人口 |

- Present 只展示；库存权威 `PlayerStock`；选中权威 `UnitSelector`。
- 开发期可用 Panel / Label / Button；图标走 `CommandButtonCatalog` + `RuntimeAssets`。

---

## 2. 布局

```text
GameHud (CanvasLayer)
└── Root
    ├── TopBar                 金 / 木 / 人口
    └── Bottom
        ├── Minimap            GameMinimap
        ├── Info（中栏）
        │   ├── Portrait       SubViewport 3D 头像
        │   ├── HpBar / ManaBar 肖像下方进度条（另有文字可选）
        │   ├── Detail         攻防 / 特殊属性 / 名
        │   ├── MultiStrip     多选时头像格（可点切主选）
        │   └── Status / BuildProgress
        └── Commands           4×3 命令格
```

现状代码：中栏已接肖像 / 血蓝条 / 攻防与特殊行 / 多选条；生产队列未接。小地图（`game/hud/game_minimap.tscn`）与命令卡（含建造二级菜单）已接线。
---

## 3. 中栏：三种形态

由 **选中集合 + 当前选中（primary）** 决定；生产队列等训练系统接通后再灌真数据。

### 3.1 单选详情

触发：选中恰好 1 个单位或建筑。

| 块 | 内容 |
|----|------|
| 肖像 | `*_Portrait` 模型（见 §5） |
| 肖像下 | **生命**进度条（数值叠在条上）；有魔法时再显 **魔法**条（同样叠字） |
| 标题 | 显示名（UnitStrings / Catalog） |
| 攻击 | `UnitCombatStatChip`：类型图标 + 伤害 + 类型名；可升级单位在图标右下角显示等级角标 |
| 防御 | 同上护甲；不可升级（英雄等）不显示角标框 |
| 其它 | 移速等可后置；**特殊属性**见下 |

**特殊属性（按单位类型叠加）：**

| 类型 | 展示 |
|------|------|
| 金矿 `ngol` | 剩余金币（`GoldMineRuntime.remaining_gold`） |
| **英雄**（`UnitBalance.Primary` ∈ STR/AGI/INT） | 主属性 + 力量/敏捷/智力 |
| 建造中建筑 / 施工中农民 | 建造进度（已有 `set_build_progress`） |
| 负重农民 | 可后置：负金 / 负木数量 |

> 英雄判定：数据侧已有——`UnitBalance.Primary` 英雄为 `STR`/`AGI`/`INT`，普通单位为 `_`；另有 `defType=hero`、`UnitData.nameCount` 等辅助信号。HUD 以 `Primary` 为准。

### 3.2 多选队列

触发：选中 ≥ 2。

- **仍有「当前选中」**：肖像框、详情、**右侧命令卡**一律跟 primary（与原作一致：框选牧师+步兵时，primary 是牧师则卡面与肖像都是牧师）。
- 中栏另显 **多选条**：各单位小头像/图标格；点击某格 → `UnitSelector.set_primary`。
- **Tab**（Shift+Tab 反向）→ `UnitSelector.cycle_primary`，刷新肖像 / 详情 / 命令卡。
- **不设**原作框选人数上限（常见 12）；选中集合可任意大（见 `UnitSelector._set_selection` 注释）。

### 3.3 生产队列（壳先于数据）

触发：单选可训练建筑，且将来存在训练/研究队列。

- 左：建筑肖像 + 血条（建筑通常无魔）。
- 右/下：训练队列槽（图标 + 剩余时间）；**真数据等 F3+ 训练系统**，此前可只留空态或占位 UI。
- 与「建造进度」区分：建造 = `BuildSite`；训练 = TrainQueue（未接）。

---

## 4. 当前选中（primary）与命令卡

```text
UnitSelector
  _selected[]     框选/点选集合（无人数上限）
  _primary        当前选中 ∈ _selected
        │
        ├─→ 中栏肖像 / 详情 /（多选条高亮）
        └─→ CommandCard.for_unit(primary.typeId, …)
```

| API | 用途 |
|-----|------|
| `get_primary()` / `get_selected()` | HUD / Director 读取 |
| `set_primary(node)` | 多选条点击 |
| `cycle_primary(step)` | Tab / Shift+Tab |

换选、清空选中时：关闭建造二级菜单、取消瞄准态（Director 已有同类逻辑）。

**可选 ≠ 可控**：点选敌方/中立仍可看肖像与属性；`primary.owner != local_player`（或中立）时命令卡为空，热键与右键指令不下达。框选仍仅己方（`marquee_owner`）。

命令卡补充（已落地）：

- 工人主卡：**一个**建造入口（`AHbu` → `open_build`），不摊平建筑。
- 二级：`Builds ∩ F2 allowlist` + `CmdCancelBuild`；Esc 回主卡。
- 可移动单位常规键（`CommandFunc` 槽位）：**Move / Stop / Hold / Attack / Patrol**（热键 M/S/H/A/P）。  
  - Hold：停步 + `hold_position`（日后射程内打不追）。  
  - Attack：瞄准态 — 点单位追击目标，点地面 Attack-Move（索敌扣血见 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md)）。  
  - Patrol：瞄准另一端，当前位置↔目标往返。

### 4.1 自动施法命令格（原作对齐）

原作（WC3）分层：

| 层 | 资产 / 行为 |
|----|-------------|
| 图标底图 | `Art=BTN*On` / `Unart=BTN*Off`（**角标烘焙进位图**） |
| 开自动时叠加 | `UI\Feedback\Autocast\UI-ModalButtonOn.mdx`（黄金粒子沿边游走；纹理 `Textures/HeroLevel-Particle.png`） |
| 交互 | 右键切换；开时额外播放 `Sound\Interface\AutoCastButtonClick1.wav` |

本仓库目标结构（**图标与角标分离**，避免把 On/Off 角标图当 Buff/命令底图）：

```
CommandButton (Button)
├── icon → 干净底图 BTNHeal / BTNInnerFire（strip On/Off）
└── AutocastButtonOverlay（独立 Control，非 icon 像素）
    ├── CAPABLE_OFF：四角暗色 L 形（静态）
    └── ON：四角亮金 L + 沿边游走火花（近似 ModalButtonOn）
```

实现要点：

- `CommandButtonCatalog.make_hud_entry`：`autocast_capable` 时 `AbilityFxCatalog.strip_autocast_art_suffix`
- Present：`game/hud/autocast_button_overlay.gd`；**禁止**再用金框 `StyleBox` 冒充开自动
- Buff 条继续只用 `Buffart`（`BTNInnerFire`），永不 `BTN*On`
- 远期可选：把 `UI-ModalButtonOn.scn` 投到 SubViewport 做像素级叠加；现用 2D 粒子近似即可

中栏高度：`PortraitXpRow` 与 `SpecialLines` 常驻占位；英雄属性压成一行，与普通单位详情高度一致。

---

## 5. 肖像（Portrait）

### 资产

- 路径习惯：与 `UnitUI.file` 同目录的 `*_Portrait.gltf` / `.scn`（大小写混用，解析需多候选）。
- 数量：转换车道内大量 Portrait；运行时只读 `assets/asset-converted/`（见 [ASSET_LANES.md](../../architecture/ASSET_LANES.md)）。

### 渲染

- HUD：`game/hud/unit_portrait_view.tscn`（队色 `ColorRect` + SubViewport）。
- 模型队色按 owner 重染；MDX 内嵌背景板运行时隐藏（勿用笼统 `_portrait` 匹配，会误藏全身）。
- **相机**（优先级）：
  1. bake 进 `.scn` 根上的 `Camera3D`（MDX Camera01；HUD 暂用 sidecar 回退相机）
  2. 旁路 `*.cameras.json`
  3. AABB 启发式

### 回退

无 Portrait → 试主模型特写 → 再退 `UnitFunc` Art 图标（2D）。

Catalog 侧建议：`Wc3IdCatalog.portrait_model_path(type_id)`（候选 stem + DirAccess 兜底），Present 经 `MapModelCache` 实例化。

---

## 6. API（现状 + 目标）

**已有：**

```gdscript
hud.set_resources(gold, lumber, food, food_max)
hud.bind_stock(player_stock)
hud.set_unit_info(name, hp, hp_max)
hud.set_build_progress(visible, ratio, caption)
hud.set_status(text)
hud.set_command_card(entries)           # 12 格 Dictionary
hud.configure_minimap(map_dir, hf, unit_host, cam, rig, local_player)
hud.set_portrait_texture(tex)           # 已改用 UnitPortraitView；保留空实现
```

小地图：`game/hud/game_minimap.tscn`（正方形 176；玩家点=队伍色，中立点=黑；金矿/nbmm 仍用原作图标）。

**目标扩展（实现时补齐）：**

```gdscript
hud.set_selection_info(info: Dictionary)
# info 建议键：
#   mode: "single" | "multi" | "train" | "empty"
#   primary_id / display_name
#   hp, hp_max, mana, mana_max
#   attack / armor: {
#     type, type_label, value, icon,
#     upgradeable,   # false → 不显示图标右下角等级框（英雄等）
#     upgrade_level, tooltip
#   }
#   attack_line, armor_line: 纯文本回退（兼容）
#   special_lines: PackedStringArray
#   portrait_type_id
#   multi: Array[{ node_id, type_id, icon }]
#   train_queue: Array[…]
```

攻防图标：`UI/Widgets/Console/Human/infocard-attack-*` / `infocard-armor-*`（`RuntimeAssets`）。

控件：`game/hud/unit_combat_stat_chip.tscn`（`AttackChip` / `ArmorChip`）。

数据来源：

| 字段 | 来源 |
|------|------|
| HP | `UnitLife`（自然回血见 `UnitRegen`） |
| 魔法 | `UnitMana`（上限 / 当前；自然回蓝见 `UnitRegen`；光环叠加） |
| 攻击 | `UnitWeaponsDef` × `BuffQuery.damage_mul` |
| 护甲 | `UnitBalanceDef.def` + `BuffQuery.bonus_armor` |
| 英雄属性 | `UnitBalanceDef` STR/AGI/INT / Primary |
| 金矿 | `GoldMineRuntime` |
| 显示名 / 图标 | `CommandButtonCatalog` / UnitStrings |

库存权威：`game/scripts/session/player_stock.gd`（**非** Godot `Resource`）。

---

## 7. 落地顺序

| 阶段 | 内容 | 状态 |
|------|------|------|
| A | 小地图 + 资源条 + 命令卡 | ✅ |
| B | 建造二级菜单（主卡 Build → 子卡建筑） | ✅ |
| C | `cycle_primary` / `set_primary`；无框选人数上限；Tab / 多选条 | ✅ |
| D | 中栏布局：肖像 SubViewport + 血/蓝条 + 攻防详情 | ✅ |
| D2 | 攻防独立 `UnitCombatStatChip`（图标/数值/类型；升级等级字段预留） | ✅ |
| E | 多选条 + Tab 切主选刷新卡面 | ✅ |
| F | Portrait 启发式相机 → 远期 MDX Camera | 🟡 启发式已用；MDX Camera 待回填 |
| G | 生产队列 UI 壳 + 训练真数据 | 📋 等 F3+ |

---

## 8. 相关文档

| 文档 | 关系 |
|------|------|
| [SELECTION_RINGS.md](SELECTION_RINGS.md) | 地面选中环颜色；与 primary 高亮可联动 |
| [BUILD_SYSTEM.md](BUILD_SYSTEM.md) | 建造命令卡 / Ghost |
| [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) | 人族竖切与 HUD 验收 |
| [minimap/MINIMAP.md](../minimap/MINIMAP.md) | 小地图 UV / 栅格 |
| [ASSET_LANES.md](../../architecture/ASSET_LANES.md) | Portrait 资产车道 |
