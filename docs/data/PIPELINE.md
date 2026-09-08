# 资产管线（Pipeline）

> 把"经典客户端 MPQ"变成"Godot 4.6 运行时可用资源"的完整链路。
> 涉及 4 个 Node 工具 + 1 个 Godot Autoload。
>
> 合规：[LEGAL.md](LEGAL.md)；资产路径：[WC3_ASSET_PATHS.md](WC3_ASSET_PATHS.md)

## 1. 总览

```text
经典客户端 MPQ
    │ tools/mpq-extract
    ▼
.cache/wc3-assets/                      (原始 BLP/MDX/W3E/DOO/W3I …)
    │
    ├── tools/asset-convert              (BLP→PNG, MDX→GLB)
    ├── tools/slk-export                (.slk → JSON)
    ├── tools/map-parse                 (.w3x → JSON)
    │
    ▼
assets/
  asset-converted/                      PNG/GLB（已 .gdignore）
  slk-exported/                         表 JSON
  map-parsed/<slug>/                    地图 JSON
    │
    ▼ 运行时
AssetProvider (Autoload)                解析逻辑路径 → 物理文件
    │
    ▼
RuntimeAssets / Wc3*Catalog / Wc3*Logic  → Map*Layer → 场景
```

## 2. 阶段拆解

### 阶段 1：解包（MPQ → 原始资产）

工具：[`tools/mpq-extract/`](../../tools/mpq-extract/)

```bash
cd tools/mpq-extract
npm install
npm run extract -- --game-dir "C:/Path/To/Warcraft III"
```

