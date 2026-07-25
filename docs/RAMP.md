# 斜坡（Ramp）模块重构计划

> **前置里程碑**：悬崖 Catalog / Logic / Present 已打 tag `milestone/cliff-layered`（见 [CLIFF_REFACTOR.md](CLIFF_REFACTOR.md)）。  
> **分支**：`feature/ramp-rebuild`  
> **领域规则**（拓扑形态、CliffTrans 命名）以本文 §6–§8 为准；本文前半只定 **怎么按五层拆** 与验收顺序。  
> **分层总纲**：[LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md)；Present 纪律：`.cursor/rules/presentation-no-logic.mdc`  
> 最后更新：2026-07-25

---

## 1. 目标

把「崖边斜坡」做成与 **直崖** 同构的可测闭环：

```text
Data（FLAG_RAMP / 层高）
  → Logic（条带笔刷 + 拓扑 Dispatcher → RampPlacement / romp / 挖洞）
  → Catalog（CliffTrans TAG → GLB；族目录由 CliffTypes.ramp_model_dir）
  → Present（MapRampLayer 或并入 CliffLayer；只 resolve + 挂 MultiMesh）
  → Editor（笔刷命令 → History → 分路径重建；蓝菱形只读旗位）
```

**禁止**：Layer 内改 `flags` / 层高；Builder 内扫 Mask 选型；笔刷绕过 Logic；Present 写 Heightfield。

**非目标（本波次）**：一次性恢复旧 romp / CliffTrans 耦合实现；水体岸浪精调；W3E 对角切分 Flag 全量编码锁定（可先锯齿拼接）。

---

## 2. 现状债（为何要拆）

| 问题 | 现状落点 |
|------|----------|
| 笔刷 Logic 仍在 Document | `MapDocument.paint_ramp_at` / `peek_ramp_strip_at` + ~600 行私有条带分析（`_find_best_ramp_strip` 等） |
| 拓扑选型旁路 | `Wc3CliffLogic.collect_ramp_placements` 恒空；`romp` 全 0；`is_ramp_entrance` / 坡面采样恒 no-op |
| Present 未接 | 无独立 Ramp Layer；地面仅直崖挖洞；`cliff_ramp_placements` 缓存为空 |
| 岸线债 | `wc3_shoreline_builder` 仍忽略 `FLAG_RAMP`（水体重开时再接） |
| Catalog 已就绪 | `Wc3CliffTransCatalog`（32 / City 16）；`Wc3CliffCatalog.ramp_model_dir` |

参考直崖已落地形态：

| Cliff（已完成） | Ramp 目标对称物 |
|-----------------|-----------------|
| `Wc3CliffLogic.paint_corner` | `Wc3RampLogic.paint_at` / `peek_strip`（从 Document 迁出） |
| `Wc3CliffPlacement` + `build_topology` | `Wc3RampPlacement` + `collect_ramp_placements` 实装 |
| `Wc3CliffCatalog.resolve_glb` | `Wc3CliffTransCatalog.resolve_*`（族目录可经 CliffCatalog） |
| `MapCliffLayer` + thin Builder | `MapRampLayer`（或同层第二通道）+ L1 Place |
| 蓝菱形 `MapRampDebugLayer` | 保留；只读 flags，不写数据 |

---

## 3. 目标目录

```text
scripts/map/
├── data/
│   ├── wc3_ramp_placement.gd       # 【新建】ix,iy,tag,model_dir,variation,拓扑元数据
│   └── （romp / topology 可挂在 Wc3CliffTopologyResult.ramp_*）
├── catalog/
│   ├── wc3_cliff_trans_catalog.gd  # 已有；可选薄封装 Wc3RampCatalog 若需统一入口
│   └── wc3_cliff_catalog.gd        # ramp_model_dir(cliff_id)
├── logic/
│   ├── cliff/wc3_cliff_logic.gd    # 保留 ramp 查询桩的公开转发，或委托 RampLogic
│   └── ramp/
│       └── wc3_ramp_logic.gd       # 【新建】笔刷条带 + Dispatcher（Mask→变体→placements）
├── presentation/
│   ├── layers/map_ramp_layer.gd    # 【新建】或扩展 map_cliff_layer
│   └── ramp/
│       ├── wc3_ramp_builder.gd     # L1：placements → MultiMesh / 实例
│       └── （可选）variants_*.gd   # L2：直坡 / 内外转角；由 Logic 产出参数，Present 只变换

editor/scripts/
├── map_document.gd                 # 委托 RampLogic；删私有条带实现
├── map_ramp_debug_layer.gd         # 已有蓝菱形
└── tools/terrain_brush.gd          # 仍调 Document 公共 API
```

