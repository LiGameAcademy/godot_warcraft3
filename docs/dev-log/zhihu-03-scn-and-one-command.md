# 【老李游戏学院】03 · 我正在用 Godot 4 复刻魔兽3，但把"模型烤熟"是为了把 7 个工具收成 1 条指令

> **副标题**：.gltf 已经能跑，为什么还要 .scn？bake 脚本集成到 JS 后，新同事一条命令完成「解包 → 转换 → 烘焙」整条管线

> **项目状态**：**正在复刻，未完工**。本文写于 2026-09-06。
>
> 最后更新：2026-09-06

---

## 我怎么把 7 个工具收成 1 条指令

新同事拉仓库跑了一下，10 分钟后找过来：

> "你这 README 让我跑 `mpq-extract` → `asset-convert` → `slk-export` → `map-parse` → 同步数据 → 同步 UI → 还要再开 Godot 编辑器点 'Bake Model Scenes'？我装 Godot 就是为了写逻辑的，让我点编辑器按钮这件事本身就是反工程。"

这就把 7 张拼图收成 1 条命令的事催了出来。

---

## 1. 为什么有 gltf 还要有 `.scn`

Footman 同一份资源，两种加载方式：

```gdscript
# 方式 A：直接 load gltf
var scene := load("res://assets/asset-converted/Units/Human/Footman/Footman.gltf") as PackedScene
# → 1 个 Skeleton3D + 4 个 MeshInstance3D
# → 没有 PE2 / 没有 Attachment / 没有 Camera
# → Geoset 显隐轨丢了（走路时剑柄会跟着腰晃）
```

```gdscript
# 方式 B：load 我们 bake 的 .scn
var scene := load("res://assets/asset-converted/Units/Human/Footman/Footman.scn") as PackedScene
# → Skeleton3D + SkinMeshes（5 桶归位） + Attachments + Pe2Root
#   （OmniLight / CPUParticles3D / GPUParticles3D） + Camera3D
# → Geoset 显隐轨保留（剑柄 :visible 轨每 50ms 切一次）
```

差 8 个节点类型。这些不是装饰，是模型本来应有的东西。哪些 glTF 表达不了：

| 资源类型 | glTF 表达 | 我们怎么办 |
|----------|-----------|------------|
| **PE2 粒子**（贴图 + 关键帧 + `active_sequences`） | ❌ 无标准扩展 | `*.pe2.json` → [`scripts/tool/wc3_scn_pe2.gd`](../../scripts/tool/wc3_scn_pe2.gd) 注入 Pe2Root |
| **Geoset 显隐** | ⚠️ KHR_materials_variants 太重 | `*.geosetvis.json` → 按 `SkinMeshes/Geoset_N` 重注 `:visible` 轨 |
| **绑骨小件**（旗子、铃铛） | ❌ 没标准 | `*.attachments.json` → 拼到 `proto` 的 Attachments 桶 |
| **MDX 相机**（Portrait 镜头） | ❌ glTF 相机很弱 | `*.cameras.json` → 挂 `Camera3D` 节点 + TRS 轨 |
| **CollisionShape** | ⚠️ KHR_mesh_features 语义对不上 | `*.collision.json` → 挂 `CollisionShape3D` 节点 |
| **Hermite 关键帧** | ⚠️ glTF cubic spline 丢 in/out tangent | `*.animkeys.json` → [`scripts/tool/wc3_scn_animkeys.gd`](../../scripts/tool/wc3_scn_animkeys.gd) 注入 |
| **BoneRest**（rest pose 偏移） | ⚠️ inverseBindMatrices 表达不一致 | `*.bone_rest.json` → 调 `Skeleton3D.set_bone_rest()` |

所以 `.scn` 是把魔兽语义焊进场景的产物——gltf 解决"几何 + 材质 + 骨架"，解决不了"魔兽3 数据语义"。

---

## 2. bake 脚本做了什么

`npm run convert` 里已经包含 bake。

### 2.1 CLI 钩子：convert 跑完自动调 bake

`tools/asset-convert/src/cli.js` 里这段：

