# doodad/ — 装饰物（Doodad）

> **角色**：`MapDoodadLayer` 把 `doodads.json` 里的 WC3 装饰物转成 Godot 3D 实例。
> 关键行为：**改地形时自动刷 Y**（`change_doodad_heights` 等价，commit `365efab`）。
> 最后更新：2026-08-08  
> 玩法侧可交互树（伐木/破坏）：见 [game/TREE_INTERACT.md](../game/TREE_INTERACT.md)。

---

## 1. 文件目录

| 文件 | 角色 |
|------|------|
| `README.md` | 本文件 —— MapDoodadLayer 架构 + 调用链 + 与 Logic 边界 |
| `Y_REFRESH.md` | `change_doodad_heights` 等价 + 撤销语义 + 触发条件 |
| `DOO_FORMAT.md` | W3E DOO 文件结构 + `doodads.json` schema 完整字段表 |

**对应的源码**：`scripts/map/presentation/layers/map_doodad_layer.gd`（169 行）

---

## 2. 架构总览

```text
MapLoader._load_all
  → MapDoodadLayer.build(ctx)
     ├── 按 (id, variation) 分组
     ├── 决定 GLB 路径（Wc3IdCatalog.converted_glb_path）
     ├── 决定 GLB 是否有动画（MapModelCache.glb_has_animation）
     ├── 渲染策略
     │     ├── ≥ multimesh_threshold 个且无动画 → MultiMesh
     │     ├── 有动画                  → 单 MeshInstance3D
     │     └── 无 GLB                 → MapPlaceholders.make_entity
     └── _apply_height_update(ctx.heightfield)  ← 刷 Y（HivEWE change_doodad_heights）

MapLoader.rebuild_terrain_only / rebuild_terrain_cliffs_water
  → _doodads.refresh_heights(ctx.heightfield)  ← 改地形后自动刷
```

---

## 3. 关键 API

### 3.1 `MapDoodadLayer.build(ctx)` — 完整重建

```gdscript
func build(ctx: MapBuildContext) -> void:
    _clear_children()
    var doodads: Array = ctx.doodads.get("doodads", [])
    if doodads.is_empty():
        return
    
    # 1. 按 (id, variation) 分组
    var groups: Dictionary = {}
    for d in doodads:
        var key := "%s#%d" % [str(d.get("id", "")), int(d.get("variation", 0))]
        groups[key] = groups.get(key, [])
        groups[key].append(d)
    
    # 2. 渲染策略
    for key_variant in groups.keys():
        var list: Array = groups[key_variant]
        var type_id: String = parts[0]
        var variation: int = parts[1]
        var glb := _catalog.converted_glb_path(type_id, variation) if try_load_glb else ""
        var has_anim := (not glb.is_empty()) and _cache.glb_has_animation(glb)
        
        if list.size() >= multimesh_threshold and not has_anim:
            _place_multimesh_group(type_id, variation, glb, list)  # MultiMesh
        elif not glb.is_empty():
            for d in list:
                _place_doodad_instance(type_id, glb, d, has_anim)  # 单实例
        else:
            for d in list:
                _place_doodad_placeholder(type_id, d)              # placeholder
    
    # 3. 刷 Y（change_doodad_heights 等价）
    _apply_height_update(ctx.heightfield)
```

**渲染策略**（行 39-71）：

| 条件 | 渲染方式 | 理由 |
|------|----------|------|
| 数量 ≥ `multimesh_threshold` 且无动画 | **MultiMesh** per (glb, variation, part) | 性能：单 draw call |
| 有 GLB 且**有动画** | **单 MeshInstance3D** per doodad | 避免共享动画状态 |
| 无 GLB | **placeholder**（`MapPlaceholders.make_entity`）| 缺资源退化 |

### 3.2 `MapDoodadLayer.refresh_heights(heightfield)` — 改地形后刷 Y

