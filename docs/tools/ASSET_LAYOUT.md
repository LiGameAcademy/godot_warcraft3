# ASSET_LAYOUT — 资源布局规则

> **角色**：明确 `godot_warcraft3` git 仓库与本地资源的边界。
> **决策**（老李 D3，2026-08-08）：**任何 wc3 资源不入 git**。
> 仓库只装：源码 / 工具 / 文档 / 配置文件。所有 wc3 资源靠 `tools/bootstrap.mjs` 一键生成。
> 最后更新：2026-08-11（staging 临时 extract；运行时与工具默认不依赖持久 `.cache`；见 [ASSET_LANES.md](../architecture/ASSET_LANES.md)）

---

## 1. 规则总览

| 类型 | 入 git | 说明 |
|------|--------|------|
| 源码 | ✅ | GDScript / JS / 配置文件 |
| 工具源码 | ✅ | `tools/` 下 .js / .mjs / .ps1（不含 vendor / node_modules）；Godot 工具脚本在 `scripts/tool/` |
| 文档 | ✅ | `docs/` 下 |
| WC3 原文件（MPQ） | ❌ | `tools/mpq-extract/tmp/` 中转 |
| 解包后文件（war3 / mdx / blp / slk） | ❌ | 同上 |
| 转换后资源 | ❌ | `assets/asset-converted/` + `assets/model-scenes/` |
| PE2 预制（*.pe2.tscn） | ❌ | `assets/pe2-prefabs/` |
| Visuals（*.tscn baked） | ❌ | `assets/visuals/` |
| 解析后地图 | ❌ | `assets/map-parsed/` |
| SLK 导出 | ❌ | `assets/slk-exported/` |
| 工具临时输出 | ❌ | `tools/asset-convert/tmp/` + `tools/map-parse/tmp/` + `tools/mpq-extract/tmp/` |
| 工具缓存 | ❌ | `tools/asset-convert/scripts/_additive_geoset_hits.json` |
| Node modules | ❌ | `node_modules/` |
| StormLib 二进制 | ❌ | `tools/mpq-extract/vendor/stormlib/**`（版权） |

---

## 2. 一键启动（git clone → 完整可用）

```text
git clone <repo>
cd godot_warcraft3
npm install                  # 顶层 workspaces（5 个子工具）
node tools/bootstrap.mjs      # 一键：extract → convert → parse → slk → sync-data
```

`tools/bootstrap.mjs` 流程：

1. **检查依赖**：node >= 18、godot 二进制、WC3 安装（`tools/bootstrap.config.json` 或环境变量 `WC3_PATH`）
2. **ensure .gdignore**：阻止 Godot 扫 `asset-converted` 生成 `.import` / `baseColor` 副产物
3. **npm install**：子工具 workspaces
4. **mpq-extract** → `assets/.staging/wc3-assets/`（临时）
5. **asset-convert**：clean → BLP/MDX → passthrough 复制 → bake `.scn`
6. **map-parse** / **slk-export**（读 staging）
7. **删除 staging**（除非 `--keep-staging`）
8. 打印「资源就绪」

运行时只读三车道：见 [ASSET_LANES.md](../architecture/ASSET_LANES.md)。

---

## 3. 配置文件

`tools/bootstrap.config.json`：

```json
{
  "wc3":    { "path": "..." },     // WC3 安装根（可被 WC3_PATH 覆盖）
  "godot":  { "path": "..." },     // Godot 4.x（可被 GODOT / GODOT_BIN 覆盖）
  "maps":   { "items": [...] },    // 要解析的地图列表
  "convert":{ "include":[...], "exclude":[...] },  // m2g 工具 filter
  "skip":   { "extract":false, "convert":false, "parse":false, "slk":false }
}
```

---

## 4. 与原 `.gitignore` 规则的差异

### 老规则（已存在）

```
assets/asset-converted/**           # 转换后 PNG/GLB/SCN
assets/model-scenes/**              # 旧 .scn 目录
assets/map-parsed/**                # 解析后地图
assets/slk-exported/**              # SLK 导出
tools/asset-convert/tmp/
tools/asset-convert/scripts/_additive_geoset_hits.json
```

### 新规则（D3 改 + N1a 加）

```
+ assets/pe2-prefabs/**            # 之前 tracked（注释"OK to commit"）→ D3 改 ignored
+ assets/visuals/**                 # 之前未列（实际未 tracked）→ D3 加 ignored
+ tools/map-parse/tmp/              # 之前未列 → 加
+ tools/mpq-extract/tmp/            # 之前已列 → 保留
```

### 已 tracked 但 D3 要 ignore（需要老李 `git rm -r`）

```
assets/map-parsed/losttemple/   # 之前 commit 内
assets/pe2-prefabs/Buildings/  # commit fe6aad6 加入
assets/visuals/Buildings/       # commit dbe96d8 加入（master 可能已合并）
```

**老李**自己 `git rm -r` —— 不是我做的事。

---

## 5. 重新生成时机

| 改动 | 触发 |
|------|------|
| WC3 安装变化（重装 / 升级） | 跑 `node tools/bootstrap.mjs` |
| 地图新增 | 改 `tools/bootstrap.config.json::maps.items` + 跑 |
| m2g 工具升级 | 跑 `node tools/bootstrap.mjs --no-extract`（跳过 mpq） |
| slk 表新增 | 跑 `node tools/bootstrap.mjs --no-extract --no-convert --no-parse` |
| 转换 filter 改 | 改 `tools/bootstrap.config.json::convert` + 跑 |

