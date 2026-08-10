# unit/ HivEWE 对齐路线图

> **角色**：记录 `MapUnitLayer` 当前与 HivEWE 的差异、已对齐项、待重构项。
> **HivEWE 是行为参考**（来自 `D:\GameMaker\HiveWE\src\brush\unit_brush.cpp` +
> `src\base\units.ixx`）；本仓库**目标**是"复刻经典 WE，扩展锦上添花"
> —— 经典 WE 是原作，HivEWE 是 0.6+ 复刻参考。
> **本仓库主目标**（按老李）："实现过程可以不同但结果应该与游戏原作一致"。
> **Doodad vs Unit 关键差异**：
> - Unit **有**玩家色（doodad 无）
> - Unit 必须单 instance（复杂骨骼，**不**走 MultiMesh）
> - Unit 数据字段**多 1 倍**（生命/魔法/玩家/技能等）
> 最后更新：2026-08-01

---

## 1. 现状总览

| 维度 | 当前状态 | HivEWE 行为 | 待对齐？ |
|------|---------|-------------|---------|
| 模型加载 | `.glb`（m2g 转换 .mdx）| `.mdx` + SkinnedMesh | ✅ 等价 |
| 数据格式 | `units.json`（typeId / variation / position / owner / angle / scale）| `war3mapUnits.doo` 二进制 + 17 字段 | ❌ **缺 11 字段**（见 §3.1）|
| 渲染策略 | **每 unit 一 Node3D**（必须单 instance）| 每 unit 一 SkinnedMesh | ✅ 等价（多 instance 成本可接受）|
| 位置/旋转 | `Transform3D` + `yaw_wc3_to_godot` | `glm::vec3 + angle` | ✅ |
| Y 重算 | **缺**（doodad 有，unit **无**）| `move_height` + 地形插值 | ❌ 待补（见 §3.5）|
| 玩家色（owner_id）| `owner` 字段 | `player` + `color (r/g/b)` | ⚠️ **缺 custom_color + 颜色** |
| Skin variation | `typeId + variation` | `id + skin_id` 字段（1.32+）| ❌ 缺 skin_id 字段 |
| 生命值 / 魔法值 | **缺** | `hp / mp` | ❌ 待补 |
| Hero level / exp | **缺** | `hero level` + `exp` | ❌ 待补 |
| Inventory / items | **缺** | `inventory_slots[]` | ❌ 待补 |
| Random variation | **缺** | `random_type + random[]` | ❌ 待补 |
| Waygate 关联 | **缺** | `waygate` | ❌ 待补 |
| Unit flags | **缺** | `flags` (8-bit) | ❌ 待补 |
| Placeholder | `MapPlaceholders.make_entity` | 简化 | ✅ |
| 选中/拖动/删除 brush | **缺** | `UnitBrush::click` + clipboard | ❌ 待补（见 §3.2）|
| 玩家色 UI 切换 | **缺** | palette picker | ❌ 待补（见 §3.3）|
| Animation 同步/异步 | autoplay_stand（单 instance）| SkinnedMesh + Skeleton | ✅ 路径不同结果一致 |

---

## 2. 已对齐项

### 2.1 渲染：每 unit 一 Node3D

`MapUnitLayer._make_unit_node(type_id, variation, owner_id)`：
- 优先 `_cache.instance_glb(glb)` → `add_child` 单 instance
- Fallback `MapPlaceholders.make_entity(type_id, owner_id, true)`
- GLB 加载后调 `_cache.autoplay_stand(node)` 播放站立动画

**与 HivEWE 路径等价**（HivEWE 用 SkinnedMesh 包装 MDX，我们用 Node3D 包装 GLB；
都是每 unit 一 instance，**不**走 MultiMesh —— unit 复杂骨骼强制单 instance）。

### 2.2 位置/旋转/缩放

`Transform3D` + `yaw_wc3_to_godot(angle)`（同 doodad），scale (x,y,z) 应用到 node。

### 2.3 玩家色（owner 字段）

