# 斜坡（Ramp）重建说明

> **分支：`feature/ramp-rebuild`**  
> **分层：逻辑层（FLAG_RAMP / 蓝菱形）→ 表现层（拓扑变体 + 三层生成结构）**  
> 直崖见 [CLIFF.md](CLIFF.md)。

---

## 1. 目标与非目标

**目标**：先把逻辑层（蓝菱形 / `FLAG_RAMP`）做对，再按拓扑变体实现表现层；生成脚本采用三层结构，并注入对地形高度图 mesh 的依赖。

**非目标（本阶段不做）**：一次性恢复旧的 romp / CliffTrans 耦合实现；不在分发器里画 mesh，不在底层绘制函数里写悬崖业务规则。

---

## 2. 拓扑形态与方向变体

斜坡最终会有哪些拓扑形态和方向变体，必须先对齐再写代码。

### 2.1 直线型变体（Straight）

最基础形态，用于连接**正南北**或**正东西**走向的直悬崖。

| 边 | 含义 |
|----|------|
| 两条平行边 | **侧脊（Edge）** |
| 另外两条平行边 | **坡顶（High）** / **坡底（Low）** |

方向：北向 / 南向 / 东向 / 西向（共 4）。

### 2.2 外转角变体（Outer Corner）

4 个凸角方向。当高地悬崖形成一个凸出的 90° 角（像城堡的凸角塔楼），玩家在转角处刷斜坡时触发。

- 坡面：**扇形展开**
- 坡顶：只有 **1** 个顶点属于高地最尖端
- 坡底：**3** 个顶点环绕在低地

### 2.3 内转角变体（Inner Corner）

4 个凹角方向。当高地呈现凹字形的 90° 拐角（像山谷深入高地的凹槽）时触发。

- 与外转角相反：坡面呈**漏斗状收敛**
- 坡顶：占据 **3** 个高地顶点
- 坡底：只有 **1** 个顶点在最深处的低地

### 2.4 对角线变体（Diagonal / 45°）

实际制图常遇到斜着 45° 延伸的山脊。WC3 对对角线斜坡有两种拓扑实现：

| 方式 | 说明 |
|------|------|
| **梯级锯齿拼接（Staircase Steps）** | 「直线变体 + 转角变体」交替排列（例：北向坡 → 东北外转角 → 东向坡）。微观锯齿，宏观 45°。 |
| **对角切分变体（Diagonal Split）** | 在一个 1×1 网格内沿对角线切成两个三角形：一个为平缓坡面，另一个归两侧悬崖缝合面。`war3map.w3e` bitmask 中有专门的对角切分标记（Diagonal Cliff Flag）。 |

实现顺序建议：先直线 → 外/内转角 → 再对角线（锯齿拼接优先于对角切分，除非对照图明确要求 Split）。

---

## 3. 表现层：三层生成结构

斜坡生成脚本实现**三层结构**，并**注入对地形高度图 mesh 的依赖**（坡面/侧脊与地面缝合时需要同一套高度采样，而不是各算各的）。

```
┌─────────────────────────────────────────┐
│  L3  Dispatcher（路由器 / 分发器）        │  ← 唯一对外入口
│  读 4-bit Mask → 识别拓扑 → 调变体       │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  L2  Variants（具体变体渲染）             │
│  直坡 / 外转角 / 内转角 / …               │
│  模块拼接、侧脊遮盖、与高度图对齐         │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  L1  基础放置（模型 / 网格）              │
│  只做几何与空间变换，无业务逻辑           │
└─────────────────────────────────────────┘
         ▲
         │ 依赖注入：Heightfield / Ground Mesh 采样
```

### 3.1 第一层：基础放置（draw / place）

只关心几何与空间变换，**完全不含业务逻辑**。

职责一句话：**给你数据/Mesh，正确塞进 SurfaceTool 或挂到 3D 节点上**。

例如：`draw_mesh_block(mesh, transform, …)`、`place_glb_instance(path, xf)`。  
不读 Mask，不算拓扑，不判断侧脊/坡顶。

### 3.2 第二层：变体实现（Variants）

处理某一种变体的模块拼接与侧脊遮盖，例如：

- `render_straight_ramp_variant(…)`
- `render_outer_corner_variant(…)`
- `render_inner_corner_variant(…)`

本层知道「北向直坡左侧侧脊要旋多少度、偏多少」，但**不负责**从整张地图扫 Mask、也不做路由。

### 3.3 第三层：分发器（Dispatcher）

**对外唯一入口**。无论是编辑器点击，还是运行时从 JSON 加载地图，全部走这里。

职责：

1. 读取顶点的 **4 位二进制 Mask**（与周围层高 / `FLAG_RAMP` 等组合，具体编码另表）
2. 识别拓扑形态（直线 / 外转角 / 内转角 / …）与方向
3. 路由到对应的变体方法

分发器**不知道** Mesh 怎么画；底层绘制**不关心**悬崖规则，只吃参数画 Mesh。

