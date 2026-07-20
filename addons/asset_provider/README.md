# AssetProvider

统一逻辑路径 → 物理文件解析（Autoload：`AssetProvider`）。

## 查找顺序

1. `register_overlay` 注册的 mod 根目录（后注册优先）
2. `assets/asset-converted/`（开发期转换产物：PNG / GLB）
3. `.cache/wc3-assets/`（`tools/mpq-extract` 解包的原始 BLP/MDX 等）

扩展名自动尝试：`.blp`→`.png`，`.mdx`/`.mdl`→`.glb`。

## 配置

| Project Settings | 含义 |
|------------------|------|
| `warcraft3/asset_cache_dir` | 覆盖 `.cache/wc3-assets` 绝对路径 |
| `warcraft3/asset_converted_dir` | 覆盖 converted 绝对路径 |

## 与 RuntimeAssets

- **AssetProvider**：只负责 `resolve(logical) → 绝对路径`
- **RuntimeAssets**：`converted_path` / `load_*`；地图代码通过它拼路径并读盘，**不要**再手写 `res://assets/asset-converted/`

示例：

```gdscript
# 推荐
var tex := RuntimeAssets.load_converted_texture("Textures/ShorelineParticleXY.png")
var glb := RuntimeAssets.converted_path("Units/Human/Footman/Footman.glb")

# 或经 Autoload（含 cache / overlay）
var abs_path: String = AssetProvider.resolve("Textures/ShorelineParticleXY.blp")
```

## 后续（未实现）

玩家首次运行：选择经典安装目录 → GDExtension（StormLib）解包到 `user://wc3_cache/`，manifest 与开发工具一致。