`MapUnitLayer` 读 `u.get("owner", 12)`（默认玩家 12 = 中立），传给
`MapPlaceholders.make_entity(type_id, owner_id, true)` —— placeholder 按 owner
染色。

**当前**：
- ✅ 读 owner 字段
- ⚠️ 传给 placeholder 但**没**传给 GLB instance 的材质（GLB 无染色逻辑）

### 2.4 Placeholder fallback

GLB 缺失时调 `MapPlaceholders.make_entity` —— 占位带 owner 染色，编辑器仍可见。

---

## 3. 待对齐项

### 3.1 `units.json` schema 字段补齐

**位置**：`docs/unit/SCHEMA.md`（**待建**，见 [roadmap/TODO.md 死链清单](../../roadmap/TODO.md)）+ `MapUnitLayer` 字段读取

**HivEWE Unit 完整字段**（`units.ixx:32-67`）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | unit type id（已有 → `typeId`）|
| `variation` | int | 变体（已有）|
| `position` | vec3 | 位置（已有）|
| `angle` | float | 旋转（已有）|
| `scale` | vec3 | 缩放（已有）|
| `skin_id` | string | 1.32+ 独立 skin（**缺**）|
| `flags` | uint8 | 8-bit 状态（**缺**）|
| `player` | int | 玩家（已有 → `owner`）|
| `color` | vec3 | 玩家色 r/g/b（**缺**，placeholder 有）|
| `hitpoints` | int | 生命值（**缺**）|
| `mana` | int | 魔法值（**缺**）|
| `hero_level` | int | 英雄等级（**缺**，0 = 非英雄）|
| `hero_exp` | int | 英雄经验（**缺**）|
| `inventory_slots` | bytes | 物品栏（**缺**）|
| `custom_color` | uint32 | 自定义玩家色 ABGR（**缺**）|
| `waygate` | int | waygate 关联（**缺**）|
| `creation_number` | uint32 | 创建序号（**缺**）|
| `random_type` / `random[]` | int / bytes | 随机 variation（**缺**）|
| `move_height` | float | 悬空高度（**缺**，地形 Y 偏移）|

**待补**：先写 `docs/unit/SCHEMA.md` 把所有字段固化（见 [roadmap/TODO.md 死链清单](../../roadmap/TODO.md)），**再**改 `MapUnitLayer`
读（按 ramp 路线图先例"docs 先行"）。

### 3.2 unit_brush（编辑器 paint）

**位置**：`editor/scripts/tools/unit_brush.gd`（**缺**）

**HivEWE**：`UnitBrush`（`unit_brush.cpp`）
- click → `add_unit(id, position)`
- clipboard（Ctrl+C 复制 → Ctrl+V 粘贴整组单位）
- Shift+R 旋转 90°
- 选中 → 拖动
- Delete 删除

**我们**：地图打开后 unit **只读**。

**待补**：
- `editor/scripts/tools/unit_brush.gd` 新建
- 选中（点击 → 高亮 + 显示 owner 染色 + 玩家色 picker）
- 拖动 / 旋转 / 删除
- clipboard 复制粘贴（经典 WE 高级功能）
- `MapDocument` 加 `add_unit(d)` / `remove_unit(idx)` / `move_unit(idx, x, y)` / `set_owner(idx, owner_id)` / `set_skin(idx, skin_id)` API

### 3.3 玩家色（owner 染色）→ GLB material

**位置**：`MapUnitLayer._make_unit_node` + GLB 转换器

**HivEWE**：`color.r/g/b` 字段（按 `units_slk.red/green/blue` 默认染色）+ `custom_color`
（玩家自定义）→ 写入 GLB material 的 `BaseMaterial3D.albedo_color`。

**我们**：
- ⚠️ placeholder 接受 owner_id 染色
- ⚠️ GLB instance **没**染色（GLB 内部用 baked color）

**待补**：
- GLB 转换器（m2g 工具）支持 `albedo_color` tint
- `MapUnitLayer` 读 `color` 字段 → 调 `BaseMaterial3D.albedo_color = tint`
- 玩家 palette picker UI（编辑器）

### 3.4 Skin 独立字段（1.32+）

