# 建造系统：四族非对称 · 数据驱动设计

> 状态：**人族竖切可玩**（F2-A～F2-D + F2-C 多工加速已接线；兽/灵/亡 Strategy 仍为 stub）  
> 相关：[GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md)  
> 分支：`feature/building-system`  
> 最后更新：2026-04-14

---

## 0. 结论（先读）

**应该**在造「人族竖切」时就把建造做成 **可扩展管线**，而不是把「农民隐藏 + 单人 timer」写死成唯一真相。

原因不是「马上做四族」，而是：

1. WC3 的建造差异是 **机制维度**（可见性 / 多工 / 召唤 / 消耗工人 / 地形谓词），不是「换皮肤」。
2. 这些差异在官方数据里 **已有钩子**（种族 Build 技能、`Builds=`、`requirePlace` / `preventPlace`），适合 Catalog + Strategy，不适合 `if race == human` 散落。
3. 当前 F2 实现与文档验收里「农民隐藏」更接近兽族/精灵，**与人族语义相反**——趁接线前校正契约成本最低。

**F2 范围不变**：只玩通人族 Farm / Altar / Barracks。  
**契约要先立**：`BuildSite` + `ConstructionProfile` + 可组合 `PlacementRule`；人族是第一个 Strategy 实现。

---

## 1. 四族行为对照（玩法语义）

| 维度 | 人族 Peasant | 兽族 Peon | 暗夜 Wisp | 亡灵 Acolyte |
|------|----------------|-----------|-----------|--------------|
| Build 技能码 | `AHbu` | `AObu` | `AEbu` | `AUbu` |
| 下令后工人 | **留在场上**，播 Work / 等价修理 | **进入建筑**（不可选、无敌感） | **进入建筑**；古树等完工后 **消耗** Wisp | **召唤**：开工后可离开，建筑自行升起 |
| 多工加速 | **可以**（额外农民对工地 `Ahrp` Repair） | 不可以 | 不可以 | 不可以 |
| 工地实体 | 半血/成长中的建筑单位；进度≈HP/修理吞吐 | 单工人占用的工地 | 类似兽族；部分建筑是「工人→建筑」转化 | 召唤中的建筑；工人不占用 |
| 取消 | 退款 + 释放所有参与农民 | 退款 + 吐出 Peon | 退款 +（未消耗则）吐出 Wisp | 退款；侍僧本就不锁在工地 |
| 特色放置 | 普通 pathing | 普通 pathing | 普通 pathing；缠绕金矿走 `Aent`≠普通 Builds | 非主城类建筑 `requirePlace=blighted` |
| 世界观钩子 | 工匠施工 | 钻进建筑搭架子 | 生命力注入 / 古树化 | 荒芜地上召唤 |

补充（实现时易混）：

- **人族开工后**，引擎侧常见「建造令 → 修理令」衔接；多农民加速本质是 **多人 Repair 同一未完工建筑**。
- **暗夜古树**（Tree of Life / Ancients）：完工后工人消失（consumed），不是「吐出来再站岗」。Moon Well 等非古树也是 Wisp 消耗型（与兽族「吐 Peon」不同）。
- **亡灵主城** `unpl` / 升级体与闹鬼金矿 `ugol`：`requirePlace` **不是** `blighted`（主城自己铺荒芜；金矿改造成闹鬼）。
- **Naga** 另有 `AGbu`；本竖切不实现，但 Profile 表留一行即可。

---

## 2. 数据权威（已在本仓库核对）

### 2.1 可造列表：`*UnitFunc.txt` → `Builds=`

不在 `UnitUI` / `UnitBalance` 里，而在种族 Func。  
**运行时权威路径**（经 `sync-data-assets`，禁止读 `.cache`）：

`assets/slk-exported/Units/*UnitFunc.txt`

（extract 源在 `.cache/wc3-assets/Units/`，仅工具管线使用；契约见 [ASSET_LANES.md](../architecture/ASSET_LANES.md)。）

