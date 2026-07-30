# 地图编辑器

独立运行场景，复用 `scenes/map/map_root.tscn` 做地形 / 悬崖 / 水面预览。

设计说明见 [`docs/editor/EDITOR.md`](../docs/editor/EDITOR.md)。

## 运行

1. 用 Godot 打开本仓库  
2. 打开 [`editor/scenes/editor_main.tscn`](scenes/editor_main.tscn)  
3. **F6**（运行当前场景）——不要改项目主场景  

主游戏入口仍是 `scenes/main.tscn`（F5）。

## 操作

| 输入 | 作用 |
|------|------|
| 顶栏菜单 | 文件→新建 / 打开示例图 / 保存 / 退出；编辑→撤销/重做；查看→栅格；窗口→工具面板 |
| Ctrl+Z / Ctrl+Y | 撤销 / 重做（笔划级） |
| 工具浮窗 | 地表贴图、悬崖工具与类型、笔刷尺寸（1/2/3/5/8）与形状（圆/方） |
| 左键拖拽 | 刷地表和/或悬崖（由面板勾选决定） |
| WASD / QE | 平移相机 |
| 右键拖拽 | 旋转 |
| 滚轮 | 缩放 |

灰色菜单项 = 尚未实现（状态栏会提示）。

## 目录

```text
editor/
  README.md
  scenes/editor_main.tscn
  scripts/
    editor_shell.gd        # 场景壳
    editor.gd              # MapEditor 总管
    editor_app.gd          # 已废弃
    map_document.gd
    editor_camera.gd
    commands/              # 命令模式（撤销/重做）
    tools/terrain_brush.gd
    ui/
  locale/editor_strings.csv
```
