# 对战地图 · 游戏场景开发路线图

> 目标：在 Godot 中跑通「打开 Echo Isles → 看见地形/装饰/单位 → 对战初始化语义 → 可操作」的竖切。  
> **明确决策（2026-08-03）：现阶段不急着实现完整 WE 触发器编辑器 / wtg VM。**  
> 先用「游戏场景 + 对战引导（Melee Bootstrap）」落地；触发器作为远期架构预留接口。  
> 配套：[ARCHITECTURE.md](ARCHITECTURE.md) · 总纲 [../architecture/LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md)

---

## 0. 为什么先不写触发器？

WE「对战初始化」本质是一张**固定动作表**（见下节截图语义），对常规对战图几乎千篇一律：

1. 对战昼夜设置  
2. 对战英雄设置  
3. 给首发英雄回城卷轴  
4. 设置初始资源  
5. 删除已用开始点附近中立生物  
6. 创建对战初始单位（主城 + 农民等）  
7. 对电脑跑 AI 脚本  
8. 强制对战胜负条件  

这些可以先做成 **`MeleeBootstrap` 硬编码模块**（对标触发器动作的原生实现），验证玩法闭环。  
等单位移动/选中/建造最小闭环跑通后，再把同一套动作挂到 `TriggerRuntime` 上，并解析 `war3map.wtg` / `war3map.j`。

过早做触发器会导致：

- 要同时啃 TriggerData / GUI / JASS 子集 / 事件总线  
- 游戏侧还没有「单位实体、玩家资源、胜负」可被动作调用  
- 与编辑器触发器 UI 抢工期，拖垮玩法竖切  

---

## 1. 阶段总览

```text
A  游戏场景壳          Echo Isles 加载 + 开发期栅格/路径显示
B  会话与玩家          从 units(sloc)/info 建玩家槽、开始点相机
C  Melee Bootstrap     对战初始化动作的原生实现（非 wtg）
D  最小 RTS 交互       选中、移动（贴地路径）、镜头
F  人族游玩竖切        采集→基建→英雄→训兵→科技→技能（当前主线）
E  触发器运行时（远期） 事件/条件/动作 VM + 默认 Melee 图挂接
```

编号即推荐顺序；**A→D 已基本落地；F 竖切完成 F0–F6 + C0–C3 + F8–F10**（大法师/山丘/P0 支援）；技能重构 Phase A–E ✅。  
**当前冲刺**不再以「再堆技能」驱动 → **[../../roadmap/NEXT.md](../../roadmap/NEXT.md)**（N0 收口 → N1 人族可玩闭环 → N2 手感）；E 仍单独开里程碑。

---

## 2. 分阶段清单

### A. 游戏场景壳（本分支首要交付）

- [x] 目录：`game/scenes/game_main.tscn` + `game/scripts/game_director.gd`
- [x] 实例化共用 `scenes/map/map_root.tscn`
- [x] 默认 `map_dir = res://assets/map-parsed/echoisles`
- [x] `place_doodads / place_units / auto_load_on_ready = true`
- [x] 开发期：`set_view_grid_level(3)`（32 最小栅格）+ `set_show_pathing_ground(true)`
- [x] 无 MapDocument；路径图：有 `pathing.json` 则读，否则 `Wc3PathingMap.synthesize_from_heightfield`
- [x] RTS 相机（`game/scenes/rts_camera.tscn`；边缘滚/滚轮缩放；**默认关闭中键旋转**对齐 WC3；阶段 B 用 `focus_on_position`）

**验收**：F6 跑 `game/scenes/game_main.tscn` 即见 Echo Isles；栅格与路径色块可见；单位/装饰与编辑器开图观感一致（允许分帧加载）。  
**说明**：工程 `run/main_scene` 仍为编辑器；玩法开发用 F6 /「运行当前场景」。

### B. 会话与玩家

- [ ] `GameSession`：map_dir、玩家列表、本地玩家 id
- [ ] 从 `units.json` 收集 `typeId=sloc` → 玩家开始点
- [ ] 读 `info.json` / `summary.json`（melee、推荐人数、tileset）
- [ ] 开局相机落到本地玩家开始点附近

**验收**：1v1 Echo Isles 能识别两个开始点；相机落在玩家 1 附近。

### C. Melee Bootstrap（对战初始化 · 原生）

对应 WE「Melee Initialization」动作表，**先实现子集**：

| 优先级 | 动作 | 说明 |
|--------|------|------|
| P0 | 设置初始资源 | 按种族/对战默认金木 |
| P0 | 创建对战初始单位 | 主城 + 工人于 sloc（需种族→单位 ID 表） |
| P0 | 删除已用开始点附近中立 | 半径对齐 WE（常用 1024） |
| P1 | 对战昼夜 / 英雄设置 | 可先做数据开关，表现后置 |
| P1 | 回城卷轴 | 依赖物品/英雄系统 |
| P2 | 电脑 AI 脚本 | 远期 |
| P2 | 胜负条件 | 远期（无建筑判负等） |

- [ ] `game/scripts/logic/melee/melee_bootstrap.gd`：输入 Session + 地图只读视图，输出「要生成/删除的单位指令」
- [ ] Present：通过 MapLoader / 单位层 API 应用指令（或临时直接改内存列表再 rebuild）
- [ ] **不**解析 wtg；动作名与 WE 字符串对齐，方便日后迁移到 Trigger