| 工人 | 文件 | 示例 |
|------|------|------|
| `hpea` | `Units/HumanUnitFunc.txt` | `Builds=htow,hhou,hbar,hbla,hwtw,halt,…` |
| `opeo` | `Units/OrcUnitFunc.txt` | `Builds=ogre,otrb,…` |
| `ewsp` | `Units/NightElfUnitFunc.txt` | `Builds=etol,emow,…` |
| `uaco` | `Units/UndeadUnitFunc.txt` | `Builds=unpl,uzig,usep,…` |

→ Catalog：`WorkerBuildListCatalog.get_builds(unit_id) -> PackedStringArray`  
→ 命令卡「建造菜单」只读此列表 + 科技/依赖过滤（依赖另表，F2 可先不做）。

### 2.2 建造模式：种族 Build 技能

`AbilityData.slk`：

| alias | comments | race |
|-------|----------|------|
| `AHbu` | Build (Human) | human |
| `AObu` | Build (Orc) | orc |
| `AEbu` | Build (Night Elf) | nightelf |
| `AUbu` | Build (Undead) | undead |
| `AGbu` | Build (Naga) | other |

注意：导出的 `UnitAbilities.abilList` **不一定列出** `AHbu`（工人表里常见 `Ahar,Amil,Ahrp` 等）。引擎按 **单位 Race** 绑定 Build 技能。  
→ 映射权威建议：`UnitData.race` → `ConstructionProfileId`，而不是「abilList 含 AHbu」。

### 2.3 放置谓词：`UnitBalance`

字段已进 `UnitBalanceDef`：

| 字段 | 含义 | 本仓库样例 |
|------|------|------------|
| `preventPlace` | 禁止落点类型 | 多数建筑 `unbuildable`；船坞 `unwalkable` |
| `requirePlace` | 必须满足的类型 | 亡灵非主城：`blighted`；人兽灵多为 `_` |
| `bldtm` / `goldcost` / `lumbercost` / `fmade` | 时间、造价、人口 | 已有 `BuildingCatalog` |
| `path_tex`（UnitData） | footprint | 已有 |

亡灵对照（节选，来自 `UnitBalance.json`）：

| id | requirePlace | 备注 |
|----|--------------|------|
| `unpl` / `unp1` / `unp2` | `_` | 主城链，自铺 blight |
| `ugol` | `_` | 闹鬼金矿（改造中立矿） |
| `uzig` `usep` `uaod` … | `blighted` | 其余地面建筑 |

→ Placement **禁止**写死「亡灵必须 blight」；只解释 `requirePlace` / `preventPlace` 字符串（可插拔 Resolver）。

### 2.4 缠绕金矿等「非 Builds 建造」

`Aent`（Entangle）等是 **独立技能**，不是 `Builds=` 菜单项。  
→ 另走 `SpecialConstructAbility` 通道（F 竖切后期 / 暗夜里程碑），不要塞进普通 `issue_build`。

---

## 3. 设计目标

| 目标 | 做法 |
|------|------|
| 数据驱动 | 造价/时间/footprint/Builds/放置谓词全部来自 Def/Func；逻辑不写死 ID 表以外的数值 |
| 机制模块化 | 四族差异收敛到 **ConstructionProfile + Strategy**；`BuildSite` 只持共享状态 |
| 分层干净 | Data/Catalog 出配置；Logic 跑状态机与合法性；Present 只反映工地/工人显隐与 Birth 动画 |
| F2 可交付 | 先实现 `HumanConstructionStrategy`；兽灵亡 Profile 可先只有数据表 + stub |
| 可测 | Profile 行为用 selftest 钉死（多工、显隐、消耗、blight 谓词） |

---

## 4. 核心抽象

### 4.1 分层落点

```text
Data / Def
  UnitBalanceDef.require_place / prevent_place / bldtm / costs
  UnitDataDef.race / path_tex
  *UnitFunc Builds=（解析进 Catalog）

Catalog
  BuildingCatalog          # 已有：造价/时间/footprint/fmade
  WorkerBuildListCatalog   # 新增：unit_id → Builds[]
  ConstructionProfileCatalog # race 或 build_ability → ConstructionProfile

Logic
  PlacementRules           # 组合谓词（pathing + require/prevent + 单位碰撞…）
  BuildSite                # 共享：进度、HP 增长、builder 槽、退款快照
  IConstructionStrategy    # 人/兽/灵/亡 行为插件
  BuildController          # 工人侧会话：走位、加入/离开工地（人族可多人）
  CommandRouter.issue_build / issue_join_build

Present
  PlacementGhost           # 读 PlacementRules
  BuildSiteVisual          # Birth / 半成品比例 / 工人挂点
```

