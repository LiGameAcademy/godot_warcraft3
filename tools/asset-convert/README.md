# asset-convert

将经典 WC3 资产转为 Godot 可用格式：

1. **贴图** `BLP` → `PNG`（`war3-model` 解码 + `pngjs`）
2. **模型** `MDX`/`MDL` → `GLB`（`war3-model` 解析 + `@gltf-transform/core`）
3. **场景** `GLB` → 同目录 `.scn`（Godot headless 烘焙；运行时优先，免 `GLTFDocument`；bake 时注入 `*.geosetvis.json` 的 Geoset 显隐轨）
4. **粒子** `ParticleEmitters2` → 同 stem 旁路 `*.pe2.json`；**`bake:scn` 写入 `Pe2Root`（GPUParticles3D）** 与各 Sequence 的 `:emitting` / position 轨。贴图内嵌进 `.scn`，不再落地 `pe2.tscn`。
   - **v2**：写入 `active_sequences`（Visibility∩EmissionRate 按 Sequence 作用域）；`null`=全程发射（火盆），数组=仅训练烟/建造尘等阶段性特效
   - 字段对照与未做项：[docs/design/asset-convert/PE2_GODOT.md](../../docs/design/asset-convert/PE2_GODOT.md)
   - **对外说明（特效全貌）**：[docs/blog/04-wc3-effects-conversion.md](../../docs/blog/04-wc3-effects-conversion.md)
5. **Geoset 显隐** → 同 stem 旁路 `*.geosetvis.json`（Sequence 作用域 alpha）；Godot 导入丢 scale 轨后由 `MapModelCache` 补 `:visible`
6. **动画关键帧** → 同 stem 旁路 `*.animkeys.json`（MDX 原始 TRS / GeosetAnim / EventTrack；时间单位毫秒）。`bake:scn` 写入各 Animation 的 `loop_mode`、`wc3_mdx_name` / `wc3_rarity` / `wc3_move_speed`，以及 `MdxEvents.fire` Method Track（SND/FPT/SPL/SPN）。Hermite 原始 Keys 仍只留在 JSON。
7. **碰撞** → 同 stem 旁路 `*.collision.json`（MDX CollisionShapes：球心/半径或箱 min/max，已 Y-up × 0.01）；`bake:scn` 写入 `MdxCollision`（Area3D，layer=0）
8. **光晕 Geoset** FilterMode Additive/AddAlpha → 材质名 `_fm3`/`_fm4`；可用 `npm run reconvert:additive` 批量重转

默认顺序：`textures → models → scn`。模型会优先使用已转换的 PNG；缺失时再即时转 BLP。无 `pe2.json` 或 `collision.json` 时会重新转换该模型。  
glTF Skin joints：`Bones` 在前（JOINTS_0 下标不变），`Helpers` 去重后追加（便于挂点绑 `Bone_Foot_L`）。attachments.json 对 Attachment 写出 `pivot`、原始 `visibility` 关键帧；`bake:scn` 把无父挂点放场景根，并把 Visibility 写成各 Sequence 的 `:visible` 轨。
`bake:scn` **不按 VertexGroup 拆网格**：`.scn` 保留 glTF 的 Geoset 蒙皮块（进 `SkinMeshes`），`BoneAttachment3D` 只给 `Attach_*`。城墙旗子等 equal-weight 错位可手工跑 `scripts/tool/split_meshes_by_group.gd`。  
`.scn` 需本机 Godot 4.x（环境变量 `GODOT` / `GODOT_BIN`）；找不到 Godot 时跳过烘焙并警告，不阻断 convert。

### 转换（含自动烘焙 .scn）

```bash
npm install
# 贴图 + 模型 + 同目录 .scn
npm run convert -- --include "Units/Human/Footman/**" --include "Textures/**"
# Echo Isles / 人族 Melee 开发子集（推荐）
npm run convert:echo-isles --
# Lost Temple 子集
npm run convert:lost-temple --
# 只要贴图
npm run convert:textures -- --include "Textures/**"
# 只要模型（仍会自动 bake .scn；可加 --skip-scn）
npm run convert:models -- --include "Units/Human/Footman/**"
# 只补烤 .scn
npm run bake:scn -- --include Units/Human/
# 或
npm run convert -- --scn-only --include Units/Human/
```

### 增量更新（推荐日常）

**默认不加 `--force`**：按源文件与产物 **mtime** 跳过已是最新的项（贴图 / 模型旁路 / passthrough / `.scn` 同理）。

