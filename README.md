# godot_warcraft3

使用 **Godot 4.6** 复刻《魔兽争霸3》玩法的实验项目。

仓库**不包含**暴雪游戏资产。开发与运行前须自备正版经典客户端，详见 [docs/LEGAL.md](docs/LEGAL.md)。

经典 MPQ 解包后各目录放什么，见 [docs/WC3_ASSET_PATHS.md](docs/WC3_ASSET_PATHS.md)（按路径查单位/地形/UI/音效等）。

水体（HiveWE 对齐、后续 Shoreline、远期增强）：[docs/WATER.md](docs/WATER.md)。

地图运行时架构（分层、数据流、演进）：[docs/MAP_ARCHITECTURE.md](docs/MAP_ARCHITECTURE.md)。

地图编辑器（HiveWE 式竖切，分支 `feature/map-editor`）：[docs/EDITOR.md](docs/EDITOR.md) · 场景 F6 → [`editor/scenes/editor_main.tscn`](editor/scenes/editor_main.tscn)。

## 前置条件

- [Godot 4.6](https://godotengine.org/)
- [Node.js 18+](https://nodejs.org/)（仅开发解包工具需要）
- 经典《魔兽争霸3》安装目录（含 `War3.mpq`、`War3x.mpq` 等；**不是**仅含 `Data/` 的现代 CASC 客户端）

## 首次设置：解包本地资产

在仓库根目录执行：

```bash
cd tools/mpq-extract
npm install
npm run extract -- --game-dir "C:/Path/To/Warcraft III"
```

常用选项：

```bash
# 全量重解
npm run extract -- --game-dir "C:/Path/To/Warcraft III" --force

# 只解单位与 UI（加快开发迭代）
npm run extract -- --game-dir "C:/Path/To/Warcraft III" --include "Units/**" --include "UI/**"
```

输出（均已被 `.gitignore` 忽略，勿提交）：

| 路径 | 说明 |
|------|------|
| `.cache/wc3-assets/` | 按逻辑路径镜像的解包文件 |
| `.cache/manifest.json` | 清单：`logicalPath` → `sourceMpq` / `size` / `sha256` |

逻辑路径与经典客户端内部路径一致，例如 `Units/Human/Footman/Footman.mdx`。游戏逻辑应通过 Autoload `AssetProvider` 解析，不要把暴雪文件放进 `res://` 并提交。

## 资产转换（贴图 / 模型 → Godot）

解包之后，用 JS 工具把经典格式转成 Godot 友好格式。**推荐顺序：先贴图，再模型**（默认 `npm run convert` 已按此顺序执行）。模型材质会引用 PNG；若 PNG 尚未生成，转换模型时会尝试即时从 BLP 补转。

```bash
cd tools/asset-convert
npm install

# 默认：BLP→PNG，再 MDX→GLB
npm run convert --

# 开发期子集（步兵）
npm run convert -- --include "Units/Human/Footman/**" --include "Textures/Footman.blp" --include "Textures/gutz.blp"

# 分步
npm run convert:textures --
npm run convert:models --
```

| 输入 | 输出（默认 [`assets/asset-converted/`](assets/asset-converted/)，已 gitignore） |
|------|------|
| `*.blp` | 同逻辑路径的 `*.png` |
| `*.mdx` / `*.mdl` | 同逻辑路径的 `*.glb`（Y-up，约 0.01 缩放；贴图嵌入 GLB） |

说明：模型导出含材质/UV、骨骼蒙皮、`Sequence` 动画，以及 GeosetAnim 显隐。Godot 路径示例：`res://assets/asset-converted/Units/Human/Footman/Footman.glb`。

## 地图解析（.w3x → JSON）

用 JS 工具打开经典地图 MPQ，解析 `war3map.*` 为 JSON。默认测试图为冰封王座 **Lost Temple**。

```bash
cd tools/map-parse
# 依赖 tools/mpq-extract 的 StormLib（请先在该目录 npm install）
npm run parse --
# 或指定地图
npm run parse -- --map "C:/war3/Maps/FrozenThrone/(4)LostTemple.w3x" --force
```

输出（gitignore）：`assets/map-parsed/<slug>/`，含 `summary.json`、`info.json`、`terrain.json`、`units.json`、`doodads.json` 等。详见 [`tools/map-parse/README.md`](tools/map-parse/README.md)。

## SLK 表导出（.slk → JSON）

单位数值、技能、地形类型等存在 `.slk` 表中。可用工具解析导出：

```bash
cd tools/slk-export
npm install
node src/cli.js
# 子集：node src/cli.js --include "Units/**" --overwrite
```

输出（gitignore）：`assets/slk-exported/`（如 `Units/UnitData.json`）。详见 [`tools/slk-export/README.md`](tools/slk-export/README.md)。

## 冒烟验证

解包成功后，在本机确认：

1. 目录 `.cache/wc3-assets/` 非空（常见可见 `Units/`、`UI/`、`ReplaceableTextures/` 等）。
2. 打开 `.cache/manifest.json`，确认顶层字段包含：
   - `version`（当前为 `1`）
   - `gameDir`
   - `extractedAt`
   - `files`（对象；每个条目含 `sourceMpq`、`size`、`sha256`）
3. 任选一个 `files` 中的键（逻辑路径），检查对应文件是否存在于 `.cache/wc3-assets/<逻辑路径>`。
4. （可选）在 Godot 中运行后，用脚本探测：
   `AssetProvider.exists("Units/Human/Footman/Footman.mdx")`  
   若你的客户端路径/版本不同，可将路径换成 manifest 里实际存在的任意条目。

无经典安装时，可先验证 CLI 报错是否清晰：

```bash
cd tools/mpq-extract
npm run extract -- --help
npm run extract -- --game-dir "C:/definitely-not-wc3"
```

应提示未找到 `War3.mpq` 等经典 MPQ。

## 项目结构（资产相关）

```text
tools/mpq-extract/     Node 解包 CLI（StormLib + koffi）
tools/asset-convert/   BLP→PNG、MDX→GLB
tools/sync-editor-assets.mjs  编辑器所需 UI txt → asset-converted
tools/map-parse/       .w3x → JSON（经典 war3map.*）
tools/slk-export/      .slk → JSON
addons/asset_provider/ 逻辑路径解析（converted → .cache）
mods/                  Mod 覆盖目录（内容不提交）
.cache/wc3-assets/     解包原始资产（不提交）
assets/asset-converted/  转换后 PNG/GLB + 同步的编辑器 UI txt（不提交）
assets/map-parsed/       解析后的地图 JSON（不提交）
assets/slk-exported/     SLK 导出表（不提交）
docs/LEGAL.md            合规说明
docs/WC3_ASSET_PATHS.md  经典资产路径手册
docs/WATER.md            水体复刻路线与远期增强（暂不实现）
```

## Lost Temple 地图预览（灰盒 → 可视复原）

1. 解析地图：`cd tools/map-parse && npm run parse -- --force`  
   → `assets/map-parsed/losttemple/terrain-heightfield.json` 等
2. 导出 SLK：`cd tools/slk-export && node src/cli.js`
3. 转换本图资源：`cd tools/asset-convert && npm run convert:lost-temple`  
   → Icecrown 地表、雪树、金矿/泉水、野怪等 PNG/GLB
4. （地图编辑器）同步 UI 配置：`node tools/sync-editor-assets.mjs`  
   → `assets/asset-converted/UI/WorldEditData.txt` 等
5. Godot 4.6 打开项目并运行主场景 `scenes/main.tscn`（编辑器见 `editor/scenes/editor_main.tscn`）

操作：WASD 平移，QE 升降，Shift 加速，右键旋转，滚轮缩放。  
地形按 tile 索引贴 Icecrown 地表；树木/岩石等用 MultiMesh 实例化 GLB；缺资源时回退占位体。

**导入卡死说明：** `assets/asset-converted/` 可达数万文件，已加 `.gdignore`，编辑器不再导入该目录；PNG/GLB 由运行时按需加载。若仍卡在旧导入：结束 Godot → 删除项目下 `.godot/imported/`（可整夹删）→ 再开。

## 后续规划（尚未实现）

1. **玩家首次运行**：选择本机经典安装路径 → GDExtension + [StormLib](https://github.com/ladislav-zezula/StormLib) 解包到 `user://wc3_cache/`，manifest 语义与开发工具一致。
2. **Mod**：在 `mods/<id>/` 下用相同逻辑路径覆盖缓存文件；`AssetProvider.register_overlay` 已预留。
3. **水体 Shoreline**：自动岸浪已用 PE2 近似；完整 MDX 粒子 / ShorelineWave 装饰浪仍未做。
4. **寻路等**：`war3map.wpm` 等。

## 开发依赖说明

- 解包工具通过 [`koffi`](https://koffi.dev/) 调用官方预编译 [StormLib](https://github.com/ladislav-zezula/StormLib) DLL（`npm install` 时自动 `fetch-stormlib`），**无需** Visual Studio / node-gyp。
- 当前 `fetch-stormlib` 拉取 Windows x64 ANSI 版 DLL；非 Windows 开发机需自行提供兼容的 `StormLib` 并设置环境变量 `STORMLIB_DLL`。
- 玩家端规划为 Godot GDExtension 直接链接 StormLib，不依赖 Node.js。
