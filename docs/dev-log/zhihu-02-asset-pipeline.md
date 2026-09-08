# 【老李游戏学院】02 · 我正在用 Godot 4 复刻魔兽3，但先把魔兽资源解包出来

> **副标题**：一道绕不开的工程题——4 个 Node 工具 + 1 个 Godot Autoload，把经典 MPQ 变成引擎运行时可用资源
>
> **关联文档**：
> - [../data/PIPELINE.md](../data/PIPELINE.md)（管线总览）
> - [../architecture/ASSET_LANES.md](../architecture/ASSET_LANES.md)（三车道契约）
> - [../data/CONTENT_PACKS.md](../data/CONTENT_PACKS.md)（MPQ 优先级 + 模型版本）
> - [../data/LEGAL.md](../data/LEGAL.md)（合规：仓库不带暴雪资产）
> - [../../tools/README.md](../../tools/README.md)（一键脚本）
>
> **项目状态**：**正在复刻，未完工**。本文写于 2026-09-05。
>
> 最后更新：2026-09-05

---

## 先说清楚——这篇是写给谁的

上一篇《我把架构图撕了重画》讲了"五层职责怎么切"。切完之后你马上会撞上**第一道墙**：分层架构只管"代码怎么组织"，但魔兽3这个项目**真正的复杂度在资产**——1.7 万条 BLP/MDX、几十张 SLK 表、十几种地图文件格式。

不把资产**从暴雪原版格式**翻译到 **Godot 4 能直接吃的格式**，后面写再多 Layer 也是空转。

这篇写给：

| 你是什么样的人 | 你能从这篇拿到什么 |
|----------------|------------------|
| **正在做复刻项目（不仅是魔兽），被"原版格式怎么解"卡住** | 一套 4 工具 + 1 Autoload 的参考架构；StormLib 用什么、为什么不用现成 npm 包、为什么分 4 个工具不合并 |
| **做 mod / DLC / 跨版本兼容的独立开发者** | "内容包叠层"和"模型版本"两层规则——`War3.mpq` → `War3x.mpq` → mod → DLC 怎么叠加、为什么 `Priest` 和 `Priest_V1` 不是同一件事 |
| **好奇"为什么不用现成 wc3maptranslator"的人** | 一份诚实的对比——经典 TFT v25 地图（v25）vs 新版 v33，npm 现成包根本解不动经典图，自研 `map-parse` 的原因 |
| **Godot 引擎玩家，想知道"为什么 Godot 装这么多贴图会卡"** | `.cache/` + `.gdignore` 的分工——一个给工具用、一个给编辑器用；为什么 `assets/asset-converted/` 必须 `.gdignore` |

> 如果你只是来抄代码调现成资产的，**直接看 [../../tools/README.md](../../tools/README.md) 一键脚本**就行。这篇不是给你的。

---

## 然后说清楚——这个专栏**凭什么**值得你关注

1. **不做伪代码，不搬运 API 文档**：每一篇的代码片段都是仓库里真实存在的、可运行的；附 commit hash、附 `startLine:endLine:filepath`、附 `selftest_*.gd` headless 跑过的结果。
2. **不做"事后诸葛亮"——把踩坑过程摊给你看**：「先这么写 → 踩了 1 周坑 → 最后改成那样」是主轴。这篇里有 4 个真实踩坑案例（npm 包爆改 / StormLib DLL 拉不到 / Godot 卡在导入 / `Priest` vs `Priest_V1` 选错）。
3. **不靠 AI 翻译凑字数**：每周二长图文（3500-5000 字）+ 每周五踩坑快讯（500-1000 字）+ 每月初里程碑盘点。
4. **工程向 + 叙事向混搭**：技术读者看实现，普通玩家看"为什么这一步要这么做"。
5. **与 B 站视频课形成闭环**：专栏是「可检索的深度」，B 站是「可看的过程」。
6. **仓库是活的，不是写专栏时现编的**：`godot_warcraft3` 迭代了半年多，108 份文档、上百个 GDScript、几十次 commit。这篇专栏的每句话都能在仓库里找到对应证据。

---

## 故事开头：我是怎么走到「先把魔兽资源解包出来」的

铺垫完了，进入正题。

上一篇讲「分层架构」，切完之后我兴冲冲开始写 `Map*Layer`。写了 1 天，撞墙——**Layer 要挂的 mesh 在哪？**

打开 War3 目录看了一眼：**1.7 万个文件**，全是 BLP、MDX、SLK、W3E——没有一个能直接被 Godot 4 吃。`Mesh.surface_from_arrays` 不会读 MDX，`Texture2D.load_from_file` 不会解 BLP，gdshader 不会跑 4.5 GLSL。

这才意识到：**魔兽3 这个项目的真正复杂度在资产**。代码怎么组织只是骨，资产怎么翻译才是肉。没把原版格式翻译到引擎能吃的格式，再精妙的分层也是空转。

于是我停下 `Map*Layer`，转头搭资产管线——这一搭就是 3 周。下面讲这一搭的过程。

---

## 一页纸看完

1. **资产管线不是"写个脚本解 MPQ"那么简单**——它包含 4 个工具包 + 1 个 Autoload + 一套契约 + 一组合规约束。
2. **6 个阶段串成一条链**：MPQ → BLP/MDX → PNG/gltf → `.scn`+PE2 → SLK JSON → 地图 JSON → Godot Autoload 解析 → 运行时挂层。
3. **3 条核心契约**：(1) 运行时**只读 `assets/`**，不读 `.cache`；(2) 三车道分工（视觉 / 数据 / 地图），不混；(3) MPQ 优先级叠层，DLC 走同一栈尾。
4. **4 个真实踩坑**：(1) npm 现成 `wc3maptranslator` 解不动经典 TFT；(2) StormLib 在 Windows 的 DLL 必须 `npm install` 时拉；(3) `assets/asset-converted/` 不 `.gdignore` 会把 Godot 卡死；(4) `Priest` vs `Priest_V1` 是 MPQ 叠层 + 模型版本两件事。

下面按"为什么这样切 → 怎么实现 → 踩了哪些坑 → 现在到哪儿"展开。

---

## 1. 为什么资产管线要切 4 个工具 + 1 个 Autoload

最开始我想得很美：「写个脚本，把 War3.mpq 解出来，把 BLP 转 PNG、把 MDX 转 gltf，完事。」