---

## 4. 分层契约

### 4.1 Data

- 权威：`Wc3Heightfield.flags` 的 `FLAG_RAMP`；层高仍由崖/笔刷维护
- 结构化：`Wc3RampPlacement`（忌长期裸 Dictionary 键穿过 Logic→Present）
- `romp: PackedByteArray`（格级斜坡种类）由 Logic 写入拓扑结果，Present / 地面挖洞只读

### 4.2 Catalog

| API | 含义 |
|-----|------|
| `Wc3CliffTransCatalog.load_cliff_trans()` / `load_city_cliff_trans()` | 运行时扫盘 |
| `resolve_path_for_tag` / `resolve_path_for_corners` | 仅登记且存在时返回路径 |
| `Wc3CliffCatalog.ramp_model_dir(cliff_id)` | `CliffTrans` vs `CityCliffTrans` |

Dispatcher / Variant **只通过 Catalog 取模型**，禁止散落 `CliffTrans%s%d.glb`。

### 4.3 Logic — `Wc3RampLogic`（目标）

| API（示意） | 含义 |
|-------------|------|
| `paint_at` / `try_paint_at` / `peek_strip_at` | 条带门禁 + 写 `FLAG_RAMP`（现 Document 语义） |
| `collect_placements(hf, meta, catalogs)` | 扫格 → 四角字符 → TAG → placements + romp |
| `should_leave_gap` 协作 | 坡格挖洞规则；地面 Layer 只读 mask |
| `dirty_rect` | 与崖同形（可选） |

与 `Wc3CliffLogic` 的关系：

- **短线**：Ramp API 先落在 `logic/ramp/`，`CliffLogic.collect_ramp_placements` 改为转发，避免 Present/Context 双入口
- **禁止**：Present 调 Logic 拓扑；Logic 不 `load()` GLB

### 4.4 Present — 三层生成结构（表现侧）

领域选型在 Logic；Present 只做「已决定的 placement → 几何」：

```text
L3 曾称 Dispatcher  → 现归 Logic（Mask / 拓扑 / 路由）
L2 变体参数         → Logic 写入 RampPlacement（方向、侧脊次数等）
L1 基础放置         → Present Builder（变换 + MultiMesh，无业务）
```

依赖注入：坡面与地面缝合时，高度采样来自 **同一套 Heightfield / 已缓存高度图**，Present 只读不写。

### 4.5 Editor

- 笔刷：`Document.paint_ramp_at` 委托 Logic；`PaintStrokeCommand` 快照已含 flags
- 悬停：`peek_ramp_strip_at` → 蓝菱形预览
- 重建：走 `rebuild_terrain_cliffs_water`；Context `ensure_cliff_topology` 填满 `ramp_placements`
- 验收调试：先开 `show_ramp_debug`，确认旗位再看 mesh

---

## 5. 实施里程碑

### M0 — 契约与笔刷迁出（不改手感）

1. 新建 `logic/ramp/wc3_ramp_logic.gd`，迁入 Document 条带笔刷 / 评分 / 落旗  
2. Document 仅委托；蓝菱形与 `selftest_ramp_logic` 行为不变  
3. ~~定义 `Wc3RampPlacement`~~ ✅（含 CollectResult / StripSpec / PaintResult；Topology+Context 已强类型）  
4. 文档：本文 + ROADMAP ⑧ 勾选进度  

**验收**：WE 同位置刷坡 → 同列/同行蓝菱形；非法处拒绝；自测绿。