### 4.2 `ConstructionProfile`（数据，不是脚本分叉）

建议字段（Resource 或 RefCounted 常量表）：

```text
profile_id: human | orc | nightelf | undead | naga

# 工人占用
builder_slot_policy:  MANY_VISIBLE | ONE_HIDDEN | NONE_SUMMON
max_builders:         int          # human=∞(软上限), orc/ne=1, undead=0（召唤后）
builder_hidden:       bool
builder_invulnerable: bool         # 隐藏占用时通常 true
consume_builder_on_complete: bool  # nightelf true；orc false；human false
release_builder_on_complete: bool  # human/orc true；ne false；undead n/a

# 进度模型
progress_model:       REPAIR_HP | OCCUPIED_TIMER | SUMMON_TIMER
# REPAIR_HP：人族——工地作为未完工建筑，基础建造 + Repair 加速
# OCCUPIED_TIMER：兽/灵——单工人绑定 timer（可用 HP 表现，但逻辑是占用）
# SUMMON_TIMER：亡灵——无工人占用，纯 timer / Birth

# 加入工地
join_via_repair:      bool         # 仅 human
join_ability_id:      String       # Ahrp / Arep / Aren / Arst…

# 取消
cancel_refund_ratio:  float        # WC3 建造取消常见 0.75；实现时用常量并单测钉死
```

Profile **不要**按建筑 id 分叉；建筑差异用 Balance 字段。  
例外（数据字段表达）：`requirePlace`、古树 `special`/unit 类型、金矿改造技能。

### 4.3 `BuildSite`（唯一工地真相）

工地是 Logic 实体（可挂 Node，或 Session 表 + Present 绑定）：

```text
building_id, site_wc3, owner_player
profile_id
state: PENDING | ACTIVE | DONE | CANCELLED
gold_spent, lumber_spent
progress: 0..1（或 current_hp / max_hp）
primary_builder_id   # 下单扣费者
active_builders[]    # 人族可多；兽灵最多 1；亡灵召唤后为空
pathing_reservation  # footprint 占用句柄（取消回滚）
```

职责：

- 推进进度（委托 Strategy）
- 接受 `add_builder` / `remove_builder`（Strategy 拒绝非法加入）
- `cancel` → 退款 + 释放工人 + 回滚 pathing
- `complete` → 刷正式建筑（或把「未完工建筑」升级为完工）+ 人口 + Strategy.on_complete（消耗/释放工人）

### 4.4 Strategy 接口（逻辑插件）

```text
IConstructionStrategy:
  on_order_accepted(site, builder)      # 扣费后：人族创建半成品建筑；亡灵开始召唤
  on_builder_arrived(site, builder)     # 人族开始修；兽灵隐藏并占用
  try_join(site, builder) -> bool       # 人族 Repair 加入；其它 false
  tick(site, dt)                        # 推进进度
  on_cancel(site)
  on_complete(site)
  present_hooks(...)                    # 可选：显隐、挂点；或纯信号给 Present
```

| Strategy | F2 | 说明 |
|----------|----|------|
| `HumanConstructionStrategy` | **必做** | 工人可见；支持 join；进度建议 HP/等效吞吐 |
| `OrcConstructionStrategy` | stub / 后置 | 隐藏单工人 |
| `NightElfConstructionStrategy` | stub / 后置 | 隐藏 + complete 消耗 |
| `UndeadConstructionStrategy` | stub / 后置 | 无占用；Placement 走 blight |

### 4.5 放置规则：组合谓词

`PlacementRules.can_build_at` 改为流水线：

