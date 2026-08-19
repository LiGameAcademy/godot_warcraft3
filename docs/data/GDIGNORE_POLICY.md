# .gdignore 政策

> Godot 4 用来**告诉编辑器**"这个目录不参与文件系统扫描"的小文件。
> 不同于 `.gitignore`（git 层）—— `.gdignore` 是**编辑器层**的忽略。

## 1. 仓库当前清单

| 路径 | 用途 | 平台 |
|------|------|------|
| `assets/asset-converted/.gdignore` | **必须**：阻止 Godot auto-import GLB → 不生成 `<model>_<tex>.png` 重复贴图副产物 | 跨平台 |
| `docs/.gdignore` | 可选：docs 不当 res:// 资源扫描（避免 docs/_assets 等污染） | 跨平台 |
| `.godot/.gdignore` | Godot 自动生成 | 缓存目录不入库 |

`git ls-files | grep '\.gdignore$'` 验证：

```text
assets/asset-converted/.gdignore
docs/.gdignore
```

## 2. 为什么 `assets/asset-converted/` 必须有 `.gdignore`

GLB 规范硬约束：`image` 必须是 embedded（bufferView），**不允许**外部 URI 共享贴图。
→ m2g 写 GLB 时把 PNG bytes 内嵌进 bufferView，**每个 GLB 自带一份** PNG。
→ Godot 编辑器打开项目时对所有 GLB 跑 auto-import，**每个 GLB 旁路都生成一份 `<model>_<tex>.png`**。
→ 同一 BLP（如 `Textures/Footman.blp` 被 50 个模型共享）→ 50 份**内容相同**的重复 PNG（md5 相同，文件名不同）。
→ 加上 `.ctex` 压缩缓存 + `.import` 元数据 → 资源目录体积暴涨。

**根因**：GLB 规范不允许外部 URI，重复贴图只能在 auto-import 层解决。
**修法**：在 `assets/asset-converted/` 放空 `.gdignore` → Godot 不扫描此目录 → 不生成副产物。

详见 [PIPELINE.md §3 重复贴图根因](PIPELINE.md) 和 `docs/tools/ASSET_LAYOUT.md` §3。

## 3. 为什么**其他**目录不需要 `.gdignore`

`assets/` 下其他子目录的 `.tscn` / `.json` / `.tres` / `.gdshader` 都是**运行时 / 编辑器要看到**的资源：

| 目录 | 文件 | Godot 要看？ |
|------|------|------------|
| `assets/visuals/` | `.tscn` | ✅（建筑视觉，可选） |
| `assets/map-parsed/` | `.json` | ✅（地图数据，运行时 Resource.load） |
| `assets/slk-exported/` | `.json` | ✅（SLK 数据） |
| `assets/materials/` | `.tres` | ✅（自定义材质） |
| `assets/shaders/` | `.gdshader` | ✅（自定义 shader） |

**唯一不能**让 Godot 看到的就是 `asset-converted/`（被 gitignore + .gdignore 双重屏蔽）。
这层屏蔽**正合需要**：`.cache/` 资源从 `.gitignore` + `tools/mpq-extract` 解包到 `.cache/wc3-assets/`，再经 `tools/asset-convert` 转成 PNG/GLB 落到 `assets/asset-converted/`。运行时直接从 `res://assets/asset-converted/...` 加载（`RuntimeAssets`），**不需要** Godot 编辑器做额外 .import 转换。

## 4. 跨平台

`.gdignore` 是 Godot 编辑器识别的纯文本文件，**与平台无关**：
- 路径分隔符：用 `/`（不是 `\`），即使在 Windows
- 编码：UTF-8 / ASCII
- 文件存在性：存在即生效，**与 .gitignore 协同但独立**

Windows / macOS / Linux 编辑器看到 `assets/asset-converted/.gdignore` 都会跳过该目录扫描。
**新协作者 clone 仓库后**直接打开 Godot 即生效，不需要任何额外配置。

## 5. 跨平台协作注意点

- **必须入库**（不像 `.cache/`）：`.gitignore` 加 `!assets/asset-converted/.gdignore` 白名单。
  当前 `.gitignore` 已配：
  ```text
  assets/asset-converted/**
  !assets/asset-converted/.gdignore
  ```
- **跨平台编辑工具**：不要用 Windows 记事本 / VSCode 默认 CRLF。统一用 LF（仓库已有 `.gitattributes` / 工具默认值约束）。
- **新增子目录的判断标准**：如果新目录放的是 "已就绪、可直接 res:// 加载" 的产物（`.tscn` / `.json` / `.tres`），**不要**加 `.gdignore`；如果是 "中间产物"（GLB / PNG / .scn），**要**加。

## 6. 验证

```bash
# 1. 仓库入库的 .gdignore（应有 2 个）
git ls-files | grep '\.gdignore$'

# 2. 编辑器实际生效（Godot 打开后资源面板看不到 asset-converted 下的内容）
# Godot Editor → FileSystem dock 不应列出 assets/asset-converted/ 的 .glb/.png/.scn

# 3. 重复 PNG 副产物：asset-converted 目录下不应存在 <model>_<tex>.png 重复文件
# （修复前会生成，修复后不会）
```
