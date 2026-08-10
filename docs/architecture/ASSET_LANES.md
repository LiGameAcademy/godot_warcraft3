# 资产三车道契约

> 目标：游戏 / 编辑器 **只读 `assets/`**；`.cache/` 仅为 MPQ extract 中间态。  
> 相关：[MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) · [PIPELINE.md](../data/PIPELINE.md) · [LEGAL.md](../data/LEGAL.md)  
> 最后更新：2026-08-09

---

## 1. 原则

| 原则 | 说明 |
|------|------|
| `.cache` 不进运行时 | `AssetProvider.resolve` / `RuntimeAssets.resolve` **不**回退 `.cache/wc3-assets` |
| 依赖落 `assets/` | 缺文件 → 跑 `bootstrap` / `sync-data-assets`，不静默读 BLP/MDX/TXT 缓存 |
| 相对路径镜像 MPQ | `Units/...`、`Buildings/...`、`UI/...` 与经典客户端逻辑路径一致 |
| 不入库（D3） | 暴雪内容 gitignore；仓库只留工具与契约 |

---

## 2. 三车道

```text
经典 MPQ
  │ tools/mpq-extract
  ▼
.cache/wc3-assets/                 ← extract 中间态（工具可读；游戏不可依赖）
  │
  ├─ tools/asset-convert ──────────► assets/asset-converted/   【视觉】
  │                                    PNG / GLTF(+bin, 外链贴图) / .scn
  │                                    （可选 .gdignore）
  │
  ├─ tools/slk-export ─────────────► assets/slk-exported/      【数据】
  │  tools/sync-data-assets            SLK JSON
  │                                    + *UnitFunc.txt / *UnitStrings.txt
  │                                    + UI/WorldEdit*.txt
  │
  └─ tools/map-parse ──────────────► assets/map-parsed/<slug>/ 【地图】
                                       heightfield / doodads / units JSON
```

| 车道 | 路径 | 内容 | 再生命令 |
|------|------|------|----------|
| 视觉 | `assets/asset-converted/` | 贴图网格场景 + `PathTextures/` | `asset-convert` + `sync-data-assets` |
| 数据 | `assets/slk-exported/` | 表 JSON + 单位 Func/Strings + 编辑器 UI txt | `slk-export` + `sync-data-assets` |
| 地图 | `assets/map-parsed/<slug>/` | 解析地图 | `map-parse` |

**不要**把 SLK / 地图塞进 `asset-converted/`：该目录有 `.gdignore`，且工具生命周期与视觉转换不同。

---

## 3. 运行时解析顺序

`AssetProvider.resolve` / `RuntimeAssets.resolve`：

1. mod overlay（后注册优先）
2. `assets/asset-converted/`
3. `assets/slk-exported/`
4. （结束；**无** `.cache`）

表数据专用：`RuntimeAssets.slk_path()` → 固定 `res://assets/slk-exported/...`。

ProjectSettings（可选覆盖）：

| 键 | 默认 |
|----|------|
| `warcraft3/asset_converted_dir` | `res://assets/asset-converted` 的绝对路径 |
| `warcraft3/asset_data_dir` | `res://assets/slk-exported` 的绝对路径 |
| `warcraft3/asset_cache_dir` | 仅诊断/工具；**resolve 不用** |

---

## 4. sync-data-assets

```bash
node tools/sync-data-assets.mjs
node tools/sync-data-assets.mjs --force
```

| 源（cache） | 目标 |
|-------------|------|
| `Units/*UnitFunc.txt` / `*UnitStrings.txt`（及 Melee_V0/Custom_* 变体若存在） | `assets/slk-exported/` |
| `UI/WorldEditData.txt` 等 | `assets/slk-exported/UI/` |
| `PathTextures/**` | `assets/asset-converted/PathTextures/` |

由 `tools/bootstrap.mjs` 与 `tools/dev-setup.mjs` 自动调用。  
旧入口 `tools/sync-editor-assets.mjs` 已转调本脚本（deprecated）。

---

## 5. 冒烟

- [ ] `assets/slk-exported/Units/UnitBalance.json`
- [ ] `assets/slk-exported/Units/HumanUnitFunc.txt`（含 `Builds=`）
- [ ] `assets/slk-exported/UI/WorldEditData.txt`
- [ ] `assets/asset-converted/PathTextures/` 非空
- [ ] 游戏/编辑器启动后，日志中无「回退 .cache」类路径
