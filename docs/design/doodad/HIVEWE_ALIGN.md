# doodad/ HivEWE 对齐路线图

> **角色**：记录 `MapDoodadLayer` 当前与 HivEWE 的差异、已对齐项、待重构项。
> **HivEWE 是行为参考**（来自 `D:\GameMaker\HiveWE\src\brush\doodad_brush.cpp` +
> `src\base\doodads.ixx`）；本仓库**目标**是"复刻经典 WE，扩展锦上添花"
> —— 经典 WE 是原作，HivEWE 是 0.6+ 复刻参考。
> **本仓库主目标**（按老李）："实现过程可以不同但结果应该与游戏原作一致"——意味着
> 已对齐项按"结果一致"标准，待对齐项按"原作能否 paint"判定。
> 最后更新：2026-08-01

---

## 1. 现状总览

| 维度 | 当前状态 | HivEWE 行为 | 待对齐？ |
|------|---------|-------------|---------|
| 模型加载 | `.glb`（m2g 转换 .mdx）| `.mdx`（WC3 原生）| ✅ 结果一致 |
| 数据格式 | `doodads.json`（id / variation / position / angle / scale / life）| `war3map.doo` 二进制 | ✅ schema 1:1 镜像（[DOO_FORMAT.md](DOO_FORMAT.md)）|
| 渲染策略 | `multimesh_threshold=8` 阈值 + `has_anim` 二分 | 每 doodad 一 SkinnedMesh | ✅ 路径不同（见 §3.2）|
| 位置/旋转 | `Transform3D` + `yaw_wc3_to_godot` | `glm::vec3 position + angle` | ✅ 等价 |
| Y 重算 | `_apply_height_update(hf)` 改地形后自动刷 | `change_doodad_heights` | ✅ 等价（[Y_REFRESH.md](Y_REFRESH.md)）|
| Pathing mask | **缺**（doodad 内嵌 pathing 未接）| `doodad.pathing` per-doodad | ❌ 延后（等 pathing 模块）|
| Skin variation | `id#variation` 分桶 | `id + skin_id` 字段 | ⚠️ variation 覆盖 skin，但缺独立 skin 字段 |
| 玩家色 | doodad **无** | doodad **无** | ✅ |
| Placeholder | `MapPlaceholders.make_entity` | 简化 | ✅ |
| 选中/拖动 brush | 无预览时点选 + 绿色地面环；拖动/Delete/`[` `]` | `DoodadBrush` | ✅ |
| 旋转 90° 离散 | 任意角度 | 离散 90/180/270 | ⚠️ 我们更灵活 |

---

## 2. 已对齐项

### 2.1 数据 schema 1:1 镜像

`doodads.json` 字段（id / variation / position.x/y/z / angle / scale.x/y/z /
life）—— 与 `war3map.doo` 字段 1:1 对应（[DOO_FORMAT.md](DOO_FORMAT.md)）。

### 2.2 Y 重算（change_doodad_heights 等价）

`refresh_heights(hf)` + `_apply_height_update()` 改地形后自动刷 doodad Y，
撤销语义通过 heightfield snapshot 实现（[Y_REFRESH.md](Y_REFRESH.md)）。

### 2.3 渲染策略（multimesh + has_anim 二分）

`MapDoodadLayer.build` 决策：
- 没动画 + ≥ 8 个同 GLB → **MultiMesh**（1 draw call，几百棵树 60fps）
- 有动画 → **单 instance**（`_cache.autoplay_stand`）
- < 8 个 → 单 instance（小批量不值得 batch）

**与 HivEWE 路径不同**（HivEWE 每 doodad 一 SkinnedMesh），**结果一致**。

### 2.4 模型 .glb 转换

m2g 工具把 WC3 `.mdx` 转为 Godot `.glb`——`MapModelCache.instance_glb` 直接
`add_child`。**结果一致**（mdx ↔ glb 转换无损）。

---

## 3. 待对齐项

### 3.1 编辑器 brush（选中 / 拖动 / 删除 / 旋转 90°）

**位置**：`editor/scripts/tools/doodad_brush.gd`（✅ 一期放置）

**面板筛选（一期）**：✅ …  
**放置笔刷（一期）**：✅ LMB 放置 / 尺寸形状 / 随机样式 / Inspect 朝向 / Ctrl+Z。

**二期编辑**：✅ 幽灵预览；点选 / 拖动 / Delete；`[` `]` / R 旋转 45°。