```javascript
// tools/asset-convert/src/cli.js（约 320-340 行）
import { bakeModelScenes } from "../scripts/bake-model-scenes.mjs";

// ...
async function main() {
  // ...
  if (doTextures) { /* convertBlpBatch */ }
  if (doModels)   { await convertMdxBatch(...); }   // gltf + sidecar
  if (doPassthrough) { /* copy */ }
  if (doScn) {                                       // ← 这里
    const workers = Number(process.env.WORKERS || process.env.BAKE_WORKERS) || 1;
    const code = await bakeModelScenes({
      include: includesForBake(opts.include),
      force: opts.force,
      workers,
      godot: opts.godot,
    });
    if (code !== 0) { errors += 1; }
  }
  // ...
}
```

`doScn` 默认 `true`（除非传 `--scn-only` / `--textures-only` / `--skip-scn`）。

### 2.2 bake 主循环（headless GDScript）

`scripts/tool/export_model_scenes.gd` 的核心（1200 行里我贴最关键那段，真实结构）：

```gdscript
# scripts/tool/export_model_scenes.gd（核心 _run 节选）
extends SceneTree

const Wc3ScnRebucketScript := preload("res://scripts/tool/wc3_scn_rebucket.gd")
const Wc3ScnAnimkeysScript := preload("res://scripts/tool/wc3_scn_animkeys.gd")
const Wc3ScnPe2Script     := preload("res://scripts/tool/wc3_scn_pe2.gd")
const Wc3ScnRibbonScript  := preload("res://scripts/tool/wc3_scn_ribbon.gd")
const Wc3ModelSceneScript := preload("res://scripts/presentation/wc3_model/wc3_model_scene.gd")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var includes: PackedStringArray = PackedStringArray()
    var force := false
    var shard := 1
    var shard_id := 0
    # 解析 --include / --force / --limit / --shard / --shard-id（worker 模式）

    var root_abs := RuntimeAssets.project_abs(RuntimeAssets.CONVERTED_RES_ROOT)
    var glb_files: PackedStringArray = []
    _collect_glb(root_abs, glb_files)
    if shard > 1:
        var filtered: PackedStringArray = []
        for p in glb_files:
            var logical := str(p).replace("\\", "/").replace(root_abs + "/", "")
            if logical.hash() % shard == shard_id:
                filtered.append(p)
        glb_files = filtered

    var cache := MapModelCache.new()
    for disk_glb in glb_files:
        var rel := str(disk_glb).replace("\\", "/")
        var logical_glb := rel.substr(rel.find("/asset-converted/") + "/asset-converted/".length())
        if not includes.is_empty() and not _matches_any_include(logical_glb, includes):
            continue
        if _is_no_scn(logical_glb):                 # 粒子/装饰/Portrait 不需要 .scn
            continue

        var glb_res  := RuntimeAssets.converted_path(logical_glb)
        var scn_res  := RuntimeAssets.model_scene_path(logical_glb)
        var disk_scn := RuntimeAssets.project_abs(scn_res)

        # mtime 命中跳过；否则删旧 .scn 防 instance 吃旧包
        if not force and FileAccess.file_exists(disk_scn):
            var gstat := FileAccess.get_modified_time(disk_glb)
            var sstat := FileAccess.get_modified_time(disk_scn)
            var pe2_stat := _sidecar_mtime(logical_glb, ".pe2.json")
            var cam_stat := _sidecar_mtime(logical_glb, ".cameras.json")
            if sstat >= gstat and sstat >= pe2_stat and sstat >= cam_stat:
                continue

        # 1) 加载 gltf → proto（带 Skin）
        var root: Node3D = cache.instance_glb_preview(glb_res, false, ...)
        if root == null: continue

        # 2) sidecar 注入（顺序敏感：BoneRest → Attachments → 5 桶归位 → Cameras → Collision → PE2 → Ribbon）
        var proto := cache.get_proto(glb_res)
        if proto != null:
            _apply_bone_rest_from_sidecar(proto, logical_glb)
            _assemble_attachments(proto, _read_attachments(logical_glb))
            var rb := Wc3ScnRebucketScript.apply(proto)               # 5 桶
            cache.reinject_geoset_vis_tracks(glb_res)                 # 重注 :visible 轨
            var cam_n := _inject_mdx_cameras(proto, logical_glb)      # Camera3D
            var col_n := _inject_mdx_collision(proto, logical_glb)    # CollisionShape3D
            var pe2: Dictionary = Wc3ScnPe2Script.apply(proto, glb_res)   # Pe2Root + 粒子
            var ribbon := Wc3ScnRibbonScript.apply(proto, glb_res)    # RibbonEmitter
            var ak := Wc3ScnAnimkeysScript.apply(proto, _read_animkeys(logical_glb))   # Hermite
            proto.set_script(Wc3ModelSceneScript)                    # 挂 wc3_model_scene.gd

        # 3) PackedScene.pack() 写盘
        if not cache.bake_model_scene(glb_res, force):
            failed += 1
            continue
        exported += 1

    quit(0 if failed == 0 or exported > 0 or skipped > 0 else 1)
```

