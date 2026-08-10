# 魔兽争霸3 经典资产路径手册

本文描述**经典客户端**（MPQ，非 Reforged/CASC）解包后的**逻辑路径**约定：每个顶层目录放什么、常见子目录含义、以及如何按路径找资源。

- 本机解包根目录：`.cache/wc3-assets/`（与 MPQ 内路径一一对应）
- 清单索引：`.cache/manifest.json`（`logicalPath` → 来源 MPQ / 大小 / 哈希）
- 转换后资源：`assets/asset-converted/`（PNG/GLB，路径结构与逻辑路径相同，扩展名不同）
- 合规：勿把解包资产提交 Git，见 [LEGAL.md](LEGAL.md)

路径一律使用正斜杠，例如 `Units/Human/Footman/Footman.mdx`。Windows 上查找时大小写通常不敏感，但 MPQ 内可能同时存在 `Buildings/` 与 `buildings/`、`Abilities/` 与 `abilities/`（来自不同归档层），以 `manifest.json` 中的键为准。

文件数量统计来自本仓库一次完整解包样本（约 1.7 万条目），你的客户端/补丁若不同，数量会有出入，**目录语义不变**。

---

## 1. 常见文件类型

| 扩展名 | 含义 | 本项目用法 |
|--------|------|------------|
| `.mdx` / `.mdl` | 3D 模型（含骨骼、动画序列） | `asset-convert` → `.glb` |
| `.blp` | 暴雪贴图（单位皮、UI、地形等） | `asset-convert` → `.png` |
| `.tga` | 路径图、部分特效/旧贴图 | 寻路遮罩、部分环境资源 |
| `.slk` | 表格数据（单位数值、地形类型、升级等） | `tools/slk-export` → JSON |
| `.txt` | 键值配置与本地化字符串（Func/Strings） | 单位名、技能描述、杂项参数 |
| `.j` | JASS 脚本（`common.j`、`Blizzard.j`） | 地图/触发公共库 |
| `.ai` | 对战/战役 AI 脚本 | AI 行为 |
| `.wav` / `.mp3` | 音效与部分音乐 | 音频 |
| `.pld` | 过场/字幕时间轴类数据 | 战役演出 |
| `.w3m` / `.w3x` | 地图包（本身也是带头的 MPQ） | `map-parse` |
| `.w3n` | 战役包 | 战役流程 |

地图**内部**还有 `war3map.w3e`、`war3mapUnits.doo` 等，见 [map-parse README](../../tools/map-parse/README.md)，不在全局资产树里。

---

## 2. 顶层目录速查

