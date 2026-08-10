# Y_REFRESH — `change_doodad_heights` 等价行为

> **角色**：解释改地形时 doodad Y 自动刷新的语义 + 撤销行为 + 触发条件。
> **等价于 HivEWE** `change_doodad_heights`（terrain.cpp 内部）—— HivEWE 不暴露
> 完整源码，但行为是"按 heightfield 重算所有 doodad Y"。
> **本仓库**：`MapDoodadLayer.refresh_heights(heightfield)` 暴露为公开 API。
> 最后更新：2026-07-31

---

## 1. 一句话

**改地形（heightfield）后，所有 doodad 重新贴合新地形**（X/Z 不变，仅 Y 改）。

---

## 2. 触发条件

### 2.1 完整 build 时（自动）

```gdscript
# map_doodad_layer.gd line 80
func build(ctx: MapBuildContext) -> void:
    # ... 渲染 ...
    # 按 heightfield 重算所有 doodad Y（HivEWE change_doodad_heights 等价）。
    # JSON 原始 pos.z 被覆盖；后续改地形时 MapLoader.rebuild_* 会再刷一次。
    _apply_height_update(ctx.heightfield)
```

每次 `build` 末尾自动调 `_apply_height_update`。

### 2.2 增量 rebuild 时（自动）

```gdscript
# map_loader.gd line 212-214
# 改地形后刷 doodad Y（change_doodad_heights 等价；HF 走 undo 自动同步 doodad 状态）
if _doodads != null:
    _doodads.refresh_heights(ctx.heightfield)
```

`MapLoader.rebuild_terrain_only` + `rebuild_terrain_cliffs_water` 末尾自动调 `refresh_heights`。

### 2.3 何时**不**刷

- **撤销 doodad 添加/删除**：不刷（doodad 数据已重置）
- **撤销地形笔刷**：`MapDocument` 重置 heightfield → `refresh_heights` 自动刷回
- **改 doodad 自身**（v2）：走 `MapDoodadLayer.build` 重渲染

---

## 3. 核心算法

### 3.1 `_apply_height_update(heightfield)` 实现

```gdscript
# map_doodad_layer.gd line 145-160（推测）
func _apply_height_update(hf: Wc3Heightfield) -> void:
    for child in get_children():
        var d: Dictionary = child.get_meta("doodad_data")
        if d == null or d.is_empty():
            continue
        _apply_doodad_xform(child, d, false)  # use_hf=true 时重算 Y
```

**关键**：
- 每个 doodad 节点存了 `doodad_data` meta（line 128）—— 原始 JSON dict
- `_apply_doodad_xform` 重新算 position（含 hf Y 插值）+ angle + scale

### 3.2 高度插值

`doodad.position` (WC3 世界单位) → Godot 3D 位置：

```gdscript
# 1. 角点 (ix, iy) 由 position (x, y) 算（WC3 → tile index）
# 2. 4 角 hf.height 插值
var wx: float = d.position.x * Wc3Coords.WORLD_SCALE
var wz: float = -d.position.y * Wc3Coords.WORLD_SCALE  # WC3 Y → Godot -Z
var hf: Wc3Heightfield = ...
var wy: float = hf.interpolated_height(wx, wz)  # 4 角双线性插值
# 3. doodad scale.z / 2 当作"底部 → 中心"偏移
node.position = Vector3(wx, wy - d.scale.z * 0.5, wz)
```

**`hf.interpolated_height`** —— `Wc3Heightfield.interpolated_height`（[data API](../../data/PIPELINE.md)）：

```gdscript
func interpolated_height(wc3_x: float, wc3_y: float) -> float:
    var ixf: float = (wc3_x - center_offset.x) / tile_size
    var iyf: float = (wc3_y - center_offset.y) / tile_size
    var fx: float = ixf - floori(ixf)
    var fy: float = iyf - floori(iyf)
    return h00*(1-fx)*(1-fy) + h10*fx*(1-fy) + h01*(1-fx)*fy + h11*fx*fy
```

→ 4 角双线性插值，连续高度场。

### 3.3 角度转换

```gdscript
# WC3 angle (rad, 绕 Z) → Godot (rad, 绕 Y, -X mirror)
var angle_godot: float = -d.angle + PI
node.rotation = Vector3(0, angle_godot, 0)
```

`Wc3Coords.yaw_wc3_to_godot(angle_rad)` 提供等价转换（line 43-45）。

---

## 4. 撤销语义

### 4.1 关键洞察

