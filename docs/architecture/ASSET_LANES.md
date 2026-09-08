# 资产三车道契约

> 目标：游戏 / 编辑器 **只读 `assets/`**；extract 只进临时 `assets/.staging/`，结束后删除。  
> 相关：[MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) · [PIPELINE.md](../data/PIPELINE.md) · [LEGAL.md](../data/LEGAL.md) · [CONTENT_PACKS.md](../data/CONTENT_PACKS.md)  
> 最后更新：2026-09-05

---

## 1. 原则

| 原则 | 说明 |
|------|------|
| 无持久 `.cache` | extract 默认写 `assets/.staging/wc3-assets`；bootstrap 结束后删除 |
| `.cache` 不进运行时 | `AssetProvider` / `RuntimeAssets` **不**回退 `.cache` |
| 依赖落 `assets/` | 缺文件 → 跑 `bootstrap`，不静默读中间态 |
| 相对路径镜像 MPQ | `Units/...`、`Buildings/...`、`UI/...` 与经典客户端逻辑路径一致 |
| 不入库（D3） | 暴雪内容 gitignore；仓库只留工具与契约 |

---

## 2. 管线

```text
经典 MPQ
  │ tools/mpq-extract
  ▼
assets/.staging/wc3-assets/        ← 临时（bootstrap 结束后删）
  │
  └─ tools/asset-convert（ingest）
        ├─ clean：清 baseColor / .import / 旧 .glb / 旁路 PNG
        ├─ 转换：BLP→PNG、MDX→.gltf（外链 Textures/）
        ├─ 复制：PathTextures / Sound / Fonts / wav·mp3·tga… → asset-converted/
        │         UnitFunc/UI txt → slk-exported/
        └─ bake：.scn
  │
  ├─ tools/slk-export ─────────────► assets/slk-exported/   【数据 JSON】
  └─ tools/map-parse ──────────────► assets/map-parsed/     【地图】

完成后只留三车道；可用 --keep-staging 保留临时目录调试。
遗留 `.cache/wc3-assets` 仅作回退（工具会警告）。
```

特效（粒子 / Geoset 显隐 / 绑骨小件）如何从 MDX 旁路进 Godot，见对外说明：[docs/blog/04-wc3-effects-conversion.md](../blog/04-wc3-effects-conversion.md)。

| 车道 | 路径 | 内容 |
|------|------|------|
| 视觉 | `assets/asset-converted/` | PNG / GLTF+bin / .scn / PathTextures / **Sound(wav·mp3)** / Fonts / 其它直拷媒体 |
| 数据 | `assets/slk-exported/` | SLK JSON + UnitFunc/Strings + UI txt |
| 地图 | `assets/map-parsed/<slug>/` | 解析地图 |

---

## 3. 运行时解析顺序

1. mod overlay  
2. `assets/asset-converted/`  
3. `assets/slk-exported/`  
4. （结束；**无** staging / `.cache`）

模型 **Edition**（`Priest` vs `Priest_V1`）不在此 VFS 层决定，见 [CONTENT_PACKS.md](../data/CONTENT_PACKS.md)。

---

## 4. 清理残留

```bash
npm run convert -- --clean-only
# 或
node tools/bootstrap.mjs --clean-imports
```

删除：`*.import`、`baseColor*.png`、旧 `.glb*`、同目录 `.gltf` 未引用的旁路 PNG（如 `Footman_Footman.png`）。  
保留：`.gltf`/`.bin`/`.scn`/sidecar、`Textures/` 等 canonical 贴图。

---

## 5. 冒烟

- [ ] `assets/slk-exported/Units/HumanUnitFunc.txt`（含 `Builds=`）
- [ ] `assets/asset-converted/PathTextures/` 非空
- [ ] 模型旁无 `baseColor*.png` / `*.import`
- [ ] 无持久依赖 `.cache/wc3-assets`（可选删掉整个 `.cache`）