### 3.4 为何这样拆

| 目的 | 效果 |
|------|------|
| **绝对解耦** | Dispatcher ↔ Variants ↔ Place 单向依赖；改画法不动路由，改规则不动 Place |
| **方便调试** | 「北向斜坡左侧穿模」→ 只进 `render_straight_ramp_variant` 查 `RAMP_EDGE_LEFT` 的旋转/偏移，不动分发逻辑 |
| **统一入口** | 笔刷与读档同一条路径，避免两套拓扑判断分叉 |

---

## 4. CliffTrans 文件命名与模型目录（Resource）

路径：

- `res://assets/asset-converted/Doodads/Terrain/CliffTrans/`（通用，当前 **32** 个 `.glb`）
- `…/CityCliffTrans/`（城市崖，当前 **16** 个，是前者的子集、无 `X`/`C` 复杂缝）

代码：`Wc3CliffTransCatalog`（`scripts/map/catalog/wc3_cliff_trans_catalog.gd`）
入口：运行时 `load_cliff_trans()` / `load_city_cliff_trans()`（扫盘，**不**检入 `resources/*.tres`）
自测：`tools/selftest_cliff_trans_catalog.gd`

### 4.1 文件名结构

```
CliffTrans  AAHL  0  .glb
└─family─┘ └TAG┘ └variation┘
```

| 段 | 含义 |
|----|------|
| **CliffTrans** | Cliff Transition（悬崖过渡 / 缝合模型）。城市族为 `CityCliffTrans`。 |
| **末尾数字** | Variation Index。同一种拓扑的随机外观变体（0、1、2…）；本仓库转换资源目前均为 **0**。 |
| **中间 4 字 TAG** | 一个 1×1 格四角的逻辑状态（见下）。 |

### 4.2 TAG 四角角序（核心）

四字依次为：**TL → TR → BR → BL**（与直崖 Cliffs 的 **BL → TL → TR → BR** 不同，对照时勿混用）。

```
        TL ---- TR
         |  格  |
        BL ---- BR
文件名顺序：TL, TR, BR, BL
```

例：`CliffTransAAHL0` → TL=A, TR=A, BR=H, BL=L。

### 4.3 单角字符含义

| 字符 | 含义 | 高程 / 逻辑 |
|------|------|-------------|
| **A** | Cliff Level 1 (High) | 标准悬崖高地顶点 |
| **B** | Cliff Level 2 (Higher) | 再高一层（多层崖） |
| **C** | Cliff Level 3 (Highest) | 再高一层；**本仓库资产中有**（如 `ACXH`），与直崖 A/B/C 相对高度同族 |
| **L** | Low Ground | 普通低地 / 平地顶点 |
| **H** | High Ramp / Edge | 斜坡高位过渡（接坡顶悬崖） |
| **X** | Complex Transition / Void | 特殊缝合切口（内外转角对角线切面等） |

> 说明：官方/HiveWE 文档有时只列 A/B/L/H/X；打开本仓库 `CliffTrans` 目录后，**C 与 X 均出现**，查表必须认 C。

### 4.4 Catalog API

```gdscript
var cat := Wc3CliffTransCatalog.load_cliff_trans()  # 运行时扫盘
var tag := Wc3CliffTransCatalog.tag_from_corners("A", "A", "H", "L")  # → "AAHL"
var path := cat.resolve_path_for_corners("A", "A", "H", "L")  # 磁盘存在才返回
var path2 := cat.resolve_path_for_tag("AAHL", 0)
```

| 方法 | 作用 |
|------|------|
| `rebuild_from_disk()` | 扫描 family 目录，登记 tag → 变体列表 |
| `tag_from_corners(tl,tr,br,bl)` | 四角状态 → 4 字 TAG |
| `path_for_tag` / `basename_for_tag` | 拼逻辑路径 / 文件名（不校验存在） |
| `resolve_path_for_tag` / `resolve_path_for_corners` | 仅已登记且磁盘存在时返回路径，否则 `""` |
| `has_tag` / `list_tags` / `variations_for` | 查询登记表 |

Dispatcher / Variant **只通过 Catalog 取模型**，不要手写 `CliffTrans%s%d.glb` 字符串散落各处。

### 4.5 开放问题 / 实现注意（补充）

1. **不是所有 6⁴ 组合都有模型**  
   当前 CliffTrans 仅 32 个 TAG。查表失败应明确失败或走回退策略（缺模警告），禁止静默乱替。

2. **角序与直崖 TAG 不同**  
   Cliffs 用 BL,TL,TR,BR + A/B/C；CliffTrans 用 TL,TR,BR,BL + A/B/C/H/L/X。从层高推 CliffTrans 字符时，先换算到本角序再查 Catalog。

3. **1×1 TAG ≠ 整条斜坡**  
   直线坡常跨 1×2 / 2×1 条带，侧脊可能要 **两块** CliffTrans（主条 + 对侧）。Catalog 只解决「四角 → 一块模」；条带如何拆成多次放置是 L2/L3 的事。

