# 【老李游戏学院】01 · 我正在用 Godot 4 复刻魔兽3，但先把架构图撕了重画

> **副标题**：一份正在被打磨的分层契约——以及为什么"先写代码"是最大的浪费
>
> **关联文档**：
> - [../architecture/LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md)
> - [../roadmap/ROADMAP.md](../roadmap/ROADMAP.md)（地图 ①–⑫）
> - [../roadmap/NEXT.md](../roadmap/NEXT.md)（当前冲刺 N0–N4）
>
> **项目状态**：**正在复刻，未完工**。本文写于 2026-09-05，到发文时进度可能有微调，以仓库 commit 与 `NEXT.md` 为准。
>
> **合规说明**：仓库 `godot_warcraft3` 不含任何暴雪资产，所有 MDX / 贴图 / SLK 都从用户本机正版 War3 客户端解包（[../data/LEGAL.md](../data/LEGAL.md)）。
>
> 最后更新：2026-09-05

---

## 先说清楚——这篇是写给谁的

我现在**正在**用 Godot 4.6 复刻《魔兽争霸3》的玩法（人族 Melee 竖切跑通了，斜坡、水体、联机、完整科技树还在 todo 里）。**这篇不是复刻成功 demo，不是 Hello World，也不是 10 分钟教程。**

我重点写给两类人：

### A. 正在做或想做"复刻 / 大型 / 多模块"项目的独立开发者

你大概率也踩过这几个坑：

- 项目超过 1 万行之后，改一个功能要触发 5 个文件的 Mesh API，bug 复现不出来
- 按"对象类型"切目录（Unit/Buff/Skill/Doodad），Skill 模块 import 7 个目录的脚本，GDScript 静态解析报"Identifier not declared"
- 编辑器改一个顶点，撤销栈只能回到一半——因为有些 flag 被 Layer 改了，有些被 Logic 改了

**这篇给一份经过实战检验的解法：Data / Catalog / Logic / Presentation / Editor 五层契约，附带门禁规则和踩坑时间线。** 我用了三种切法（前两次都翻车了），告诉你哪种能活下来。

### B. Godot 中级开发者，对"项目大了以后怎么切"感到困惑

你已经会用 Godot 写小游戏，但项目一上规模就乱。你想找一套**能跨引擎、跨年度**的分层思路——不是"Godot 4.6 这一版怎么用"。

**这篇给的是「分层思想」而不是「分层 API」**：Data / Catalog / Logic / Presentation / Editor 这五层，每层"可以 / 禁止"清单，放到 Godot 5、Unity、Unreal 都成立。代码会过时，**分层思想不会过时**。

> 如果你是只想看 demo / 只想抄一段代码 / 只想知道"这个项目能不能跑起来"的读者——**现在关掉一点不亏**。这篇不是给你的。

---

## 然后说清楚——这个专栏**凭什么**值得你关注

知乎上"复刻 XXX"的教程不少，光"复刻魔兽"我就能搜出十几个。这个专栏不一样的地方：

1. **不做伪代码，不搬运 API 文档**：每一篇的代码片段都是仓库里真实存在的、可运行的；附 commit hash、附 `startLine:endLine:filepath`、附 `selftest_*.gd` headless 跑过的结果。
2. **不做"事后诸葛亮"——把踩坑过程摊给你看**：「先这么写 → 踩了 1 周坑 → 最后改成那样」是主轴。比如分层这篇，我会告诉你**前两张架构图为什么必撕**。
3. **不靠 AI 翻译凑字数**：每周二长图文（4000-6000 字）+ 每周五踩坑快讯（500-1000 字）+ 每月初里程碑盘点。**不发水文。**
4. **工程向 + 叙事向混搭**：技术读者看实现，普通玩家看"为什么这一步要这么做"。**两个读者群都能 get 各自的点。**
5. **与 B 站视频课形成闭环**：专栏是「可检索的深度」，B 站是「可看的过程」。两边互为印证。
6. **仓库是活的，不是写专栏时现编的**：`godot_warcraft3` 迭代了半年多，108 份文档、上百个 GDScript、几十次 commit。这篇专栏的每句话都能在仓库里找到对应证据。

---

## 故事开头：我是怎么走到「先把架构图撕了重画」的

铺垫完了，进入正题。

