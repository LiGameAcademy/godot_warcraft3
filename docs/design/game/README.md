# 游戏场景（Gameplay）

> 与地图编辑器（`editor/`）对称的**运行时**入口：加载已解析地图、跑对战规则、将来接 WE 触发器。  
> 默认开发地图：**Echo Isles**（`res://assets/map-parsed/echoisles`）  
> 最后更新：2026-09-05  
> **当前主线**：[../../roadmap/NEXT.md](../../roadmap/NEXT.md) **N1 人族可玩闭环**（复活 / Keep / 铁匠 / HUD 队列 / U3）；F10 与技能重构 A–E 已完成

## 文档

| 文档 | 内容 |
|------|------|
| [ORIGINAL_RTS_VISION.md](ORIGINAL_RTS_VISION.md) | **原创产品总纲 v0.13**：西式奇幻三联盟、100人口非对称编制、三位剧情英雄、装备与天赋 |
| [WORLD_AND_ALLIANCES.md](WORLD_AND_ALLIANCES.md) | **世界观对齐稿 v0.14**：逆潮当代史、四次护约远征、两次大陆战争、衡约诸传与三大联盟 |
| [COSMOLOGY_AND_MAGIC.md](COSMOLOGY_AND_MAGIC.md) | **底层规则框架 v0.7**：虚空与两仪、生命与灵魂、诸界生命，以及作者规律与世界内信仰的边界 |
| [GEOGRAPHY_AND_MAGIC.md](GEOGRAPHY_AND_MAGIC.md) | **世界地理框架 v0.13**：逆潮事件、两次大陆战争遗产、公约纪元、云泽飞地与三河圣城 |
| [CHRONICLE_AND_COVENANT_TRADITIONS.md](CHRONICLE_AND_COVENANT_TRADITIONS.md) | **编年史框架 v0.3**：逆潮之年、公约前年代、四次护约远征、两次大陆战争与五套历法 |
| [CONTEMPORARY_HISTORY_AND_CAMPAIGNS.md](CONTEMPORARY_HISTORY_AND_CAMPAIGNS.md) | **当代史与战役 v0.1**：公约纪301—327年、三位主角、三族各五章官方战役及教学分配 |
| [ORIGINAL_GAMEPLAY_FRAMEWORK.md](ORIGINAL_GAMEPLAY_FRAMEWORK.md) | **原创玩法框架 v0.4**：100人口上限、非对称编制、共享规则、战斗公式及三族机制 |
| [FACTION_UNIT_ROSTERS.md](FACTION_UNIT_ROSTERS.md) | **三族首发单位 v0.2**：差异化人口消耗、每族八个战斗单位、数据种子、组合与克制 |
| [CULTURAL_REGIONS_AND_NORTHERN_PEOPLES.md](CULTURAL_REGIONS_AND_NORTHERN_PEOPLES.md) | **地域文化与盟族 v0.2**：远枝盟约、精灵诸庭、兽狼灰途盟与三个原创北方族群 |
| [SILICON_LEGACY_AND_ENGINEERING.md](SILICON_LEGACY_AND_ENGINEERING.md) | **远古工程背景 v0.2**：晶格群、深眠者、工程传统、半身人起源与云泽转盟 |
| [../../roadmap/NEXT.md](../../roadmap/NEXT.md) | **先读（冲刺）**：N0–N4 近中期优先级 |
| [ROADMAP.md](ROADMAP.md) | 对战地图阶段 A→F→E；现阶段**不**急着实现完整触发器 VM |
| [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) | **人族游玩竖切**：F0–F10 / C0–C3 ✅；缺口见 NEXT N1 |
| [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) | **战斗系统**：Attack / 攻移 / 伤害管线 / 死亡 · C0–C3 契约 + **as-built** |
| [UNIT_AI.md](UNIT_AI.md) | **单位 AI**：野怪反击 / 警戒索敌（非 AI 玩家）· U0–U3 可执行切片 |
| [BUILD_SYSTEM.md](BUILD_SYSTEM.md) | **建造系统设计**：四族非对称 · Profile/Strategy · 数据钩子（F2 契约） |
| [TREE_INTERACT.md](TREE_INTERACT.md) | **可交互树**：MultiMesh promote、扣血统一入口、防闪烁 |
| [SELECTION_RINGS.md](SELECTION_RINGS.md) | **选中环**：己方绿 / 中立目标黄（金矿·树） |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 游戏层架构、与 Editor/Map 分层关系、触发器远期设计 |
| [PATHFINDING_CHOICE.md](../pathfinding/CHOICE.md) | **寻路选型**：网格 A\* vs NavMesh+RVO（主推网格） |
| [ENVIRONMENT.md](ENVIRONMENT.md) | 天空 / 天气 / 光照 / 阴影复刻方案（WC3→Godot） |
| [HUD.md](HUD.md) | **游戏 HUD**：三分栏、中栏三种形态、肖像、主选/Tab、命令卡二级建造 |
| [ABILITY_SYSTEM.md](ABILITY_SYSTEM.md) | **技能系统**：F10 as-built、Data/Logic/Present 分层 |
| [BLIZZARD.md](BLIZZARD.md) | **暴风雪 AHbz**：引导逻辑、多波伤害、落冰/命中资产路径与缺口 |
| [ABILITY_REFACTOR_PLAN.md](ABILITY_REFACTOR_PLAN.md) | **技能重构计划**：BehaviorCatalog → FxCatalog → BuffSystem → Director 瘦身 |
| [BUFF_SYSTEM.md](BUFF_SYSTEM.md) | **Buff 系统**：BuffHost / BuffQuery / HUD 图标条 as-built |

## 与编辑器的关系

```text
editor/          改地图（MapDocument + 笔刷）
scripts/map/     地图 Data/Catalog/Logic/Present（两边共用）
game/            玩地图（GameDirector + Session + 将来 Trigger）
```

- 游戏场景**不**依赖 `MapDocument` / 笔刷 / 撤销。
- 表现继续复用 `scenes/map/map_root.tscn`（`MapLoader`）。
- 开发期默认打开：**最小栅格（32）** + **路径-地面** overlay。

## 入口（目标）

| 场景 | 用途 |
|------|------|
| `game/scenes/game_main.tscn` | 游戏壳（阶段 A）；**F6 运行当前场景**做玩法开发（勿改工程主场景，编辑器仍 F5） |
| `editor/scenes/editor_main.tscn` | 地图编辑器（现主场景） |
| `scenes/main.tscn` | 旧 Lost Temple 静态预览（可保留） |
