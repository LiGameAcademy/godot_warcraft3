# AssetProvider

统一逻辑路径 → 物理文件解析（Autoload：`AssetProvider`）。

## 查找顺序

1. `register_overlay` 注册的 mod 根目录（后注册优先）
2. `assets/asset-converted/`（视觉：PNG / GLB / PathTextures）
3. `assets/slk-exported/`（数据：SLK JSON / UnitFunc / UI txt）

**不读** `.cache/wc3-assets/`（MPQ extract 中间态）。缺文件请跑 `node tools/bootstrap.mjs` 或 `node tools/sync-data-assets.mjs`。

扩展名自动尝试：`.blp`→`.png`，`.mdx`/`.mdl`→`.glb`。

契约详见 [docs/architecture/ASSET_LANES.md](../../docs/architecture/ASSET_LANES.md)。

## 配置

| Project Settings | 含义 |
|------------------|------|
| `warcraft3/asset_converted_dir` | 覆盖 converted 绝对路径 |
| `warcraft3/asset_data_dir` | 覆盖 slk-exported（数据车道）绝对路径 |
| `warcraft3/asset_cache_dir` | 仅工具/诊断；**resolve 不使用** |

## 与 RuntimeAssets

- **AssetProvider**：只负责 `resolve(logical) → 绝对路径`
- **RuntimeAssets**：`converted_path` / `slk_path` / `load_*`；地图代码通过它拼路径并读盘，**不要**再手写 `res://assets/asset-converted/`

示例：

```gdscript
# 推荐
var tex := RuntimeAssets.load_converted_texture("Textures/ShorelineParticleXY.png")
var glb := RuntimeAssets.converted_path("Units/Human/Footman/Footman.glb")

# 或经 Autoload（converted + slk-exported）
var abs_path: String = AssetProvider.resolve("Units/HumanUnitFunc.txt")
```

## 后续（未实现）

玩家首次运行：选择经典安装目录 → GDExtension（StormLib）解包到 `user://wc3_cache/`，再同步到与三车道等价的用户目录；仍不在运行时直读 MPQ。