我是哈尔滨的独立开发者，做 B 站 + 知乎双平台。`godot_warcraft3` 是 2025 年底开工，目标：**用 Godot 4.6 把《魔兽争霸3》的玩法（不是贴图，不是数值，是"能玩"）复刻出来，仓库开源，文档齐全。**

按惯例，第一件事应该是建个目录、开个 Main 场景、跑个 Hello World。**我偏不。**

我先把 HiveWE 0.6+ 源码、`War3.mpq` 数据字典、GDScript 4.6 语言限制、Godot 4 forward+ 渲染管线——四份资料摆桌上，对比了一周。

一周后得出一个结论：**这种规模的项目，第一件事不是写代码，是画架构图。** 而且画的图一定会被自己撕了重画——但必须画，不画不行。

于是画了第一张图，按"功能模块"切。写了 3000 行代码。撕了。
又画了第二张图，按"对象类型"切。又写了 2000 行代码。又撕了。
直到第三张图——按"能做什么 / 不能做什么"切——**分层架构才有了该有的样子**。

下面讲第三张图。

---

## 一页纸看完

1. **复刻 ≠ 翻译**：跨引擎、跨范式、跨数据规模的"复刻"，本质是重新设计。
2. **五层职责**：Data（数据映射）→ Catalog（资源映射）→ Logic（领域 API）→ Presentation（表现层）→ Editor（编辑层）。**禁止逆流**：Layer 不能写 flags；Catalog 不能算拓扑；Editor 不能直接拼 GLB 路径。
3. **强制顺序**：每个新模块一律 `Data → Catalog → Logic → Presentation → Editor`。先写代码的会回来补课。
4. **一张图胜过一千行代码**：建议收藏。

```text
┌─────────────────────────────────────────────────────────┐
│  Editor（编辑层）  Editor 总管 + Document / Tools / UI   │
│  改数据、调逻辑 API；不建 Mesh、不 resolve 资产路径       │
└───────────────────────────┬─────────────────────────────┘
                            │ mutate / query · 请求重建
┌───────────────────────────▼─────────────────────────────┐
│  Logic（逻辑层）  Domain：拓扑、门禁、选型、placements   │
│  输入 Heightfield + Catalog；输出「放什么 / 哪张贴图索引」│
└─────────────┬─────────────────────────────┬─────────────┘
              │ 读/写地图态                  │ 查资产
┌─────────────▼─────────────┐   ┌───────────▼─────────────┐
│  Data（数据映射）           │   │  Catalog（资源映射）      │
│  JSON ↔ RefCounted / SoA  │   │  ID/TAG/tile → 路径/索引 │
│  不含 Godot Mesh           │   │  不含「这一格该用哪 TAG」│
└───────────────────────────┘   └───────────┬─────────────┘
                                            │
┌───────────────────────────────────────────▼─────────────┐
│  Presentation（表现层）  MapRoot / Layer / Mesh         │
│  只消费 placements + 已解析资源；不写 heightfield         │
└─────────────────────────────────────────────────────────┘
```

![分层架构图](./images/01-01-layered-architecture.png)

---

## 1. 五层职责——一张表记一辈子

我把它写成 Cursor 规则 `map-layered-architecture.mdc`，每次让 AI 改代码前它会先看：

| 层 | 目录 / 前缀 | 可以 | 禁止 |
|----|------------|------|------|
| **Data** | `scripts/map/data/` | JSON↔类型、SoA、FLAG/TILE 常量 | 建 Mesh、拼 GLB 路径、算崖 TAG |
| **Catalog** | `scripts/map/catalog/` | ID/TAG/tileset → 路径或 Texture 索引；运行时扫盘 | 改 heightfield、判「这一格是崖」 |
| **Logic** | `scripts/map/logic/` | 拓扑、门禁、选型、placements | `SurfaceTool`、挂节点、直接 `load` 资产 |
| **Presentation** | `scripts/map/presentation/` | 消费 placements + resolve 结果 | 写 flags/layer、硬编码资产路径 |
| **Editor** | `editor/scripts/` | `@export` 注入 MapRoot；调 Logic API、脏区重建 | 根节点堆业务；笔刷里组 Mesh / resolve 路径 |

**为什么禁止逆流？** 一旦允许，就会出现这种"先图省事、后期地狱"的代码：

