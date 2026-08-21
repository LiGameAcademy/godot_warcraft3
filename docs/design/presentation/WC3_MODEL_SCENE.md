# WC3 模型场景（.scn）运行时职责

> 状态：**设计约定**（讨论落地，迁目录可另开 PR）  
> 目标：把单位/建筑 **模型表现** 收进 bake 场景门面，策略层变薄；理清与 `scripts/map/` 地图表现的边界。  
> 关联代码：`wc3_model_scene.gd` · `wc3_anim_player.gd` · `mdx_anim_events.gd` · `game/scripts/unit/unit.gd` · `building_visual.gd`  
> 资产管线：[ATTACHMENTS_BAKE.md](../asset-convert/ATTACHMENTS_BAKE.md) · [tools/asset-convert/README.md](../../tools/asset-convert/README.md)  
> 最后更新：2026-08-21

---

## 1. 问题

当前模型相关脚本散落且边界模糊：

| 现状 | 问题 |
|------|------|
| `Wc3ModelScene` / `Wc3AnimPlayer` / PE2 / AnimPlayback 在 `scripts/map/presentation/` | 与 **地图层**（地形/水/崖 `Map*Layer`）混在同一目录；模型是 **资产运行时**，不是地图拓扑表现 |
| `UnitVisual` 在 `game/scripts/presentation/` | 承担过多「怎么播 Sequence」细节，本可下沉到 .scn 门面 |
| `BuildingVisual` 在 `scripts/map/presentation/` | 仅为避开 map→game 依赖而放 map；语义是建筑 **实体策略**，不是 map layer |
| 策略层直接摸 `AnimPlayback` / 翻子树找 AP | 与「bake 根对外 API」目标冲突 |

**共识方向：**

1. **表现封装在 `Wc3ModelScene`**（.scn 门面 + 子脚本）；玩法不要再扩 `*Visual`。  
2. **`UnitVisual` 命名废弃**：表现已够，下一步是 **Unit 实体根（logic）**，不是更薄的 Visual。  
3. **Building** 同理：实体/相位助手，而不是 `BuildingVisual` 当「表现」。  
4. **目录**：模型运行时迁 `scripts/presentation/wc3_model/`（见 §5）。

---

## 2. 目标分层

```text
GameDirector / Controllers（命令、经济、战斗）
  │
  ▼
Unit / Building（实体根 · game 侧 · 含 logic 门面）
  │  typeId、Stance/Activity 意图、尸体生命周期、挂 Navigator/Controllers
  │  对外：set_moving / set_stance / play_death / apply_building_phase…
  │  对内：只调 model.play_* ，不摸 AnimationPlayer
  ▼
Wc3ModelScene（.scn · 表现唯一门面 · 可作 Unit 子节点）
  ├── Wc3AnimPlayer
  ├── MdxAnimEvents
  ├── Pe2Root
  └── …
```

### 2.0 现状 → 目标（实体树）

**现状（已迁）：** `MapUnitLayer` 放置 **`Unit` 实体根**，bake 模型为子节点 `Model`（`Wc3ModelScene`）。`UnitVisual` 仅为 `extends Unit` 的兼容别名。

**目标：**

```text
Unit (Node3D + unit.gd)                    # 实体：logic 入口、meta/typeId、生命周期
├── Model (Wc3ModelScene 实例)             # 仅表现：来自 .scn
├── UnitNavigator                          # 移动执行（可仍挂实体下）
├── Selectable / Interactable / …
└── （按需）AttackController、Defend…     # 或继续用 of(unit) 查挂
```

建筑对称：`Building` 实体 + `Model`，相位 API 留在实体（或小助手），**不再叫 BuildingVisual**。

| 旧名 | 新名（建议） | 职责 |
|------|--------------|------|
| `UnitVisual` | 并入 `Unit`（或过渡名 `UnitBody`） | Stance/Activity 意图 → `model.play_*`；尸体链 |
| `BuildingVisual` | `Building` 实体 API / `BuildingPhase` | Phase → `model.play_*`；`is_building` → Catalog |
| `Wc3ModelScene` | 保持 | 纯表现门面 |

**为何不是「更薄的 UnitVisual」：**  
名字仍暗示「只有表现」，但真正缺的是 **实体根**。表现已由 ModelScene 承担；实体根应公开 logic 向 API，并拥有子树。

### 2.1 谁拥有什么状态

| 状态 | 归属 | 说明 |
|------|------|------|
| 负金 / 顶盾 / 主城升级档（Stance） | **Unit / Building 实体** | 由玩法写入；再转 play 意图 |
| 移动 / 攻击 / 施工 / 死亡（Activity） | **Unit 实体** | 同上 |
| 建筑 Birth / Work / Idle（Phase） | **Building 实体** | 由建造/训练驱动 |
| 播哪条 `Attack-2`、rarity 抽签 | **Wc3AnimPlayer** | 资产元数据 |
| OverHead / Origin 挂点 | **Wc3ModelScene** | bake 挂点 |
| PE2 emitting 跟 Sequence | **Wc3AnimPlayer → Pe2** | 跟当前 clip |
| 尸体链何时 `queue_free` | **Unit 实体** + Director | 生命周期属游戏 |