### M1 — Logic Dispatcher：空壳 → 真 placements

1. 实装 `collect_ramp_placements`：直线变体优先（4 向）  
2. 层高 + `FLAG_RAMP` → CliffTrans 四角字符（角序 **TL,TR,BR,BL**）→ Catalog  
3. 输出 `romp` + `Array[Wc3RampPlacement]`；接入 `Wc3CliffTopologyResult` / Context  
4. 缺模：警告 + 跳过，禁止静默乱替  

**验收**：有 `FLAG_RAMP` 的 Lost Temple / 手刷图，placements 非空且 TAG 合理；`ramp_models` 统计 > 0。

### M2 — Present L1：只消费 placements

1. `MapRampLayer`（或 CliffLayer 第二通道）+ thin Builder  
2. 恢复坡格挖洞 / 与直崖 gap 协作（TerrainLayer 只读 mask）  
3. 高度图采样只读，用于缝合对齐（若本步需要）  

**验收**：直线坡视觉可辨；无 Present 写 hf；自测 + 手测。

### M3 — 变体补全

1. 外转角 / 内转角（各 4 向）  
2. 对角线：锯齿拼接优先；对角切分 Flag 对照后再锁  
3. 侧脊多块 CliffTrans（1×2 / 2×1 条带）由 Logic 拆成多次 placement  

**验收**：常见转角与 45° 锯齿不穿模；调试时只改对应变体参数，不动笔刷。

### M4 — 编辑增强与收尾（可选）

1. 斜坡笔划 label / 脏区局部重建  
2. 岸线重新识别 `FLAG_RAMP`（属水体债，可另开）  
3. 打 tag（建议 `milestone/ramp-layered`）  

---

## 6. 拓扑形态与方向变体（领域）

实现前必须对齐；选型在 **Logic**，不在 Layer。

### 6.1 直线型（Straight）

连接正南北或正东西直崖。两条平行边为侧脊（Edge），另两边为坡顶（High）/ 坡底（Low）。方向：北 / 南 / 东 / 西（4）。

### 6.2 外转角（Outer Corner）

凸 90°：坡面扇形；坡顶 1 顶点、坡底 3 顶点。

### 6.3 内转角（Inner Corner）

凹 90°：漏斗状；坡顶 3、坡底 1。

### 6.4 对角线（Diagonal）

| 方式 | 说明 |
|------|------|
| 梯级锯齿 | 直线 + 转角交替，宏观 45°（优先） |
| 对角切分 | 格内对角切分；对应 W3E Diagonal Cliff Flag / TAG 中 `X`（后锁） |

顺序：直线 → 外/内转角 → 对角线。

---

## 7. CliffTrans 文件命名与 Catalog

路径：

- `res://assets/asset-converted/Doodads/Terrain/CliffTrans/`（约 **32** 个 `.glb`）
- `…/CityCliffTrans/`（约 **16**，前者子集，无 `X`/`C` 复杂缝）

代码：`scripts/map/catalog/wc3_cliff_trans_catalog.gd`  
自测：`tests/unit/selftest_cliff_trans_catalog.gd`

### 7.1 文件名

```text
CliffTrans  AAHL  0  .glb
└─family─┘ └TAG┘ └variation┘
```

### 7.2 TAG 角序（与直崖不同）

四字：**TL → TR → BR → BL**（直崖 Cliffs 为 **BL → TL → TR → BR**）。

```text
        TL ---- TR
         |  格  |
        BL ---- BR
```

例：`CliffTransAAHL0` → TL=A, TR=A, BR=H, BL=L。

### 7.3 单角字符

| 字符 | 含义 |
|------|------|
| **A/B/C** | 崖层高相对阶（与直崖同族） |
| **L** | 低地 |
| **H** | 斜坡高位过渡 |
| **X** | 复杂缝 / 切口 |

### 7.4 实现注意

1. 不是所有组合都有模 → 失败要显式  
2. 角序与直崖 TAG 勿混用  
3. 1×1 TAG ≠ 整条坡；条带拆多块是 Logic 的事  
4. City 族缺模是否回退通用族由策略决定；Catalog 不自动跨族  
5. `FLAG_RAMP` 描述「哪些顶点在坡上」；四字 TAG 描述「这一格缝合模」；Logic 负责二者映射  

