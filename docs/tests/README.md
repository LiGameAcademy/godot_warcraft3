# tests/ — 测试索引

> `tests/` 目录全景 + headless 跑法。

## 目录结构

```text
tests/
├── README.md                              (headless 跑法精简版)
├── unit/                                  单元测试
│   ├── selftest_unit_regen.gd
│   ├── selftest_terrain_logic.gd
│   ├── selftest_ground_mesh.gd
│   ├── selftest_map_data.gd
│   ├── selftest_map_document.gd
│   ├── selftest_cliff_trans_catalog.gd
│   ├── selftest_def_store_cliff.gd
│   ├── selftest_editor_commands.gd
│   ├── selftest_paint_ground_rebuild.gd
│   ├── selftest_ramp_data.gd
│   ├── selftest_ramp_logic.gd
│   └── selftest_ramp_present.gd
├── cliff/                                 直崖回归
│   ├── selftest_cliff_variants.gd
│   ├── selftest_cliff_level3.gd
│   └── selftest_cliff_ground_tex.gd
├── water/                                 水体
│   └── selftest_shoreline.gd
└── integration/                           集成测试
    ├── selftest_doodads.gd
    └── selftest_path_grid.gd
```

## 跑法

源自 [`tests/README.md`](../../tests/README.md)：

```bash
# 单个
godot --headless --path . -s res://tests/unit/selftest_terrain_logic.gd

# 全部（按模块归类）
godot --headless --path . -s res://tests/unit/selftest_ramp_logic.gd
godot --headless --path . -s res://tests/unit/selftest_ramp_present.gd
godot --headless --path . -s res://tests/unit/selftest_ramp_data.gd
godot --headless --path . -s res://tests/cliff/selftest_cliff_variants.gd
godot --headless --path . -s res://tests/cliff/selftest_cliff_level3.gd
godot --headless --path . -s res://tests/cliff/selftest_cliff_ground_tex.gd
godot --headless --path . -s res://tests/unit/selftest_def_store_cliff.gd
godot --headless --path . -s res://tests/unit/selftest_cliff_trans_catalog.gd
godot --headless --path . -s res://tests/water/selftest_shoreline.gd
godot --headless --path . -s res://tests/unit/selftest_building_catalog.gd
godot --headless --path . -s res://tests/unit/selftest_build_flow.gd
```

> 注：`.claude/settings.json` 已允许 `Bash(godot --headless --path . -s res://tests/unit/selftest_ramp_logic.gd)`。

## 测试覆盖一览

| 区域 | 覆盖 |
|------|------|
| Data | `selftest_map_data.gd`（heightfield JSON 往返） |
| Catalog | `selftest_cliff_trans_catalog.gd` / `selftest_def_store_cliff.gd` / `selftest_building_catalog.gd`（F2 建筑数据）/ `selftest_build_flow.gd`（F2 资源/退款/流程数据）|
| Logic - Terrain | `selftest_terrain_logic.gd` / `selftest_ground_mesh.gd` / `selftest_paint_ground_rebuild.gd` |
| Logic - Cliff | `selftest_cliff_variants.gd` / `selftest_cliff_level3.gd` / `selftest_cliff_ground_tex.gd` |
| Logic - Ramp | `selftest_ramp_data.gd` / `selftest_ramp_logic.gd` / `selftest_ramp_present.gd` |
| Logic - Water | `selftest_shoreline.gd` |
| Document | `selftest_map_document.gd` / `selftest_editor_commands.gd` |
| Integration | `selftest_doodads.gd` / `selftest_path_grid.gd` |

## 何时查这里

- 改 Logic / Catalog / Data → 跑对应 `unit/selftest_*`
- 改 Cliff → 跑 `cliff/selftest_cliff_*`
- 改 Water → 跑 `water/selftest_shoreline.gd`
- 改 Editor commands → 跑 `unit/selftest_editor_commands.gd`
- 改 Document → 跑 `unit/selftest_map_document.gd`
