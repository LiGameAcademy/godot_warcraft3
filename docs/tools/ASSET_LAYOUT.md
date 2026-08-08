# ASSET_LAYOUT — 资源布局规则

> **角色**：明确 `godot_warcraft3` git 仓库与本地资源的边界。
> **决策**（老李 D3，2026-08-08）：**任何 wc3 资源不入 git**。
> 仓库只装：源码 / 工具 / 文档 / 配置文件。所有 wc3 资源靠 `tools/bootstrap.mjs` 一键生成。
> 最后更新：2026-08-08

---

## 1. 规则总览

| 类型 | 入 git | 说明 |
|------|--------|------|
| 源码 | ✅ | GDScript / JS / 配置文件 |
| 工具源码 | ✅ | `tools/` 下 .js / .mjs / .gd（不含 vendor / node_modules）|
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
node tools/bootstrap.mjs      # 一键：extract → convert → parse → slk
```

`tools/bootstrap.mjs` 流程：

1. **检查依赖**：node >= 18、godot 二进制、WC3 安装（`tools/bootstrap.config.json` 或环境变量 `WC3_PATH`）
2. **npm install**：5 个子工具（并行）
3. **mpq-extract**：从 WC3 安装 → MPQ → 原文件（war3 / mdx / blp / slk）→ `tools/mpq-extract/tmp/`
4. **asset-convert**：原文件 → PNG / GLB / SCN / PE2 → `assets/asset-converted/`
5. **map-parse**：地图 w3x → JSON → `assets/map-parsed/<name>/`
6. **slk-export**：SLK → JSON → `assets/slk-exported/`
7. **打印** "✅ 资源就绪"

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

最后更新：2026-08-08