sidecar 注入顺序是死规定——BoneRest 先于 Attachments，Attachments 先于 5 桶归位，PE2 先于 Omni 重 parent。反过来 TownHall 的 Omni 相机轨会悬空。mtime 跳过这条要 scn 比 `*.pe2.json` 和 `*.cameras.json` 都新才算。

### 2.3 5 桶归位（5-bucket rebucket）

**这是 .scn 与 gltf 的最大结构差异**。gltf 加载出来是 `Skeleton3D + N 个 MeshInstance3D`（蒙皮网格挂在骨架上）。我们 bake 时拆成：

```text
Footman.scn
├── Root (Node3D)
│   ├── Skeleton3D            ← 只剩骨头
│   ├── SkinMeshes/           ← 蒙皮网格（独立于 Skeleton3D）
│   │   ├── Geoset_0          ← 身体蒙皮
│   │   ├── Geoset_1          ← 武器蒙皮
│   │   └── Geoset_2          ← 披风蒙皮
│   ├── Attachments/          ← 绑骨小件（旗子、铃铛、宝石）
│   ├── Pe2Root/              ← 粒子（OmniLight / CPUParticles3D / GPUParticles3D）
│   ├── Cameras/              ← Portrait 相机
│   └── Colliders/            ← CollisionShape3D
└── AnimPlayer (Wc3AnimPlayerScript)
```

拆桶的原因是 Godot 4.6 的 `Skeleton3D` 只接受**自己直接子节点**的蒙皮网格——否则蒙皮会失效。glTF 加载器临时挂的蒙皮是 transient 的，bake 时必须重新整理。

---

## 3. JS 集成层：`bake-model-scenes.mjs`

这一步是把 Godot 调用藏进 Node，让上层脚本不感知 Godot 存在。

### 3.1 共享层：`tools/lib/godot-cli.mjs`

所有调 Godot 的入口统一走它。核心 `runGodotScript`：

```javascript
// tools/lib/godot-cli.mjs（核心 runGodotScript 节选）
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

export function findGodotExecutable(explicit = "") {
  if (explicit && fs.existsSync(explicit)) return explicit;
  const candidates = [
    process.env.GODOT, process.env.GODOT_BIN,
    path.join(os.homedir(), "Desktop", "Godot_v4.6.3-stable_win64_console.exe"),
    "C:\\Program Files\\Godot\\Godot_v4.exe",
    "/Applications/Godot.app/Contents/MacOS/Godot",
    "godot",       // 走 PATH（where/which 二次解析）
  ].filter(Boolean);
  for (const c of candidates) {
    if (c === "godot") {  /* where/which */ }
    else if (fs.existsSync(c)) return c;
  }
  return "";
}

export function runGodotScript({ scriptRes, userArgs = [], godot, required = true }) {
  const g = findGodotExecutable(godot);
  if (!g) {
    if (required === false) return 0;            // 可选：缺 Godot 不报错
    console.error("未找到 Godot 4.x。设置 GODOT 或 GODOT_BIN。");
    return 1;
  }
  const args = ["--headless", "--path", PROJECT_ROOT, "-s", scriptRes];
  if (userArgs.length) args.push("--", ...userArgs);
  console.log(`godot: ${g}\n  -s ${scriptRes}${userArgs.length ? " -- " + userArgs.join(" ") : ""}`);
  const r = spawnSync(g, args, { cwd: PROJECT_ROOT, stdio: "inherit", shell: false });
  return r.status ?? 1;
}
```