```text
1. BuildingCatalog.is_building / footprint 合法
2. pathing：preventPlace 语义（unbuildable / unwalkable…）
3. requirePlace Resolver：
     "_" / 空 → 通过
     "blighted" → Heightfield/地表 blight 掩码（角点或 cell）
     其它 → 扩展点（金矿上、水上等）
4. 与单位 / 未完工工地碰撞（F2 应补）
5. （可选）科技/依赖、中立区…
```

`requirePlace=blighted` 依赖地图 **blight 数据**（编辑器侧已有设计讨论：`corner_blight`）。  
亡灵里程碑前可先实现 Resolver 接口 + human 恒 true；不要在人族代码里写 `if undead`。

---

## 5. 命令流（与现有 Router 对齐）

```text
选中工人 → 命令卡读 WorkerBuildListCatalog
  → 进入 PlacementGhost（PlacementRules）
  → 确认：CommandRouter.issue_build(builders, building_id, site_wc3)

issue_build：
  1. 解析 profile = ConstructionProfileCatalog.from_unit(primary_builder)
  2. 校验 Builds 列表含 building_id
  3. PlacementRules.can_build_at
  4. 扣费一次（仅 primary；禁止对每个选中农民各扣一次）
  5. **仅 primary** path 到工地；到位后创建 BuildSite（半成品）
  6. 框选中的其余农民**不**自动帮工；半成品出现后需再选中并右键工地 → `issue_join_build`
  7. Powerbuild 附加费按进度周期扣（造价×Ahrp DataC×(N-1)×Δratio），非 join 时整笔扣费
  8. orc/ne/undead：按各族 Profile/Strategy（非人族竖切路径）
```

与采集一致：`GameDirector.ensure_build` 注入 session/pathing；**工地完成信号由 Director 刷建筑**。

`UnitOrder` vs `BuildOrder`：Router 只发轻量令；`BuildController` / `BuildSite` 持有 `BuildOrder` 或 site 句柄。禁止把 `builder` 动态挂到 `UnitOrder` 上充数。

---

## 6. 与当前 F2 代码的差距（契约校正）

| 现状 | 问题 | 目标契约 |
|------|------|----------|
| `BuildController` 到位后 `peasant.visible=false` | 兽/灵语义；**不是人族** | Human：保持可见 + Work/Repair |
| 单农民单 timer | 无法表达人族多工 | `BuildSite.active_builders` + Repair 加速 |
| `issue_build` 对每个农民 `start_build` | 重复扣费 | 一单一次扣费 + 多人 join |
| `PlacementRules` 忽略 `requirePlace` | 亡灵无法扩展 | 谓词组合 |
| 无 `Builds=` Catalog | 命令卡只能硬编码 3 建筑 | Func 解析；F2 可过滤子集 |
| 文档验收「农民隐藏」 | 与人族不符 | 改为可见施工；多农民可加速 |

F2 验收剧本应改为：

1. 选农民 → 建 Farm → ghost 绿/红 → 扣费 → 农民走过去并 **仍可见** 施工  
2. 框选多农民建造 → **仅 1 人**前往；半成品出现后另选农民右键工地 → 加速；附加费按进度累计（非 join 整扣）  
3. 完工刷建筑、人口 +`fmade`；农民释放  
4. 取消：退款比例按 Profile（建议先钉 **0.75** 并与实测对照）+ 农民恢复

---

## 7. 实现分期（不挡人族竖切）

| 阶段 | 交付 | 四族？ |
|------|------|--------|
| **F2-A 契约** | 本文档 + Profile 表 + 接口空壳；修「隐藏农民」验收文案 | 仅表数据 |
| **F2-B Human** | `HumanConstructionStrategy` + 单次扣费 + Director 接线 + pathing 占用 | 人族可玩 |
| **F2-C 多工** | `issue_join_build` / Repair 加入 + 进度加速 | 人族完整 |
| **F2-D 数据** | `WorkerBuildListCatalog`（解析 UnitFunc）+ 命令卡读 Builds | 仍人族过滤 |
| **Fx 兽/灵** | Orc/NE Strategy + 显隐/消耗 | 开兽灵时做 |
| **Fy 亡灵** | Undead Strategy + blight Resolver + 主城铺 blight | 开亡灵时做 |

原则：**每阶段只启用一个 Strategy 实现**；禁止在 `BuildController` 里堆四族 `match race`。

