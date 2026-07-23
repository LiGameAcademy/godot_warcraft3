# 开发路线图（MapRoot + Map Editor）

> 依据当前架构文档：[MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md)、[EDITOR.md](EDITOR.md)。  
> 原则：先稳住预览与编辑闭环，再加深工具与导出；重构以「减双通路、统一契约」优先于目录搬家。  
> 最后更新：2026-07-23

---

## 1. 现状快照

| 子系统 | 状态 |
|--------|------|
| MapRoot 分层预览 | ✅ 地面 / 悬崖 / 水面 / 装饰；单位默认关 |
| 离线资产管线 | ✅ MPQ → cache → converted / slk / map-parsed |
| 地图编辑器壳 | ✅ 独立场景、菜单、新建/打开/存 JSON、工具浮窗 |
| 地表笔刷 | ✅ 圆/方，尺寸 1/2/3/5/8 |
| 悬崖 / 水 / 坡笔刷 | ✅ 层差约束、分路径重建 |
| 高度笔刷 | ❌ 仅 UI |
| 撤销 / 导出 w3x | ❌ |
| 单位 / 装饰编辑 | ❌ 预览可摆，编辑器未做放置工具 |

---

## 2. 里程碑总览

```text
M0 文档与基建对齐     ← 当前
M1 编辑器核心闭环
M2 MapRoot 质量与重构
M3 内容工具（单位/装饰/高度）
M4 互通与导出
M5 运行时玩法（可选）
```

---

## 3. MapRoot 路线

### M0 — 文档与入口澄清（进行中 / 可立即收尾）

- [x] 节点树分层与脚本职责文档（本文档体系）
- [ ] **P0** 调试栅格单一入口（弱化 `MapPathingDebugLayer`）
- [ ] 主场景 / 编辑器 export 默认值在 README 写清

### M1 — 预览正确性（高优先）

| 项 | 说明 | 优先级 | 主要文件 |
|----|------|--------|----------|
| 斜坡几何/材质 | 对齐 HiveWE；甲板与岩壁 | P0 | `wc3_cliff_*`、`wc3_terrain_autotile` |
| 岸浪精调 | 偏移/贴图；可后置 | P2 | `wc3_shore*`、WATER.md |
| 大图重建性能 | 悬崖笔刷避免无谓 Autotile | P1 | `map_loader.rebuild_*` |
| 缺模/缺贴图可诊断 | 更清晰的 warning + 占位 | P2 | `runtime_assets`、`map_placeholders` |

### M2 — 架构收敛（中优先）

| 项 | 说明 | 优先级 |
|----|------|--------|
| Layer 契约统一 | Doodad/Unit → `build(ctx)` | P1 |
| Pipeline 配置化 | 步骤表驱动 `_load_all` | P1 |
| 泡沫参数单源 | Context 或 Options 对象 | P1 |
| 目录归位 | `app/layers/domain/infra` | P2 |
| Domain 输出结构化 | 减少松散 Dictionary | P2 |

### M3 — 运行时能力扩展（按产品需要）

| 项 | 说明 | 优先级 |
|----|------|--------|
| 默认摆单位 | 完整 tscn/资源管线后再开 `place_units` | P2 |
| Pathing 真数据可视化 | 超出 shader 栅格 | P2 |
| 玩法逻辑 | 选单位、指令、战斗 | P3（另立项目阶段） |

---

## 4. Map Editor 路线

### M0 — 壳与文档

- [x] `docs/EDITOR.md` 架构
- [x] 启动空白图 + 工具浮窗 + 地表/悬崖笔刷
- [ ] 修 `always_on_top` + transient 警告（`show` 代替不当 `popup`）

### M1 — 核心编辑闭环（高优先）

