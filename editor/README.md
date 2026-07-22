# 地图编辑器

独立运行场景，复用 `scenes/map/map_root.tscn` 做地形预览。

## 运行

1. 用 Godot 打开本仓库
2. 打开 [`scenes/editor_main.tscn`](scenes/editor_main.tscn)
3. **F6**（运行当前场景）——不要改项目主场景

主游戏入口仍是 `scenes/main.tscn`（F5）。

## 操作

| 输入 | 作用 |
|------|------|
| 左键拖拽 | 刷当前选中地表贴图（整格） |
| WASD / QE | 平移相机 |
| 右键拖拽 | 旋转 |
| 滚轮 | 缩放 |
| 顶栏「新建空白图」 | 32×32 格平坦图 |
| 顶栏「打开 Lost Temple」 | 加载解析后的官方图 |
| 顶栏「保存 JSON」 | 写到 `user://editor_maps/` |
| 侧栏 | 选择地表 tileID |

## 目录

```text
editor/
  README.md
  scenes/editor_main.tscn
  scripts/
    editor_app.gd
    map_document.gd
    editor_camera.gd
    tools/terrain_brush.gd
    ui/toolbar.gd
    ui/tile_palette.gd
```

设计说明见 [`docs/EDITOR.md`](../docs/EDITOR.md)。