| 逻辑路径 | 大约内容 | 典型用途 |
|----------|----------|----------|
| [`Units/`](#3-units单位与数据表) | 单位模型 + 全局 SLK/TXT 数据表 | 步兵、英雄、野怪、物品数据 |
| [`Buildings/`](#4-buildings建筑物) / `buildings/` | 建筑模型（大小写两套可能并存） | 基地、兵营、防御塔 |
| [`Doodads/`](#5-doodads装饰物与可破坏物) | 树、岩石、桥梁等装饰模型 | 地图摆件、可砍伐树木 |
| [`Textures/`](#6-textures共享贴图池) | 大量共享 `.blp`（扁平目录） | 模型材质引用的贴图 |
| [`ReplaceableTextures/`](#7-replaceabletextures可替换贴图) | 队伍色、技能图标、水体、树叶等 | 运行时替换/UI 按钮 |
| [`TerrainArt/`](#8-terrainart地形美术) | 各地形 tileset 地表贴图 + 地形 SLK | 地面、悬崖、水体、天气表 |
| [`UI/`](#9-ui界面) | 菜单、控制台、光标、小地图、Frame 定义 | 游戏内 HUD / 胶水界面 |
| [`Sound/`](#10-sound声音) | 环境、单位、建筑、对白、音乐 | 音效与 BGM |
| [`Abilities/`](#11-abilities技能特效) / `abilities/` | 技能与投射物特效模型/贴图 | 暴风雪、光环、导弹 |
| [`Objects/`](#12-objects杂项对象) | 出生点、掉落物、出生特效、过场相机 | 地图物件与演出辅助 |
| [`Scripts/`](#13-scripts脚本) | JASS / AI / 过场 PLD | 脚本与近战 AI |
| [`PathTextures/`](#14-pathtextures寻路遮罩) | 建筑/装饰占用格 TGA | 碰撞与可建造区域 |
| [`SharedModels/`](#15-sharedmodels共享模型碎片) | 出生/死亡/通用粒子小模型 | 多单位共用特效 |
| [`Environment/`](#16-environment环境) | 天空盒、昼夜、建筑着火等 | 场景氛围 |
| [`Splats/`](#17-splats地面印记数据) | 地面印记/出生印记 SLK | 脚印、技能地面贴花规则 |
| [`Fonts/`](#18-fonts字体) | TTF 字体 | UI 文字 |
| [`Maps/`](#19-maps内置地图) | 客户端自带地图/战役相关 | 官方图；本地 `C:\war3\Maps\` 也可能另有一份 |

根目录还可能散落：安装说明 HTML、嵌套小 MPQ（如 `L.mpq` 等地形包）、未知名 `File00000xxx.*`（补丁/本地化残留）。**游戏资源查找优先用上表有语义的路径**，不要依赖 `File00000xxx`。

---

## 3. `Units/` — 单位与数据表

### 3.1 模型目录（按种族/类别）

结构：`Units/<阵营或类别>/<单位名>/<单位名>.mdx`（常伴 `_Portrait.mdx`、同名或共享 `.blp`）。

| 子路径 | 内容 |
|--------|------|
| `Units/Human/` | 人族单位与英雄（如 `Footman/Footman.mdx`） |
| `Units/Orc/` | 兽族 |
| `Units/Undead/` | 不死族 |
| `Units/NightElf/` | 暗夜精灵 |
| `Units/Naga/` | 娜迦（冰封王座） |
| `Units/Creeps/` | 野怪、中立敌对（豺狼人、巨魔、龙等） |
| `Units/Critters/` | 小动物（羊、鸡等） |
| `Units/Demon/` | 恶魔相关单位 |
| `Units/Other/` | 中立建筑单位、特殊单位等杂项 |

**查找示例**

- 步兵模型：`Units/Human/Footman/Footman.mdx`
- 步兵肖像：`Units/Human/Footman/Footman_Portrait.mdx`
- 金矿：在 `Units/Other/` 或中立相关目录中搜 `GoldMine`（具体以 manifest 为准）

### 3.2 根下数据表（玩法核心）

这些文件在 `Units/` **根目录**（不是某个种族子文件夹里）：

| 文件 | 作用 |
|------|------|
| `UnitData.slk` | 单位基础定义（四字符 ID、类别等） |
| `UnitBalance.slk` | 生命、护甲、成本、建造时间等平衡 |
| `UnitWeapons.slk` | 武器、射程、攻击类型 |
| `UnitAbilities.slk` | 单位自带技能列表 |
| `unitUI.slk` | 模型路径、图标、选中圈等 UI 绑定 |
| `UnitMetaData.slk` | 物编元数据（字段类型） |
| `AbilityData.slk` / `AbilityMetaData.slk` | 技能数据与元数据 |
| `UpgradeData.slk` / `UpgradeMetaData.slk` 等 | 升级 |
| `ItemData.slk` | 物品 |
| `DestructableData.slk` | 可破坏物（树、大门等）数据 |
| `*UnitFunc.txt` / `*UnitStrings.txt` | 各族单位功能参数与显示名/提示 |
| `*AbilityFunc.txt` / `*AbilityStrings.txt` | 技能参数与描述 |
| `*UpgradeFunc.txt` / `*UpgradeStrings.txt` | 升级 |
| `ItemFunc.txt` / `ItemStrings.txt` | 物品 |
| `CommandFunc.txt` / `CommandStrings.txt` | 命令按钮与提示 |
| `MiscData.txt` / `MiscGame.txt` | 全局杂项数值与规则 |

四字符单位 ID（如 `hfoo` 步兵、`ngol` 金矿）主要在 SLK/`war3mapUnits.doo` 中出现；模型文件夹名多为英文可读名。

---

## 4. `Buildings/` — 建筑物

结构与单位类似：`Buildings/<阵营>/<建筑名>/...`

| 子路径 | 内容 |
|--------|------|
| `Buildings/Human/` | 人族建筑（城镇大厅、兵营、农场等） |
| `Buildings/Orc/` | 兽族建筑 |
| `Buildings/Undead/` | 不死建筑 |
| `Buildings/NightElf/` | 暗夜建筑 |
| `Buildings/Naga/` | 娜迦建筑 |
| `Buildings/Demon/` | 恶魔建筑 |
| `Buildings/Other/` | 中立建筑、特殊建筑（商店、市场等） |

注意：解包结果里可能还有小写 `buildings/`，内容常为补丁或扩展层增量。查找时两个都搜，或只信 `manifest.json`。

---

## 5. `Doodads/` — 装饰物与可破坏物

结构：`Doodads/<地形主题或类别>/...`，并带有数据表。

| 子路径 / 文件 | 内容 |
|---------------|------|
| `Doodads/Terrain/` | 通用地形装饰（体量通常最大） |
| `Doodads/LordaeronSummer/`、`Ashenvale/`、`Barrens/`、`Northrend/`、`Icecrown/`、`Outland/`、`Ruins/` 等 | 与 tileset 配套的主题装饰 |
| `Doodads/Cityscape/`、`Dalaran/`、`Village/`、`Dungeon/`、`Underground/`、`Felwood/`、`BlackCitadel/` | 城市场景、地下城等 |
| `Doodads/Cinematic/` | 过场专用装饰 |
| `Doodads/Doodads.slk` | 装饰物 ID、模型路径、尺寸等 |
| `Doodads/DoodadMetaData.slk` | 物编元数据 |

地图里的 `war3map.doo` 用四字符 ID（如 `WTst` 雪树）引用此处模型；解析结果见 `assets/map-parsed/*/doodads.json`。

---

## 6. `Textures/` — 共享贴图池

- **扁平**存放大量 `.blp`（单位皮、特效片、部分建筑/装饰贴图）。
- 模型材质常写 `Textures/Footman.blp` 这类路径，而不是放在单位文件夹内。
- 命名多为资源英文名：`Footman.blp`、`Arthas.blp`、`gutz.blp` 等。

**查找技巧**：先打开 `.mdx`/转换后的 GLB 看材质名，再到 `Textures/` 与 `ReplaceableTextures/` 下按文件名搜。

---

## 7. `ReplaceableTextures/` — 可替换贴图

运行时或编辑器会按规则替换的贴图，以及大量 UI 图标。

| 子路径 | 内容 |
|--------|------|
| `TeamColor/` | 队伍色色块（`TeamColor00.blp` …） |
| `TeamGlow/` | 队伍光晕 |
| `CommandButtons/` | 技能/命令按钮图标（可用） |
| `CommandButtonsDisabled/` | 禁用态按钮图标 |
| `PassiveButtons/` | 被动技能图标 |
| `Water/` | 水体动画帧 |
| `Weather/` | 天气粒子相关 |
| `Cliff/` | 悬崖相关替换贴图 |
| `Splats/` | 地面印记贴图 |
| `Selection/` | 选中相关 |
| `Shadows/` | 阴影贴图 |
| `*Tree/`（如 `LordaeronTree/`、`AshenvaleTree/`） | 各 tileset 树木叶子/树干替换 |
| `WorldEditUI/` | 世界编辑器 UI 图 |
| `CameraMasks/` | 相机遮罩 |
| `Occlusion/` | 遮挡相关 |

单位模型里「品红」层通常对应 Replaceable ID（队伍色），真正贴图路径可能为空，需映射到 `TeamColor/`。

---

## 8. `TerrainArt/` — 地形美术

| 子路径 / 文件 | 内容 |
|---------------|------|
| `TerrainArt/<Tileset名>/` | 该地形的地表 `.blp`（泥地、草、雪、砖等） |
| 常见 Tileset 文件夹 | `LordaeronSummer`、`LordaeronFall`、`LordaeronWinter`、`Ashenvale`、`Barrens`、`Northrend`、`Icecrown`、`Dungeon`、`Felwood`、`Cityscape`、`Dalaran`、`Village`、`Outland`、`Ruins`、`BlackCitadel`、`DalaranRuins` 等 |
| `TerrainArt/Blight/` | 枯萎地表 |
| `TerrainArt/Terrain.slk` | 地表 tile 四字符 ID → 贴图（地图 `w3e` 里的 `Idrt`、`Ldrt` 等在此查） |
| `TerrainArt/CliffTypes.slk` | 悬崖类型 |
| `TerrainArt/Water.slk` | 水体参数 |
| `TerrainArt/Weather.slk` | 天气效果 ID |

Lost Temple 使用 Icecrown（主 tileset `I`），地表 ID 如 `Idrt`、`Iice` 等，对应 `TerrainArt/Icecrown/` 与 `Terrain.slk`。

---

## 9. `UI/` — 界面

| 子路径 / 文件 | 内容 |
|---------------|------|
| `UI/Glues/` | 游戏外壳菜单（开始界面、战役、多人对战大厅等「胶水」UI） |
| `UI/Console/` | 游戏内底部控制台（各族：`Human/`、`Orc/` 等） |
| `UI/Widgets/` | 通用控件贴图与布局资源 |
| `UI/Cursor/` | 鼠标指针 |
| `UI/Feedback/` | 点击、警告等反馈特效/图 |
| `UI/MiniMap/`、`UI/Minimap/` | 小地图框与图标（注意大小写两种可能） |
| `UI/Buttons/` | 部分按钮资源 |
| `UI/FrameDef/` | Frame 定义（界面布局脚本类文本） |
| `UI/Captions/` | 字幕相关 |
| `UI/SoundInfo/` | UI 音效索引类数据 |
| `UI/*Strings.txt`、`TriggerData.txt`、`WorldEdit*.txt` 等 | 界面文案、触发器/物编用字符串与配置 |

游戏内 HUD 优先看 `UI/Console/`；主菜单看 `UI/Glues/`。

---

## 10. `Sound/` — 声音

| 子路径 | 内容 |
|--------|------|
| `Sound/Music/` | 主题音乐、战斗/失败等 BGM |
| `Sound/Units/` | 单位应答、攻击、死亡等 |
| `Sound/Buildings/` | 建筑相关音效 |
| `Sound/Interface/` | UI 点击、提示音 |
| `Sound/Ambient/` | 环境氛围 |
| `Sound/Dialogue/` | 战役/单位对白（体量最大） |
| `Sound/Destructibles/` | 可破坏物 |
| `Sound/Time/` | 与昼夜/时间相关的少量音效 |

---

## 11. `Abilities/` — 技能特效

结构：`Abilities/Spells/<阵营或类别>/<技能名>/` 与 `Abilities/Weapons/`。

| 子路径 | 内容 |
|--------|------|
| `Abilities/Spells/Human|Orc|Undead|NightElf|.../` | 各族法术特效模型与贴图 |
| `Abilities/Spells/Other/`、`Items/`、`Demon/` 等 | 中立、物品、恶魔技能特效 |
| `Abilities/Weapons/` | 攻击弹道、武器轨迹类模型 |

同样可能存在小写 `abilities/`。技能**数值与图标路径**在 `Units/AbilityData.slk` 与 `ReplaceableTextures/CommandButtons/`，特效模型在本目录。

---

## 12. `Objects/` — 杂项对象

| 子路径 | 内容 |
|--------|------|
| `Objects/StartLocation/` | 出生点模型 |
| `Objects/InventoryItems/` | 地上物品模型（宝箱、神器外观等） |
| `Objects/Spawnmodels/` | 单位训练完成/召唤等出生特效 |
| `Objects/CinematicCameras/` | 过场相机路径模型 |
| `Objects/CameraHelper/` | 相机辅助 |
| `Objects/RandomObject/` | 随机物件占位 |
| `Objects/Invalidmodel/`、`InvalidObject/` | 缺失资源时的占位模型 |

---

## 13. `Scripts/` — 脚本

| 类型 | 说明 |
|------|------|
| `Scripts/common.j` | JASS 原生/类型公共定义 |
| `Scripts/Blizzard.j` | 暴雪通用库（BJ 函数等） |
| `Scripts/Cheats.j`、`InitCheats.j` | 作弊相关 |
| `Scripts/human.ai`、`orc.ai`、`undead.ai`、`elf.ai`、`common.ai` | 近战 AI |
| `Scripts/*.ai`（如 `h05_green.ai`） | 战役关卡专用 AI |
| `Scripts/*.pld` | 过场字幕/时间轴 |

地图自带脚本在地图包内的 `war3map.j`，不在此目录。

---

## 14. `PathTextures/` — 寻路遮罩

- 大量 `*x*.tga`（如 `4x4Default.tga`、`16x16Goldmine.tga`）。
- 表示建筑/装饰在路径网格上的占用形状（可建造、不可飞行等）。
- 与 `Buildings`/`Doodads` 数据中的 pathtex 字段对应。

---

## 15. `SharedModels/` — 共享模型碎片

短小的通用 MDX/贴图：出生动画零件、羽毛、内脏飞溅（`Gutz`）、通用光晕等，供多个单位/技能引用。

---

## 16. `Environment/` — 环境

| 子路径 | 内容 |
|--------|------|
| `Environment/Sky/` | 天空盒 |
| `Environment/DNC/` | 昼夜光照相关 |
| `Environment/*BuildingFire/` | 建筑着火特效（小/大/各族） |
| `Environment/BlightDoodad/` | 枯萎相关装饰 |

---

## 17. `Splats/` — 地面印记数据

主要为 SLK：`SplatData.slk`、`SpawnData.slk`、`UberSplatData.slk` 等，描述脚印、技能地面贴花如何贴到地形上。贴图资源多在 `ReplaceableTextures/Splats/`。

---

## 18. `Fonts/` — 字体

客户端 UI 使用的 TTF（含西文与部分东亚字体文件名）。Godot 侧是否直接使用另议；逻辑路径仍可按此查找。

---

## 19. `Maps/` — 内置地图

MPQ 内可能带有官方地图副本。本机更常见的是安装目录下的：

- `C:\war3\Maps\`（人族战役/对战等）
- `C:\war3\Maps\FrozenThrone\`（冰封王座对战图，如 `(4)LostTemple.w3x`）

解析后的 JSON 在 `assets/map-parsed/`，**不是** MPQ 逻辑路径的一部分。

---

## 20. 按需求查找（速查表）

| 我想找… | 去哪里 |
|---------|--------|
| 某个兵种的模型和动画 | `Units/<种族>/<英文名>/` |
| 单位贴图 | 单位目录内 `.blp`，或 `Textures/<名>.blp` |
| 队伍色 | `ReplaceableTextures/TeamColor/` |
| 技能按钮图 | `ReplaceableTextures/CommandButtons/` |
| 技能特效模型 | `Abilities/Spells/...` |
| 建筑模型 | `Buildings/<种族>/` |
| 树/石头装饰 | `Doodads/<地形主题>/` + `Doodads.slk` |
| 地形皮肤与 tile ID | `TerrainArt/<Tileset>/` + `Terrain.slk` |
| 单位生命/攻击等数值 | `Units/UnitBalance.slk`、`UnitWeapons.slk` |
| 单位显示名称 | `Units/*UnitStrings.txt` |
| 游戏内底板 UI | `UI/Console/<种族>/` |
| 主菜单 UI | `UI/Glues/` |
| 单位语音 | `Sound/Units/` |
| 背景音乐 | `Sound/Music/` |
| 出生点模型 | `Objects/StartLocation/` |
| JASS 标准库 | `Scripts/common.j`、`Blizzard.j` |
| 四字符 ID 对应模型 | `Units/unitUI.slk` 或 `Doodads/Doodads.slk` |

---

## 21. 推荐工作流

1. 在 `.cache/manifest.json` 的 `files` 键里按关键字搜索（如 `Footman`、`ngol`、`Icecrown`）。
2. 用资源管理器或 `rg` 在 `.cache/wc3-assets/` 下搜文件名。
3. 需要进 Godot 时：对目标路径跑 `tools/asset-convert`，产物在 `assets/asset-converted/` 下同逻辑路径。
4. 地图摆放数据：先 `tools/map-parse`，再根据 `units.json` / `doodads.json` 的四字符 ID 回到本手册对应目录找模型。
5. Godot 灰盒预览：运行主场景 `scenes/main.tscn`（读 `assets/map-parsed/losttemple/` + `terrain-heightfield.json`）。

---

## 22. 与本项目路径的对应关系

```text
MPQ 逻辑路径
  Units/Human/Footman/Footman.mdx
       │
       ├─ 解包 → .cache/wc3-assets/Units/Human/Footman/Footman.mdx
       │
       └─ 转换 → assets/asset-converted/Units/Human/Footman/Footman.glb
                    （贴图多为嵌入或同目录/Textures 下的 .png）
```

游戏代码应通过逻辑路径（`AssetProvider`）访问，而不是写死磁盘绝对路径。

---

## 23. 维护说明

- 若你重新全量解包后顶层目录有增减，以新的 `manifest.json` 为准，可更新本文统计数字。
- Reforged（CASC）目录布局与经典 MPQ **不同**，本文不适用。
- 发现某条路径在经典版中的用途与本文不符时，以游戏内实际引用（SLK / 模型材质路径）为准并修正本文。
