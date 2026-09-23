# 测试说明

自测脚本已从 `tools/selftest_*.gd` 迁至本目录。运行示例：

```text
python tools/workspace/test_apps.py --godot <Godot_console.exe> --app map_editor --case unit/selftest_terrain_logic.gd
```

| 子目录 | 内容 |
|--------|------|
| `unit/` | 数据 / Catalog / TerrainLogic / MapDocument / Ground Mesh / 斜坡逻辑 |
| `cliff/` | 直崖回归（变体、层高、贴图） |
| `water/` | 岸浪等 |
| `integration/` | 装饰物、寻路栅格等 |

双产品迁移后，测试源码仍保留在 tests/；运行工具只把选定测试和依赖复制到对应应用。根目录不再是可运行的 Godot 项目。静态包依赖门禁：`python tools/workspace/check_layout.py`。
