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
| 顶栏菜单 | 原版世界编辑器菜单（文件→新建弹出对话框 / 打开/保存/退出 已接通） |
| 创建新地图 | 选尺寸、地形集、初始地表贴图、悬崖高度、水位、随机高度 |
| 左键拖拽 | 刷当前选中地表贴图（整格） |
| WASD / QE | 平移相机 |
| 右键拖拽 | 旋转 |
| 滚轮 | 缩放 |
| 侧栏 | 选择地表 tileID |

灰色菜单项 = 尚未实现（状态栏会提示）。

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
