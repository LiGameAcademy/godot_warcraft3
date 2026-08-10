# 寻路移动模块 · 方案选型评估

> 状态：**已拍板倾向**（2026-08-05）  
> 场景：Echo Isles 游戏竖切 · 阶段 D「选中 + 右键移动」  
> 相关：[ROADMAP.md](../game/ROADMAP.md) · [ARCHITECTURE.md](../game/ARCHITECTURE.md) · `scripts/map/data/wc3_pathing_map.gd`

---

## 1. 决策问题

在实现单位移动时，二选一（或明确「主方案 + 远期备选」）：

| 方案 | 一句话 |
|------|--------|
| **A. WC3 离散网格 A\*** | 以 `war3map.wpm` / `Wc3PathingMap`（32 WC3 单位/格）为图，自研或对齐经典 A\* + 占用 |
| **B. Godot NavMesh + RVO** | `NavigationRegion3D` / `NavigationAgent3D` + 避障（RVO/ORCA 类），连续空间导航 |

目标不是「哪个更现代」，而是：**哪个更贴本仓库的数据契约、分层门禁、以及「复刻 WC3 玩法」的验收标准。**

---

## 2. 评估维度

| 维度 | 权重 | 说明 |
|------|------|------|
| 与现有数据对齐 | 高 | 已有 WPM、`pathTex` blit、建筑脚印、编辑器 pathing overlay |
| 玩法语义对齐 | 高 | 不可走/不可建/荒芜/飞行位；农民绕建筑；金矿/树木碰撞感 |
| 分层架构 | 高 | Logic 纯规则、Present 不写 pathing flags；可单测 / headless |
| 竖切成本 | 高 | 阶段 D 要尽快「右键能走到可走格」 |
| 多单位避障 | 中 | 群走、堵门、编队（可后置） |
| 表现与手感 | 中 | 折线 vs 平滑曲线；贴地；卡边 |
| 远期扩展 | 中 | 飞行单位、两栖、动态开关闸门、联机确定性 |
| 维护成本 | 中 | Godot 引擎升级、自研算法复杂度 |

---

## 3. 方案 A — 离散网格 A\*（WC3 同构）

### 3.1 做法概要

```text
Wc3PathingMap（静态 WPM + 动态 blit）
    → 按 unit 碰撞 / 层（Walk/Fly）生成「可走」掩码
    → A* / JPS（格点）得路径
    → 可选：字符串拉直 / 漏斗简化
    → 单位按路点移动；占用格或 soft radius 防重叠
```

权威图 = **已有** `Wc3PathingMap`（`FLAG_NO_WALK` 等），与 HiveWE / 编辑器 overlay **同一真相**。

### 3.2 优势

1. **数据零阻抗**：`pathing.json`、地形合成、树木/建筑 `pathTex` blit 已为网格服务；不必再 bake NavMesh。  
2. **语义对齐 WE**：不可走、不可建、动态脚印、开始点清野后的通道，与地图制作工具一致。  
3. **落在 Logic 层干净**：输入 flags + 起终点，输出路点数组；不依赖场景树 / NavigationServer。  
4. **确定性好**：同输入同路径，利于日后录像 / 联机 / 触发器「单位走到某区域」。  
5. **验收直观**：开发期 32 栅格 + pathing 染色已在用，debug「为何走不动」成本低。  
6. **路线图已写明**：阶段 D「贴地 + `Wc3PathingMap` 可行走检测（先直线，后寻路）」。

### 3.3 劣势

1. **手感偏「格」**：折线路径；需拉直/插值才像原作流畅。  
2. **群走要自研**：WC3 有单位碰撞与让路；完整复刻工作量大。可先「单单位 + 简单 soft 分离」。  
3. **A\* 大图成本**：Echo Isles 全图可接受；需限帧、限开集或分层（粗细格）。  
4. **斜坡/悬崖**：可行走性已在 WPM；高度贴地仍要查 Heightfield（与 NavMesh 一样要接）。

### 3.4 与本仓库锚点

| 能力 | 已有 |
|------|------|
| 路径图 | `Wc3PathingMap` · `map_pathing_layer` |
| 动态脚印 | `blit` pathTex（建筑/装饰） |
| Catalog | `parse_path_tex_cells` / collision |
| 游戏阶段 D | ROADMAP 明确先走 PathingMap |

---

## 4. 方案 B — Godot NavMesh + RVO

### 4.1 做法概要

```text
Heightfield / 碰撞体 → bake NavigationMesh
    → NavigationAgent3D 求路
    → RVO / avoidance 做单位间避让
    →（难题）如何把 WPM flags、pathTex 动态更新同步进 NavMesh
```

### 4.2 优势

1. **引擎现成**：避障、局部绕行、Agent 半径开箱即用。  
2. **路径更平滑**：连续空间，观感「现代 RTS」。  
3. **少写核心算法**：不必维护 A\* 开闭集细节。

### 4.3 劣势（对本项目尤其致命）