4. **CityCliffTrans 子集**  
   城市族无 `X`/`C` 复杂缝；缺模时是否回退到 `CliffTrans` 同 TAG，由 Variant 策略决定（Catalog 保持家族隔离，不自动跨族）。

5. **Variation**  
   现资源只有 `0`；API 已预留多变体。随机外观可在 L2 用 `variations_for` 选取。

6. **与逻辑层 FLAG_RAMP 的关系**  
   蓝菱形 / `FLAG_RAMP` 描述「哪些顶点在坡上」；四字 TAG 描述「这一格缝合模吃什么角状态」。Dispatcher 负责从层高 + 旗位 → 四角字符，再问 Catalog。

7. **对角切分 Flag**  
   W3E Diagonal Cliff Flag 与 TAG 中的 `X` 如何对应，需对照官方图/HiveWE 后再锁编码表（本阶段只登记模型，不定映射）。

---

## 5. 与「逻辑层 / 表现层」的关系

| 阶段 | 职责 | 验收 |
|------|------|------|
| **逻辑层** | 笔刷写 `FLAG_RAMP`；可选修正条带中间层高；蓝菱形只读旗位 | WE 同位置出现同列/同行蓝菱形 |
| **表现层** | 上节三层结构 + 各拓扑变体；挖洞 / CliffTrans / 甲板 / 与高度图缝合 | 视觉对齐 WE |

逻辑层产出的旗位与层高，是 Dispatcher 识别 Mask / 拓扑的输入之一；表现层不得回头改「乱写旗」来补视觉。

---

## 6. 当前进度

- [x] 清空旧斜坡表现耦合（基线 `948c979`）
- [x] **逻辑层**：条带笔刷 + 蓝菱形调试层（`4b05702`）
- [x] **CliffTrans Catalog**：命名解码 + Resource 查表（32 / City 16）
- [ ] 表现层 L1：基础放置 API + 高度图依赖注入
- [ ] 表现层 L3：Dispatcher（Mask / 四角状态 → 拓扑 → Catalog）
- [ ] 表现层 L2：直线变体（4 向）
- [ ] 表现层 L2：外转角 / 内转角（各 4 向）
- [ ] 表现层 L2：对角线（锯齿拼接 → 对角切分）

表现层仍旁路：`collect_ramp_placements` 恒空；地面仅直崖挖洞；水体忽略 ramp。

---

## 7. 逻辑层规则（蓝菱形）

对齐 WE / 已验证的条带语义：

| 情况 | 旗位形态 | 蓝菱形 |
|------|----------|--------|
| 单脊竖 | 一列 3 点 | 该列 3 个菱形 |
| 单脊横 | 一行 3 点 | 该行 3 个菱形 |
| 宽坡 | 邻列 `111\|111` | 两列并排菱形 |
| U 凹 | `111\|000\|111` | 两列独立；中间空列不填（除非再刷中间） |

| API | 作用 |
|-----|------|
| `MapDocument.paint_ramp_at` / `try_paint_ramp_at` | 落旗 |
| `peek_ramp_strip_at` | 悬停预览将写旗的顶点 |
| `MapRampDebugLayer`（`show_ramp_debug`） | 蓝菱形 |

自测：`tools/selftest_ramp_logic.gd`。

### 逻辑层验收

1. 悬崖工具 → 斜坡，在直线崖边点击/拖动  
2. 蓝菱形在脊线顶点（竖=一列 3 点，横=一行 3 点）  
3. 邻列续刷 → 宽 2；隔列刷 → 独立 U，中间无菱形  
4. 非法处（角柱、层差≠1）拒绝并提示，不写乱旗  

---

## 8. 术语对照（便于对照 WE / 代码命名）

| 中文 | 英文建议 | 备注 |
|------|----------|------|
| 侧脊 | Edge / Side ridge | 直线变体两侧，常对应 CliffTrans |
| 坡顶 / 坡底 | High / Low | 层高较高 / 较低一侧 |
| 外转角 | Outer corner | 凸 90°，扇形 |
| 内转角 | Inner corner | 凹 90°，漏斗 |
| 对角切分 | Diagonal split | W3E Diagonal Cliff Flag |
| 分发器 | Dispatcher | L3 唯一入口 |
| 基础放置 | Place / draw mesh block | L1 无业务 |
| 缝合模目录 | CliffTrans catalog | `Wc3CliffTransCatalog` |
| TAG 四字 | Corner tag | TL,TR,BR,BL |

---

## 9. 实现约定

1. **一次只做一步**，由用户指定；每步可独立验收。  
2. 新表现层按本文拓扑 + 三层结构接入，不恢复旧耦合实现。  
3. 调试穿模 / 错位时：先确认逻辑层蓝菱形，再只改对应 Variant，不动 Dispatcher。  
4. 取 CliffTrans 模型一律走 Catalog，禁止散落硬编码路径。  
