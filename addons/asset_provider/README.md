# AssetProvider

开发期资产解析占位：

- 逻辑路径与经典 WC3 内部路径一致（如 `Units/Human/Footman/Footman.mdx`）
- 默认从项目根下 `.cache/wc3-assets` 读取（由 `tools/mpq-extract` 生成）
- 可通过 Project Settings 键 `warcraft3/asset_cache_dir` 覆盖缓存根目录
- `register_overlay(mod_id, root)` 已预留，供后续 mod 覆盖

已注册为 Autoload：`AssetProvider`。

## 转换后的 Godot 资产

`tools/asset-convert` 默认输出到 `assets/asset-converted/`（PNG/GLB，gitignore）。

## 后续（未实现）

玩家首次运行：选择经典安装目录 → GDExtension（StormLib）解包到 `user://wc3_cache/`，manifest 字段与开发工具保持一致。