`-s` 让 Godot 跑脚本而不是开编辑器（脚本必须 `extends SceneTree`）；`shell: false` 避免 Windows 上 cmd.exe 把路径里的空格/括号拆碎；`required: false` 允许调用方"找不到 Godot 时优雅跳过"。

### 3.2 bake 入口：`bake-model-scenes.mjs`

```javascript
// tools/asset-convert/scripts/bake-model-scenes.mjs（核心）
import { spawn } from "node:child_process";
import {
  findGodotExecutable, runGodotScript, PROJECT_ROOT,
} from "../../lib/godot-cli.mjs";
import { getLog } from "../../pipeline-log.mjs";

export function bakeModelScenes(opts = {}) {
  const godot = findGodotExecutable(opts.godot || "");
  if (!godot) {
    getLog().warn(
      "bake:scn: 未找到 Godot，已跳过 .scn 烘焙",
      "设置 GODOT / GODOT_BIN 后可 npm run bake:scn；运行时仍可从 .gltf 解析",
    );
    return 0;
  }
  const workers = Math.max(1, Number(opts.workers) || 1);

  // 1) 串行：单 Godot 实例
  if (workers === 1) {
    return runGodotScript({
      scriptRes: "res://scripts/tool/export_model_scenes.gd",
      userArgs: buildUserArgs(opts),
      godot,
      required: false,
    });
  }

  // 2) 并行：N 个 Godot 进程各跑 1/N 桶
  const baseArgs = [
    "--headless", "--path", PROJECT_ROOT,
    "-s", "res://scripts/tool/export_model_scenes.gd",
  ];
  const procs = [];
  for (let k = 0; k < workers; k += 1) {
    const args = [...baseArgs, "--shard", String(workers), "--shard-id", String(k),
                   ...(buildUserArgs(opts))];
    getLog().info(`  worker ${k + 1}/${workers}: ${path.basename(godot)}`);
    procs.push(spawn(godot, args, {
      cwd: PROJECT_ROOT, stdio: "inherit", shell: false, windowsHide: true,
      env: process.env,
    }));
  }
  return Promise.all(procs.map((p, k) => new Promise((resolveP) => {
    p.on("close", (code, signal) => {
      if (code !== 0) getLog().error(`worker ${k + 1} failed: code=${code} signal=${signal}`);
      resolveP(code);
    });
  }))).then((codes) => codes.reduce((acc, c) => (c !== 0 ? (acc || c || 1) : acc), 0));
}

function buildUserArgs(opts) {
  const args = [];
  for (const inc of opts.include || []) args.push("--include", inc);
  if (opts.force) args.push("--force");
  if (opts.limit > 0) args.push("--limit", String(opts.limit));
  return args;
}
```

默认串行（一个 Godot 进程顺序处理）；`--workers N` 启 N 个实例各跑 1/N 桶（按 `logical.hash() % shard == shard_id` 切，互不重叠），每个 ~300-500MB 内存，2-4 适合老 PC。

---

## 4. 一条命令打通：`dev-setup.mjs` 与 `bootstrap.mjs`

### 4.1 两个入口的关系

| 入口 | 角色 | 命令 |
|------|------|------|
| [`tools/dev-setup.mjs`](../../tools/dev-setup.mjs)（[`Dev-Setup.ps1`](../../tools/Dev-Setup.ps1) 包装） | **轻量版**——按 `--profile` 切档，给新同事 / 日常开发用 | `node tools/dev-setup.mjs --game-dir "<wc3>"` |
| [`tools/bootstrap.mjs`](../../tools/bootstrap.mjs) | **严肃版**——读 `bootstrap.config.json`、支持 `--clean`、支持 `--verbose`、跑全量 | `node tools/bootstrap.mjs` |

两者最终都串行调 `mpq-extract` → `slk-export` → `map-parse` → `asset-convert` → `sync-data-assets` → `export-godot-assets`。

### 4.2 dev-setup 顶层结构（看代码最直接）

