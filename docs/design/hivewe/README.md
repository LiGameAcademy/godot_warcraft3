# docs/hivewe/ — HiveWE 实现方式分析

> 把 HiveWE（`D:/GameMaker/HiveWE`）的关键模块读一遍，结合 godot_warcraft3 项目对照。
> 目的：**为后续 vibecoding 提供技术指导**——遇到地形/悬崖/斜坡/水体相关决策时，直接照 HivEWE 的"已验证算法"。

## 路径与版本

| 用途 | 路径 | 状态 |
|------|------|------|
| **新版源码（0.6+ C++20 modules）** | `D:\GameMaker\HiveWE` | ✅ 实际可读 |
| v0.3 二进制 | `D:\GameMaker\HiveWE.0.3\HiveWE.exe` | ❌ 缺失（参考 rule） |
| v0.3 源码 | `D:\GameMaker\HiveWE-classic\` | ❌ 缺失（参考 rule） |
| v0.6 二进制 | `D:\GameMaker\HiveWE.0.6\` | ❌ 缺失（参考 rule） |
| **WC3 经典 1.27.1 客户端** | `D:\Program Files (x86)\Warcraft3` | ✅ 实际可读（`war3.mpq` 420MB + `World Editor.exe`） |

> **本文基于新版源码（0.6+ 风格）**。0.3 旧实现（`HiveWE-classic/HiveWE/Terrain.cpp` / `CliffMesh.*`）不可访问，但核心算法（cliff TAG 选型、ramp placement）多年未变。  
> Reforged / CASC 特定部分（CASC 解包、Reforged 资产）**不适用**——我们面向经典 1.27.1 MPQ。

## 阅读顺序

1. **[OPERATORS.md](OPERATORS.md)** — `TerrainOperator` 策略模式（4 类 Operator + apply 三段式）—— **架构总览，先读这个**
2. **[TERRAIN_MESH.md](TERRAIN_MESH.md)** — 高度场布局、corner/cell 区分、脏矩形
3. **[TERRAIN_TEXTURE.md](TERRAIN_TEXTURE.md)** — tile_id/tile_index、变体加权、cliff 邻接禁贴
4. **[CLIFF.md](CLIFF.md)** — `CliffOperator` 8 种操作 + TAG 选型 + 跨层 clamp
5. **[RAMP.md](RAMP.md)** — `update_ramp` 完整算法（3 角/对角线/L-corner 补 center）
6. **[WATER.md](WATER.md)** — `CellOperator` 4 种操作 + 水位公式
7. **[WATER_DEEP_ANALYSIS.md](WATER_DEEP_ANALYSIS.md)** — 浅水/深水（CliffOperator 水路径）+ 水体与斜坡交互 + Water/foam shader 完整对照
8. **[UNDO.md](UNDO.md)** — `WorldUndoManager` + 笔划期全 heightfield 快照

## HiveWE 项目结构

```text
D:\GameMaker\HiveWE\
├── CMakeLists.txt / vcpkg.json       Qt6 + OpenGL + Bullet + GLM
├── data/                              测试数据（地形/单位/触发器）
├── src/
│   ├── types.ixx                      类型别名（u8/u16/u32/i8...f32/f64）
│   ├── map_global.ixx                 `Map* map = nullptr` 全局
│   ├── test.ixx                       测试 module
│   ├── base/map/                      Map 类（32K） + resize + protection
│   │   ├── map.ixx                    Map 全状态（terrain/pathing/doodads/units/undo）
│   │   ├── resize.cpp / unused_files.cpp
│   │   └── protection.ixx
│   ├── brush/                         笔刷
│   │   ├── terrain_brush.{h,cpp}      TerrainBrush（含 4 个 Operator）
│   │   ├── terrain_operators.{h,cpp}  4 个 Operator（核心算法）
│   │   ├── doodad_brush / unit_brush / pathing_brush / region_brush
│   ├── menus/                         各种面板
│   │   ├── terrain_palette / tile_picker / tile_setter / tile_pather
│   │   ├── doodad_palette / unit_palette / pathing_palette / region_palette
│   ├── main_window/                   主窗口
│   │   ├── glwidget.{h,cpp}           OpenGL 渲染（terrain/doodads/units）
│   │   ├── hivewe.{h,cpp}             主入口（QMainWindow）
│   │   └── main_ribbon.{h,cpp}        Ribbon UI
│   ├── file_formats/                  文件格式
│   │   ├── mdx/                       MDX/MDL 读写 + optimizer + validator
│   ├── models/single_model.{h,cpp}    GL 模型渲染
│   ├── model_editor/                  模型编辑器
│   ├── object_editor/                 对象编辑器
│   ├── trigger_editor/                触发器编辑器
│   ├── qt_imgui/                      Qt + ImGui 桥接
│   ├── custom_widgets/                自定义 Qt 控件
│   ├── resources/                     资源
│   ├── utilities/                     工具
│   ├── asset_manager/                 资产管理
│   └── globals.ixx                    全局
```

## 命名约定对照

| HiveWE | godot_warcraft3 | 含义 |
|--------|----------------|------|
| `TerrainBrush` (继承 `Brush`) | `TerrainBrush` (extends `Node3D`) | 地形笔刷 |
| `TerrainOperator` 基类 | **无对应**（见 OPERATORS.md） | 笔刷内策略 |
| `HeightOperator` | `Wc3TerrainLogic` 部分功能（`set_height` 等） | 高度 |
| `TextureOperator` | `Wc3TerrainLogic` 部分功能（`set_ground_tex`）+ `Wc3GroundTileCatalog` | 纹理 |
| `CliffOperator` | `Wc3CliffLogic`（`scripts/map/logic/cliff/`） | 悬崖 |
| `CellOperator` | **无独立对应**（`Wc3TerrainLogic` 暂未拆 cell） | 水/边界 |
| `TerrainRect` / `PathingRect` | `MapDocument` 脏矩形（`dirty_min/max`） | 脏区 |
| `WorldUndoManager` | `EditorCommandHistory` | 撤销栈 |
| `TerrainUndo` (4 类) | `EditorCommand` + `PaintStrokeCommand` | 笔划命令 |
| `Map::terrain` | `MapLoader` / `MapBuildContext` 持 `Wc3Heightfield` | 高度场 |
| `Map::pathing_map` | **未实现** | 寻路 |
| `Map::doodads / units` | `MapDoodadLayer` / `MapUnitLayer` | 装饰/单位 |
| `corner_height[]` | `Wc3Heightfield.heights[]` | 顶点高度 SoA |
| `corner_layer_height[]` | `Wc3Heightfield.layer_heights[]` | 层高（0-14） |
| `corner_water[]` + `corner_water_height[]` | `Wc3Heightfield.water_heights[]` | 水面标志 + 水位 |
| `corner_ground_texture[]` + `corner_ground_variation[]` | `ground_textures[]` + `ground_variations[]` | 地表贴图 |
| `corner_cliff[]` + `corner_cliff_texture[]` + `corner_cliff_variation[]` | `cliff_textures[]` + `cliff_variations[]` | 悬崖 |
| `corner_ramp[]` | `flags_packed[]`（FLAG_RAMP=4） | 斜坡标志 |
| `corner_blight[]` / `corner_boundary[]` | **未实现**（待加） | 污染/边界 |
| `Brush::Type::corner` | 默认 corner 模式 | 以 corner（顶点）为中心 |
| `Brush::Type::cell` | `MapDocument` 未拆 | 以 cell（格子）为中心 |

## 我们能从 HiveWE 借的 5 件事

| 借鉴点 | 状态 | 文档 |
|--------|------|------|
| `TerrainOperator` 策略模式 | ❌ **未引入**（推荐 P1 重构） | [OPERATORS.md](OPERATORS.md) |
| 笔划期全 heightfield 快照（撤销） | ❌ **局部快照**（CAPTURE_RADIUS=3） | [UNDO.md](UNDO.md) |
| 悬崖 4 角不等的 cliff 判定 | ✅ 已实现（`Wc3CliffLogic.is_cliff_tile`） | [CLIFF.md](CLIFF.md) |
| 斜坡 3-corner valid + L-corner center | ⚠️ 部分实现（待验证） | [RAMP.md](RAMP.md) |
| CellOperator 4 操作拆开 | ❌ **未拆**（待 Cell 层） | [WATER.md](WATER.md) |
| `change_doodad_heights`（改地形自动调 doodad Y） | ❌ **未实现**（ROADMAP §⑩ 待） | [TERRAIN_MESH.md](TERRAIN_MESH.md) |
| `WATER_GROUND_ZERO=0.7` / `WATER_HEIGHT=0.25` 常量 | ❌ 未常量 | [WATER.md](WATER.md) |
| 4 角 `corner_blight=false`（放 cliff 自动清 blight） | ❌ 未实现 | [TERRAIN_TEXTURE.md](TERRAIN_TEXTURE.md) |

## 何时查这里

- **改悬崖/斜坡算法前** → [CLIFF.md](CLIFF.md) / [RAMP.md](RAMP.md)（**先看 v0.3 + 新版对照**）
- **加新 Operator 类**（比如 RampOperator 独立） → [OPERATORS.md](OPERATORS.md) §"vibecoding 指导"
- **做脏区局部重建** → [UNDO.md](UNDO.md) §"vibecoding 指导"
- **做水体/边界/污染** → [WATER.md](WATER.md) + [WATER_DEEP_ANALYSIS.md](WATER_DEEP_ANALYSIS.md) / [TERRAIN_TEXTURE.md](TERRAIN_TEXTURE.md)
- **改浅水/深水笔刷 / 水-斜坡交互 / water-foam shader** → [WATER_DEEP_ANALYSIS.md](WATER_DEEP_ANALYSIS.md)
- **决策"我们要不要照 HivEWE 这么做"** → 每个文档末"vibecoding 指导"段

## 已知差异

- **CASC/Reforged** 不适用（我们面向经典 1.27.1 MPQ）
- **Qt6 / OpenGL** 渲染管线不适用（Godot 4.6 自己的渲染）
- **Bullet Physics** 不适用（Godot 用 Jolt）
- **GLM** 几何库不适用（Godot 内置 `Vector2/3/4`）

## 相关项目内文档

- [architecture/LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md) — 我们的分层总纲
- [architecture/SCRIPTS_LAYOUT.md](../../architecture/SCRIPTS_LAYOUT.md) — `scripts/` 目录全景
- [cliff/CLIFF.md](../cliff/CLIFF.md) — 我们的悬崖（思路门禁 + 实际实现）
- [ramp/RAMP_WE.md](../ramp/RAMP_WE.md) — 我们的斜坡（Paint 只写 FLAG_RAMP）
- [data/PIPELINE.md](../../data/PIPELINE.md) — 我们的资产管线
- [editor/BRUSHES.md](../editor/BRUSHES.md) / [editor/COMMANDS.md](../editor/COMMANDS.md) — 我们的笔刷/命令