---

## 3. 各脚本职责（契约）

### 3.1 `Wc3ModelScene`（门面 · .scn 根）

**做：**

- 对外稳定 API：`play_logical` / `play_activity` / `resolve_logical`、`find_socket`、`overhead_anchor`、`portrait_camera`、`wc3_anim_player()`  
- `_ready`：bone rest sidecar、ensure `Wc3AnimPlayer`、缺省补挂 PE2  
- 外界 **禁止** `get_node` 翻子树找 AP / 挂点  

**不做：**

- Stance / Phase / 尸体 / 寻路 / 扣血  
- 解析 rarity 明细（交给 `Wc3AnimPlayer`）  
- 地图 heightfield / pathing  

### 3.2 `Wc3AnimPlayer`（`extends AnimationPlayer`）

**做：**

- `play_logical` / `play_activity`；族变体收集（`Attack-1/2`）  
- 读 `wc3_rarity` / `wc3_seq_looping` / `wc3_move_speed` / `wc3_mdx_name`  
- （约定中）按 rarity 加权随机同族 clip  
- 切 Sequence 时通知 PE2  
- loop / ping-pong 与 `AnimPlayback` 协作  

**不做：**

- 挂点查询、肖像机  
- 知道自己是农民还是兵营  

### 3.3 `MdxAnimEvents`

- Method Track 回调节点；`event_fired` 给打击帧 / 音效钩子  
- 不负责选 clip  

### 3.4 `AnimPlayback` / `AnimSequenceResolver`

- 无 Node 纯函数：名变体匹配、Stance×Activity→逻辑名字符串  
- 可被 `Wc3AnimPlayer` 调用；策略层 **逐步停止直接调用** `AnimPlayback.play_*`（经门面）  

### 3.5 从 `UnitVisual` / `BuildingVisual` → 实体根（目标）

| | 旧 UnitVisual | 新 Unit 实体 |
|--|---------------|--------------|
| 位置 | `game/.../unit_visual.gd` 子节点 | `game/scripts/unit/unit.gd`（名可再定）挂在实体根 |
| 输入 | set_moving / set_combat_attack / set_stance / play_death… | **同一套或更完整**（可再挂血量/命令钩子） |
| 输出 | → ModelScene.play_* | 同左 |
| 子树 | 挂在模型根下 | **模型是 Unit 的子节点** |

| | 旧 BuildingVisual | 新 Building |
|--|-------------------|-------------|
| 形态 | 静态工具类 | 实体脚本 + Phase API；`is_building` → Catalog |

**迁移约束：**

- `MapUnitLayer` 今天 `add_child(model_node)` 且 `unit_data` 打在模型上 → 改为 spawn `Unit` 再 `instance` 模型为子节点，或先「模型根临时挂 Unit 脚本」过渡（次优）。  
- Controllers 的 `of(body)` 以 **实体根** 为准，不要再假定 body == Wc3ModelScene。  
- 未完成迁移前，保留 `UnitVisual` 类名作别名/转发，避免一次爆改。

---

## 动画族与 rarity

- bake 写入 `Animation` meta：`wc3_rarity`（来自 MDX Sequence.Rarity）。  
- 逻辑名 `Attack` / `Stand` / `Walk` / `Death` → `Wc3AnimPlayer.collect_family` 收集同族，排除 Defend/Gold/Lumber/Work 等。  
- 加权：`pick_family` 使用 `weight ∝ 1/(rarity+1)`（rarity=0 最常见）。  
- `AnimPlayback.resolve` 在族分支委托 `ap.pick_family`；无 AP 脚本时回退编号最小。  
- `AnimPlayback` 与 `Wc3AnimPlayer` 同目录：`scripts/presentation/wc3_model/`（已从 `map/presentation` 迁出）。

---

## 5. 目录：为何不宜长期放在 `scripts/map/presentation/`

`scripts/map/` 在仓库契约里是 **地图运行时**（Heightfield、Cliff、`Map*Layer`、MapLoader）。见 [LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) §4.1、[SCRIPTS_LAYOUT.md](../../architecture/SCRIPTS_LAYOUT.md)。

模型 .scn 脚本是：

- **资产绑定**：bake 进 `asset-converted/**/*.scn`  
- **编辑器 + 游戏 + 地图单位层** 共用  
- 与地形/水网 **无依赖**  

故与 `map_terrain_layer` 同目录会造成「改模型动画却翻 map 分层规则」的认知税。

### 5.1 目录（已落地）

```text
scripts/presentation/wc3_model/       # 游戏/编辑器/地图单位层共用（非 map 拓扑）
  wc3_model_scene.gd                  # 门面
  wc3_anim_player.gd                  # AP 脚本
  mdx_anim_events.gd
  anim_playback.gd
  anim_sequence_resolver.gd
  anim_soft_loop.gd
  model_visual_sync.gd                # 旧 visuals ExtResource 兼容
```