---

## 6. 异常处理

| 情况 | 处理 |
|------|------|
| WC3 没装 | bootstrap 报错，提示装 WC3 + 设 `WC3_PATH` |
| Godot 没装 | 同上 + 提示装 Godot 4.x（asset-convert bake .scn 用）|
| StormLib 没编译 | mpq-extract 跳过，提示 `cd tools/mpq-extract && npm install` |
| node < 18 | bootstrap 报错，提示升级 node |

---

## 7. 贴图共享（方案 B：`.gltf` + 外部 URI）

**问题（旧 GLB）**：二进制 GLB 规范要求 image embedded，同一张 `Textures/Foo.png` 会被 N 个模型各嵌一份；
Godot auto-import 还会再抽出 `<model>_baseColor_*.png` 副产物。

**解法**：MDX → **`.gltf` + `.bin`**，`images[].uri` 相对指向 `Textures/*.png` / `_placeholders/*.png`（磁盘唯一）。
运行时 `RuntimeAssets.load_gltf_scene` 对 `.gltf` 走 `GLTFDocument.append_from_file`，才能解析外部图。

**`.gdignore`**：外链后不再强制。若要在编辑器 FileSystem 看模型，可删顶层 `.gdignore`；
共享贴图只会 import 一次。若仍想避免大批量 import，可保留 `.gdignore`，运行时仍走磁盘路径。

**迁移**：`npm run convert -- --models-only` 会生成 `.gltf` 并删掉同 stem 的旧 `.glb`。
加载侧仍回退识别遗留 `.glb`。

**.gitignore 配对**：`assets/asset-converted/**` 忽略所有 + `!assets/asset-converted/.gdignore` 白名单（若保留）。

**老 PC 升级步骤**：
```bash
git pull
node tools/bootstrap.mjs --clean-imports   # 清旧 import / 旁路 PNG 副产物
npm run convert -- --models-only           # 重出 .gltf
npm run bake:scn                           # 重烤 .scn
```

`--clean-imports` 删除：
- `**/*.import`
- GLB/GLTF 旁的 `<model>_<tex>.png`（重复副产物；canonical 在 `Textures/`）

不动：`*.gltf` / `*.bin` / `*.scn` / `Textures/*.png` / `_placeholders/` / `*.pe2.json` / `*.geosetvis.json`。

---

## 8. eager bake (.scn 一次性烤完)

**为什么需要 eager bake**：
- `.scn` 是 Godot native PackedScene binary，runtime 加载比 `.glb` 快 **3-5x**
  - `.scn` 直接 `_get_object_from_buf` 解码
  - `.glb` 走 `GLTFDocument` 解析 JSON + BIN chunk + 递归 build + 后处理
- `.scn` 预烘焙 4 件事，runtime 不用再算：
  1. **Geoset visibility 注入**：从 `*.geosetvis.json` 写 `:visible` 轨到 AnimationPlayer
  2. **PE2 粒子 prefab**：从 `*.pe2.json` 构 GPUParticles3D 子树
  3. **WC3 材质修正**：FilterMode → depth_draw_mode（避免半透明建筑透视）
  4. **ImageTexture 内嵌 + Stand 显隐预 roll**

**当前默认行为**（`m2g` cli）：

| 阶段 | `--scn-only` | `--skip-scn` | 默认 |
|------|------|------|------|
| textures | ✗ | ✗ | ✅ |
| models | ✗ | ✗ | ✅ |
| scn bake | ✅ | ✗ | ✅ |

`m2g` cli 默认 `doScn=true`（modelsOnly 也跑 bake），所以 `node tools/asset-convert/src/cli.js` 默认就 = MDX → GLB → SCN 一条龙。bootstrap 阶段叫"asset-convert"，但实际含 eager bake。

**bootstrap CLI**：
- `--no-bake`：m2g 加 `--skip-scn`，asset-convert 只产 GLB（备用场景：手动 bake）
- `config.skip.bake: true`：同上（配置文件等价）

**Lazy bake 兜底**（`MapModelCache`）：
- 首次 `instance_glb` 时如果 .scn 缺失 → 走 `GLTFDocument` 慢路径 + 后台 `_lazy_bake_queue` 排队烤 .scn
- 下次同 path 命中走 PackedScene 快路径
- eager bake 跑完后 lazy queue 几乎为空（除非 earger 之后又删了 .scn）

**为什么不让 lazy bake 替代 eager bake**：
- lazy bake 在 cold start 首次 instance 时才烤，单位面板 50+ 模型冷启动会卡（每个 1-10s）
- eager bake 把 30-50 min 烘焙集中到 bootstrap 阶段，runtime 零成本

**预期时间**（老 PC 满跑）：
- mpq-extract: 2-3 min（首次），< 1 min（增量）
- asset-convert + bake: 30-50 min（全量），3-10 min（增量）
- map-parse: 1-2 min（每张图）
- slk-export: < 30s
- 总计: **30-50 min 首次**，**3-10 min 增量**

**完整性检查**（`tools/check-asset-integrity.mjs`）：
- 检查 6 项：MDX→GLB→SCN 覆盖 / 地图解析 / SLK 导出 / Godot import 残留 / GLB 旁重复 PNG
- 用法：`node tools/check-asset-integrity.mjs [--md report.md] [--fail]`
- `--fail` 模式有缺口 exit 1，可接入 pre-commit / CI
- 当前状态（**bf9fa2f**）：1 个缺口（EchoIsles 缺 w3x 源，等老李补）

---

最后更新：2026-08-09