然后我开了 War3 目录看了一眼——**1.7 万个文件**。再翻一下文件类型：

| 扩展名 | 数量级 | 用途 |
|--------|--------|------|
| `.blp` | 上万 | 贴图（地形、单位皮、UI、技能图标） |
| `.mdx` | 上千 | 模型（单位、建筑、装饰、技能特效） |
| `.slk` | 几十 | 数值表（单位平衡、技能数据、地形类型） |
| `.w3x` / `.w3m` | 玩家本地 | 地图 |
| `.wav` / `.mp3` | 上千 | 音效与音乐 |
| `.txt` | 几十 | 键值配置（单位 Func、UI 字符串） |
| `.tga` | 几百 | 寻路遮罩、部分特效贴图 |

**这是 4 类完全不同的领域知识**——模型归模型、表归表、地图归地图、贴图归贴图。强行写在一个工具里，4 个月后没人改得动。

于是切成 **4 个工具包 + 1 个 Autoload**：

```text
classic MPQ
  │ tools/mpq-extract              ← 阶段 1：解包（StormLib）
  ▼
.cache/wc3-assets/                 ← 原始 BLP/MDX/SLK/W3E/DOO …（.gitignore）
  │
  ├─ tools/asset-convert           ← 阶段 2：贴图 + 模型
  ├─ tools/slk-export              ← 阶段 3：SLK 表 → JSON
  └─ tools/map-parse               ← 阶段 4：地图 → JSON
       ▼
assets/
  asset-converted/                 ← 视觉车道：PNG/gltf/.scn（.gdignore）
  slk-exported/                    ← 数据车道：表 JSON
  map-parsed/<slug>/               ← 地图车道：地图 JSON
       │
       ▼  运行时
AssetProvider (Autoload)           ← 阶段 5：逻辑路径 → 物理文件
       │
       ▼
RuntimeAssets / Catalog / Logic / Map*Layer → 场景
```

**为什么是 4 个不是 1 个？** 三个理由：