| 场景 | 命令 |
|------|------|
| 日常同步（只转有变动的） | `npm run convert --` |
| 改了转换工具、要对全库吃新算法 | `npm run convert -- --force` |
| 只重转某个英雄/技能 | `npm run convert -- --include "Units/Human/HeroArchMage/**" --include "Abilities/Weapons/FireBallMissile/**"` |
| 只重烤 .scn | `npm run bake:scn -- --include Units/Human/HeroArchMage/` |

工具代码 hash 变化时会打日志提醒，但**不会**再自动全量 force。

输出根目录默认：`../../assets/asset-converted`（`Foo.glb` + `Foo.scn` 同目录，已 gitignore）。

未烘焙时：编辑器首次预览后会懒写入同目录（失败则 `user://model-scenes/`）。

### `.scn` 烘焙：doScn / --workers / --shard

m2g 转完模型后默认**自动**调 Godot 烘焙 `.scn`（除非显式 `--skip-scn`），
以免主线程 `GLTFDocument` 加载 GLB（runtime 优先 `.scn`，3-5× 更快）。

#### `doScn` 决定矩阵

| 入口参数 | 跑 textures | 跑 models | 跑 .scn bake |
|---------|:-----------:|:---------:|:------------:|
| `npm run convert`（默认） | ✅ | ✅ | ✅ |
| `npm run convert:models` | ❌ | ✅ | ✅（`--models-only` 不等于 `--skip-scn`） |
| `npm run convert:textures` | ✅ | ❌ | ❌ |
| `npm run convert -- --skip-scn` | ✅ | ✅ | ❌ |
| `npm run convert -- --scn-only` | ❌ | ❌ | ✅ |
| `npm run bake:scn -- --include ...` | ❌ | ❌ | ✅ |

**要点**：
- `--models-only` **不等于** `--skip-scn`：m2g 内部 `doScn = opts.scnOnly || (!opts.skipScn && !opts.texturesOnly)`，
  跑模型时默认也跑 bake（`--skip-scn` 才跳过）。
- `--textures-only` 等价于 `--skip-scn`（不需要贴图就不需要 bake）。
- 找不到 Godot 时静默跳过 bake 并 warn，**不阻断** convert。

#### `--workers N`（并行 bake）

`npm run bake:scn -- --workers N` 启 N 个 Godot 子进程**同时**跑（`Promise.all` 等全部 close）。
每个 worker 跑 1/N 桶，由 `export_model_scenes.gd --shard N --shard-id K` 配合：

```text
worker 1/4: godot ... --shard 4 --shard-id 0  # logical_glb.hash() % 4 == 0
worker 2/4: godot ... --shard 4 --shard-id 1  # logical_glb.hash() % 4 == 1
worker 3/4: godot ... --shard 4 --shard-id 2  # logical_glb.hash() % 4 == 2
worker 4/4: godot ... --shard 4 --shard-id 3  # logical_glb.hash() % 4 == 3
```

桶是**确定性**的（基于 `logical_glb` 字符串的 `String.hash()`，Godot 内置），
所以同 N 下多次跑结果一致、不会重复处理同一文件。

| 参数 | 含义 | 默认 | 备注 |
|------|------|------|------|
| `--workers 1` | 串行 | ✅ | 内存友好；调试 / 少量文件 |
| `--workers 2` | 老 PC 起步 | | 约 1.5-2× 加速 |
| `--workers 4` | 老 PC 推荐上限 | | 约 3× 加速；每 Godot ~300-500MB，4 个就是 1.2-2GB |
| `--workers 8+` | 不推荐 | | 内存吃紧；bash 启动开销也变大 |

环境变量等价：`WORKERS=2` 或 `BAKE_WORKERS=2` 也能设。`bootstrap.mjs` 默认透传 `--workers 2` 给 bake。

**bootstrap 集成**：`node tools/bootstrap.mjs` 走 m2g 阶段时显式 `WORKERS=2` 透传。

#### `--shard N --shard-id K`（手动分桶调试）

`export_model_scenes.gd` 直接调用时手传这两个 flag 做单桶调试：

```bash
# 只跑 hash % 4 == 2 的那桶
godot --headless --path . -s res://scripts/tool/export_model_scenes.gd -- --shard 4 --shard-id 2 --include Units/Human/
```

通常**不需要**手传 —— `bake:scn --workers N` 已经帮你启 N 个 worker 并自动分桶。
只在**手动复现某 worker 失败**或**只跑 1/N 验证**时用。

