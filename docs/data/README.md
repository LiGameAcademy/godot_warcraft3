# data/ — 数据契约与资产

> 经典客户端资产路径、合规说明、离线解包/转换管线。

## 文件

| 文件 | 内容 |
|------|------|
| [CONTENT_PACKS.md](CONTENT_PACKS.md) | 内容包 / DLC：MPQ 同路径覆盖 + `fileVerFlags`→`*_V1` Edition 规则 |
| [WC3_ASSET_PATHS.md](WC3_ASSET_PATHS.md) | 经典 MPQ 解包后各目录放什么（按路径查单位/地形/UI/音效等） |
| [LEGAL.md](LEGAL.md) | 合规说明（不提交暴雪资产；缓存进 `.cache/`，gitignore） |
| [PIPELINE.md](PIPELINE.md) | 离线工具链（**优先** `node tools/dev-setup.mjs`；或分步 mpq → convert → slk → map-parse） |
| [GDIGNORE_POLICY.md](GDIGNORE_POLICY.md) | `.gdignore` 政策：哪些目录需要 / 不需要 + 跨平台说明（已 P3-12 收尾） |

## 关键路径

| 路径 | 说明 | gitignore |
|------|------|-----------|
| `.cache/wc3-assets/` | 解包原始资产（MPQ → BLP/MDX/…） | ✅ |
| `assets/asset-converted/` | BLP→PNG、MDX→GLB | ✅ |
| `assets/slk-exported/` | SLK 表 → JSON | ✅ |
| `assets/map-parsed/<slug>/` | `.w3x` → JSON | ✅ |
| `assets/asset-converted/` | 已被 `.gdignore`，编辑器不导入 | — |

## 运行时路径

游戏逻辑应通过 Autoload `AssetProvider`（[`addons/asset_provider/`](../../addons/asset_provider/)）解析，**不要**直接读 `res://`。

`AssetProvider` 优先级（详见 [PIPELINE.md](PIPELINE.md)）：
1. `mods/<id>/` — Mod 覆盖
2. `assets/asset-converted/` — 转换后（PNG/GLB）
3. `.cache/wc3-assets/` — 原始解包（BLP/MDX）

## 何时查这里

- **新电脑一次跑通**：仓库根 [README.md](../../README.md) → `node tools/dev-setup.mjs --game-dir "..."`（详见 [../tools/README.md](../../tools/README.md)）
- 解包客户端：按 [WC3_ASSET_PATHS.md](WC3_ASSET_PATHS.md) 对路径
- 跑工具链：按 [PIPELINE.md](PIPELINE.md)（先贴图，再模型；或一键脚本）
- 上传资产前：[LEGAL.md](LEGAL.md)
- 编辑器按路径查资源：`AssetProvider.exists("<logical_path>")`