```gdscript
## 公开 API：按 heightfield 重算所有 doodad 的 Y（change_doodad_heights 等价）。
## 改地形笔刷时由 MapLoader.rebuild_* 调。doodad Y 重新贴合新地形。
## 撤销时：MapDocument.heightfield 回到 before 状态 → 再次 refresh → Y 自动回到原值。
func refresh_heights(hf: Wc3Heightfield) -> void:
    _apply_height_update(hf)
```

**详见 [Y_REFRESH.md](Y_REFRESH.md)**

### 3.3 关键成员

```gdscript
@export var try_load_glb: bool = true            # 试加载 GLB（否则全部 placeholder）
@export var multimesh_threshold: int = 8        # ≥ 这个数走 MultiMesh

var _catalog: Wc3IdCatalog                       # 注入
var _cache: MapModelCache                        # 注入
var last_placed: int = 0
var last_placeholder: int = 0
```

---

## 4. doodads.json schema（`DOO_FORMAT.md` 详情）

每个 doodad 字典字段（`tools/map-parse` 输出）：

| 字段 | 类型 | 含义 |
|------|------|------|
| `id` | String | W3E 4 字符 ID（如 `"WTst"`、`"ATtr"`）|
| `variation` | int | 0-15（变体 +16 = extended 集）|
| `position` | `{x, y, z}` | WC3 世界单位（**未缩放**，需 × 0.01 转到 Godot）|
| `angle` | float | 弧度（radians）|
| `angleDegrees` | float | 同 `angle` 的度数（冗余）|
| `scale` | `{x, y, z}` | 缩放（通常 1.0）|
| `flags` | int | bitmask：`2` = 不可破坏 / `4` = 不可选中等 |
| `life` | int | 0-100 |
| `itemTablePtr` | int | -1 = 无掉落表 |
| `droppedItemSets` | Array | 掉落表（空 = 无）|
| `creationNumber` | int | 唯一实例 ID（用于 scene 编辑选回）|

详见 [DOO_FORMAT.md](DOO_FORMAT.md)。

---

## 5. 与 Logic / Data 的边界

| 维度 | Present (MapDoodadLayer) | Logic / Data |
|------|--------------------------|---------------|
| 改 `doodads.json` | ❌ | ✅（Data 写）|
| 改 `heightfield` | ❌（只读 + 刷 Y 用）| ✅ |
| 调 GLB 资源 | ✅（`Wc3IdCatalog` + `MapModelCache`）| — |
| 调 `change_doodad_heights` 等价 | ✅（`refresh_heights`）| — |
| 写 placeholder mesh | ✅（`MapPlaceholders`）| — |
| 写 doo file 格式 | ❌ | ✅（`tools/map-parse`）|

**核心**：present 只**渲染** doodad + 刷 Y；doodads 数据由 `tools/map-parse` 从 `war3map.doo` 解析。

---

## 6. 调用链

```text
MapLoader._load_all (L259+)
  → MapDoodadLayer.build(ctx)
     → _place_multimesh_group / _place_doodad_instance / _place_doodad_placeholder
     → _apply_height_update（line 80）

MapLoader.rebuild_terrain_only (L186+)
MapLoader.rebuild_terrain_cliffs_water (L220+)
  → _doodads.refresh_heights(ctx.heightfield)  (line 214)
     → _apply_height_update
```

**注**：`rebuild_*` 路径**不**重建 doodad GLB 实例——只刷 Y。如果 doodad 数据本身变了（add/remove）走完整 build。

---

## 7. vibecoding 指导

### 7.1 改 MapDoodadLayer 渲染策略

1. **先看 [LAYERS.md §5](../presentation/LAYERS.md)** —— 7 个 layer 对照
2. **改 GLB / placeholder 选择** —— 改 `try_load_glb` 或 `multimesh_threshold` 即可，逻辑在 `build` line 39-71
3. **改 placeholder 形状** —— `MapPlaceholders.make_entity(type_id, -1, false)` 返回基础占位 mesh

### 7.2 加新 doodad 字段渲染