```gdscript
# ❌ 反例：Layer / Brush 内
flags[i] |= FLAG_RAMP
var path = "Doodads/Terrain/Cliffs/AAAB0.glb"

# ✅ 正解
doc.heightfield.vertex_at(ix, iy).has_ramp = true  # Logic/Editor → Data
var path = cliff_catalog.resolve(tag, variation)     # Logic 选型后 Catalog
layer.build(placements)                              # Presentation
```

第二段代码看起来"啰嗦"，但职责清晰：**改贴图路径改 Catalog；改拓扑改 Logic；挂 Mesh 改 Present。** 第一段代码两个问题：

1. Layer 改了 Data 层的 `flags`——别的 Layer 改了同一个 flag，互相覆盖时根本不知道谁负责。
2. Layer 直接拼 GLB 路径——以后改资产目录结构，要在所有 Layer 里搜一遍字符串。

### 强制顺序：Data → Catalog → Logic → Presentation → Editor

每个新模块一律按这个顺序落地。**这是硬门禁，不是建议。**

举个例子：加"装饰物（Doodad）"模块。

```text
1. Data     定义 doodads.json 的 SoA 映射：id, position, scale, variation, yaw
2. Catalog  扩展 Wc3IdCatalog：Doodad id → GLB 路径
3. Logic    写 placement_rules：pathing、Y 贴 heightfield、Z 偏移
4. Present  MapDoodadLayer 读 placements + Catalog，MultiMesh 渲染
5. Editor   DoodadBrush 调 Logic API，生成 Command（用于撤销）
```

**先写代码的会回来补课**——我跳过 Data 直接写 Layer，结果 `MapDoodadLayer` 里塞了一堆 `doodad["rotation"] = ...`、`doodad["position"] = ...`，3 个月后想加"Y 贴 heightfield"特性，发现全要在 Layer 里改。这才回过头补 Data 层。

### 编辑总管：让脏区合并、撤销栈、调度有个归属

主线场景树：

```text
EditorMain (Node3D)                    ← 场景壳：环境光、挂载子节点；无业务脚本
├── Editor (Node)                      ← 总管 MapEditor；@export map_root → MapRoot
├── MapRoot (instance)                 ← 表现入口 MapLoader
├── EditorCamera
├── TerrainBrush                       ← 由 Editor 在 _ready 绑定，或 @export 注入
└── UI (CanvasLayer)
    └── …
```

```gdscript
# editor/scripts/editor.gd （节选）
extends Node
class_name MapEditor

@export var map_root: MapLoader          # 注入，不写死

func _on_brush_painted(rect: Rect2i) -> void:
    doc.heightfield.update_region(rect) # Editor → Logic → Data
    map_root.request_rebuild(rect)      # Presentation 脏区重建
```

**为什么要总管？** 没有总管的话，3 个笔刷同帧触发 `request_rebuild()` 会出现 3 次全量重建；撤销栈也会因为"Layer 直接改 flags"断裂（这就是我第三遍踩的坑）。

---

## 2. 5 个现有脚本的"裁决"（改造前必看）

| 脚本 | 进哪一层 | 理由 |
|------|---------|------|
| `wc3_coords.gd` | **Data** | 基础常量 + WC3 空间工具；`wc3_to_godot` 是表现边界，由 Presentation 调用 |
| `heightfield_mesh_builder.gd` | **已删** | 合并到 `Wc3Heightfield`（数据）+ `HeightfieldMesh`（表现） |
| `wc3_cliff_trans_catalog.gd` | **Catalog** | 运行时 `load_*()` 扫盘——只要运行时需要 `load("res://...")` 拿真实资产，就是 Catalog |
| `wc3_cliff_tiles.gd` | **Logic** | 选型（"这一格该放哪个 TAG"），不放路径 |
| `wc3_cliff_trans_catalog.gd` vs `wc3_cliff_tiles.gd` | **拆清** | Tiles = 选型，Catalog = TAG→路径，Layer = 挂树 |

地面管线作为「参照实现」（任何新模块照着抄）：

```text
HeightfieldMesh        # 底层：采样 + Packed* 三角/四边形批建 + active_material
MapTerrainLayer        # 领域：WC3 地表规则 + @export ground_material + 调底层画网格
MapDebugGridLayer      # 跨子系统调试栅格，不塞进 TerrainLayer
assets/materials/*.tres + assets/shaders/*.gdshader  # 静态材质与 shader
Wc3GroundTileCatalog   # tileset → Texture2DArray
```

**核心规则**：`Layer 只 duplicate 材质后改运行时参数`；**禁止** Layer 里 `var mat := ShaderMaterial.new()` + `mat.shader = preload("...")`——那是耦合的开始。

