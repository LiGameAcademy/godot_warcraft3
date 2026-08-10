# 从 godot_hex_map 可吸收的经验

> 对比对象：`D:\GodotProject\laoli_gamedev_godot4_course\godot_hex_map`  
> 本仓库：`godot_warcraft3`  
> 相关：[LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) · [ROADMAP.md](../../roadmap/ROADMAP.md) · [EDITOR.md](../editor/EDITOR.md)  
> 最后更新：2026-07-27

---

## 1. 一句话定位

| | `godot_hex_map` | `godot_warcraft3` |
|--|-----------------|-------------------|
| 目标 | Catlike 风格六边形地图 + 可复用 EditorPlugin | 复现/编辑 WC3 地形（离线资产 → 可编辑 3D） |
| 规模 | ~17 个 GDScript，插件即产品 | 多子系统 + 严格五层门禁 |
| 文档 | README + drawio | `LAYERED_ARCHITECTURE` / `ROADMAP` / 单域契约 |

**结论：** hex_map 是「可跑通的教学型六边形编辑器」；本项目是「对齐 WC3 资产的分层地形管线」。能吸收的是编辑体验与分块重建手法，不是整体架构。

---

## 2. 相同点

1. **都是 Godot 4 地图编辑器**：笔刷改数据 → 重建 Mesh → 预览。
2. **Logic / UI 意图分离**：hex 的 `HexMapEditor` ↔ `HexMapEditorPanel`；本项目的 `MapEditor` ↔ `editor/ui/*`。
3. **笔划式 Undo**：hex 用 stroke 前后 diff；本项目用 `PaintStrokeCommand` + 顶点快照。
4. **Texture2DArray + 自定义 Shader 混地形**：两边都走这条路（本项目已有 `Wc3GroundTileCatalog`）。
5. **几何/规则常量集中**：hex 的 `HexMetrics` ↔ 本项目的 `Wc3Coords` + 各 Logic 常量。
6. **多层地表语义**：海拔 / 水 / 路（或崖坡）分管线，而不是一张高度图糊弄过去。

---

## 3. 相异点（决定「能抄什么、不能抄什么」）

| 维度 | hex_map | warcraft3 |
|------|---------|-----------|
| 网格 | 六边形 cell 中心 | **tilepoint 顶点** + 方形格 |
| 数据模型 | `HexCell` 对象数组 | `Wc3Heightfield` **SoA** |
| 分层 | 有意分层，但 Cell setter 直接 `chunk.refresh()` | **五层硬门禁**（Data/Catalog/Logic/Present/Editor） |
| 资产 | 项目内纹理/prefab | **WC3 离线解析 + Catalog 扫盘** |
| 子系统 | 河/路/墙/特征揉在 chunk 三角化里 | terrain → cliff → ramp → water **严格顺序** |
| 重建粒度 | **5×5 chunk**，帧内合并 | 分档全量（ground / cliff+water）；**脏区接口有、实现未做** |
| 产品形态 | `addons/` 可整包复制 | 独立编辑场景 + MapRoot 表现栈 |
| 测试 / 文档 | 几乎无 selftest，文档薄 | headless selftest + 契约文档重 |

核心差异：**hex 用「简单耦合换上手快」；本项目用「分层契约换可对齐 HiveWE / 可长期演进」。** 不宜把 Cell→直接 refresh 搬过来。

### hex_map 关键路径（便于对照）

| 类型 | 路径 |
|------|------|
| 插件入口 | `godot_hex_map/addons/hex_map_editor/plugin.gd` |
| 编辑逻辑 | `…/scripts/hex_map_editor.gd` |
| 编辑 UI | `…/ui/hex_map_editor_panel.gd` |
| 整图 / chunk | `…/prefabs/hex_grid.gd` · `hex_grid_chunk.gd` |
| 单格数据 | `…/scripts/hex_cell.gd` |
| 几何常量 | `…/scripts/hex_metrics.gd`（`CHUNK_SIZE_* = 5`） |
| 说明 | `godot_hex_map/README.md` |