---

## 8. 目录建议（增量，不推翻现有）

```text
game/scripts/
├── data/
│   ├── building_catalog.gd              # 已有
│   ├── worker_build_list_catalog.gd     # 新增：Builds=
│   └── construction_profile_catalog.gd  # 新增：race → profile
├── logic/construction/
│   ├── build_order.gd                   # 已有（改为 site 句柄友好）
│   ├── build_site.gd                    # 升级为共享工地真相
│   ├── build_controller.gd              # 工人侧；变瘦
│   ├── placement_rules.gd               # 谓词组合
│   ├── placement_require_resolvers.gd   # blighted 等
│   └── strategies/
│       ├── construction_strategy.gd     # 接口
│       ├── human_construction.gd
│       ├── orc_construction.gd          # stub
│       ├── nightelf_construction.gd     # stub
│       └── undead_construction.gd       # stub
└── presentation/
    ├── placement_ghost.gd
    └── build_site_visual.gd             # 半成品 / Birth
```

---

## 9. 测试契约（selftest 应覆盖的维度）

| # | 用例 | 断言 |
|---|------|------|
| 1 | Human 单工 | 扣费一次；工人 `visible==true`；完工释放 |
| 2 | Human 双工 | 第二人 join 后 `progress` 速率上升；仍只扣一次费 |
| 3 | Human 取消 | 退款比例；工人可见且 IDLE；pathing 回滚 |
| 4 | Profile stub Orc | `try_join` 第二人 == false；arrived 后 hidden |
| 5 | Placement `requirePlace=blighted` | 无 blight 拒绝；有 blight 通过（可用假 Heightfield） |
| 6 | Builds 列表 | `hpea` 含 `hhou`；不含敌族建筑 |

当前 `selftest_build_flow.gd` 若只测 stock 字面量退款，**不算**建造系统测试。

---

## 10. 明确不做（本设计边界）

- 不在 F2 实现完整四族可玩
- 不把编辑器 `unit_placement_rules` 与游戏 Placement 合并成一个类（可共享纯函数）
- 不在 Present 层判断种族建造规则
- 不用「建筑 id 前缀 h/o/e/u」推断机制（以 race / profile / Balance 字段为准）
- 金矿缠绕 / 闹鬼改造不走普通 `Builds` 下单

---

## 11. 决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 是否为四族预留？ | **是（Profile + Strategy）** | 差异是机制轴；后补人族隐藏逻辑返工更大 |
| F2 是否做人族多工？ | **P0 单工正确语义；P1 多工加速** | 先修正「可见施工」，再加 join |
| 进度模型 | 人族目标 `REPAIR_HP`；F2 可先用「等效 timer + 人数系数」 | 对齐体验优先于帧级修理公式 |
| 放置 | 解释 `requirePlace`/`preventPlace` | 亡灵 blight 零分叉 |
| Builds 来源 | `*UnitFunc.txt` | 与对象编辑器「Structures Built」一致 |

---

## 12. 下一步（实现侧）

见 §13.5 路线图（文档曾写的 Catalog / BuildSite 重构已落地）。

---

## 13. 当前实现状态（2026-04-14）

人族最小闭环已可玩；分支 `feature/building-system` 已与 `master` 同步（含网格寻路 / 加载热修）。分层重构主线仍优先 Heightfield→Ground，本系统不挡斜坡。

### 13.1 已落地模块

| 模块 | 状态 | 说明 |
|------|------|------|
| ConstructionProfile / Catalog | ✅ | 四族表；Human：`hides_builder=false`，`cancel_refund_ratio=0.75` |
| WorkerBuildListCatalog | ✅ | 解析 UnitUI.builds；命令卡可展开建筑列表 |
| BuildingCatalog | ✅ | 造价 / bldtm / pathTex / fmade |
| PlacementRules | ✅ | 越界 / 占格 / 可通行；荒地谓词未接 |
| BuildPlacementController | ✅ | begin / update_screen / confirm / cancel |
| BuildPlacementGhost | ✅ | 寻路格吸附；逐格贴地绿/红；半透明建筑模型 |
| BuildController | ✅ | 走位、扣费、按 profile hide、退款 |
| BuildSite | ✅ | 首工到位后创建；0 人暂停；速率 `1+(N-1)×0.6`；帮工附加费按进度累计 `造价×0.15×(N-1)×Δ进度`（非整次 join 扣） |
| HumanConstructionStrategy | ✅ | 人族策略接线 |
| CommandCard `ubuild` | ✅ | builds 展开 → `begin_placement` |
| GameDirector 接线 | ✅ | `_ensure_build_placement_objects` |
| 自测 | ✅ | `tests/unit/selftest_f2_build_system.gd` |

