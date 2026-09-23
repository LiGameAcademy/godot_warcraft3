# 地图编辑器

独立运行场景，复用 `scenes/map/map_root.tscn` 做地形 / 悬崖 / 水面预览。

设计说明见 [`docs/design/editor/EDITOR.md`](../../docs/design/editor/EDITOR.md)。
当前目标、已验证结果与后续验收见 [编辑器目标基线](../../docs/roadmap/EDITOR_GOAL_BASELINE.md)。
完整地图的保存、打开与版本限制见 [地图文件 v1](../../docs/design/editor/MAP_FILE_FORMAT.md)。
文件 → 测试地图可打开当前未保存内容的[运行预览](../../docs/design/editor/MAP_PREVIEW.md)。

## 运行

1. 在仓库根运行 `python tools/workspace/sync_packages.py --app map_editor`。
2. 用 Godot 打开 `apps/map_editor/project.godot`，按 F5 运行完整编辑器。
3. 本机外部资产根由应用的 `override.cfg` 指定；同步会首次生成配置。

游戏使用独立的 `apps/game/project.godot`。编辑器只依赖 foundation/content/map，不装载 gameplay 或 GAS。

## 操作

| 输入 | 作用 |
|------|------|
| 顶栏菜单 | 文件→新建 / 打开示例图 / 保存 / 退出；编辑→撤销/重做；查看→栅格；窗口→工具面板 |
| Ctrl+Z / Ctrl+Y | 撤销 / 重做（笔划级） |
| 工具浮窗 | 地表贴图、高度工具、悬崖工具与类型、笔刷尺寸（1/2/3/5/8）与形状（圆/方） |
| 左键拖拽 | 绘制勾选的地形工具；对象模式下放置对象或拖动已选对象 |
| Esc | 清除对象选择，再按可取消放置预览；拖动中清除选择会结束移动，仍可撤销 |
| R / [ / ] | 旋转已选对象或放置朝向 |
| Delete | 删除已选对象 |
| 双击单位 | 打开单位属性，可编辑归属、朝向、生命值、魔法值与警戒范围；技能和掉落页仍只读 |
| 双击树木 / 装饰物 | 编辑朝向、三轴缩放和生命值；确认后可撤销，取消不修改地图 |
| WASD / QE | 平移相机 |
| 右键拖拽 | 旋转 |
| 滚轮 | 缩放 |

灰色菜单项 = 尚未实现（状态栏会提示）。

键盘移动相机需要主编辑窗口拥有焦点；输入文本、操作属性浮窗或按住 Ctrl/Alt/Meta 时不会推动背景相机。

“查看 → 地图资源检查”提供只读报告，列出缺失对象定义或转换模型的原版 ID、模型路径、变体、数量及实例编号。可选中复制报告文字。它检查模型引用，不代表内部贴图、动画和视觉已全部通过；定义为编辑辅助对象的条目不因缺少模型而报警。

## 目录

```text
apps/map_editor/
  app/                   # 场景装配、MapEditor、设置与诊断
  documents/commands/    # 文档、文件、撤销/重做
  tools/                # 地形/单位/装饰笔刷
  input/                # 编辑器输入路由
  presentation/         # 相机与预览
  ui/                   # 窗口、菜单、属性面板
  scenes/               # 完整编辑器场景
  resources/            # 编辑器环境资源
  addons/               # 同步生成的共享包，不直接编辑
```

本地化共享源码位于 `packages/content/localization/`。
