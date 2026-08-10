# editor/ — 编辑器

> 编辑器架构、笔刷、命令模式、国际化、UI 组件。

## 文件

| 文件 | 内容 |
|------|------|
| [EDITOR.md](EDITOR.md) | 编辑器总览（场景 F6 → `editor/scenes/editor_main.tscn`，按 HiveWE 竖切；脏区/笔刷/重建设计） |
| [BRUSHES.md](BRUSHES.md) | 笔刷架构（地表/崖/坡）+ 与 Logic API 边界 + 加新笔刷流程 |
| [COMMANDS.md](COMMANDS.md) | 命令模式 + 撤销/重做（`PaintStrokeCommand` / `EditorCommandHistory` / `EditorVertexSnapshot`） |
| [I18N.md](I18N.md) | 国际化（`EditorI18n` Autoload + `editor/locale/editor_strings.csv`） |
| [UI.md](UI.md) | UI 组件目录（menu_bar / toolbar / tool_palette / new_map_dialog / tile_palette） |

## 状态（按 [TODO.md §"编辑层"](../../roadmap/TODO.md)）

| 项 | 状态 |
|----|------|
| Editor 总管 + 命令模式 + 地表笔刷可见重建 | ✅ |
| 悬崖笔刷全面委托 `Wc3CliffLogic` | ✅ |
| 删除 `Wc3CliffTiles`（拓扑→Logic，GLB/变体→Catalog） | ✅ |
| Document 去掉 `hf` 属性（仅 `as_build_dict()` 过渡） | ✅ |
| 脏区局部重建 Ground（接口已有 dirty rect） | ⏳ |
| 撤销 UI 灰显 / i18n | ⏳ |

**验收（地面）**：改地表 → 数据变 → Ground 更新；Ctrl+Z 可撤销。

## 关键概念

- **Editor 总管**：`editor/scripts/editor.gd`，挂在 `editor_main.tscn` 下直接子节点 `Editor`（`Node`）
- **场景壳**：`editor/scripts/editor_shell.gd`
- **Document**：`editor/scripts/map_document.gd`（编辑器状态权威；委托 `Wc3*Logic`）
- **命令模式**：`editor/scripts/commands/`（详见 [COMMANDS.md](COMMANDS.md)）
- **笔刷**：`editor/scripts/tools/terrain_brush.gd`（详见 [BRUSHES.md](BRUSHES.md)）

## 何时查这里

- 改编辑器入口 / 加载顺序 → [EDITOR.md](EDITOR.md)
- 加新笔刷 → [BRUSHES.md](BRUSHES.md) + `editor/scripts/tools/terrain_brush.gd`
- 加新命令（撤销/重做）→ [COMMANDS.md](COMMANDS.md) + `editor/scripts/commands/`
- 加新字符串翻译 → [I18N.md](I18N.md) + `editor/locale/editor_strings.csv`
- 改 UI 面板 → [UI.md](UI.md) + `editor/ui/`
- 编辑器运行入口 → [`editor/scenes/editor_main.tscn`](../../../editor/scenes/editor_main.tscn)（F6）