**位置**：`units.json` schema + `MapUnitLayer`

**HivEWE**：1.32+ 起每个 unit 有独立 `skin_id`，与 `id` 解耦（同一 unit 用不同 skin）。

**我们**：用 `typeId + variation` 桶代替，**没有**独立 skin 字段。

**待补**（**不**紧急，1.32+ 之前不存在）：
- `units.json` 加可选 `skinId` 字段
- `MapUnitLayer` 读 skin 选 GLB（fallback 到 variation）

### 3.5 Y 重算（地形变化后自动刷）

**位置**：`MapUnitLayer.refresh_heights(hf)`（**缺**） + 地形 rebuild 流程

**HivEWE**：`move_height` + 地形插值（units.ixx:78-93 `final_position = position + move_height + 地形高度`）。

**我们**：
- doodad 有 `refresh_heights`（commit `365efab`）
- unit **没**对应实现 —— 改地形后 unit 浮空 / 陷地

**待补**：
- `MapUnitLayer.refresh_heights(hf)` —— 遍历 children，按 metadata 里的 (x,y) 调 `interpolated_height` 重设 `position.y`
- `MapLoader.rebuild_*` 调 `_units.refresh_heights(ctx.heightfield)`
- 撤销语义：同 doodad（heightfield snapshot）

### 3.6 Animation 多状态（stand / walk / attack / death）

**位置**：`_cache.autoplay_stand` + GLB 内部 animation

**HivEWE**：SkinnedMesh + Skeleton，多状态通过 `AnimationPlayer` 切换。

**我们**：`autoplay_stand` 只播 stand —— 选中/拖动/删除时**无**反馈动画。

**待补**（**锦上添花**，**不**关键）：
- 编辑器选中 → 播 `stand` 或 `selection` 动画
- 拖动 → 播 `walk` 动画
- hover → 改 `stand` 动画速度

### 3.7 Pathing 集成（unit 阻挡）

**位置**：unit 数据层 + pathing 模块

**HivEWE**：unit 自动写入 pathing（`Units::add_unit` 调 `PathingMap::blit_pathing_texture`），
selectable 单位阻挡 pathing。

**我们**：pathing 模块**完全没**接（之前 summary 提"pathing 留到后面单独实现"）。

**待补**（**延后**，等 pathing 模块）：
- 读 unit.pathing（每个 type 自带 mask）→ 写入 `Wc3PathingMap`
- selectable / unselectable 区分

---

## 4. 测试状态

### 4.1 当前 selftest

| 文件 | 状态 |
|------|------|
| `selftest_unit_data.gd`（integration）| **缺**（无 unit integration test）|
| `selftest_unit_logic.gd` | **缺**（unit 没 Logic 层）|
| `selftest_unit_present.gd` | **缺**（验收 path）|

**当前 unit 没有任何 selftest**——D2 brush 落地后才有 paint 测试。

### 4.2 Lost Temple unit 数据

- `assets/map-parsed/losttemple/units.json` 加载 OK
- unit 数（待统计）
- 主要种类（待分类）

---

## 5. 决策点（待老李手测经典 WE 后填）

| 决策 | 描述 |
|------|------|
| **U1** | unit 选中走 AABB（包围盒）vs 单 mesh pick？经典 WE 走 AABB |
| **U2** | unit 拖动是否限制在 heightfield 内？经典 WE 是；HivEWE 是 |
| **U3** | unit 玩家色是 12 玩家 palette 还是 24-bit custom？两个都支持，UI 怎么切？ |
| **U4** | unit 选中是否播动画反馈？经典 WE 是；锦上添花可加 |
| **U5** | clipboard 复制粘贴是否实现？经典 WE 有；HivEWE 有；**非**关键 |
| **U6** | hero level / inventory / items 是否在编辑器内可改？经典 WE 不改（trigger 改）；**不**做 |

---

## 6. 实施步骤

按 5 节点计划：

### 6.1 N1（已完成）：写路线图

→ 当前文件 `docs/unit/HIVEWE_ALIGN.md`