```javascript
// tools/dev-setup.mjs（约 380-440 行；步骤拼装段）
const TOOL_PKGS = ["mpq-extract", "asset-convert", "slk-export", "map-parse"];

function main() {
  const opts = parseArgs(process.argv.slice(2));

  // 1. 找 Godot（找不到也不崩，bake 时再 warn）
  const godotHint = findGodotExecutable(opts.godot);
  console.log(`Godot: ${godotHint || "(未找到 — convert 仍可出 gltf，bake/PE2 将跳过)"}`);

  // 2. 拼流水线
  const pipeline = [];
  if (!opts.skip.install)  pipeline.push(["install", () => stepInstall()]);
  if (!opts.skip.extract)  pipeline.push(["extract", () => stepExtract(opts, opts._gameDir)]);
  if (!opts.skip.slk)      pipeline.push(["slk",     () => stepSlk(opts)]);
  if (!opts.skip.maps)     pipeline.push(["maps",    () => stepMaps(opts, opts._gameDir)]);
  if (!opts.skip.convert)  pipeline.push(["convert", () => stepConvert(opts)]);   // 含 bake！
  if (!opts.skip.sync)     pipeline.push(["sync",    () => stepSync(opts)]);
  if (!opts.skip.godot)    pipeline.push(["godot",   () => stepGodot(opts)]);      // 含 PE2/visuals

  // 3. 顺序跑，每步 exit != 0 → 全停
  for (const [name, fn] of pipeline) {
    const code = fn();
    if (code !== 0) {
      console.error(`\ndev-setup 失败于步骤: ${name} (exit ${code})`);
      process.exit(code);
    }
  }

  printSummary(opts, opts._gameDir);
}
```

**步骤 vs 函数**：

```javascript
function stepInstall() { /* npm install × 4 个 tools 包 */ }
function stepExtract(opts, gameDir) { /* spawn: node tools/mpq-extract/src/cli.js --game-dir ... */ }
function stepSlk(opts)               { /* spawn: node tools/slk-export/src/cli.js */ }
function stepMaps(opts, gameDir)     { /* 对每个 map slug spawn node tools/map-parse/src/cli.js --map ... */ }
function stepConvert(opts)           { /* 拼 --profile 决定跑 convert-echo-isles 还是全量 cli */ }
function stepSync(opts)               { /* spawn: node tools/sync-data-assets.mjs */ }
function stepGodot(opts)             { /* spawn: node tools/export-godot-assets.mjs --include Buildings/... */ }
```

每步都是 `spawnSync` 调 `node` 子进程——不走 `npm run`，避免 Windows 上 cmd.exe 对路径空格/括号的转义。`convert` 步在 `game` profile 下跑 [`convert-echo-isles.mjs`](../../tools/asset-convert/scripts/convert-echo-isles.mjs)，只解 Echo Isles 用得到的模型，新设备 3 分钟跑完（全量要 40 分钟）。`godot` 步调的是 [`export-godot-assets.mjs`](../../tools/export-godot-assets.mjs)——PE2 粒子 + 肖像 visuals 在这里单独跑，不在 `convert` 里。

### 4.3 一条命令 3 分钟跑完（典型新设备）

```powershell
# Windows（PowerShell）
$env:WC3_GAME_DIR = "D:\Warcraft III"
.\tools\Dev-Setup.ps1
```

或显式：

```powershell
.\tools\Dev-Setup.ps1 -GameDir "D:\Warcraft III" -Profile game
```

后台会按顺序跑：

```text
=== 1. npm install（tools） ===
=== 2. MPQ 解包 → .cache/wc3-assets ===
=== 3. SLK → assets/slk-exported ===
=== 4. 地图解析 → assets/map-parsed/echoisles ===
=== 5. 资产转换 BLP/MDX → assets/asset-converted ===     ← 含 bake .scn
=== 6. sync-data-assets → slk-exported + PathTextures ===
=== 7. Godot：bake .scn + PE2 粒子预制 + visuals ===
✅ 准备完成

打开 Godot 4.6 → game/scenes/game_main.tscn  ← F6 直接跑
```

### 4.4 bootstrap 的严肃版

```powershell
# 全量 + 清理 + 详细日志
node tools/bootstrap.mjs --clean --verbose --config tools/bootstrap.config.json
```

| 特性 | dev-setup | bootstrap |
|------|-----------|-----------|
| 读配置文件 | ❌ | ✅ `bootstrap.config.json` |
| `--clean` 清缓存 | ❌ | ✅（保留 `.gdignore`） |
| `--no-bake` | ❌ | ✅（m2g 加 `--skip-scn`） |
| `--keep-staging` | ❌ | ✅（保留 `assets/.staging/`） |
| 适合 | 新同事 / 日常 | CI / 全量重导 / 调试 |