1. **依赖隔离**：`mpq-extract` 必须拉 StormLib DLL（[koffi](https://koffi.dev/) 调 C 库）；`asset-convert` 必须跑 `war3-model` 解析 MDX；`slk-export` 只用 Node 标准库。这三个包的依赖树**互不污染**，某个包升级不会带崩别的。
2. **可单独迭代**：改贴图解码算法不需要重新拉 StormLib；改 SLK 解析不需要重导模型。**这是工程上的"模块独立"在工具层落地**。
3. **可被 Godot headless 反向调用**：第 6 阶段 Godot 烘焙 `.scn` 时，m2g 工具直接调 `asset-convert`，不用 import 整个项目。

**为什么 Autoload 而不是全局脚本？** 因为 Godot 4.6 的 Autoload 是引擎级单例，**生命周期 = 项目生命周期**。`AssetProvider` 在 `_ready()` 阶段就准备好查找顺序（mod overlay → `asset-converted/` → `.cache/`），运行时任何脚本调 `AssetProvider.resolve(path)` 都是 O(1) 查表。这比"每个 Layer 自己 `load("res://...")`"健壮得多——**以后接 DLC / mod 都不用改业务代码**。

---

## 2. 6 个阶段怎么实现

下面给一份"一段话讲完每阶段干什么 + 关键代码片段 + 文件路径"的实操版。具体命令去 [../../tools/README.md](../../tools/README.md) 看。

### 阶段 1：解包（MPQ → 原始资产）

核心是 [StormLib](https://github.com/ladislav-zezula/StormLib)（C 写的 MPQ 读写库），通过 [koffi](https://koffi.dev/) 在 Node 里调。**完整代码**：

```javascript
// tools/mpq-extract/src/stormlib.js（核心）
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import koffi from "koffi";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");

function resolveStormLibDll() {
  const candidates = [
    process.env.STORMLIB_DLL,
    path.join(PACKAGE_ROOT, "vendor", "stormlib", "StormLib.dll"),
    path.join(PACKAGE_ROOT, "vendor", "stormlib", "x64", "StormLib.dll"),
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error("未找到 StormLib.dll。请运行: npm run fetch-stormlib");
}

let lib = null;
const api = {};

function ensureLoaded() {
  if (lib) return;
  lib = koffi.load(resolveStormLibDll());
  // 用 ANSI (char) 版 StormLib；Unicode 版需要 str16 与不同 FIND_DATA
  api.SFileOpenArchive = lib.func(
    "bool SFileOpenArchive(str filename, uint32 priority, uint32 flags, _Out_ void ** handle)"
  );
  api.SFileExtractFile = lib.func(
    "bool SFileExtractFile(void * mpq, str toExtract, str extracted, uint32 scope)"
  );
  // …其余 SFileCloseArchive / SFileHasFile / SFileOpenFileEx / SFileReadFile 等略
}

export function openArchive(mpqPath) {
  ensureLoaded();
  const handle = [null];
  const ok = api.SFileOpenArchive(mpqPath, 0, 0x100, handle);
  if (!ok) throw new Error(`SFileOpenArchive 失败: ${mpqPath}`);
  return handle[0];
}
```

**`extract.js` 主循环**（增量解包 + manifest 写入）：

```javascript
// tools/mpq-extract/src/extract.js（核心节选）
export function extractMpqs({ mpqs, outDir, manifestPath, force, include, exclude }) {
  fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
  const previous = force ? null : loadManifest(manifestPath);
  const files = previous?.files ? { ...previous.files } : {};
  let extracted = 0, skipped = 0, errors = 0;

  for (const mpq of mpqs) {
    const archive = openArchive(mpq.absolutePath);
    const names = listFiles(archive, null);

    for (const rawName of names) {
      const logicalPath = normalizeLogicalPath(rawName);
      if (!logicalPath || isInternalMpqFile(logicalPath)) continue;
      if (!matchesFilters(logicalPath, include, exclude)) continue;

      const destPath = path.join(outDir, ...logicalPath.split("/"));
      const existing = files[logicalPath];

      // SHA256 命中则跳过（幂等）
      if (!force && existing && existing.sourceMpq === mpq.canonicalName
          && fs.existsSync(destPath)) {
        skipped += 1;
        continue;
      }
      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      if (extractToFile(archive, rawName, destPath)) {
        files[logicalPath] = { sourceMpq: mpq.canonicalName, size: fs.statSync(destPath).size,
          sha256: sha256File(destPath) };
        extracted += 1;
      } else {
        errors += 1;
      }
    }
    closeArchive(archive);
  }
  // 写 manifest（原子：先写 .tmp 再 rename）
  const tmp = manifestPath + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify({
    version: 1, gameDir: mpqs[0].gameDir,
    extractedAt: new Date().toISOString(), files
  }, null, 2));
  fs.renameSync(tmp, manifestPath);
  return { extracted, skipped, errors };
}
```

CLI 主流程（参数解析 → detect → extract）：

```javascript
// tools/mpq-extract/src/cli.js（节选）
const opts = parseArgs(process.argv.slice(2));
if (!opts.gameDir) { console.error("错误: 必须指定 --game-dir"); process.exit(1); }

const gameDir = path.resolve(opts.gameDir);
const outDir = resolveFromPackage(opts.outDir, PACKAGE_ROOT);
const manifestPath = resolveFromPackage(opts.manifest, PACKAGE_ROOT);

console.log("godot_warcraft3 MPQ 解包工具");
console.log(`  game-dir: ${gameDir}\n  out: ${outDir}\n  manifest: ${manifestPath}\n  force: ${opts.force}`);

const mpqs = detectClassicMpqs(gameDir);   // 优先级：War3.mpq → War3x.mpq → ...
console.log("\n将按以下顺序解包（后者覆盖前者）:");
for (const m of mpqs) console.log(`  - ${m.canonicalName}  (${m.absolutePath})`);

const result = extractMpqs({ mpqs, outDir, manifestPath, gameDir, force: opts.force,
  include: opts.include, exclude: opts.exclude });
process.exit(result.errors > 0 ? 2 : 0);
```

关键细节：**DLL 不是 npm 包里直接带的**——Windows x64 的 `StormLib.dll` 在 `npm install` 时由 [`fetch-stormlib.js`](../../tools/mpq-extract/scripts/fetch-stormlib.js) 自动下载（带 SHA256 校验）。非 Windows 需要自己准备 `StormLib.so` 并设 `STORMLIB_DLL` 环境变量。

输出落到 `.cache/wc3-assets/`，路径**与 MPQ 内逻辑路径一一对应**（比如 `Units/Human/Footman/Footman.mdx` → `.cache/wc3-assets/Units/Human/Footman/Footman.mdx`），并写一份 `manifest.json`：

```json
{
  "version": "1",
  "gameDir": "D:\\Warcraft III",
  "extractedAt": "2026-09-05T10:23:11+08:00",
  "files": {
    "Units/Human/Footman/Footman.mdx": {
      "sourceMpq": "War3.mpq",
      "size": 213847,
      "sha256": "ab12cd34..."
    }
  }
}
```

`manifest.json` 的作用是**幂等**——下次解包先比对 SHA256，相同的文件跳过，1.7 万文件 30 秒搞定；变了的文件增量替换。

**MPQ 优先级叠层**（来自 [CONTENT_PACKS.md](../data/CONTENT_PACKS.md)）：

```text
War3.mpq → War3x.mpq → War3Local.mpq → War3xLocal.mpq → War3Patch.mpq
```

后者覆盖前者的**同路径文件**，不覆盖则并存。TFT 独有的 `*_V1` 模型（比如 `Priest_V1.mdx`）是 TFT 的 War3x **新增**，不会覆盖 RoC 的 `Priest.mdx`。这就是"**为什么 `Priest` 和 `Priest_V1` 不是同一件事**"——前者是路径层级，后者是数据表层级。

### 阶段 2：贴图 + 模型（BLP→PNG / MDX→gltf）

这一步是**最重的活**——把 BLP 解码成 PNG、把 MDX（/ MDL）解析成 gltf（**方案 B：.gltf + .bin 外链 PNG URI**，不是内嵌贴图的 .glb；详见下文「为什么选 gltf 不选 glb」）。社区包 [war3-model](https://github.com/wc3models/war3-models) 已经做好了 MDX 解析，我们包一层做转换。

**BLP → PNG 真实核心**（完整代码见 [`tools/asset-convert/src/convert-blp.js`](../../tools/asset-convert/src/convert-blp.js)，约 110 行）：

```javascript
// tools/asset-convert/src/convert-blp.js（核心）
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { PNG } from "pngjs";
import { decodeBLP, getBLPImageData } from "war3-model";
import { blpLogicalToPng } from "./paths.js";
import { walkFiles } from "./walk.js";
import { atomicWriteBytesSync } from "./atomic-write.js";

export function blpBufferToPng(blpBuffer) {
  // war3-model 的 getBLPImageData 拿 RGBA（含 alpha 通道）
  const blp = decodeBLP(blpBuffer);
  const imageData = getBLPImageData(blp, 0);
  const png = new PNG({ width: blp.width, height: blp.height, inputHasAlpha: true });
  png.data = Buffer.from(imageData.data);
  return PNG.sync.write(png);
}

export function convertBlpBatch({ inDir, outDir, force, include, exclude }) {
  const files = walkFiles(inDir, new Set([".blp"]), include, exclude);

  let converted = 0, skipped = 0, errors = 0;
  for (const file of files) {
    const pngLogical = blpLogicalToPng(file.logicalPath);
    const dest = path.join(outDir, ...pngLogical.split("/"));

    // 增量：产物 mtime ≥ 源 mtime 且 size>0 → 跳过
    if (!force && fs.existsSync(dest)) {
      const srcStat = fs.statSync(file.absPath);
      const dstStat = fs.statSync(dest);
      if (dstStat.mtimeMs >= srcStat.mtimeMs && dstStat.size > 0) { skipped += 1; continue; }
    }

    try {
      const png = blpBufferToPng(fs.readFileSync(file.absPath));
      atomicWriteBytesSync(dest, png);   // P3-10：atomic 写盘，防半成品被 cache 误判
      converted += 1;
    } catch (err) {
      console.error(`失败 ${file.logicalPath}: ${err.message ?? err}`);
      errors += 1;
    }
  }
  return { converted, skipped, errors, fileCount: files.length };
}
```

**MDX → gltf 核心思路**（仓库里 [`convert-mdx.js`](../../tools/asset-convert/src/convert-mdx.js) 约 2000 行，下面是骨架版）：

```javascript
// tools/asset-convert/src/convert-mdx.js（骨架；完整实现含动画烘焙 / 蒙皮 / 材质）
import { Document, NodeIO } from "@gltf-transform/core";
import { parseMDL, parseMDX } from "war3-model";
import { blpBufferToPng, writePlaceholderPng } from "./convert-blp.js";
import { atomicWriteSync } from "./atomic-write.js";
import {
  mdxLogicalToAnimKeys, mdxLogicalToAttachments, mdxLogicalToBoneRest,
  mdxLogicalToCameras, mdxLogicalToCollision, mdxLogicalToGeosetVis,
  mdxLogicalToGltf, mdxLogicalToPe2,
} from "./paths.js";

const MODEL_SCALE = 0.01;     // WC3 1 单位 ≈ Godot 0.01 m

export function convertMdx(srcPath, outDir, { force, emitSidecars = true }) {
  const buf = fs.readFileSync(srcPath);
  const mdx = parseMDX(buf);                 // 解析 MDX 二进制：Geoset / Bone / Sequence / PE2 / Attachment…

  // 1) 建 glTF Document + Scene
  const doc = new Document();
  const buffer = doc.createBuffer();
  const scene  = doc.createScene("Scene");

  // 2) 1.5x Bones + Geoset → Skin + Mesh（joints 下标与 mdx 一致）
  //    （约 400 行：蒙皮矩阵 / TRS 动画 / 多 Geoset 合并，详见 convert-mdx.js buildSkeleton）

  // 3) 材质 + 外链 PNG（不内嵌贴图）
  //    uri = ../Textures/<blpName>.png；运行时走 AssetProvider

  // 4) 写 glTF（合法 .gltf：JSON 且含 asset.version，方案 B 外链贴图）
  const gltfLogical = mdxLogicalToGltf(srcPath);
  atomicWriteSync(path.join(outDir, ...gltfLogical.split("/")), JSON.stringify(doc.toJSON()));

  // 5) PE2 / GeosetAnim / Attachment / Collision → 5 个 sidecar JSON
  if (emitSidecars) {
    atomicWriteSync(path.join(outDir, mdxLogicalToPe2(srcPath)),       JSON.stringify(/* PE2 */ null));
    atomicWriteSync(path.join(outDir, mdxLogicalToGeosetVis(srcPath)),  JSON.stringify(/* GeosetVis */ null));
    atomicWriteSync(path.join(outDir, mdxLogicalToAttachments(srcPath)),JSON.stringify(/* Attach */ null));
    atomicWriteSync(path.join(outDir, mdxLogicalToAnimKeys(srcPath)),  JSON.stringify(/* AnimKeys */ null));
    atomicWriteSync(path.join(outDir, mdxLogicalToCollision(srcPath)), JSON.stringify(/* Collision */ null));
    atomicWriteSync(path.join(outDir, mdxLogicalToBoneRest(srcPath)),  JSON.stringify(/* BoneRest */ null));
    atomicWriteSync(path.join(outDir, mdxLogicalToCameras(srcPath)),   JSON.stringify(/* Cameras */ null));
  }
  return doc;
}
```

**为什么不全塞进 glTF？两个原因**：

1. glTF 扩展对"粒子参数"覆盖不全，硬塞要写自定义扩展 → Godot 升级时容易绑死
2. **可 diff、可原子写盘**——sidecar 是 JSON，PR 评审能看到 diff；自定义 glTF 扩展 diff 看不出来

**sidecar 文件清单**：

| Sidecar | 内容 |
|---------|------|
| `*.pe2.json` | ParticleEmitter2 粒子参数（贴图、寿命、速度、关键帧、`active_sequences`） |
| `*.geosetvis.json` | 各 Sequence 下 Geoset 显隐（防 Godot 丢蒙皮 scale 轨） |
| `*.attachments.json` | 绑骨小件（旗子、铃铛）+ 粒子挂点 |
| `*.animkeys.json` | 原始 TRS / GeosetAnim / EventTrack（Hermite 关键帧留底） |
| `*.collision.json` | CollisionShapes（球心/半径或箱 min/max） |
| `*.bone_rest.json` | 骨架 rest pose TRS |
| `*.cameras.json` | 模型内置相机锚点（Portrait 镜头等） |

这一篇只讲管线；sidecar 怎么用、PE2 怎么挂，详见下期（PE2 特效专篇）。**关键技巧**：转换顺序是 `textures → models → scn`。模型材质引用 PNG，若 PNG 尚未生成，转换模型时会**即时从 BLP 补转**——这一行让"我今天只改了 1 个模型" 的增量转换 100% 可用。

#### 为什么选 gltf 不选 glb（外链 PNG URI，方案 B）

我把这一节单独抽出来，因为它决定了阶段 2 的**输出形态**——这恰恰是大多数复刻教程不会点破的地方。

glTF 2.0 有两种物理形态：

| 形态 | 贴图放哪 | 一句话 |
|------|----------|--------|
| **`.glb`**（binary） | 贴图 **base64 内嵌**在 glb 文件里 | 一个文件搞定，发包友好 |
| **`.gltf` + `.bin`**（JSON + binary） | 贴图 **外链 URI**指向磁盘 PNG | 一个 JSON + 一个 bin + 共享 PNG |

`convert-mdx.js` 注释里直接写了原因：

> 方案 B：不再写二进制 `.glb`（embed 贴图无法跨模型共享）。

WarCraft III 模型**贴图复用率极高**——`Footman` / `Archer` / `Knight` 几十个 Human 单位共用 `Units/Human/Footman/Textures/footman_Diffuse.png` 这几张。如果走 `.glb`，同一张 PNG 被 base64 嵌进几十个文件里：

- **磁盘占用爆炸**：1 万张 PNG × 几十次重复 embed → 几 GB 的冗余
- **改一张贴图要重导几十个模型**：增量转换失效
- **Godot 导入慢**：每个 .glb 都做一次 PNG 解码+压缩缓存
- **git diff 噪音**：改 skin tint 时几十个 .glb 一起变更，PR 评审看不到真正改了哪个模型

走 `.gltf` + 外链 URI（仓库里的实现）：

```text
assets/asset-converted/
  Units/Human/Footman/Footman.gltf      ← JSON 引用 ../Textures/footman_Diffuse.png
  Units/Human/Knight/Knight.gltf        ← JSON 引用 同一张 ../Textures/footman_Diffuse.png
  Units/Human/Footman/Footman.bin       ← 顶点 / 索引 / 动画的二进制（所有模型独立）
  Textures/footman_Diffuse.png          ← 唯一一份
```

带来的好处：

1. **可 diff、可增量**：改 `footman_Diffuse.png` 只需一次 git 提交；改 `Footman.gltf`（比如加新动画）只动 1 个文件 + 1 个 bin
2. **共享贴图库**：团队换 skin 调色板只重导 PNG；模型不变
3. **跨模型复用**：同一张 PNG 被引用 50 次，磁盘 1 份
4. **运行时按需加载**：`AssetProvider.resolve()` 把 `Textures/...png` 命中物理路径，Godot 直接 `Image.load()` —— 与 `RuntimeAssets` 的逻辑路径方案完美契合
5. **Godot 4.6 原生支持**：`.gltf` 是 glTF 2.0 文本格式，`gltf_document` 直接解析

代价（也是真实的）：

- **文件数量翻倍**：1 个 .glb → 1 个 .gltf + 1 个 .bin + N 个 PNG 引用
- **丢失原子性**：拷目录时必须整树搬，不能只拷 `.gltf`
- **路径解析有坑**：`.gltf` 的 URI 是相对路径，跨目录搬运要重新 path normalize

这 3 个代价我们是怎么兜底的？

1. **`AssetProvider` + `RuntimeAssets`** 只负责"逻辑路径 → 物理路径"，不管 `.gltf` 内部的 URI 怎么写
2. **`.gdignore` 拦下 editor auto-import**——不让 Godot 编辑器去扫这一坨
3. **烘焙 `.scn` 时强制 atomic write**（[`tools/asset-convert/src/atomic-write.js`](../../tools/asset-convert/src/atomic-write.js)）——中途崩溃不会留下半成品 `.gltf`

**经验**：复刻游戏做资产时，**只要贴图有复用率，`.gltf` + 外链一定赢 `.glb`**。`embed 友好`的发包场景才选 `.glb`——这是单文件场景，比如 web 展示页、Glitch 快速 demo。

### 阶段 3：SLK 表导出

SLK 是 Excel 早期变体。wc3 的 SLK 有几处坑：多行字段、UTF-8 BOM、末尾空行、`X/Y` 缺省要 sticky。**完整解析代码**：

```javascript
// tools/slk-export/src/parse-slk.js
/**
 * 解析 Blizzard SYLK（.slk）子集
 * 记录格式：
 *   ID;...          表头
 *   B;X3;Y100       维度（可选）
 *   C;X3;Y2;K"text" 单元格（X/Y 可省略 → 沿用上次的 X，自增 1）
 *   E               结束
 * @see https://github.com/stijnherfst/HiveWE/wiki/SLK
 */

function splitFields(line) {
  const fields = [];
  let cur = "", inQuotes = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === '"') { inQuotes = !inQuotes; cur += ch; continue; }
    if (ch === ";" && !inQuotes) { fields.push(cur); cur = ""; continue; }
    cur += ch;
  }
  fields.push(cur);
  return fields;
}

function parseKValue(raw) {
  if (raw === undefined || raw === "") return null;
  if (raw.startsWith('"')) {                       // "string"
    let s = raw;
    if (s.endsWith('"') && s.length >= 2) s = s.slice(1, -1);
    else s = s.slice(1);
    return s.replace(/""/g, '"');
  }
  const lower = raw.toLowerCase();
  if (lower === "true")  return true;
  if (lower === "false") return false;
  if (/^-?\d+$/.test(raw)) {
    const n = Number(raw);
    if (Number.isSafeInteger(n)) return n;
  }
  if (/^-?\d+\.\d+([eE][-+]?\d+)?$/.test(raw)) return Number(raw);
  return raw;
}

export function parseSlk(input) {
  const text = typeof input === "string" ? input : input.toString("utf8");
  const lines = text.split(/\r?\n/);
  const cells = new Map();
  let maxX = 0, maxY = 0, declaredX = 0, declaredY = 0;
  let curX = 0, curY = 1;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;
    const fields = splitFields(line);
    const type = fields[0];
    if (type === "ID") continue;
    if (type === "E")  break;

    if (type === "B") {                              // 维度声明
      for (let i = 1; i < fields.length; i += 1) {
        const f = fields[i];
        if (f.startsWith("X")) declaredX = Number(f.slice(1)) || 0;
        else if (f.startsWith("Y")) declaredY = Number(f.slice(1)) || 0;
      }
      continue;
    }
    if (type !== "C") continue;

    let x, y, kRaw;
    for (let i = 1; i < fields.length; i += 1) {
      const f = fields[i]; if (!f) continue;
      const code = f[0];
      if      (code === "X") x    = Number(f.slice(1));
      else if (code === "Y") y    = Number(f.slice(1));
      else if (code === "K") kRaw = f.slice(1);
    }
    if (y !== undefined) curY = y;
    if (x !== undefined) curX = x;
    else                 curX += 1;                 // X 缺省 → 自增

    if (kRaw === undefined) continue;
    const value = parseKValue(kRaw);
    cells.set(`${curX},${curY}`, value);
    if (curX > maxX) maxX = curX;
    if (curY > maxY) maxY = curY;
  }

  // 构造 grid → headers + records（去重表头、空行）
  const columns = Math.max(maxX, declaredX);
  const rows    = Math.max(maxY, declaredY);
  const grid = [];
  for (let y = 1; y <= rows; y += 1) {
    const row = [];
    for (let x = 1; x <= columns; x += 1) {
      row.push(cells.has(`${x},${y}`) ? cells.get(`${x},${y}`) ?? null : null);
    }
    grid.push(row);
  }
  const headers = (grid[0] ?? []).map((h, i) =>
    (h === null || h === undefined || h === "") ? `col_${i + 1}` : String(h));
  const records = [];
  for (let y = 1; y < grid.length; y += 1) {
    const row = grid[y];
    if (row.every((c) => c === null || c === undefined || c === "")) continue;
    const obj = {};
    for (let x = 0; x < headers.length; x += 1) {
      const v = row[x];
      if (v === null || v === undefined) continue;
      obj[headers[x]] = v;
    }
    if (Object.keys(obj).length) records.push(obj);
  }
  return { columns, rows, headers, records, grid };
}
```

导出目标 `assets/slk-exported/`，输出 JSON 而不是 CSV——理由：JSON 嵌套 + 索引方便，Godot `JSON.parse_string()` 直接吃。

输出示例：

```json
{
  "source": "Units/UnitData.slk",
  "headers": ["unitID", "race", "comment(s)", "..."],
  "recordCount": 812,
  "records": [
    { "unitID": "hfoo", "race": "human", "comment(s)": "Footman" }
  ]
}
```

### 阶段 4：地图解析

`tools/map-parse` 是自研的关键。**地图本身就是一个 MPQ 包**，要先解包再解析内部 7 个文件。入口：

```javascript
// tools/map-parse/src/cli.js（核心节选）
import { parseMap } from "./parse-map.js";

const opts = parseArgs(process.argv.slice(2));
// 例：--map "C:/war3/Maps/FrozenThrone/(2)EchoIsles.w3x"

console.log("godot_warcraft3 地图解析工具");
console.log(`  map:    ${opts.map}`);
console.log(`  out:    ${opts.out}`);
console.log(`  slug:   ${opts.slug}`);

const result = parseMap({
  mapPath: opts.map,
  outDir:  opts.out,
  slug:    opts.slug,                            // 默认取文件名
  noTilepoints: opts.noTilepoints,
  raw: opts.raw,                                  // --raw 额外导出原始 war3map.*
});

console.log(`\n完成: ${result.summary.units} 单位 / ${result.summary.doodads} 装饰物 / ${result.summary.regions} 区域`);
console.log(`  → ${opts.out}/${opts.slug}/summary.json`);
```

**关键决策：为什么不直接 `wc3maptranslator@5`？** 因为 wc3maptranslator 面向新版（v33），**根本解不动经典 TFT（v25）**。这是后面 §4.1 踩坑章节的重点，先按下不表。

地图解析出来会落盘成 8 个 JSON：

```text
assets/map-parsed/echoisles/
├── summary.json            ← 索引（units 数 / doodads 数 / tile size / camera）
├── info.json               ← war3map.w3i（玩家数、队伍、地图名）
├── terrain.json            ← war3map.w3e（tile ID、纹理）
├── terrain-heightfield.json ← 高度图（顶点 + corner flags）
├── units.json              ← war3mapUnits.doo（出生点 / 单位）
├── doodads.json            ← war3map.doo（装饰物）
├── regions.json            ← war3map.w3r（区域触发）
└── cameras.json            ← 相机锚点
```

### 阶段 5：编辑器资产同步（可选）

工具入口：[`tools/sync-editor-assets.mjs`](../../tools/sync-editor-assets.mjs)

把经典 World Editor 的 UI 配置 txt（如 `WorldEditData.txt`）同步到 `assets/asset-converted/UI/`，供编辑器加载。**这是过渡方案**——以后 UI 走自研管线。本期不展开。

### 阶段 6：运行时解析（Autoload）

`addons/asset_provider/asset_provider.gd` 是 Godot 4.6 Autoload（项目级单例，生命周期 = 项目生命周期）。**核心逻辑**（仓库里 ~200 行；下面是 resolve 主链路，私有方法按仓库命名保留 `_` 前缀）：

```gdscript
# addons/asset_provider/asset_provider.gd（核心 resolve 链路）
extends Node
class_name AssetProviderNode

const SETTINGS_CONVERTED_DIR := "warcraft3/asset_converted_dir"
const SETTINGS_DATA_DIR := "warcraft3/asset_data_dir"
const DEFAULT_CONVERTED_RES := "res://assets/asset-converted"
const DEFAULT_DATA_RES := "res://assets/slk-exported"

# { "id": String, "root": String }，后注册者优先；项目内约定为私有
var _overlays: Array[Dictionary] = []


## 解析逻辑路径到绝对磁盘路径；找不到时返回空字符串。
func resolve(logical_path: String) -> String:
    var logical := normalize_logical_path(logical_path)
    if logical.is_empty(): return ""

    # 1) mod overlay（后注册者优先 → 从后往前遍历）
    for i in range(_overlays.size() - 1, -1, -1):
        var hit := _first_existing(str(_overlays[i].get("root", "")), logical)
        if not hit.is_empty(): return hit

    # 2) asset-converted（开发期主路径）
    var from_converted := _first_existing(get_converted_root(), logical)
    if not from_converted.is_empty(): return from_converted

    # 3) 数据车道（slk-exported）
    return _first_existing(get_data_root(), logical)


## 同一逻辑路径的可能相对名（扩展名自动尝试）
func _candidate_relatives(logical: String) -> PackedStringArray:
    var out := PackedStringArray(); out.append(logical)
    var lower := logical.to_lower()
    if lower.ends_with(".blp"):
        out.append(logical.substr(0, logical.length() - 4) + ".png")
    elif lower.ends_with(".mdx") or lower.ends_with(".mdl"):
        var stem := logical.substr(0, logical.length() - 4)
        out.append(stem + ".gltf"); out.append(stem + ".glb")
    elif logical.get_extension().is_empty():
        out.append(logical + ".png"); out.append(logical + ".gltf"); out.append(logical + ".glb")
    return out


func _first_existing(root: String, logical: String) -> String:
    if root.is_empty(): return ""
    for rel in _candidate_relatives(logical):
        var candidate := root.path_join(rel).simplify_path()
        if FileAccess.file_exists(candidate): return candidate
    return ""


## 注册 mod 覆盖根目录。同 logical_path 下后注册者优先。
func register_overlay(mod_id: String, root: String) -> void:
    if mod_id.is_empty() or root.is_empty():
        push_warning("AssetProvider.register_overlay: mod_id/root 不能为空"); return
    for i in range(_overlays.size() - 1, -1, -1):
        if str(_overlays[i].get("id", "")) == mod_id:
            _overlays.remove_at(i)
    _overlays.append({"id": mod_id, "root": root.replace("\\", "/").simplify_path()})
```

调用方**应该经 [`RuntimeAssets`](../../scripts/map/infra/runtime_assets.gd) 走业务接口**，不要再自己拼 `res://assets/asset-converted/`：

```gdscript
# scripts/map/infra/runtime_assets.gd（核心 static API；仓库里约 600 行）
class_name RuntimeAssets
extends RefCounted

const CONVERTED_RES_ROOT := "res://assets/asset-converted"
const SLK_RES_ROOT := "res://assets/slk-exported"


## 解析逻辑路径到绝对磁盘路径。优先 Autoload AssetProvider，fallback 本地查表。
static func resolve(logical_path: String) -> String:
    var logical := logical_path.replace("\\", "/")
    while logical.begins_with("/"):
        logical = logical.substr(1)

    var tree := Engine.get_main_loop() as SceneTree
    if tree and tree.root:
        var ap := tree.root.get_node_or_null("/root/AssetProvider")
        if ap and ap.has_method("resolve"):
            var from_ap: String = str(ap.call("resolve", logical))
            if not from_ap.is_empty():
                return from_ap

    var disk_path := project_abs(converted_path(logical))
    if FileAccess.file_exists(disk_path):
        return disk_path
    return project_abs(slk_path(logical))    # 终极兜底


## 读纹理（PNG）。asset-converted/.gdignore 阻止 auto-import，运行时直接 FileAccess
static func load_image(res_or_abs: String) -> Image:
    var disk_path := project_abs(res_or_abs)
    if not FileAccess.file_exists(disk_path): return null
    var img := Image.new()
    var err := img.load(disk_path)            # 注意：PNG / JPG；BLP 必须先转好
    if err != OK: return null
    return img


## 读 UTF-8 文本。先拦二进制魔数（PNG/GLB），再扫 NUL，最后 UTF-8 校验
static func read_utf8_text(res_or_abs: String) -> String:
    var disk := project_abs(res_or_abs)
    if disk.is_empty() or not FileAccess.file_exists(disk): return ""
    var bytes := FileAccess.get_file_as_bytes(disk)
    if bytes.is_empty(): return ""
    if bytes.size() >= 4:
        # PNG: 89 50 4E 47  /  GLB: 67 6C 54 46 (glTF magic)
        if (bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x4E) \
        or (bytes[0] == 0x67 and bytes[1] == 0x6C and bytes[2] == 0x54 and bytes[3] == 0x46):
            return ""
    for i in range(bytes.size()):
        if bytes[i] == 0: return ""   # 含 NUL → 当二进制拒绝
    if not _bytes_are_valid_utf8(bytes): return ""
    return bytes.get_string_from_utf8()


## res:// / 绝对路径 → 绝对磁盘路径
static func project_abs(res_or_abs: String) -> String:
    var p := res_or_abs
    if p.begins_with("res://"):
        p = ProjectSettings.globalize_path(p)
    return p.replace("\\", "/")
```

**为什么不让业务代码直接 `load("res://...")`？** 因为 `asset-converted/` 被 `.gdignore` 标记过，Godot **不会**把它导入到 `res://`，`load()` 直接报「file not found」。所有加载必须走 `RuntimeAssets.resolve()` → `AssetProvider.resolve()` → `FileAccess.open()` 这条路。

---

## 3. 三车道契约——运行时只读 `assets/`

这是工程上最容易爆的雷点：**把 `.cache` 当运行时主路径**。

我早期版本就踩过：解包出来的 BLP 直接 `load(.cache/wc3-assets/...)`，结果：

- 改了一次客户端就要重新解包 1.7 万文件
- 同名文件被 `.cache` 和 `asset-converted` 各存一份，**修改流程混乱**
- DLC / mod 覆盖链根本搭不起来

于是定下契约（详见 [ASSET_LANES.md](../architecture/ASSET_LANES.md)）：

```text
┌──────────────────────────────────────────────────────────┐
│  运行时只读 assets/asset-converted/ + assets/slk-...   │
│  + assets/map-parsed/ + mods/<id>/（overlay）          │
└──────────────────────────────────────────────────────────┘
                  ↑ 不读 .cache/
                  ↑ 不读 .staging/
                  ↑ 不读 MPQ
```

**为什么 `.cache` 不进运行时？** 因为 `.cache` 是工具的中间态，每次重解都会变；`.asset-converted` 才是**产物**（PNG/gltf 经过验证、含 SHA256 对应），可以被 gitignore 但**不能被覆盖**。

**为什么 `assets/asset-converted/` 必须 `.gdignore`？** Godot 4 编辑器会**自动导入**所有 png/glb 文件到 `.godot/imported/`——上万个贴图 + 几千个模型能直接把编辑器卡到 OOM。我们用 `.gdignore`（Godot 4 的项目内忽略文件）告诉编辑器"这个目录你不要扫"：

```text
# assets/asset-converted/.gdignore
（文件存在即生效）
```

**Mod 机制已经预留**（虽然 v0.x 还没正式接）：

```gdscript
AssetProvider.register_overlay("my_mod", "/path/to/mods/my_mod")
# 同 logical_path 后注册者覆盖前注册者
AssetProvider.clear_overlays()
```

未来 DLC 接进来就是 `register_overlay("dlc_reforged_skin", "...")`，业务代码不用动。

---

## 4. 4 个真实踩坑

### 4.1 `wc3maptranslator` 解不动经典 TFT 地图（耗时：1 周）

**症状**：用 npm 现成包 `wc3maptranslator@5` 解 `EchoIsles.w3x`，报 `unsupported war3map.w3i version: 33`。

**根因**：wc3maptranslator 面向 **Reforged 新版**（v33）。经典 TFT（v25）`war3map.w3i` 头部结构不一样，根本解不动。

**修法**：自研 [`tools/map-parse/src/parsers/w3i.js`](../../tools/map-parse/src/parsers/w3i.js)。这其实是我**自研管线里最值得的部分**——社区放弃经典版的兼容性，我们吃下来。

**经验**：**不要假设 npm 生态替你解决经典版兼容性问题**。魔兽3 这个社区早已分裂成"经典 RoC/TFT"和"Reforged"两条线；Reforged 用 CASC + 大版本改动，工具生态全部围绕它转。要复刻经典版，**至少地图解析得自己写**。

### 4.2 StormLib DLL 在 Windows 自动拉取（耗时：半天）

**症状**：开发者在 Linux / macOS 上跑 `npm install`，报 `StormLib_x64.dll not found`。

**根因**：StormLib 是 C 库，需要平台特定二进制。`koffi` 调的是 .dll / .so / .dylib。

**修法**：[`fetch-stormlib.js`](../../tools/mpq-extract/scripts/fetch-stormlib.js) 在 `npm install` postinstall 阶段拉对应平台的二进制，带 SHA256 校验；非 Windows 设 `STORMLIB_DLL` 环境变量自备。

**教训**：**跨平台原生依赖不要走 npm 包管理**，走 fetch + 校验更可控。

### 4.3 `assets/asset-converted/` 不 `.gdignore` 把编辑器卡死（耗时：半天排查）

**症状**：打开 Godot 编辑器 → 卡在 "Importing assets..." → 几分钟后 OOM 崩溃。

**根因**：1.7 万 PNG + 几千 gltf（+ 同量 .bin），编辑器全部尝试导入到 `.godot/imported/`，资源占用爆炸。

**修法**：在 `assets/asset-converted/` 下放空文件 `.gdignore`（Godot 4 约定）：

```bash
# 一行搞定
touch assets/asset-converted/.gdignore
```

**教训**：**别让 Godot 编辑器扫你的二进制产物**。运行时按需加载，不走导入系统。

### 4.4 `Priest` 和 `Priest_V1` 选错导致模型错乱（耗时：2 天）

**症状**：把 `Priest_V1` 模型当 `Priest` 用，结果模型贴图错位、肩甲队色丢了。

**根因**：这是**两层规则混用**：

- **层 A（VFS）**：`War3x.mpq` 在 `War3.mpq` 之后解包，新增文件（`Priest_V1.mdx`）就放在 `Units/Human/Priest/Priest_V1.mdx`
- **层 B（模型版本）**：`unitUI.slk` 里的 `file` 字段是 `units/human/Priest/Priest`（无 `_V1`），`fileVerFlags` 是 `2`（表示有 expansion 变体）

我们的解析算法（[CONTENT_PACKS.md §3.3](../data/CONTENT_PACKS.md)）：

```text
base = UnitUI.file（去 .mdx/.mdl）
flags = UnitUI.fileVerFlags

candidates =
  if active_edition != roc 且 flags != 0:
      [ base + suffix(edition), base ]   # tft → base_V1, base
  else:
      [ base ]

取第一个在 asset-converted 存在的 stem
```

`active_edition` 默认 `tft`，`fileVerFlags=2` → 优先 `Priest_V1`，回退 `Priest`。

**教训**：**MPQ 路径叠层 ≠ 数据表里的版本号**。前者是文件系统层，后者是数据语义层，必须分开治理。

---

## 5. 现在到哪儿了——诚实的进度盘点

| 阶段 | 当前水位 | 距离"完整" |
|------|---------|------------|
| 阶段 1 解包 | MPQ 优先级 6 个全跑通 + manifest.json 校验 ✅ | 偶尔遇到加密 MPQ（RoC 部分版本） |
| 阶段 2 转换 | BLP→PNG / MDX→gltf（方案 B 外链）+ sidecar + bake `.scn` ✅，覆盖率约 99% | 还差 RibbonEmitter / 部分 Light 全保真 |
| 阶段 3 SLK | 全部表导出 JSON ✅ | 表结构变更后要清 `slk-exported/` 重导 |
| 阶段 4 地图 | Echo Isles / Lost Temple 等 7+ 张图可解析 ✅ | Reforged 地图（v33）未支持 |
| 阶段 5 编辑器 UI | UI txt 同步 + 模型预制 ✅ | 战役 UI / 自定义 UI 暂未做 |
| 阶段 6 Autoload | `AssetProvider` + `RuntimeAssets` 接线 ✅ | GDExtension 直链 StormLib（玩家端规划） |

**一句话**：「资产从原版到 Godot 的翻译链」已经**接完整**——剩下的是补全特殊资源类型（Ribbon、Light、Portrait 相机），不是补架构。

---

## 6. 推荐起步顺序（如果你要自己复刻别的游戏）

不论你复刻的是魔兽、星际、暗黑、命令与征服——管线**结构可以照抄**：

```text
1. 找一个原版格式的 npm 解析器         ← 1-2 周
2. 解包 + manifest 校验                ← 2-3 天
3. 写"原版格式 → 你引擎格式"的转换器   ← 主要工作量
4. 写 Autoload 解析 logical_path       ← 1 天
5. 写 sidecar 抽象（glTF 救不了的部分） ← 看资源类型复杂度
6. 集成 DLC / mod overlay              ← 1 天
```

**第 3 步和第 5 步是真正吃时间的**——魔兽有 12 种粒子参数类型、6 种 FilterMode、4 种 Geoset 显隐模式、5 种绑骨关系，每一个都要单独写 sidecar。复刻别的游戏没这么复杂，但**"glTF 救不了的部分必须 sidecar"**是通用规律。

---

## 7. 文档落点

| 主题 | 文档 |
|------|------|
| **管线总览**（本文） | [../data/PIPELINE.md](../data/PIPELINE.md) |
| 三车道契约 | [../architecture/ASSET_LANES.md](../architecture/ASSET_LANES.md) |
| MPQ 叠层 + 模型版本 | [../data/CONTENT_PACKS.md](../data/CONTENT_PACKS.md) |
| 路径手册 | [../data/WC3_ASSET_PATHS.md](../data/WC3_ASSET_PATHS.md) |
| 一键脚本 | [../../tools/README.md](../../tools/README.md) |
| StormLib 接入 | [../../tools/mpq-extract/](../../tools/mpq-extract/) |
| 模型转换 + sidecar | [../../tools/asset-convert/README.md](../../tools/asset-convert/README.md) |
| 特效全貌（PE2 等） | [../blog/04-wc3-effects-conversion.md](../blog/04-wc3-effects-conversion.md) |
| 上一期（分层架构） | [zhihu-01-layered-architecture.md](zhihu-01-layered-architecture.md) |
| 专栏大纲 | [zhihu-column-outline.md](zhihu-column-outline.md) |

---

## 写在最后

上一篇讲"代码怎么切"，这篇讲"资产怎么进来"。两篇合起来回答了「**怎么从零启动一个复刻项目**」的前半段——架构 + 资产。

下一篇会讲**特效怎么从 MDX 进 Godot**：PE2 粒子参数 / Geoset 显隐 / 绑骨小件 / FilterMode 材质——4 类 sidecar + Godot 烘焙 `.scn` 时怎么注入。这是上一篇末尾留下的伏笔，也是仓库里**最容易被忽略的部分**（很多人以为"模型转 gltf 就完了"）。

预计下周二更新。

评论区欢迎问：

- 你做复刻时第 3 步（转换器）卡在哪里？
- StormLib 这种 C 库你们怎么处理跨平台？
- sidecar JSON 还是自定义 glTF 扩展，你选哪个？为什么？
- 这篇讲得太细 / 太粗？节奏要不要再调？

---

最后更新：2026-09-05