---

## 3. 踩过的坑（按发现顺序，省 1 个月）

| # | 坑 | 症状 | 修法 | 耗时 |
|---|----|------|------|------|
| 6.1 | 第一遍按"功能模块"切 → 上帝类 | 编辑器改一个顶点要触发 5 个 Mesh API | 画分层图 + 门禁规则 + PR 标层 | 2 周重构 + 后续每个新模块省 1 周 |
| 6.2 | 第二遍按"对象类型"切 → 循环依赖 | Skill import 7 个目录报"Identifier not declared" | 按"能/不能做什么"切——5 层职责 | 3 周 |
| 6.3 | Layer 里 `flags[i] \|= FLAG_RAMP` → 撤销栈断了 | Ctrl+Z 不能完全撤销 | Editor 笔刷只调 Logic API；Logic 内部 `EditorCommandHistory.record()` | 1 天 |
| 6.4 | Catalog 写成 `resources/*.tres` → 改资源目录要重导 | 资产目录换了，所有 `.tres` 的 `path` 字段要手动改 | Catalog 改运行时扫盘；根本不检入 `.tres` | 半天 |
| 6.5 | Editor 根节点挂大杂烩 → 笔刷相互打架 | 3 个笔刷同帧触发，全量重建 3 次 | 加 `Editor`（Node）作为总管，`@export map_root` 注入 | 1 天 |

**前两张架构图撕掉的代价：5 周**。如果一上来就有人告诉我"按'能做什么/不能做什么'切"，这 5 周完全不用花。这就是这个专栏存在的意义。

---

## 4. 现在到哪儿了——一份诚实的进度盘点

| 轨道 | 当前水位 | 距离"完整复刻" |
|------|---------|----------------|
| **资产管线** | MPQ → 三车道（视觉 / SLK / 地图）→ `.scn`+PE2；有效覆盖率约 99% | 还差 DLC 叠加 / 全量 race 转完 |
| **地图** | 高度图 + 地面纹理 + 崖 M0–M2 + 坡核心 ✅；水体 / 装饰物 Y / 单位笔刷仍有缺口 | 水体稳定化、Y 贴地、装饰物 pathing 还在做 |
| **对战** | Echo Isles 壳 + 采矿伐木 + 建造训兵 + 战斗 C0–C3 + 野怪 AI + 大法师 / 山丘 / 支援技能 ✅ | 英雄复活、Keep 升级、铁匠升级、战斗手感层还没收口 |
| **技能架构** | Behavior / Fx / Buff / Effect + Director 外提（Phase A–E）✅ | 单技能竖切够用，批量化 / 插件化未做 |

**翻译成人话**：✅ **能玩的最小集**已经跑通（采矿 / 伐木 / 造建筑 / 训兵 / 打野怪 / 放技能）；❌ **完整科技树、联机、战役、斜坡视觉**还在排队。具体进度以 `NEXT.md` 为准——那里是我每周更新的当前冲刺优先级。

---

## 5. 文档落点

| 主题 | 文档 |
|------|------|
| **本文**（架构总纲） | [../architecture/LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md) |
| Cursor 门禁规则 | `.cursor/rules/map-layered-architecture.mdc` · `map-presentation-split.mdc` |
| 实施顺序 | [../roadmap/ROADMAP.md](../roadmap/ROADMAP.md)（地图 ①–⑫） |
| 当前冲刺 | [../roadmap/NEXT.md](../roadmap/NEXT.md)（N0–N4） |
| 拆分尺度 | [../architecture/LAYERED_ARCHITECTURE.md §6](../architecture/LAYERED_ARCHITECTURE.md) |
| 专栏大纲 | [zhihu-column-outline.md](zhihu-column-outline.md) |

---

## 写在最后

下一篇讲**资产三车道**：怎么从 `War3.mpq` 解包到 `assets/asset-converted/`，怎么不污染工程目录，怎么给未来 DLC 留位置。预计下周二更新。

评论区欢迎问：

- 你做复刻 / 大型项目时第一遍切分是什么？撕了几次？
- 五层对你来说太多 / 太少了吗？
- 想听哪一篇先写？（我手头有 4 篇 ✅ draft 的，02-05 任选）
- 作为魔兽3老玩家，你最想先看哪个系统的复刻过程？

---

最后更新：2026-09-05
