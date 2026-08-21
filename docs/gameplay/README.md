# gameplay/ — Gameplay 教程大纲

> **角色**：Gameplay 模块的**对外博客教程**大纲（**不**含地图编辑器）。
> 与 `docs/game/`（工程内部规范）和 `docs/blog/`（跨引擎移植类技术博客）区分。
> **本文是索引 + 章节列表**——具体博客内容陆续按章节补齐。
> 最后更新：2026-08-08

---

## 1. 范围与边界

**包含**：
- 游戏场景（`game/scenes/`）—— `game_main` / `rts_camera` / `game_hud` / `unit_selector` / `move_confirm_fx`
- 游戏逻辑（`game/scripts/logic/`）—— `command` / `economy` / `pathing` / `melee_bootstrap`
- 游戏表现（`game/scripts/presentation/`）—— `rts_camera` / `game_hud` / `unit_navigator` / `wc3_game_cursor` / …
- 单位实体（`game/scripts/unit/unit.gd`）—— Stance×Activity → `Wc3ModelScene`；spawn 树：`Unit` + 子节点 `Model`
- Session 状态（`game/scripts/session/`）—— `game_session` / `player_stock`
- GameDirector（`game/scripts/game_director.gd` 37487 行 —— 跨切编排）
- Units Defs（`scripts/definitions/units/`）—— Data 层支撑

**不包含**（归地图编辑器 / 工程文档）：
- 地图编辑器 UI（`editor/scripts/ui/`）
- 笔刷 / 工具（`editor/scripts/tools/`）
- 历史编辑命令（`editor/scripts/commands/`）
- 渲染管线 / Shader 跨引擎（已在 `docs/blog/01-...`）
- 地形 / 斜坡 / 水 / 装饰物 / 单位的 HivEWE 对齐（已在 `docs/{ramp,water,doodad,unit}/HIVEWE_ALIGN.md`）

---

## 2. 章节大纲

按主题聚合 12 章。每章标"状态"（✅ = 已写 / 🟡 = draft / 📋 = 待写）和"来源 commit"。

### 入门 / 架构

| # | 章节 | 状态 | 来源 | 一句话 |
|---|------|------|------|--------|
| 01 | **Game 架构总览**（Game vs Editor 双层）| ✅ | `0f9c7e0` + `docs/game/ARCHITECTURE.md` | 双层结构、MeleeBootstrap、Defer 完整 WE trigger VM |
| 02 | **场景与 RTS 相机** | 📋 | `0e5af2e` + `rts_camera.gd` 8938 行 | 6 档 yaw/pitch、键鼠绑定、占格 vs 镜头 |
| 03 | **Melee Bootstrap：4 玩家主城开局** | 📋 | `fe6aad6` + `melee_bootstrap.gd` 5124 行 | Echo Isles 4 角放位 + 兵种配额 + 起始资源 |

### 视觉 / 场景壳

| # | 章节 | 状态 | 来源 | 一句话 |
|---|------|------|------|--------|
| 04 | **建筑可视：Sequence / PE2 / Geoset / TeamColor** | 📋 | `dbe96d8` + `building_visual.gd` + `wc3_team_color_underlay.gdshader` | 4 玩家色 underlay + Sequence 切特效 + Geoset Alpha 采样 |
| 05 | **Echo Isles 完整场景** | 📋 | `0e5af2e` 3946 行 | pathTex 脚印 + Units Def 映射 + WPM 动态 blit 建筑寻路 |

### 寻路

| # | 章节 | 状态 | 来源 | 一句话 |
|---|------|------|------|--------|
| 06 | **寻路选型：A\* vs Flow Field vs HPA\*** | ✅ | `docs/game/PATHFINDING_CHOICE.md` 9KB | grid A\* 胜出理由 + 性能数据 |
| 07 | **grid A\* 实现** | 📋 | `ea465e2` + `path_query.gd` 17838 行 | 网格节点 + JPS-lite + 缓存 + 批量查询 |
| 08 | **单位导航与编队避让** | 📋 | `fb7404f` + `469528d` + `unit_navigator.gd` 12425 行 | UnitNavigator 状态机 + crowd_query 避让 + move_slots 占格净空 |
| 09 | **寻路 debug 可视化** | 📋 | `path_debug_draw.gd` 2965 行 | 节点 debug 画 + ghost 路径预览 |