PE2 暂留 `scripts/map/presentation/effects/`（装饰物与单位共用）。

**迁目录原则：**

- `git mv` + 改 preload/路径；bake 脚本与 `MapModelCache` 同步  
- 不改 class_name 对外语义  
- `BuildingVisual` 仍可留在 `map/presentation`（策略；依赖 DefStore）  

旧 bake `.scn` 内 ExtResource 可能仍指向 `map/presentation/`；该处保留 **薄 shim**（`extends` 新路径）。运行时 `ensure_on` / `_ensure_model_scene_scripts` 也会按新路径补挂。全库 `--force` 重烤后可删 shim。

---

## 6b. 排查结论（2026-08-21）

### JSON「缺动画元数据」

| 文件 | 是否含 rarity / loop / move_speed |
|------|-----------------------------------|
| `*.animkeys.json` | ✅ 权威旁路（convert 写出） |
| bake 后 `.scn` 内 `Animation` meta | ✅ `wc3_rarity` / `wc3_seq_looping` / … |
| `*.pe2.json` / `*.geosetvis.json` | ❌ 故意不含（粒子 / Geoset 显隐） |
| `tmp/human_preview` 旧副本 | ❌ 曾漏拷 `animkeys.json`（已改复制脚本） |

在编辑器里看 pe2/geosetvis **看不到** rarity 是预期；请打开同目录 `*.animkeys.json`，或 Inspect 已 bake 的 Animation 资源 meta。

### `.scn` 根未挂 `Wc3ModelScene`

**现象：** 磁盘 `.scn` 仅有 `mdx_anim_events.gd` 等 ExtResource，**无** `wc3_model_scene.gd`。  
**原因：** `export_model_scenes` 虽在 proto 上 `set_script`，但 `bake_model_scene` 保存路径未强制保证；且 `bake_model_scene` 在「已有 scn 且非 force」时会直接 `return true` 跳过重打包。  
**修复：** `MapModelCache.bake_model_scene` 在 `save_packed_scene` **直前**调用 `_ensure_model_scene_scripts`（根 + AP）。旧资产需 `--force` 重烤。运行时 `Wc3ModelScene`/`ensure_on` 仍可作兜底。

### `UnitVisual` / `BuildingVisual` 能否删除？

| | 结论 |
|--|------|
| **立刻整文件删除** | **否**（调用面 + 尸体/相位仍要落点） |
| **改名并升为实体根** | **是**（推荐方向，取代「变薄 Visual」叙事） |

**推荐：** 新建 `Unit`（logic 实体根），吸收今日 `UnitVisual` 的意图 API；表现只经子节点 `Wc3ModelScene`。`BuildingVisual` → Building 实体 / Catalog。过渡期可 `class_name Unit` + `UnitVisual = Unit` 别名或薄包装。

---

## 6. 非目标

- 把玩法状态机（Harvest / Combat Arbiter）写进 `Wc3ModelScene`  
- 用 AbilitySystem 插件替代 Sequence 名约定（F10 另议）  
- 位级复刻 WC3 粒子 / rarity 公式（先可玩近似）  
- 立刻全库重烤 .scn（运行时 `ensure_on` 可补挂 AP 脚本）  

---

## 7. 落地顺序（建议）

| 步 | 内容 | 状态 |
|----|------|------|
| A | 门面 + `Wc3AnimPlayer` + 文档 | ✅ / 进行中 |
| B | `play_logical` 接入 rarity 族抽取 | ✅ |
| C | 引入 `Unit` 实体根；`UnitVisual` 迁入或别名转发 | ✅ |
| D | `MapUnitLayer` / spawn：模型改为 Unit 子节点 | ✅ |
| E | `git mv` → `scripts/presentation/wc3_model/` | ✅ |
| F | Building 对称；`is_building` → Catalog | 后置 |

---

## 8. 决策记录

| 日期 | 决策 |
|------|------|
| 2026-08-20 | 表现封装以 `Wc3ModelScene` 为门面；AP 用 `extends AnimationPlayer` 的 `Wc3AnimPlayer`，不用旁路兄弟节点 |
| 2026-08-20 | 策略层变薄；rarity 随机属 AP，不属 UnitVisual |
| 2026-08-20 | 模型运行时脚本目标迁出 `scripts/map/presentation/`，入 `scripts/presentation/wc3_model/` |
| 2026-08-21 | 放弃「变薄 UnitVisual」叙事 → **Unit 实体根（logic）+ 子节点 ModelScene（表现）**；Building 对称 |
| 2026-08-21 | 落地 C+D：`game/scripts/unit/unit.gd`；`MapUnitLayer` 包 `Model`；`UnitVisual` 薄别名 `extends Unit` |
| 2026-08-21 | 模型脚本迁入 `scripts/presentation/wc3_model/`；PE2 暂留 map/effects |