**验收**：开局后开始点出现主城+工人；附近野怪被清；金木 HUD 有数（可用简陋 Label）。

### D. 最小 RTS 交互

- [x] 点选单位 / 框选（可复用 `scripts/shared/selection/`）
- [x] 右键移动：贴地 + `Wc3PathingMap` 网格 A\*（`PathQuery` + `UnitNavigator`）  
  → 选型见 [PATHFINDING_CHOICE.md](../pathfinding/CHOICE.md)（**主推网格 A\***，不用 NavMesh 作权威图）
- [x] 选中环尺寸继续走单位配置（已有 Catalog 逻辑）

**验收**：能选中农民并命令移动到可走格子；不可走区域有反馈。

### F. 人族游玩竖切（当前主线）

按真实开局顺序推进采集、建造、英雄、训兵、科技与大法师技能。  
**细项、ID 表、验收剧本、AbilitySystem 策略 → [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md)**

摘要：

| 步 | 内容 | 状态 |
|----|------|------|
| F0 | 命令 / SmartTarget / Router；农民移动停止面板 | ✅ |
| F1 | 采集金、木、送回；树 promote；CarrySlot | ✅ |
| F2 | 祭坛、农场、兵营（建造 + 占位 + 人口） | ✅ |
| F3 | 召唤大法师 `Hamg` | ✅ 竖切接线（祭坛只训大法师；英雄上限 1） |
| F4 | 训练步兵 `hfoo` | ✅ |
| F5 | 伐木场 `hlum`（收木） | ✅ 可造；送回能力已有 |
| F6 | 铁匠铺 → 解锁火枪手 | ✅ Requires 置灰 + `hrif`；铁匠武器/护甲科技后置 |
| **C0–C3** | **攻击 / 攻移 / 射程 / 攻防伤害** | ✅ · 尸体停留后移除 · 契约 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) |
| F7 | 主城升 Keep | 后置 |
| F8 | 顶盾科技 `Rhde` | ✅ 兵营研究；完成后按钮消失；玩家级解锁 |
| F9 | 顶盾切换 `Adef` | ✅ 减速 / Defend 姿态 / Unart |
| F10 | 大法师技能（先原生，再评估插件） | ✅ 大法师 + 山丘 + P0 支援；见 [ABILITY_SYSTEM.md](ABILITY_SYSTEM.md) |

**Present 并行（不挡 F2）：** 野怪/小动物 Stand 藏尸体 Geoset（`geosetvis` + `MapUnitLayer` snap；同树桩管线）。

**下一步（跨文档）**：人族可玩闭环收尾（复活 / Keep / 铁匠升级 / 生产队列 HUD / U3 手测）→ [../../roadmap/NEXT.md](../../roadmap/NEXT.md) N1。

### E. 触发器运行时（远期 · 仅设计，本阶段不开发）

见 [ARCHITECTURE.md §4](ARCHITECTURE.md)。里程碑条件建议：

- F 竖切已验收（至少到 F4）  
- Melee Bootstrap 动作表稳定  
- 再开 `feature/trigger-runtime`，引入 wtg/j 解析与 VM  

---

## 3. 非目标（本路线图内不做）

- 触发器编辑器 GUI（对标 WE 触发器面板）
- 完整 JASS / Lua 脚本宿主
- 联机 / 录像
- 物体编辑器（自定义单位数值）
- 把编辑器主场景改成游戏（编辑器保持独立）
- 完整多族科技树（人族竖切范围见 GAMEPLAY_VERTICAL）

---

## 4. 建议迭代节奏

| 迭代 | 产出 |
|------|------|
| 1 | A：game_main + Echo Isles + 栅格/路径 |
| 2 | B：Session + 开始点相机 |
| 3 | C：资源 + 初始单位 + 清野 |
| 4 | D：选中 + 移动竖切 |
| 5 | F0–F1：命令 + 采金伐木（✅） |
| 6 | **F2–F6：建造扩展 + 训练 + Requires**（✅） |
| **7** | **C0–C3：战斗框架（Attack / Attack-Move / 伤害）** ✅ |
| 8 | F8–F10（顶盾 → 技能）✅；Keep/铁匠科技后置 → NEXT N1 |
| **9+** | **[NEXT.md](../../roadmap/NEXT.md)**：N0 收口 → N1 闭环 → N2 手感 → N4 扩展 |
| 并行 | 单位/野怪尸体 Geoset 显隐（Present）；地图 N3 补债 |
| 远期 | E：触发器 VM |

---

## 5. 相关代码锚点（实现时）

| 能力 | 已有锚点 |
|------|----------|
| 地图加载 | `scripts/map/presentation/map_loader.gd` |
| 路径图 | `scripts/map/data/wc3_pathing_map.gd` · `map_pathing_layer.gd` |
| 栅格 | `map_debug_grid_layer.gd` · `set_view_grid_level` |
| 开始点 | `typeId=sloc` · Catalog 注入 |
| 单位层 | `map_unit_layer.gd`（分帧/线程预载） |
| 框选 | `scripts/shared/selection/` |
| 游戏相机 | `game/scenes/rts_camera.tscn` · `game/scripts/presentation/rts_camera.gd` |
| 解析图目录 | `assets/map-parsed/echoisles/` |