### 13.2 文件落点

| 层 | 文件 | 角色 |
|----|------|------|
| Data | `building_catalog.gd` / `construction_profile_catalog.gd` / `worker_build_list_catalog.gd` | 造价、Profile、Builds 列表 |
| Logic | `construction/build_*.gd` / `placement_rules.gd` / `*_strategy.gd` | 订单、工地、放置、策略 |
| Logic | `command/command_card.gd` / `command_router.gd` | 建造按钮、issue_build |
| Present | `presentation/build_placement_ghost.gd` | Ghost 预览 |
| Session | `game_director.gd` | 瞄准态、完工刷建筑、地面采样 |

### 13.3 近期热修

| 项 | 说明 |
|----|------|
| **Ghost 地面采样 arity**（2026-04-14） | Director 绑定 `Callable(self, "_ground_at_screen")`（需 `screen_pos`）。`BuildPlacementController._recompute` 曾 `.call()` 零参 → 点建造按钮即报错。已改为 `.call(_screen_pos)`。 |
| **Ghost 跟手 / 整图变色 / 贴地遮挡 / 逐格预览**（2026-04-14） | 误用 `1/WORLD_SCALE`；整块变色。已改为：寻路格吸附、footprint **逐格**绿/红贴地、半透明模型。建造格=调试「小」格(32)；「中」格(128)=4×4 建造格。 |

### 13.4 与设计契约的差距

| 项 | 现状 | 优先级 |
|----|------|--------|
| 人族可见施工 / Profile 退款 | ✅ 已按 `hides_builder` / `cancel_refund_ratio` | — |
| 多工加速（BuildSite） | ✅ 多选建造只派 1 人；半成品后右键 join；速率 `1+(N-1)×0.6`；附加费按进度累计（Ahrp DataC 0.15） | — |
| WorldMembership.exit/enter | 流程文档曾写；当前人族路径未强制依赖 | P1（亡灵必做） |
| `requirePlace` / `preventPlace` | PlacementRules 未接 | P2（亡灵） |
| Birth / 工地幼体视觉 | ✅ 开工播 Birth；完工回 Stand | — |
| Orc / NE / Undead Strategy | stub | 各族里程碑 |
| 兵营 TrainQueue | 属 F3/F4，非建造核心 | F3+ |

### 13.5 开发路线图（本分支）

```text
已完成
  F2-A 契约文档 + Profile 表
  F2-B Human Strategy + 扣费 + Director + pathing 预约
  F2-C BuildSite 多工加速（入口再验）
  F2-D WorkerBuildListCatalog + CommandCard builds
  热修：_get_ground_hit.call(screen_pos)

下一刀（建议顺序）
  1. ~~实机：Peasant → Ghost 跟手~~（2026-04-14 热修：top_level / HUD 武装）
  2. 第二农民 join（Repair / 点工地）UI 与验收
  3. Undead：hide + WorldMembership + blight requirePlace
  4. Orc / NightElf：hide / 消耗工人分叉
  5. Birth / 半成品 Present
  6. 建筑训练队列（并入 F3/F4）
```

### 13.6 验收清单（人族）

1. 选中农民 → 点「建造」→ 展开建筑列表，**无** `_ground_at_screen` arity 报错  
2. 选建筑 → Ghost 绿/红跟鼠标 → 合法点确认扣金木  
3. 建造中农民仍可见、可取消；退款按 Profile（0.75）  
4. 完工建筑出现、`food_cap` 增加、农民恢复空闲  
5. （P1）第二农民加入 → 进度加快且不二次扣费  