| 项 | 说明 | 优先级 | 主要文件 |
|----|------|--------|----------|
| **撤销 / 重做** | 至少地表+悬崖层快照或命令栈 | P0 | `map_document`、`editor_app` |
| **高度笔刷接通** | Raise/Lower/Plateau/Noise/Smooth → 改 `heights` | P0 | `tool_palette`、`terrain_brush`、`map_document` |
| 局部重建优化 | 脏矩形 / 跳过未变层 | P1 | `editor_app`、`map_loader` |
| 保存体验 | Save As、最近文件、覆盖确认 | P1 | `editor_app`、`map_document` |
| 打开任意 map-parsed | 文件对话框选 slug | P1 | `editor_app` |

### M2 — 工具对齐 WE（中优先）

| 项 | 说明 | 优先级 |
|----|------|--------|
| Blight / Boundary | 特殊纹理 flags | P1 |
| 斜坡笔刷打磨 | 与 Domain 斜坡修复同步 | P1 |
| 多笔刷光标/状态栏 | 工具名、层高、cliff 类型 | P2 |
| 查看菜单实装 | 线框、层显隐（单位/装饰/水） | P2 |
| 关闭地图 / 多文档 | 按需 | P2 |

### M3 — 内容放置（中后）

| 项 | 说明 | 优先级 |
|----|------|--------|
| 装饰物面板 + 放置 | 复用 `MapDoodadLayer` / Catalog | P1 |
| 单位面板 + 放置 | 复用 `MapUnitLayer`；注意碰撞/占位 | P2 |
| 区域 / 相机面板 | Placeholder → 最小数据模型 | P3 |

### M4 — 互通与导出（后）

| 项 | 说明 | 优先级 |
|----|------|--------|
| 导入 `.w3e` / 地图包 | 对接现有 map-parse 或运行时解析 | P1 |
| 导出 `.w3e` | 与 JSON 双向 | P1 |
| 打包 `.w3x` | 完整地图 | P2 |
| Godot EditorPlugin | 可选；非阻塞独立场景方案 | P3 |

---

## 5. 跨系统依赖（避免返工）

```text
斜坡 Domain 修对 ──┬──► 编辑器斜坡笔刷才有意义
                   └──► 地面留缝 / 水面 skip ramp 一致

撤销栈 ──► 高度/悬崖/地表 都走 MapDocument 命令
           （不要各刷各的直接写 hf）

导出 w3e ──► 先稳定 JSON 字段语义与 layerHeights/flags
             （编辑器不要引入无法往返的临时字段）

Layer build(ctx) 统一 ──► 编辑器增量重建更好写
```

---

## 6. 建议迭代顺序（实操）

### 第一季度焦点（示例）

1. **P0** 撤销栈 + 高度笔刷（编辑器立刻好用）  
2. **P0** 斜坡预览对齐（MapRoot 观感）  
3. **P0** 调试栅格单入口（减坑）  
4. **P1** 打开/另存、Blight、Doodad 放置起步  
5. **P1** Layer 契约 + 重建粒度  

### 明确不抢跑

- 一上来做 `.w3x` 打包  
- 未统一文档字段就上多文档/云同步  
- 为搬家而搬家（目录归位放在契约统一之后）  

---

## 7. 验收口碑（每阶段自测）

| 阶段 | 最低验收 |
|------|----------|
| MapRoot M1 | Lost Temple F5 可玩预览；斜坡目视可接受；无崩溃 |
| Editor M1 | 新建→刷地表/悬崖/高度→撤销→保存→再打开一致 |
| Editor M3 | 能放下一种装饰并进 JSON 再加载 |
| 导出 M4 | 导出的 w3e 可被现有 parse 或经典 WE 打开（按目标平台定） |

---

## 8. 文档索引

| 文档 | 用途 |
|------|------|
| [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) | MapRoot 分层、数据/调用流、干预点、重构评估 |
| [EDITOR.md](EDITOR.md) | 编辑器编排与信号 |
| [TODO.md](TODO.md) | 细粒度缺陷 |
| [WATER.md](WATER.md) | 水体专项 |
| [editor/README.md](../editor/README.md) | 如何 F6 跑编辑器 |
