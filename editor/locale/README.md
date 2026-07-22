# 编辑器多语言

文案表：`editor/locale/editor_strings.csv`（列：`keys,zh_CN,en`）。

| 前缀 | 用途 |
|------|------|
| `EDITOR_*` | 本仓库自有 UI（状态栏、工具条、语言菜单等） |
| `WESTRING_*` | 对齐经典世界编辑器；可由 `assets/asset-converted/UI/WorldEditStrings.txt` 覆盖中文（`node tools/sync-editor-assets.mjs`） |

## 用法

脚本：

```gdscript
EditorI18n.t("EDITOR_STATUS_IDLE")
EditorI18n.t("EDITOR_STATUS_ABOUT", [EditorI18n.t("WESTRING_APPNAME")])
EditorI18n.set_locale("en")  # 或 "zh_CN"
```

场景里控件 `text` 写 key 占位；运行时由对应脚本 `_localize` / `_apply_strings` 替换。

语言选择：窗口菜单 →「语言：中文 / English」（写入 `user://editor_locale.cfg`）。

## 维护

增补文案：直接编辑 `editor_strings.csv`，勿在 `.gd` 里写死用户可见字符串。