bootstrap 默认跑完**删 staging**（中间态不留），`--keep-staging` 保留。

---

## 5. 3 个真实踩坑

### 5.1 gltf 按需解析太慢（耗时：1 天）

**症状**：场景里 30 个单位（Footman × 20 + Archer × 5 + Knight × 5），第一次进入战斗场景卡 6 秒。

**根因**：每个 gltf 都要 Godot 现场解析——`gltf_document.parse()` + 蒙皮矩阵计算 + 纹理引用解析。Footman 一个文件 ~200ms，30 个 = 6 秒。

**修法**：bake 成 `.scn` 后，`PackedScene` 是预序列化的二进制——加载 5ms 一个。30 个单位 = 150ms。

### 5.2 PE2 注入时序坑（耗时：1 周）

**症状**：Footman 的剑在 Stand 动画期间**闪**——Omni 灯先闪一下才稳。

**根因**：早期 `wc3_scn_pe2.gd` 是按顺序 `inject_particles → reparent_lights → write_visible_tracks`。但 MDX 里 Omni 灯的 `:visible` 轨是**先 particle move、再 light move**——顺序反了就空一帧。

**修法**：[`export_model_scenes.gd`](../../scripts/tool/export_model_scenes.gd) 里强制按 `Particle → Omni → :visible` 顺序写：

```gdscript
# scripts/tool/export_model_scenes.gd（约 175-190 行；顺序敏感段）
# Pe2Root 先就位，再挪 Omni，最后写 :visible——避免 TownHall/Omni01 轨悬空
var pe2: Dictionary = Wc3ScnPe2Script.apply(proto, glb_res)
if bool(pe2.get("ok", false)) and int(pe2.get("emitters", 0)) > 0:
    _plog("INFO", "inject_pe2 emitters=%s tracks=%s (%s)" % [pe2.get("emitters", 0), pe2.get("tracks", 0), logical_glb])
var ribbon: Dictionary = Wc3ScnRibbonScript.apply(proto, glb_res)
var light_n := _reparent_lights_into_pe2(proto)
```

### 5.3 并行 worker 内存爆炸（耗时：半天）

**症状**：`dev-setup --workers 4` 跑在 16GB 机器上，Linux OOM kill。

**根因**：每个 Godot 实例都把 `*.gltf` 全部加载到内存做 cache——4 个 worker × 1GB gltf 池 = 4GB。机器才 16GB。

**修法**：`shard` 桶 + `cache.evict()`：

```gdscript
# export_model_scenes.gd（约 220 行；防泄漏段）
# 释放原型，避免 headless 退出泄漏（下一文件再 ensure）
if cache.has_cached(glb_res):
    cache.evict(glb_res)
exported += 1
```

每个 worker 只保留**当前文件**的 cache，处理完即释放。

---

## 6. 还差什么

- scn bake 5 桶归位已稳态；PE2 / Ribbon 还有个别模型空轨（TownHall 0/8、Ribbon 0/12）
- `dev-setup --profile game` 3 分钟跑通；`bootstrap` 配置档示例待补
- worker 2-4 安全，8+ 在 16GB 机器上 OOM

---

## 写在最后

#02 讲"资产怎么进来"，#03 讲"进来之后怎么变成 Godot 能直接吃的 `.scn`"，以及怎么把这一切收成 1 条命令。

下一篇讲 PE2 粒子参数 / Ribbon / Geoset 显隐怎么从 MDX 进 Godot——sidecar 注入时序、GPUParticles3D vs CPUParticles3D 的取舍。这是 #02、#03 留下的坑，也是仓库里最容易被忽略的部分。

预计下周二更新。

---

🌐 更多资源：

[知识星球](https://wx.zsxq.com/group/28885154818841) | [GitHub仓库](https://github.com/LiGameAcademy) | [itch.io页面](https://godot-li.itch.io/)

[B站频道](https://space.bilibili.com/8618918) | [YouTube频道](https://www.youtube.com/@user-oldLee) | [Discord社群](https://discord.gg/V5nuzC2BcJ)