### 6.2 N2：`SCHEMA.md` + `MapUnitLayer` 字段读取 —— 2-3 commit

- `docs/unit/SCHEMA.md` 新建 —— 17 字段完整固化（仿 DOO_FORMAT.md）
- `MapUnitLayer.build` 读 17 字段（start with skin/flags/player/color/hp/mp；其他可选）
- `MapUnitLayer.refresh_heights(hf)` —— 改地形后自动刷 unit Y
- `MapLoader.rebuild_*` 调 `_units.refresh_heights(ctx.heightfield)`

### 6.3 N3：unit_brush（编辑器 paint）—— 1-2 commit

- `editor/scripts/tools/unit_brush.gd` 新建
- 选中 / 拖动 / 旋转 90° / 删除
- clipboard（**可**推迟到 N4+）
- `MapDocument` 加 5+ unit API（add/remove/move/set_owner/set_skin）

### 6.4 N4：玩家色 → GLB tint —— 1-2 commit

- m2g 工具支持 `albedo_color` tint 字段
- `MapUnitLayer._make_unit_node` 读 color → `BaseMaterial3D.albedo_color`
- 玩家 palette picker UI（编辑器）

### 6.5 N5：selftest_unit + 集成测试 —— 1-2 commit

- `tests/unit/selftest_unit.gd` —— brush paint / move / rotate / delete
- `tests/integration/selftest_units.gd`（新建）
- `tests/unit/selftest_unit_present.gd` —— 染色 + Y 重算

每个 N 节点完成后报告老李 → 等 OK 再进下一节点。

---

## 7. 源码索引

| 主题 | HivEWE 文件 | HivEWE 符号 | 本仓库符号 |
|------|------------|------------|------------|
| 单位数据 | `base/units.ixx` | `class Unit` (17 字段) | `units.json` schema（**缺 11 字段**）|
| 单位模型 | `brush/unit_brush.cpp` | `UnitBrush::get_mesh` | `MapModelCache.instance_glb` |
| 选中 / 拖动 | `brush/unit_brush.cpp` | `UnitBrush::click` | **缺**（N3 待补）|
| 玩家色 | `units.ixx:78-93` | `color.r/g/b` | placeholder 有；GLB tint **缺**（N4 待补）|
| Skin | `units.ixx:35` | `skin_id` (1.32+) | **缺**（N2 延后）|
| 生命 / 魔法 | `units.ixx:148-152` | `hitpoints / mana` | **缺**（N2 字段）|
| 英雄 | `units.ixx:154-162` | `hero_level / exp` | **缺**（N2 字段）|
| 物品 | `units.ixx:170-200` | `inventory_slots` | **缺**（N2 字段）|
| Random | `units.ixx:170-200` | `random_type + random[]` | **缺**（N2 字段）|
| Waygate | `units.ixx:212` | `waygate` | **缺**（N2 字段）|
| Y 重算 | `units.ixx:93` | `move_height + 地形` | **缺**（N2）|
| Pathing | `units.ixx` + pathing | per-unit blit | **缺**（N7 延后）|
| 渲染 | `skinned_mesh.ixx` | SkinnedMesh | Node3D + GLB instance |
| Placeholder | `unit_brush.cpp` | 简化 | `MapPlaceholders.make_entity` |

---

## 8. 相关文档

- [../doodad/HIVEWE_ALIGN.md](../doodad/HIVEWE_ALIGN.md) —— 装饰物对齐路线图（doodad 与 unit 大量共用）
- [../doodad/README.md](../doodad/README.md) —— MapDoodadLayer 架构参考
- [../hivewe/OPERATORS.md §6.4](../hivewe/OPERATORS.md) —— HivEWE unit 操作符
- [../present/Z_ORDER.md §3](../presentation/Z_ORDER.md) —— Unit Z 顺序（在 doodad 之上 / cliff 之下）
- [../shader/](../shader/) —— shader 文档（INSTANCE_CUSTOM 用法）
- 待建：[SCHEMA.md](../../roadmap/TODO.md) —— 17 字段完整 schema（待建，N2 落地；死链清单已记）

---

最后更新：2026-08-01