### 单位交互

| # | 章节 | 状态 | 来源 | 一句话 |
|---|------|------|------|--------|
| 10 | **单位选中 + 命令层** | 🟡 partial | `2de6449` + `18ebfd1` + `docs/game/SELECTION_RINGS.md` 4.7KB | UnitSelector 框选 + command_router 派单 + order_queue 队列 |
| 11 | **农民 / 采金循环** | 📋 | `5c80c25` + `gold_mine_runtime.gd` 13261 行 + `harvest_controller.gd` 28822 行 | 固定走廊 + 幽灵寻路 + 进出矿语义 + F1 采金 |
| 12 | **Session / Stock 经济** | 📋 | `2de6449` + `game_session.gd` + `player_stock.gd` | 玩家 12 玩家 + 资源状态 + GameDirector 编排 |

### 视觉 / UI

| # | 章节 | 状态 | 来源 | 一句话 |
|---|------|------|------|--------|
| 13 | **Game HUD** | 🟡 partial | [HUD.md](../design/game/HUD.md) | 小地图✅ 资源条✅ 命令卡（含建造二级）✅；中栏肖像/详情/多选条 📋 |
| 14 | **Game Cursor + 移动确认 FX** | 📋 | `wc3_game_cursor.gd` 6789 行 + `move_confirm_fx.tscn` | 人类种族光标 + 移动确认特效 + 转向 / Walk/Stand |

### 收尾

| # | 章节 | 状态 | 来源 | 一句话 |
|---|------|------|------|--------|
| 15 | **Tree 互动（选中 → 采金 → 回到主城）** | ✅ | `docs/game/TREE_INTERACT.md` 10.6KB | 完整端到端流：选中农民 → 派单 → 寻路 → 采金 → 回家 |
| 16 | **移动对准 + WASD 镜头冲突修复** | ✅ | `origin/HEAD` fix | 落点偏 1 格 + 镜头移动抢键 |
| 17 | **矿空时贴矿农民立刻进** | ✅ | `master` fix | 矿没金立刻去下一个矿 + 取消 dead wait |

---

## 3. 跨章参考

| 主题 | 位置 |
|------|------|
| 寻路选型决策 | `docs/game/PATHFINDING_CHOICE.md` |
| Game 架构图 | `docs/game/ARCHITECTURE.md` |
| Game Environment 变量 / 资源加载 | `docs/game/ENVIRONMENT.md` |
| Echo Isles 路线图 | `docs/game/ROADMAP.md` |
| 选中环设计 | `docs/game/SELECTION_RINGS.md` |
| Tree 互动端到端 | `docs/game/TREE_INTERACT.md` |
| Gameplay 纵切 | `docs/game/GAMEPLAY_VERTICAL.md` 18.4KB |

---

## 4. 写作风格（与 `docs/blog/` 一致）

每章 **3000-5000 字**，结构：
1. 标题 + 副标题
2. TL;DR（3-5 行）
3. 背景（300-500 字）
4. 核心方案（1500-2500 字 + 精简代码）
5. 踩过的坑（500-1000 字）
6. 结果（300-500 字）
7. 引用

**区别于 `docs/blog/`**：
- `docs/blog/` 是"跨引擎 / 跨模块"通用话题（shader / pathing / 算法）
- `docs/gameplay/` 是 **godot_warcraft3 专有** Gameplay 纵切

---

## 5. 写作顺序建议

按"读者最有共鸣"的顺序：

1. **GP-06 寻路选型**（✅ 已写）—— "为什么选 A*" 是 RTS 开发者最关心的问题
2. **GP-04 建筑可视**（📋）—— TeamColor + Sequence 是炫技点
3. **GP-08 单位选中 + 命令层**（🟡）—— RTS 基础交互
4. **GP-11 采金循环**（📋）—— 端到端完整 loop
5. **GP-15 Tree 互动**（✅）—— 已有完整文档

按"基建 → 应用"逐章推进，每章 1-2 commit。

---

最后更新：2026-08-08