#### 已知边界

- **headless 加载失败不阻断**：部分模型（DNC / UI 等）`GLTFDocument` headless 失败属可预期，
  脚本 `quit(0 if failed == 0 or exported > 0 or skipped > 0 else 1)`——
  只要有成功 / 跳过的文件就视为通过。
- **MapModelCache 懒兜底**：编辑器第一次预览某 GLB 时如果 `.scn` 不存在，
  `MapModelCache.bake_model_scene` 会即时烘焙（写同目录；失败则 `user://model-scenes/`）。
  → 早期 dev 跑局部 convert 不全，编辑器预览会慢，但**不会**看到模型缺失。

### 批量重转 Additive 光晕

```bash
# 默认只扫 Doodads/**
npm run reconvert:additive
# 全库
node scripts/reconvert-additive-geosets.mjs --include "**/*"
# 仅列表
node scripts/reconvert-additive-geosets.mjs --list-only
```

### bake .scn（含 PE2）+ 可选 visuals

```bash
# 仓库根目录
node tools/export-godot-assets.mjs --include Buildings/Human/ --force --bake-only
```

PE2 打进 `.scn`；`pe2.json` / 贴图仍在 `asset-converted`（不入库）。  
`MapModelCache` 优先 `visuals/*.tscn` → `.scn` → GLB。

## 已知问题与处理

- **UV**：MDX 的 `TVertices` 不要做 `1-V` 翻转。
- **队伍色**：优先选用带真实路径的材质层；双层（Rep1+漫反射 Blend）标 `_rep1`，Godot 用 `wc3_team_color_underlay` 垫底混合。
- **GeosetAnim**：按 **Sequence 作用域** 采样 alpha（区间内无 key → 默认可见）。全局 hold 会错误隐藏 TownHall 的 `Stand` 等建筑档。
- **Geoset 显隐（Godot）**：`GLTFDocument` 会丢掉蒙皮 `Geoset_*` 的 scale 轨；convert 写旁路 `*.geosetvis.json`，`MapModelCache` 加载/bake 时注入 `Skeleton3D/Geoset_*:visible`。
- **Morph / Alternate（天神下凡等）**：变身外观多靠 Helper **Scaling**（非另套 Geoset）。`Alternate*` 烘焙对 Scaling 做 carry-in；`Morph*` 从 bind 插到变身目标。普通 Stand 仍无 carry-in（避免兵营门被打开）。见 `anim_morph_alternate.test.mjs`。
- **Transparent**：FilterMode=1 使用 MASK + cutoff 0.75，避免半透明碎片。
- **Additive / AddAlpha（FilterMode 3/4）**：glTF 无加法混合；材质名带 `_fm3`/`_fm4`，Godot `MapModelCache` 加载时改成 `BLEND_MODE_ADD`（否则 `Yellow_Glow*` 黑底会变成实心黑牌）。
- **动画**：每个 Sequence → 一条 glTF Animation。名称用驼峰、变体序号用 `-`（`Stand - 2` → `Stand-2`，不要 `Stand_-_2`）。原始 Keys 另写旁路 `*.animkeys.json`（毫秒时间轴 + LineType / InTan / OutTan）。`bake:scn` 再写入 loop / rarity / move_speed / Event 轨。扁平 Armature + 等权蒙皮。
- **Global Sequence（全模型同一规则）**：`AnimVector.GlobalSeqId ≥ 0` 的骨骼（主城旗布、时针等）按 `GlobalSequences[id]` 独立时钟采样，**不**走 Sequence 区间过滤。循环 Sequence 的 glTF 时长 = `max(本段, 该模型用到的最长 Global Sequence，但忽略 >20s 的时钟轨)`，段内骨骼 `% seqDur`、GlobalSeq 骨骼 `% globalDur`。非循环段（Birth/Death）保持原长，段内用 `% globalDur` 循环飘。静止骨骼会折叠成 2 个关键帧。超过 20s 的时针仍按 `% dur` 写进短循环，会周期性跳一下（避免单条 Stand 变成 80s / 上百 MB）。
- **Billboard / 双面**：只认 MDX。节点 `Flags & 0x8` 才是 Billboard；Layer `Shading & 16` 才是 TwoSided。人族主城旗**两者都没有**——单面、不转朝向。RTS 固定机位与原作一致；编辑器绕到背面看不到旗是预期，不要给所有旗开公告牌。