---

## 8. 逻辑层规则（蓝菱形）— 已验证基线

| 情况 | 旗位形态 | 蓝菱形 |
|------|----------|--------|
| 单脊竖 | 一列 3 点 | 该列 3 个菱形 |
| 单脊横 | 一行 3 点 | 该行 3 个菱形 |
| 宽坡 | 邻列 `111\|111` | 两列并排 |
| U 凹 | `111\|000\|111` | 两列独立；中间空列不填 |

| API（现状 → 目标） | 作用 |
|--------------------|------|
| `MapDocument.paint_ramp_at` → 委托 `Wc3RampLogic` | 落旗 |
| `peek_ramp_strip_at` | 悬停预览 |
| `MapRampDebugLayer`（`show_ramp_debug`） | 蓝菱形 |

自测：`tests/unit/selftest_ramp_logic.gd`。

### 逻辑层验收（M0）

1. 悬崖工具 → 斜坡，直线崖边点击/拖动  
2. 蓝菱形在脊线顶点  
3. 邻列续刷 → 宽 2；隔列 → 独立 U  
4. 非法（角柱、层差≠1）拒绝，不写乱旗  

---

## 9. 当前进度

- [x] 清空旧斜坡表现耦合（基线 `948c979`）  
- [x] 逻辑层条带笔刷 + 蓝菱形（仍在 Document；待 M0 迁出）  
- [x] CliffTrans Catalog  
- [x] 直崖五层闭环 + tag `milestone/cliff-layered`  
- [x] **数据层**：StripSpec 贯通 Document 条带路径；Topology/Context 嵌入 `ramp: CollectResult`；去掉 Dictionary 过渡 API  
- [ ] **M0** 笔刷 → `Wc3RampLogic`（Document 私有条带实现迁出）  
- [ ] **M1** `collect_ramp_placements` 真输出  
- [ ] **M2** Present 消费 placements + 挖洞  
- [ ] **M3** 内外转角 / 对角线  
- [ ] **M4** 脏区 / tag `milestone/ramp-layered`  

---

## 10. 实现约定

1. **一次只做一步**，由用户指定；每步可独立验收。  
2. 新表现层按本文拓扑接入，**不**恢复旧耦合实现。  
3. 调试穿模：先确认蓝菱形，再只查对应变体 / placement 参数。  
4. 取模一律 Catalog；跨边界禁止调 `_` 私有 API。  
5. Present **不得**写 Heightfield（写了即为 BUG）。  

---

## 11. 回归清单

```text
godot --headless --path . -s res://tests/unit/selftest_ramp_logic.gd
godot --headless --path . -s res://tests/unit/selftest_cliff_trans_catalog.gd
godot --headless --path . -s res://tests/cliff/selftest_cliff_variants.gd
godot --headless --path . -s res://tests/unit/selftest_paint_ground_rebuild.gd
```

编辑器手测：直线崖边刷坡 → 蓝菱形 →（M2 后）CliffTrans 可见 → 撤销/重做 → 栅格仍在。

---

## 12. 明确不做（本重构波次）

- 以「先好看」驱动、跳过 M0/M1  
- 水体 / 岸浪精调（⑨）  
- 导出 w3e  
- 与「应用高度」纯高度坡（B）混为一谈（那是 ⑩）  

---

## 13. 相关文档

| 文档 | 角色 |
|------|------|
| [CLIFF_REFACTOR.md](CLIFF_REFACTOR.md) / [CLIFF.md](CLIFF.md) | 直崖；本模块前置 |
| [LAYERED_ARCHITECTURE.md](LAYERED_ARCHITECTURE.md) | 五层总纲 |
| [ROADMAP.md](ROADMAP.md) | ⑧ 斜坡层勾选 |
| [TODO.md](TODO.md) | 细项 |
| [EDITOR.md](EDITOR.md) | 总管 / 命令 / 重建 |