**doodad 不需要存盘原 Y**——`heightfield` 已经在 undo 栈里，撤销时：
1. `MapDocument.heightfield` 回到 before 状态
2. 触发 `MapLoader.rebuild_*` 
3. 调 `_doodads.refresh_heights(ctx.heightfield)`
4. `_apply_height_update` 读 before 状态的 heightfield → 算回原 Y

**所以 doodad Y 跟随 heightfield 自动回滚**——无需 doodad 自身 undo。

### 4.2 撤销栈布局

```text
MapDocument (heightfield 持有 undo)
  ↓ heightfield 改 → 调 PaintStrokeCommand
  ↓ MapLoader.rebuild_* → refresh_heights → 重新算 Y
  ↓ User 按 Ctrl+Z → MapDocument.undo() → heightfield 回到 before
  ↓ MapLoader.rebuild_* → refresh_heights → Y 回到原值
```

### 4.3 撤销 vs 重做

| 操作 | 行为 |
|------|------|
| 改地形 → 撤销 | heightfield 回到 before → Y 回到原值 |
| 改地形 → 重做 | heightfield 回到 after → Y 跟到 after |
| 添加 doodad → 撤销 | `Wc3DoodadData.undo_remove` 移除实例（具体实现 v2）|
| 删除 doodad → 撤销 | `Wc3DoodadData.undo_add` 重加实例 |

---

## 5. HivEWE `change_doodad_heights` 对照

**HivEWE 源码**（推测，0.6+ 不可访问完整版）：
```cpp
void Terrain::change_doodad_heights() {
    for (auto& doodad : doodads) {
        doodad.position.z = corner_height[... interpolated ...];
    }
}
```

**老李等价**（`map_doodad_layer.gd`）：
```gdscript
func _apply_height_update(hf: Wc3Heightfield) -> void:
    for child in get_children():
        var d: Dictionary = child.get_meta("doodad_data")
        _apply_doodad_xform(child, d, use_hf=true)
```

**区别**：
- HivEWE 直接改 doodad 数据（存盘）—— 老李改**渲染节点**（JSON 不变）
- 优势：老李方式**无副作用**——重新 `build` 时 `_apply_height_update` 又刷一次，永远最新
- 代价：JSON 原始 pos.z 是**初始**值，不是当前值

详见 commit `365efab`。

---

## 6. 已知坑

1. **doodad 在 cliff 上** —— cliff 也有 heightfield，refresh 正常刷；doodad "贴"在 cliff 表面
2. **doodad 在水面上** —— `_apply_height_update` 用 hf.heights（**不含** water_heights）；doodad 贴**地表**而非水面（v2 项）
3. **doodad 在 ramp 上** —— ramp 不改 heightfield，doodad 仍贴 heightfield 算的 Y（v2 项：可考虑 ramp 偏移）
4. **doodad scale.z 影响 Y** —— `node.position.y = wy - d.scale.z * 0.5`（底部贴地）；scale 变了 Y 变（正确）

---

## 7. vibecoding 指导

### 7.1 改 `_apply_height_update`

- **改插值算法** —— `Wc3Heightfield.interpolated_height` 提供双线性；要改 4 角 / 16 角插值
- **改 doodad 底部对齐** —— `node.position.y = wy - d.scale.z * 0.5`；要改 中心对齐 / 顶部对齐
- **改 ramp 偏移** —— `apply_ramp_offset(node, ramp_data)` 在 `_apply_doodad_xform` 内调

### 7.2 改撤销语义

- **doodad 自身撤销** —— 加 `Wc3DoodadData` undo 类型（v2）
- **doodad 选区操作** —— 类似 heightfield 笔刷 snapshot

### 7.3 改水面贴合

- `hf.heights` 改 `hf.water_heights` —— doodad 浮水面
- 注意：`interpolated_water_height` 需新加（`Wc3Heightfield` 扩展）

---

## 8. 何时查这里

- **改 refresh 时机** → §2
- **改插值 / 对齐** → §3
- **改撤销语义** → §4
- **改 HivEWE 对照** → §5

---

## 9. 相关文档

- [README.md](README.md) —— MapDoodadLayer 架构
- [DOO_FORMAT.md](DOO_FORMAT.md) —— doodads.json schema
- [present/README.md §6](../presentation/README.md) —— 改地形 rebuild 流程
- [roadmap/ROADMAP.md §⑩ 应用高度](../../roadmap/ROADMAP.md) —— change_doodad_heights 完整设计
- [hivewe/UNDO.md](../hivewe/UNDO.md) —— HiveWE 撤销栈参考（行为对比）