---

## 4. 可吸收的经验（按对本项目价值排序）

### 4.1 Chunk 分块重建（最值得学）

hex：改 1 格 → 只 rebuild 本 chunk（+ 边界邻居 chunk），`_mesh_rebuild_queued` 帧内合并。

本项目：`dirty_min/max` 已预留，但仍常全图 rebuild。  
**可吸收：** Ground（乃至 cliff gap）按 tile 块（如 16×16 / 32×32）分 Mesh 节点；脏矩形映射到 chunk 集合再局部 `build`。正对 ROADMAP ⑤ / TODO「脏区局部重建」。

### 4.2 多 Mesh 层拆分（表现层）

hex 每 chunk：Terrain / River / Road / Water / WaterShore / Estuaries 分 mesh、分材质。

本项目已有 Layer 拆分（Terrain/Cliff/Ramp/Water），但 **Ground 内部**仍可借鉴「几何职责拆 Surface」：甲板、岸边、调试线不要和主地面抢同一 SurfaceTool 生命周期。

### 4.3 笔刷影响范围 → Undo / dirty 范围

hex 的问题：stroke 仍扫**全图** cell 做 diff。  
本项目的笔划快照已经更对（顶点级）。  
**可吸收的是思路强化：** diff / dirty 只覆盖笔刷半径 + 拓扑扩边（崖/坡常要扩 1～2 格），与 HiveWE「脏区再扩」一致，别退回全图快照。

### 4.4 Metrics 式「只读规则库」写法

`HexMetrics`：台阶/悬崖判定、噪声、chunk 尺寸一处集中，三角化只读它。

本项目可把散落的「Δlayer→FLAT/SLOPE/CLIFF」「坡宽 3 点」等进一步收成 **Logic 侧只读表**（别塞进 Layer），减少 Present 里魔法数。cliff/ramp 文档已在走这条路；hex 只是提醒「常量库要薄、要稳定」。

### 4.5 Logic 无 UI、Panel 只绑 signal

两边共同正确面。保持：**笔刷/命令不碰 Mesh，Panel 不写 flags**。不要学 hex 的 Cell 反向耦合。

### 4.6 插件化打包（后置、可选）

hex 把核心塞进 `addons/hex_map_editor/`，复制即用。  
本项目短期不必插件化；若以后要做「可嵌入的地图编辑模块」，再参考 addon 边界。现在优先分层迁完目录。

---

## 5. 明确不要从 hex_map 学的

| 反模式 | 原因 |
|--------|------|
| 数据 setter 直接触发 Mesh refresh | 破坏 Logic/Present 边界，自测困难 |
| 无 Document、无 Catalog | WC3 资产映射是本项目核心难点 |
| 单文件巨型三角化（~675 行 chunk） | 崖/坡/水会更炸；本项目已按层拆，继续 |
| 零自动化测试 + 薄文档 | 本项目契约/selftest 是优势，别弱化 |
| 运行时 Editor 与 Plugin 双实例路径 | 本项目已统一 MapRoot，保持单一表现栈 |

---

## 6. 对照本项目当前主线，怎么用

```text
hex 的 chunk 脏区思路  →  优先喂给 Ground 局部重建（ROADMAP ⑤）
hex 的多 mesh 层       →  参考 Present 拆 Surface，不改五层契约
hex 的插件形态         →  后置
hex 的 Cell 直刷 Mesh  →  拒绝
```

**一句话：** hex_map 证明「小地图编辑器可以很快做出手感」；warcraft3 要的是「对齐官方地形语义」。吸收 **chunk 脏区 + 多层 mesh + 笔刷扩边 dirty**，用本项目已有的 Document / Logic / Catalog 接住——不要倒退成 HexCell 式耦合。
