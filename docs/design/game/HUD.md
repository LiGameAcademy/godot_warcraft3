# 游戏 HUD

> 场景：`game/scenes/game_hud.tscn` · 脚本：`game/scripts/presentation/game_hud.gd`  
> 选中权威：`scripts/shared/selection/unit_selector.gd`  
> 命令卡：`game/scripts/logic/command/command_card.gd`  
> 最后更新：2026-08-14

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

现状代码：中栏已接肖像 / 血蓝条 / 攻防与特殊行 / 多选条；生产队列未接。小地图与命令卡（含建造二级菜单）已接线。
---

## 3. 中栏：三种形态

由 **选中集合 + 当前选中（primary）** 决定；生产队列等训练系统接通后再灌真数据。

### 3.1 单选详情

触发：选中恰好 1 个单位或建筑。

| 块 | 内容 |
|----|------|
| 肖像 | `*_Portrait` 模型（见 §5） |
| 肖像下 | **生命**进度条；有魔法时再显示 **魔法**进度条（数值可叠在条上或旁注） |
| 标题 | 显示名（UnitStrings / Catalog） |
| 攻击 | 攻击类型 + 伤害（`UnitWeapons`：`atk_type1` + dice/sides/plus 或 min–max） |
| 防御 | 护甲类型 + 数值（`UnitBalance.def` / `def_type`）；无敌等特殊态单独文案 |
| 其它 | 移速、视野等可后置；**特殊属性**见下 |

**特殊属性（按单位类型叠加）：**

| 类型 | 展示 |
|------|------|
| 金矿 `ngol` | 剩余金币（`GoldMineRuntime.remaining_gold`） |
| 英雄 | 主属性（STR/AGI/INT）+ 力量 / 敏捷 / 智力（`UnitBalance`） |
| 建造中建筑 / 施工中农民 | 建造进度（已有 `set_build_progress`） |
| 负重农民 | 可后置：负金 / 负木数量 |

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

命令卡补充（已落地）：

- 工人主卡：**一个**建造入口（`AHbu` → `open_build`），不摊平建筑。
- 二级：`Builds ∩ F2 allowlist` + `CmdCancelBuild`；Esc 回主卡。

---

## 5. 肖像（Portrait）

### 资产

- 路径习惯：与 `UnitUI.file` 同目录的 `*_Portrait.gltf` / `.scn`（大小写混用，解析需多候选）。
- 数量：转换车道内大量 Portrait；运行时只读 `assets/asset-converted/`（见 [ASSET_LANES.md](../../architecture/ASSET_LANES.md)）。

### 渲染

- HUD 内 `SubViewport` + 实例化 Portrait 场景；队伍色按 owner 重染（与战场模型同一套）。
- **相机**：当前 glTF 转换**未带出** MDX Portrait Camera（`cameras=0`）。
  1. **近期**：启发式相机（看向 `Bone_Head` / AABB 中心，固定 FOV）。
  2. **远期**：转换器回填 Camera，或从 MDX 读机位后写入旁路数据。

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
hud.set_portrait_texture(tex)           # 占位，未实现
```

**目标扩展（实现时补齐）：**

```gdscript
hud.set_selection_info(info: Dictionary)
# info 建议键：
#   mode: "single" | "multi" | "train" | "empty"
#   primary_id / display_name
#   hp, hp_max, mana, mana_max
#   attack_line, armor_line, special_lines: PackedStringArray
#   portrait_type_id
#   multi: Array[{ node_id, type_id, icon }]   # 多选条
#   train_queue: Array[…]                     # 训练接通后
```

数据来源：

| 字段 | 来源 |
|------|------|
| HP | `UnitLife` |
| 魔法上限 | `UnitBalance.mana_n`（当前魔法运行时 meta，可后补） |
| 攻击 | `UnitWeaponsDef` |
| 护甲 | `UnitBalanceDef.def` / `def_type` |
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