1. **第二套真相**：NavMesh 与 `Wc3PathingMap` 双轨；编辑器显示「可走」、运行时 NavMesh 不一致时极难查。  
2. **动态 pathTex 贵**：建筑造/拆、树砍、闸门开关要 **rebake 或 runtime obstacle**；WC3 是 **blit 几格 byte**。  
3. **分层违规风险**：寻路易绑在 `NavigationRegion3D` 场景节点上，Logic 单测变重。  
4. **语义缺口**：WPM 位语义（build/fly/blight/water）不能无损映射到一层 NavMesh；常要多 region 或硬编码。  
5. **复刻验收难**：「和 WE 同一张 pathing 图」变成「和 bake 参数碰巧像」。  
6. **竖切更慢**：先要可靠 bake 流水线 + 与 heightfield/cliff 对齐，才谈右键移动。

### 4.4 何时方案 B 才合理

- 产品目标改为「类 WC3 题材的现代 RTS」，**不**追求 WPM 一致；或  
- 已弃用 pathing overlay / pathTex 制作管线；或  
- 仅做 **表现层局部避障**，全局路径仍由网格 A\* 给出（见 §5 混合）。

---

## 5. 对比总表

| 维度 | A 网格 A\* | B NavMesh+RVO | 胜出 |
|------|------------|---------------|------|
| 对齐 `Wc3PathingMap` / WPM | 原生 | 需同步/近似 | **A** |
| 动态建筑/树木脚印 | blit 廉价 | rebake/obstacle 重 | **A** |
| 分层（Logic 可测） | 易 | 易绑场景树 | **A** |
| 阶段 D 竖切速度 | 快（直线→A\*） | 慢（bake 先行） | **A** |
| 多单位避障成品度 | 需自研/简化 | 引擎强 | **B** |
| 路径平滑度 | 需后处理 | 默认更好 | **B** |
| 联机/录像确定性 | 强 | 依赖引擎版本与浮点 | **A** |
| 与 ROADMAP/架构文档 | 已指定 | 偏离 | **A** |
| 长期「现代手感」扩展 | 可加平滑与 soft RVO | 起点即现代 | **B**（仅此项） |

---

## 6. 推荐结论

### 主方案：**A — 基于 `Wc3PathingMap` 的离散网格寻路**

**不**在阶段 D 引入 NavMesh 作为权威寻路面。

理由（压缩）：

1. 仓库已把 pathing 网格当作地图态的一部分，编辑器与游戏共用；再上 NavMesh = 双真理源。  
2. 项目门禁是「WC3 数据映射正确」，不是「Godot 最新导航 API」。  
3. ROADMAP 阶段 D 已规定 PathingMap 路径；改 B 会推翻数据与 debug 投资。  
4. 群走/RVO 的痛点可用 **后期局部避障** 补，不必先换全局图表示。

### 明确不采用（本阶段）

- 以 NavMesh 替换 WPM 作为唯一可行走查询。  
- 为了 RVO 而忽略 `pathTex` / 动态 blit。

### 可选增强（主方案落地后）

| 阶段 | 内容 |
|------|------|
| D0 | 右键：直线可达？`can_walk` 采样；否 → 提示 |
| D1 | 网格 A\*（Walk 层）+ 路点跟随 + 贴地 |
| D2 | 路径拉直；**PathAgentProfile 净空**（collision→clearance） |
| D3 | 简单分离（push）或 **局部** RVO，**不**改全局图；编队落点 + 凹角脱困 |
| 远期 | 若要做飞行层 / 特殊导航，仍优先「第二套网格掩码」，而非整图 NavMesh |

「网格全局路径 + 局部连续避障」是可接受的混合；**NavMesh 全局路径**不是。

---

## 7. 建议落地架构（主方案）

```text
Application（GameDirector / Order）
    下达 MoveOrder(unit, goal_wc3)
        ↓
Logic（game/scripts/logic/pathing/）
    PathQuery.is_walkable / find_path(start, goal, agent_profile)
        ← 读 Wc3PathingMap + Heightfield（只读）
        ↓ 路点列表（WC3 XY）
Presentation
    单位插值移动、贴地、选中环；不写 pathing cells
```

| 类型建议 | 职责 |
|----------|------|
| `PathAgentProfile` | walk/fly、碰撞半径（格）、能否过水等 |
| `PathQuery` | A\* / 直线检测；纯函数式，可测 |
| `MoveOrder` / `UnitMotor` | 消费路点、速度、到达阈值 |

禁止：在 `MapUnitLayer` 里直接 new `NavigationAgent3D` 当唯一寻路。

---

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| A\* 卡顿 | 限每帧搜索数；大距离分层；异步队列 |
| 卡拐角 | 拉直 + 终点吸附到最近可走格 |
| 多农民堵门 | D3 soft 分离；占格预约（后置） |
| 「手感不如 NavMesh」 | 路点 Catmull-Rom / 转向限速；勿换权威图 |
| 有人强推 NavMesh | 仅允许作 **视觉调试对比** 或局部 avoidance，禁止当 WPM 替代 |

---

## 9. 总结（一页纸）

- **选 A（WC3 网格 A\*）做全局寻路权威**；用已有 `Wc3PathingMap`。  
- **不选 B（NavMesh+RVO）做主路径**；它与 WPM/`pathTex`/编辑器 overlay 冲突，竖切更慢，且违背当前数据驱动门禁。  
- **RVO/平滑属于增强层**，挂在网格路径之后，而不是替换网格。  
- **阶段 D 顺序**：可走检测 → A\* → 跟随贴地 →（再）群体分离。  

**一句话**：在这个仓库里，寻路的「地图真相」已经是离散 pathing 图；算法应服从数据，而不是另起一套 Godot 导航世界。