| 项 | 值 |
|----|-----|
| 实现 | Node 18+，`koffi` 调 [StormLib](https://github.com/ladislav-zezula/StormLib) DLL |
| StormLib 拉取 | `npm install` 时通过 `fetch-stormlib` 自动下载 |
| 输入 | `War3.mpq` / `War3x.mpq` 等经典 MPQ（**不是**仅含 `Data/` 的现代 CASC 客户端） |
| 覆盖顺序 | 见 `MPQ_PRIORITY`：后者覆盖前者；**同路径**才覆盖。TFT 另增的 `*_V1` 模型见 [CONTENT_PACKS.md](CONTENT_PACKS.md) |
| 输出 | `.cache/wc3-assets/<logicalPath>` 镜像原始结构 |
| 清单 | `.cache/manifest.json`：`version` / `gameDir` / `extractedAt` / `files: { logicalPath → sourceMpq, size, sha256 }` |
| 排除 | 通用 npm ignores；StormLib DLL 不进 git |

常用选项：

```bash
# 全量重解
npm run extract -- --game-dir "C:/Path/To/Warcraft III" --force

# 只解单位与 UI（加快开发迭代）
npm run extract -- --game-dir "C:/Path/To/Warcraft III" --include "Units/**" --include "UI/**"

# 冒烟验证（无客户端时也能跑）
npm run extract -- --game-dir "C:/definitely-not-wc3"
# → 提示未找到 War3.mpq 等
```

### 阶段 2：转换贴图 + 模型（BLP/MDX → PNG/GLB）

工具：[`tools/asset-convert/`](../../tools/asset-convert/)

```bash
cd tools/asset-convert
npm install

# 默认：BLP→PNG，再 MDX→GLB
npm run convert --

# 子集（步兵）
npm run convert -- --include "Units/Human/Footman/**" --include "Textures/Footman.blp" --include "Textures/gutz.blp"

# 分步
npm run convert:textures --
npm run convert:models --
```

| 输入 | 输出 | 备注 |
|------|------|------|
| `*.blp` | 同逻辑路径的 `*.png` | `war3-model` 解码 + `pngjs`；UV 不做 1-V 翻转 |
| `*.mdx` / `*.mdl` | 同逻辑路径的 `*.glb` | `@gltf-transform/core`；Y-up，~0.01 缩放（与 `Wc3Coords.WORLD_SCALE` 一致）；贴图嵌入 GLB；扁平 Armature + 等权蒙皮；每个 Sequence → 一条 glTF Animation；GeosetAnim 显隐按帧 |

**默认顺序**：`textures → models`。模型材质引用 PNG；若 PNG 尚未生成，转换模型时会**即时从 BLP 补转**。

**已知问题**：
- MDX `TVertices` 不做 `1-V` 翻转
- 队伍色：优先选用带真实路径的材质层
- GeosetAnim alpha=0 网格（如死亡内脏）默认 scale=0
- `FilterMode=1` 用 MASK + cutoff 0.75
- `FilterMode=2` Blend：glTF 仍标 BLEND；Godot `MapModelCache` 改为 `ALPHA_SCISSOR`（阈值 0.08），且 **每次 instance 都再修**（避免旧 .scn 跳过修正）
- `FilterMode=3/4` Additive：材质名 `_fm3/_fm4`，Godot 改为 ADD

### 阶段 3：SLK 表导出

工具：[`tools/slk-export/`](../../tools/slk-export/)

```bash
cd tools/slk-export
npm install
node src/cli.js

# 子集 + 覆盖
node src/cli.js --include "Units/**" --overwrite
```

| 项 | 值 |
|----|-----|
| 输入 | `.cache/wc3-assets/**/*.slk` |
| 输出 | `assets/slk-exported/<逻辑路径>.json` + `index.json` 汇总 |
| 排除 | `File*.slk`、`NotUsed_*`、`Custom_V*`、`Melee_V0` |
| 格式 | JSON（已弃用 CSV） |

输出形如：

```json
{
  "source": "Units/UnitData.slk",
  "headers": ["unitID", "sort", "comment(s)", "..."],
  "recordCount": 812,
  "records": [
    { "unitID": "hfoo", "race": "human", "comment(s)": "Footman", "...": "..." }
  ]
}
```

**关键表**（按 Autoload `Wc3DefStore` 自动注册）：

| 逻辑路径 | 表名 | 主键 | 用途 |
|----------|------|------|------|
| `TerrainArt/Terrain.slk` | `Terrain` | `tileID` | 地表 tile ID → 贴图（`TerrainTileDef`） |
| `TerrainArt/CliffTypes.slk` | `CliffTypes` | `cliffID` | 悬崖类型（`CliffTypeDef`） |
| `TerrainArt/Water.slk` | `Water` | `waterID` | 水面参数（`WaterTypeDef`） |
| `TerrainArt/Weather.slk` | `Weather` | `effectID` | 天气（`WeatherEffectDef`） |
| `Units/unitUI.slk` | — | — | 单位模型/缩放/图标（`Wc3IdCatalog`） |
| `Units/UnitData.slk` | — | — | 单位基础定义 |
| `Units/UnitBalance.slk` | — | — | 生命/成本平衡 |
| `Units/UnitWeapons.slk` | — | — | 武器与攻击 |
| `Units/AbilityData.slk` | — | — | 技能数据 |
| `Units/ItemData.slk` | — | — | 物品 |
| `Doodads/Doodads.slk` | — | — | 装饰物 |

### 阶段 4：地图解析

工具：[`tools/map-parse/`](../../tools/map-parse/)

```bash
# 先确保 tools/mpq-extract 装好（依赖 StormLib）
cd tools/mpq-extract && npm install && cd ../map-parse

# 默认测试图：冰封王座 Lost Temple
npm run parse --

# 指定图
npm run parse -- --map "C:/war3/Maps/FrozenThrone/(4)LostTemple.w3x" --force

# 不写完整格点（文件更小）
npm run parse -- --no-tilepoints

# 额外导出原始 war3map.*
npm run parse -- --raw
```

| 项 | 值 |
|----|-----|
| 输入 | `.w3x` / `.w3m` MPQ（**经典 TFT**，version 25，非新版 v33） |
| 输出 | `assets/map-parsed/<slug>/`：`summary.json` / `info.json` / `terrain.json` / `terrain-heightfield.json` / `terrain-tilepoints.json`（`--tilepoints`）/ `units.json` / `doodads.json` / `strings.json` / `regions.json` / `cameras.json` |
| 已支持 | `war3map.w3i v25` / `war3map.w3e v11` / `war3mapUnits.doo` / `war3map.doo v8` / `war3map.wts` / `war3map.w3r` / `war3map.w3c` |

> 自研原因：npm `wc3maptranslator@5` 面向新版 w3i（v33），经典 TFT 地图（v25）无法直接用。

### 阶段 5：编辑器资产同步

工具：[`tools/sync-editor-assets.mjs`](../../tools/sync-editor-assets.mjs)

```bash
node tools/sync-editor-assets.mjs
# → assets/asset-converted/UI/WorldEditData.txt 等
```

把经典 World Editor 的 UI 配置 txt 同步到 `asset-converted/UI/`，供编辑器加载。

### 阶段 6：运行时解析（Autoload）

实现：[`addons/asset_provider/asset_provider.gd`](../../addons/asset_provider/asset_provider.gd)（Autoload `AssetProvider`）

```gdscript
# 推荐：经 RuntimeAssets（地图代码统一入口）
var tex := RuntimeAssets.load_converted_texture("Textures/ShorelineParticleXY.png")
var glb := RuntimeAssets.converted_path("Units/Human/Footman/Footman.glb")

# 或经 AssetProvider（含 cache / overlay 完整查找）
var abs_path: String = AssetProvider.resolve("Textures/ShorelineParticleXY.blp")
var bytes := AssetProvider.open("...").get_buffer(...)
```

**查找顺序**：

1. `register_overlay(mod_id, root)` 注册的 mod 根（**后注册优先**）
2. `assets/asset-converted/`（开发期转换产物：PNG/GLB）
3. `.cache/wc3-assets/`（解包原始 BLP/MDX）

**扩展名自动尝试**：`.blp`→`.png`、`.mdx`/`.mdl`→`.glb`、无扩展名追加 `.png`/`.glb`。

**Project Settings 覆盖**：

| 键 | 含义 | 默认 |
|----|------|------|
| `warcraft3/asset_cache_dir` | 覆盖 `.cache/wc3-assets` 绝对路径 | `res://.cache/wc3-assets` |
| `warcraft3/asset_converted_dir` | 覆盖 converted 绝对路径 | `res://assets/asset-converted` |

**Mod 机制**（已预留）：

```gdscript
AssetProvider.register_overlay("my_mod", "/path/to/mods/my_mod")
# 同 logical_path 后注册者覆盖前注册者
AssetProvider.clear_overlays()
```

## 3. 路径与忽略

| 路径 | 内容 | gitignore |
|------|------|-----------|
| `.cache/wc3-assets/` | 原始解包（MPQ 镜像） | ✅ |
| `.cache/manifest.json` | 解包清单 | ✅ |
| `assets/asset-converted/` | 转换后 PNG/GLB | ✅ + `.gdignore`（编辑器不导入） |
| `assets/slk-exported/` | SLK 导出 JSON | ✅ |
| `assets/map-parsed/<slug>/` | 地图 JSON | ✅ |
| `mods/<id>/` | Mod 覆盖 | 内容不提交 |
| `tools/*/node_modules/` | Node 依赖 | ✅ |

> **导入卡死说明**：`assets/asset-converted/` 可达数万文件，已加 `.gdignore`，编辑器不再导入该目录；PNG/GLB 由运行时按需加载。若仍卡在旧导入：结束 Godot → 删除项目下 `.godot/imported/` → 再开。

## 4. 推荐运行顺序（首次设置）

**优先用一键脚本**（解包 + SLK + 地图 + 转换 + Godot PE2/visuals）：

```bash
# 仓库根目录；详见 tools/README.md
node tools/dev-setup.mjs --game-dir "C:/Path/To/Warcraft III"
# Windows: .\tools\Dev-Setup.ps1 -GameDir "C:\Path\To\Warcraft III"
```

默认 `--profile game` ≈ Echo Isles + 人族 Melee 子集。全量用 `--profile full`。

手工分步（等价于旧流程）：

```bash
# 1. 解包原始
cd tools/mpq-extract && npm install
npm run extract -- --game-dir "C:/Path/To/Warcraft III"

# 2. 转换贴图 + 模型（开发推荐 echo-isles 子集）
cd ../asset-convert && npm install
npm run convert:echo-isles --
# 或全量: npm run convert --

# 3. 导出 SLK 表
cd ../slk-export && npm install
node src/cli.js

# 4. 解析地图（Echo Isles / Lost Temple）
cd ../map-parse && npm install
npm run parse -- --map "C:/war3/Maps/FrozenThrone/(2)EchoIsles.w3x" --force

# 5. 同步编辑器 UI + Godot 特效预制
cd ../..
node tools/sync-editor-assets.mjs
node tools/export-godot-assets.mjs --include Buildings/Human/ --force

# 6. 打开 Godot → 运行 game/scenes/game_main.tscn
```

## 5. 何时查哪里

- 改解包逻辑 → `tools/mpq-extract/src/cli.js`
- 改贴图 / 模型转换 → `tools/asset-convert/src/`
- 改表解析 → `tools/slk-export/src/cli.js`
- 改地图解析 → `tools/map-parse/src/`
- 改路径解析 → [`addons/asset_provider/asset_provider.gd`](../../addons/asset_provider/asset_provider.gd)
- 改加载顺序 / 开关 → [`scripts/map/presentation/map_loader.gd`](../../scripts/map/presentation/map_loader.gd)

## 6. 后续（未实现）

- **玩家首次运行**：选择本机经典安装路径 → GDExtension + StormLib 解包到 `user://wc3_cache/`，manifest 语义与开发工具一致
- **Mod 覆盖**：`mods/<id>/` 用相同逻辑路径覆盖缓存；`AssetProvider.register_overlay` 已预留
- **GDExtension 直链 StormLib**：不依赖 Node.js（玩家端规划）
