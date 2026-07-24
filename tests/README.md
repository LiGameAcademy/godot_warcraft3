# 测试说明

自测脚本已从 `tools/selftest_*.gd` 迁至本目录。运行示例：

```text
godot --headless --path . -s res://tests/unit/selftest_terrain_logic.gd
```

| 子目录 | 内容 |
|--------|------|
| `unit/` | 数据 / Catalog / TerrainLogic / MapDocument / Ground Mesh / 斜坡逻辑 |
| `cliff/` | 直崖回归（变体、层高、贴图） |
| `water/` | 岸浪等 |
| `integration/` | 装饰物、寻路栅格等 |
