# 悬崖（Cliff）

> 编辑器直崖数据、选型、异种策略与回归。斜坡见 [RAMP_WE.md](../ramp/RAMP_WE.md)（WE 思路；实现待重做）。  
> **分层重构计划**见 [CLIFF_REFACTOR.md](CLIFF_REFACTOR.md)。  
> HiveWE 路径见 [`.cursor/rules/hivewe-cliff-reference.mdc`](../../../.cursor/rules/hivewe-cliff-reference.mdc)。

## 1. 数据模型

| 字段 | 形状 | 含义 |
|------|------|------|
| `layerHeights` | tilepoint | 悬崖层 0–14；最终高度 ≈ ground×128 + (layer−2)×128 |
| `heights` | tilepoint | WC3 最终高度（含层步进） |
| `cliffTextures` | tilepoint | `cliffTilesets` 下标（15→1） |
| `cliffVariations` | tilepoint | 变体，再按 TAG clamp |
| `cliffTilesets` | 地图级 | 如 `["CLdi","CLgr"]` |
| `groundTextures` | tilepoint | 地表；崖旁可被 `cliff.groundTile` 覆盖 |

**地表格** = 四角 `(ix,iy),(ix+1,iy),(ix,iy+1),(ix+1,iy+1)`。四角层高不全相等 → 直崖格。

## 2. TAG 与叠段

角序 **BL → TL → TR → BR**，相对本段 `base_layer` 映射为 `A/B/C`（0/1/2）。

- **跨度 ≤2**：只放 **一片**完整 TAG（含 `AABC`「底两边顶一边」）。禁止再按 `min_up` 叠第二段。
- **跨度 >2**（旧图/异常）：每次剥满 C（+2），再收尾剩余 ≤2。

选型表：`Wc3CliffCatalog` → `Doodads/Terrain/Cliffs/Cliffs{TAG}{var}.glb`。

**Variation（岩壁）**：对齐 HiveWE——每格用 **BL 角** `cliffVariations`（0 也是合法变体）。笔刷写入 **0–7 真随机**；挂模按 TAG `clamp`。**同墙允许不同变体**。勿用「ix 空间哈希」当主路径（两变体时易成 010101 条纹）。

**groundTile**：直崖格四角写入/强制 `cliff.groundTile`（对齐 viewer `cornerTexture`）。台心不贴直崖则保持原地表；台缘/崖脚与泥土靠四角 bitmask 过渡。

## 3. 笔刷拓扑（蛋糕）

`MapDocument.paint_cliff_corner`：

1. 改中心点层高  
2. `_propagate_cliff_adjacency`：正交邻接差 ≤2；升则抬低邻到 `high−2`  
3. `_enforce_tile_spans_at`：单格四角 `max−min ≤2`（含对角）  
4. `_sync_cliff_corner_textures`：策略 B 贴图同步  

硬常量：`LAYER_MIN=0`、`LAYER_MAX=14`、`MAX_CLIFF_ADJ_DELTA=2`。

## 4. 异种悬崖：策略 B（折中）

| 规则 | 行为 |
|------|------|
| **接触同化** | 种子 = `touched` ∪ 落笔 2×2；凡「至少含一个种子角」的直崖格，**四角**写成当前笔刷 `ctype` + `groundTile` |
| **远处隔离** | 不按 AABB 扫无关旧崖；未触及结构的类型/地表不动 |
| **高度仍可改形** | 蛋糕外扩碰到旧崖时可能改层高甚至抹平（与 WE 一致），这是高度传播，不是贴图误伤 |

**为何不能混角：** 同一直崖格四角若 `CLdi`/`CLgr` 混用，`_corner_texture` 会按邻崖强制 `groundTile`，Mesh 又按角选岩壁 → 台面渗色、岩壁错贴。接触区整格同化可避免。

对照：完整 WE 会在更大 `updated_area` 内统一 `cliff_texture`；我们收窄到「真正触及」，减少远程误伤。

## 5. 层高上限

| 层级 | 取值 | 说明 |
|------|------|------|
| 硬上限 | **0–14** | 对齐 W3E；编辑器不另加更严硬帽 |
| 相对跨度 | 邻接/单格 **≤2** | 官方模型仅 A/B/C |
| 目视建议 | 单次结构相对抬升 **≤4～6 层** | 叠段可继续堆，岩壁重复感强；仅文档提醒，无 UI 拦截 |

## 6. 工具面板图标

悬崖类型按钮使用 Cliffs.slk 的 **`groundTile`** 地表 atlas 首格（泥土/草地），与原版 WE 一致；缺省时才回退裁崖壁 PNG。

## 7. 回归

```text
godot --headless --path . -s res://tests/cliff/selftest_cliff_variants.gd
godot --headless --path . -s res://tests/cliff/selftest_cliff_level3.gd
godot --headless --path . -s res://tests/cliff/selftest_cliff_ground_tex.gd
```

`selftest_cliff_variants.gd` 覆盖：TAG/GLB、AABC 单片、叠段、台面+柱、远程隔离、异种接触同化、直墙 variation 按格打散。

## 8. 相关文件

| 文件 | 职责 |
|------|------|
| `scripts/definitions/terrain_art/cliff_type_def.gd` | CliffTypes.slk → Resource |
| `scripts/map/catalog/wc3_cliff_catalog.gd` | 直崖 Catalog（贴图 / groundTile / modelDir） |
| `scripts/map/catalog/wc3_terrain_tile_catalog.gd` | 地表 Catalog（仅 Terrain） |
| `editor/scripts/map_document.gd` | 笔刷、蛋糕、策略 B 同步 |
| `scripts/map/logic/cliff/wc3_cliff_logic.gd` | TAG / 叠段 / placements / 同步 |
| `scripts/map/presentation/cliff/wc3_cliff_builder.gd` | 直崖 MultiMesh 实例 |
| `scripts/map/presentation/layers/map_terrain_layer.gd` | 挖洞、`corner_texture` |
| `editor/ui/tool_palette_window.gd` | 类型图标 |
| [EDITOR.md](../editor/EDITOR.md) §5.3 | 编辑器流程 |
| [CLIFF_REFACTOR.md](CLIFF_REFACTOR.md) | 分层重构里程碑 |