**朝向 UX（相对经典 WE）**：预览窗拖拽 = **环视相机**（不写地图）；**放置朝向**独立控件（输入框 + ↺↻）+ 快捷键；地图幽灵显示放置朝向。

**Click Helper（粉黑棋盘）**：✅ 读 SLK `useClickHelper` / `selSize`；空壳 GLB（气泡等 PE2-only）与旗帜类特效挂洋红-黑立方体；蝙蝠等有网格者也挂 helper（对齐 WE）。Stand 动画随机相位，避免齐刷刷。空模另加简易上升粒子近似特效。

**ParticleEmitter2**：✅ `convert-mdx` 写出 `*.pe2.json`；装饰层 / Inspect / 幽灵预览挂 `GPUParticles3D`（火盆火焰等）。MultiMesh 组对有 PE2 的类型关闭。

**HivEWE**：`DoodadBrush`（`src/brush/doodad_brush.cpp`）
- click → `add_doodad(id, position, angle, scale, variation, life)`
- pathing 自动避让（doodad 内嵌 pathing mask）
- 旋转 90° 离散（Shift+R）
- 选中 → 拖动 → 删除（Delete / Backspace）

**待补**：
- MultiMesh 组内精确删除 / 更新
- pathing 自动避让
- 玩家色切换（**仅 unit**，doodad 不接）

### 3.2 大量 mesh 渲染策略（同步动画 / 错相位）

**位置**：`MapDoodadLayer._place_multimesh_group` + shader 端

**HivEWE**：每 doodad 一 SkinnedMesh（**无** MultiMesh），动画 CPU 端推。

**我们**：
- **同步**动画（shader 推 TIME，所有 instance 同步）→ MultiMesh ✅
- **错相位**摇曳（每棵树不同步）→ 用 `INSTANCE_CUSTOM` 推 phase + shader 错相
- **per-instance 复杂动画**（不同帧）→ **不**支持，必须单 instance

**待补**：
- m2g 工具加 `_sync_anim` 标志（GLB 标记"同步动画可用 MultiMesh"）
- 树/草 shader 加 `vertex() { VERTEX.x += sin(TIME + world_pos.x * 0.01 + INSTANCE_CUSTOM.x) * 0.5 }`
- 几百棵树典型 1 draw call

### 3.3 Skin 独立字段

**位置**：`doodads.json` schema + `MapDoodadLayer`

**HivEWE**：每个 doodad 有 `skin_id` 字段（WC3 1.32+ 起），与 `id` 解耦
—— 同 unit 用不同 skin。

**我们**：用 `id#variation` 桶代替，但**没有**独立的 skin 字段。
WC3 数据里 skin 出现概率低（doodad 通常不用 skin），**非关键**。

**待补**（**不**紧急）：
- `doodads.json` 加可选 `skinId` 字段
- `MapDoodadLayer` 读 skin 选 GLB（fallback 到 variation）

### 3.4 Pathing 集成（doodad 内嵌 pathing）

**位置**：doodad 数据层 + pathing 模块

**HivEWE**：`doodad.pathing` 字段是 doodad 自带的寻路 mask；brush 放 doodad
时**自动**避免与现有 pathing 冲突。

**我们**：pathing 模块**完全没**接（之前 summary 提"pathing 留到后面单独实现"）。
doodad 放位时不查 pathing。

**待补**（**延后**，等 pathing 模块）：
- 读 doodad.pathing → 写入 `Wc3PathingMap` dynamic 段
- brush 放 doodad 时先查 pathing free → 不允许再拒绝

### 3.5 旋转 90° 离散 vs 任意角度

**位置**：`MapDoodadLayer` 渲染 + `doodad_brush`

**HivEWE**：旋转 90° 离散（doodad 模型按 90/180/270/0 区分网格）。

**我们**：任意角度（`yaw_wc3_to_godot(angle)`）—— **更灵活**。

**决策**：保留任意角度（WC3 数据**支持**任意角度，只是 doodad 模型
通常用 90° 离散）。**不**改。

---

## 4. 测试状态

### 4.1 当前 selftest

| 文件 | 状态 |
|------|------|
| `selftest_doodad_data.gd`（integration）| 之前 summary 提过老李改过（layer.build(ctx) 适配）|
| `selftest_doodad_logic.gd` | **缺** —— doodad 没 Logic 层（pure data 加载）|
| `selftest_doodad_present.gd` | **缺** —— present 层验收 |

**当前 doodad 没有任何完整 selftest**——D2 brush 落地后才有 paint 测试。

