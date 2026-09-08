# godot_warcraft3

用 **Godot 4.6** 复刻《魔兽争霸3》玩法的实验项目。

仓库**不含**暴雪游戏资产。开发前须自备正版**经典**客户端（含 `War3.mpq` / `War3x.mpq`，不是仅有 `Data/` 的现代 CASC）。合规说明：[docs/data/LEGAL.md](docs/data/LEGAL.md)。

| 入口 | 场景 |
|------|------|
| **对战壳（推荐）** | `game/scenes/game_main.tscn`（Echo Isles，F6） |
| 地图编辑器 | `editor/scenes/editor_main.tscn` |
| 文档索引 | [docs/README.md](docs/README.md) |

---

## 新电脑：一条命令准备资源

### 前置

- [Godot 4.6](https://godotengine.org/)（建议 **console** 版 exe，便于 headless）
- [Node.js 18+](https://nodejs.org/)
- 经典 WC3 安装目录（能看到 `War3.mpq`）

建议先设环境变量（可选，命令行也可传）：

```powershell
$env:WC3_GAME_DIR = "D:\Program Files (x86)\Warcraft3"
$env:GODOT = "D:\Godot\Godot_v4.6.3-stable_win64_console.exe"
```

### 一键流水线（推荐）

在仓库根目录：

```powershell
# Windows
.\tools\Dev-Setup.ps1 -GameDir $env:WC3_GAME_DIR -Godot $env:GODOT

# 或跨平台
node tools/dev-setup.mjs --game-dir "D:/Program Files (x86)/Warcraft3"
```

默认 `--profile game` 会依次：

1. `npm install`（`mpq-extract` / `asset-convert` / `slk-export` / `map-parse`）
2. MPQ 解包 → `.cache/wc3-assets/`（**仅中间态**；运行时不读）
3. SLK → `assets/slk-exported/`
4. 解析 Echo Isles → `assets/map-parsed/echoisles/`
5. 转换人族 Melee + Lordaeron 子集 → `assets/asset-converted/`（含自动 bake `.scn`）
6. `sync-data-assets`：UnitFunc/UI txt → `slk-exported`；PathTextures → `asset-converted`
7. Godot headless：bake `.scn`（含 PE2）

完成后用 Godot 打开本仓库，运行 `game/scenes/game_main.tscn`。

更多选项见：

```bash
node tools/dev-setup.mjs --help
```

| 常用 | 说明 |
|------|------|
| `--profile lost-temple` | Lost Temple 可视复原子集 |
| `--profile full` | 全量转换（很慢） |
| `--profile deps-only` | 只装 npm 依赖 |
| `--maps echoisles,losttemple` | 多图解析 |
| `--skip-godot` | 暂无 Godot 时跳过 bake/PE2 |
| `--only convert` | 只重跑某一步 |
| `--force` | 强制重解/重转 |

工具总览与分步说明：[tools/README.md](tools/README.md)。管线细节：[docs/data/PIPELINE.md](docs/data/PIPELINE.md)。

### 仅补导 Godot 特效 / 场景

资源已转换、只想重烤 `.scn`（含 PE2）：

```bash
node tools/export-godot-assets.mjs --include Buildings/Human/ --force
```

等价于调用 `scripts/tool/export_model_scenes.gd`（GLB→`.scn`，**含 PE2**），可选再导 `assets/visuals/`。

---

## 产物目录（均不提交）

| 路径 | 说明 |
|------|------|
| `.cache/wc3-assets/` | MPQ 解包**中间态**（工具用；游戏/编辑器禁止依赖） |
| `assets/asset-converted/` | 视觉车道：PNG / GLB / `.scn`（内嵌 PE2）/ PathTextures（`.gdignore`） |
| `assets/slk-exported/` | 数据车道：SLK JSON + UnitFunc/Strings + UI txt |
| `assets/map-parsed/` | 地图车道：解析 JSON（如 echoisles） |
| `assets/visuals/` | 模型视觉封装 tscn（薄继承，可选） |

逻辑路径与经典客户端一致。运行时经 Autoload `AssetProvider`：**overlay → converted → slk-exported**（不读 `.cache`）。

三车道契约：[docs/architecture/ASSET_LANES.md](docs/architecture/ASSET_LANES.md)。路径手册：[docs/data/WC3_ASSET_PATHS.md](docs/data/WC3_ASSET_PATHS.md)。

---

## 冒烟检查

1. `.cache/wc3-assets/` 非空（bootstrap 中间态），且存在 `.cache/manifest.json`
2. `assets/slk-exported/Units/UnitBalance.json` 与 `HumanUnitFunc.txt` 存在
3. `assets/map-parsed/echoisles/summary.json` 存在
4. `assets/asset-converted/Buildings/Human/TownHall/` 下有 `.glb`（或 `.scn`）；`PathTextures/` 非空
5. Godot 运行 `game_main`：能看到主城、农民可框选右键移动

热键：`S` 停止选中单位 · `F9` 路径调试线。

---

## 文档与架构

- 分层总纲：[docs/architecture/LAYERED_ARCHITECTURE.md](docs/architecture/LAYERED_ARCHITECTURE.md)
- 资产三车道：[docs/architecture/ASSET_LANES.md](docs/architecture/ASSET_LANES.md)
- 游戏场景：[docs/game/README.md](docs/game/README.md) · 寻路选型：[docs/game/PATHFINDING_CHOICE.md](docs/game/PATHFINDING_CHOICE.md)
- 地图编辑器：[docs/editor/EDITOR.md](docs/editor/EDITOR.md)
- 水体：[docs/water/WATER.md](docs/water/WATER.md)
- 路线图：[docs/roadmap/NEXT.md](docs/roadmap/NEXT.md)（近中期）· [docs/roadmap/ROADMAP.md](docs/roadmap/ROADMAP.md)（地图 ①–⑫）

---

## 开发依赖说明

- 解包通过 [koffi](https://koffi.dev/) 调预编译 [StormLib](https://github.com/ladislav-zezula/StormLib)（`npm install` 时自动拉取 Windows x64 DLL）。非 Windows 需自备兼容库并设 `STORMLIB_DLL`。
- Godot headless 依赖本机 `GODOT`；找不到时转换仍可产出 GLB，但会跳过 `.scn` / PE2 / visuals。
- `assets/asset-converted/` 文件极多且已 `.gdignore`。若编辑器卡在旧导入：关 Godot → 删 `.godot/imported/` → 再开。
