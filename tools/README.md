# tools/

离线资产管线：解包 → 转换 → 表/地图 → Godot 烘焙与粒子预制。

**新设备请优先用一键脚本**，不必逐个 `cd`。

## 一键准备

```bash
# 仓库根目录
node tools/dev-setup.mjs --game-dir "<经典WC3目录>"

# Windows
.\tools\Dev-Setup.ps1 -GameDir "D:\Warcraft III" -Godot "D:\Godot\Godot_v4.6_console.exe"

# Unix
./tools/dev-setup.sh --game-dir "/path/to/Warcraft III"
```

| 脚本 | 作用 |
|------|------|
| [`dev-setup.mjs`](dev-setup.mjs) | 主编排（install → extract → slk → maps → convert → sync → godot） |
| [`Dev-Setup.ps1`](Dev-Setup.ps1) | PowerShell 包装 |
| [`dev-setup.sh`](dev-setup.sh) | bash 包装 |
| [`export-godot-assets.mjs`](export-godot-assets.mjs) | 只跑 Godot：bake `.scn` + PE2 + visuals |
| [`lib/godot-cli.mjs`](lib/godot-cli.mjs) | 定位 Godot / headless 调用 |

```bash
node tools/dev-setup.mjs --help
node tools/export-godot-assets.mjs --help
```

### 配置档（`--profile`）

| 值 | 转换范围 |
|----|----------|
| `game`（默认） | Echo Isles + 人族 Melee（[`convert-echo-isles.mjs`](asset-convert/scripts/convert-echo-isles.mjs)） |
| `lost-temple` | Lost Temple 可视子集 |
| `full` | 全量 BLP/MDX（慢） |
| `deps-only` | 仅各包 `npm install` |

### 环境变量

| 变量 | 含义 |
|------|------|
| `WC3_GAME_DIR` / `WAR3_GAME_DIR` | 经典客户端根目录 |
| `GODOT` / `GODOT_BIN` | Godot 4.x **console** 可执行文件 |
| `STORMLIB_DLL` | 非 Windows 时自备 StormLib |

---

## 工具包一览

| 目录 / 脚本 | 输入 | 输出 | 说明 |
|-------------|------|------|------|
| [`mpq-extract/`](mpq-extract/) | 经典 MPQ | `.cache/wc3-assets/` | StormLib 解包 |
| [`asset-convert/`](asset-convert/) | BLP / MDX | `assets/asset-converted/` | PNG + GLB + pe2.json；可自动 bake `.scn` |
| [`slk-export/`](slk-export/) | `.slk` | `assets/slk-exported/` | 单位/技能/地形表 |
| [`map-parse/`](map-parse/) | `.w3x` | `assets/map-parsed/<slug>/` | 地形/单位/装饰物 JSON |
| [`sync-editor-assets.mjs`](sync-editor-assets.mjs) | cache UI txt | `asset-converted/UI/` | 编辑器字符串 |
| [`extract-icecrown-replaceables.mjs`](extract-icecrown-replaceables.mjs) | War3x 内 `I.mpq` | cache 悬崖/水贴图 | Lost Temple Icecrown |
| [`gen-unit-defs.mjs`](gen-unit-defs.mjs) | slk-exported | `scripts/definitions/units/*.gd` | **会重写 Def 脚本**；改表结构时才用 |
| [`export_model_scenes.gd`](../scripts/tool/export_model_scenes.gd) | GLB | 同目录 `.scn`（含 PE2） | Godot headless |
| [`export_visual_scenes.gd`](../scripts/tool/export_visual_scenes.gd) | `.scn` | `assets/visuals/` | 薄封装（可选） |

分步细节与 AssetProvider 优先级：[docs/data/PIPELINE.md](../docs/data/PIPELINE.md)。  
asset-convert 已知问题（队伍色、Geoset 显隐、Additive）：[asset-convert/README.md](asset-convert/README.md)。

---

## 常用分步命令

```bash
# 解包
cd tools/mpq-extract && npm install
npm run extract -- --game-dir "C:/Path/To/Warcraft III"

# Echo Isles 子集转换（含 bake .scn）
cd tools/asset-convert && npm install
npm run convert:echo-isles --

# 全量 / Lost Temple
npm run convert --
npm run convert:lost-temple --

# SLK / 地图
cd tools/slk-export && npm install && node src/cli.js
cd tools/map-parse && npm install
npm run parse -- --map "C:/war3/Maps/FrozenThrone/(2)EchoIsles.w3x" --force

# 编辑器 UI
node tools/sync-editor-assets.mjs

# 重烤 TownHall .scn（含 PE2）
node tools/export-godot-assets.mjs --include Buildings/Human/TownHall --force --bake-only
```

---

## 推荐验收顺序

1. 跑通 `dev-setup`（`--profile game`）
2. Godot 打开项目 → `game/scenes/game_main.tscn`
3. 框选农民，右键地面移动；`S` 停止；`F9` 看路径线
4. 主城打开 `.scn` 播 Stand Work / Birth / Death 应见 PE2

缺图/粉模：对对应逻辑路径加 `--include` 再 `npm run convert`，或改用 `--profile full`。