### 4.2 Lost Temple doodad 数据

- `assets/map-parsed/losttemple/doodads.json` 加载 OK
- doodad 数（待统计）
- 主要种类（待分类）

---

## 5. 决策点（待老李手测经典 WE 后填）

| 决策 | 描述 |
|------|------|
| **D1** | doodad 选中是否走 AABB（包围盒）vs 单 mesh pick？经典 WE 走 AABB；复杂 doodad 应走 AABB |
| **D2** | doodad 拖动是否限制在 heightfield 内？经典 WE 是；HivEWE 是 |
| **D3** | doodad 删除时是否联动 pathing（恢复）？等 pathing 模块 |
| **D4** | doodad 内嵌 pathing 是否走 HivEWE 同款（doodad 自带 mask）vs 派生（从 GLB 提取）？ |

---

## 6. 实施步骤

按 5 节点计划：

### 6.1 N1（已完成）：写路线图

→ 当前文件 `docs/doodad/HIVEWE_ALIGN.md`

### 6.2 N2：doodad_brush（编辑器 paint）—— 1-2 commit

- `editor/scripts/tools/doodad_brush.gd` 新建
- 选中（点击 → 高亮）
- 拖动（按 → 拖 → 释放）
- 旋转（Shift+R / 滚轮）
- 删除（Delete）
- `MapDocument` 加 `add_doodad(d)` / `remove_doodad(idx)` / `move_doodad(idx, x, y)` API
- undo 走 `PaintStrokeRecorder` 模式（与 ramp 一致）

### 6.3 N3：M2G 工具加 sync_anim 标志 —— 1 commit

- m2g 转换时检查 GLB 内部 animation 特征
- 全部同步（shader 可模拟）→ 标 `sync_anim: true`（允许 MultiMesh）
- 复杂骨骼（必须单 instance）→ 标 `sync_anim: false`

### 6.4 N4：树/草 shader 错相位 —— 1-2 commit

- `wc3_doodad_wind.gdshader` 新建
- `vertex() { VERTEX.x += sin(TIME + world_pos.x * 0.01 + INSTANCE_CUSTOM.x * 6.28) * 0.5 }`
- `MapDoodadLayer` 给同 type GLB 的 instance 写不同 `INSTANCE_CUSTOM.x`（错相位）
- 几百棵树 1 draw call

### 6.5 N5：selftest_doodad + 集成测试 —— 1-2 commit

- `tests/unit/selftest_doodad.gd` —— brush paint / move / rotate / delete
- `tests/integration/selftest_doodads.gd`（已有，需补 case）
- `tests/unit/selftest_doodad_present.gd` —— MultiMesh 路径 + 错相位

每个 N 节点完成后报告老李 → 等 OK 再进下一节点。

---

## 7. 源码索引

| 主题 | HivEWE 文件 | HivEWE 符号 | 本仓库符号 |
|------|------------|------------|------------|
| 装饰物数据 | `base/doodads.ixx` | `class Doodad` | `doodads.json` schema |
| 装饰物模型 | `brush/doodad_brush.cpp` | `get_mesh(id)` | `MapModelCache.instance_glb(glb)` |
| 选中 / 拖动 | `brush/doodad_brush.cpp` | `DoodadBrush::click` | **缺**（N2 待补）|
| Pathing | `doodad.pathing` | per-doodad mask | **缺**（N5 延后）|
| Placeholder | `doodad_brush.cpp` | 简化 | `MapPlaceholders.make_entity` |
| 渲染 | `skinned_mesh.ixx` | SkinnedMesh | MultiMesh / MeshInstance3D |
| Y 重算 | `base/doodads.ixx` | `change_doodad_heights` | `refresh_heights` + `_apply_height_update` |

---

## 8. 相关文档

- [README.md](README.md) —— MapDoodadLayer 架构 + 调用链
- [Y_REFRESH.md](Y_REFRESH.md) —— change_doodad_heights 等价
- [DOO_FORMAT.md](DOO_FORMAT.md) —— W3E DOO 文件结构 + `doodads.json` schema 完整字段表
- [../hivewe/OPERATORS.md §6.4](../hivewe/OPERATORS.md) —— HivEWE doodad 操作符
- [../present/Z_ORDER.md §3](../presentation/Z_ORDER.md) —— Doodad Z 顺序（与 cliff/unit 关系）
- [../shader/](../shader/) —— shader 文档（INSTANCE_CUSTOM 用法）

---

最后更新：2026-08-01