1. **改 `_apply_doodad_xform`** —— 写 position/angle/scale
2. **改 `_doodad_transform`** —— 内部 transform 构造（含 heightfield Y）
3. **新字段**：doodads.json schema + 改 `tools/map-parse/src/parsers/doo-doodads.js` + 本地 selftest

### 7.3 改 Y_REFRESH 行为

详见 [Y_REFRESH.md](Y_REFRESH.md) 的 3 步流程 + 撤销语义。

### 7.4 改 doodad 动画

- `MapModelCache.autoplay_stand(node)` —— 调模型 `Stand` 动画
- `_cache.glb_has_animation(glb)` —— 是否有动画
- 有动画 → 单实例（避免 MultiMesh 共享状态）

### 7.5 性能调优

- `multimesh_threshold` 默认 8 —— 性能/实例化 平衡点
- 大量同 (id, variation) doodad（如树木）→ MultiMesh 性能优
- 动画 doodad（营地、火焰）→ 单实例（性能次优但正确）

---

## 8. 已知坑

1. **`refresh_heights` 仅改 Y** —— X/Z 不变；如果 doodad 被刷掉（飞起来）说明 heightfield 不对（不是 doodad 自身）
2. **JSON 原始 pos.z 被覆盖** —— `refresh_heights` 改 Y 后 JSON 还保留旧 pos.z；下次 build 时**重新刷**（不存盘覆盖）
3. **撤销时** —— `MapDocument.heightfield` 回到 before → `refresh_heights` 再调 → Y 回到原值（**无需保存 doodad 原 Y**）
4. **placeholder scale × 0.8** —— `MapPlaceholders.make_entity` 后续 `.scale *= 0.8`（行 137）—— 历史决策，不改
5. **doodad 不读 ctx.ramp** —— doodad 摆放独立于 ramp（如果 doodad 在 ramp 上，Y 仍按 heightfield 算）

---

## 9. 何时查这里

- **改 doodad 渲染** → §3 + `map_doodad_layer.gd`
- **改 Y_REFRESH 行为** → [Y_REFRESH.md](Y_REFRESH.md)
- **改 doodads.json schema** → [DOO_FORMAT.md](DOO_FORMAT.md)
- **加新 doodad 字段** → [DOO_FORMAT.md](DOO_FORMAT.md) + `tools/map-parse/`
- **改 doodad 动画** → §7.4 + `MapModelCache`

---

## 10. 相关文档

- [present/README.md](../presentation/README.md) —— present 总览
- [present/LAYERS.md §5](../presentation/LAYERS.md) —— MapDoodadLayer 关键 API
- [hivewe/TERRAIN_MESH.md](../hivewe/TERRAIN_MESH.md) —— heightfield 体系
<<<<<<< HEAD:docs/design/doodad/README.md
- [data/PIPELINE.md](../../data/PIPELINE.md) —— `war3map.doo` → `doodads.json` 解析流水线
- [data/WC3_ASSET_PATHS.md](../../data/WC3_ASSET_PATHS.md) —— `Units/<id>/<id>.mdx` 路径
- [roadmap/ROADMAP.md §⑩ 应用高度](../../roadmap/ROADMAP.md) —— change_doodad_heights 完整设计
=======
- [data/PIPELINE.md](../data/PIPELINE.md) —— `war3map.doo` → `doodads.json` 解析流水线
- [data/WC3_ASSET_PATHS.md](../data/WC3_ASSET_PATHS.md) —— `Units/<id>/<id>.mdx` 路径
- [roadmap/ROADMAP.md §⑩ 应用高度](../roadmap/ROADMAP.md) —— change_doodad_heights 完整设计
- [game/TREE_INTERACT.md](../game/TREE_INTERACT.md) —— **可交互树**：MM→Node promote、扣血入口、防闪烁（玩法侧）
- [game/SELECTION_RINGS.md](../game/SELECTION_RINGS.md) —— 树/金矿黄环
>>>>>>> master:docs/doodad/README.md
