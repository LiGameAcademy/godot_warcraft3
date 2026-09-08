# 内容包 / DLC 资源规则

> 目标：以 **TFT（冰封王座）为默认最终版**，并预留后续 DLC 叠层；  
> 解包同路径覆盖与运行时模型版本选择 **正交**，勿混为一谈。  
> 相关：[PIPELINE.md](PIPELINE.md) · [ASSET_LANES.md](../architecture/ASSET_LANES.md) · `ContentPackRules` · `Wc3IdCatalog`  
> 最后更新：2026-09-05

---

## 1. 两层规则（必读）

| 层 | 管什么 | 不做什么 |
|----|--------|----------|
| **A. 虚拟文件系统（VFS）** | 同逻辑路径多包写入，后者覆盖前者 | 不决定 `Priest` vs `Priest_V1` |
| **B. 模型版本（Edition）** | `UnitUI.file` + `fileVerFlags` → 选 `Name` / `Name_V1` / 未来后缀 | 不改已经落盘的同名文件 |

牧师就是典型：**War3x 不覆盖** `Priest.mdx`，另放 `Priest_V1.mdx` + `BloodPriest.blp`。  
只做「War3x 盖 War3」永远选不到肩甲队色那套 TFT 模。

---

## 2. 层 A — MPQ / 内容包叠层

### 2.1 经典客户端（已实现）

`tools/mpq-extract` 的 `MPQ_PRIORITY`（后者覆盖前者）：

```text
War3.mpq → War3x.mpq → War3Local.mpq → War3xLocal.mpq → War3Patch.mpq
```

落盘后相对路径与 MPQ 内逻辑路径一致（见 [WC3_ASSET_PATHS.md](WC3_ASSET_PATHS.md)）。

### 2.2 运行时三车道（已实现）

见 [ASSET_LANES.md](../architecture/ASSET_LANES.md)：

```text
mod overlay → assets/asset-converted/ → assets/slk-exported/
```

### 2.3 未来 DLC（约定，待接包）

把每个 DLC 看成 **又一个 VFS 源**，压进同一优先级栈的尾部：

```text
… → War3Patch → dlc/<id>/raw 或 dlc/<id>/converted（后写覆盖）
```

| 规则 | 说明 |
|------|------|
| 同路径覆盖 | DLC 改 `Textures/Foo.blp` → 最终版即 DLC |
| 新路径新增 | DLC 只加 `Units/.../Bar_V2.mdx` → 不碰旧文件 |
| 数据表 | DLC 的 `unitUI` / SLK 增量合并进 `slk-exported`（后行覆盖） |
| 合规 | 暴雪内容不进 git；DLC 产物同 [LEGAL.md](LEGAL.md) |

**不要**在 convert 阶段把 RoC 文件删掉「只留最终版」——基模仍是回退与对照。

---

## 3. 层 B — 模型版本（Edition）

### 3.1 数据字段

| UnitUI 字段 | 含义 |
|-------------|------|
| `file` | 基路径，无扩展名，如 `units/human/Priest/Priest` |
| `fileVerFlags` | 是否存在 expansion 变体。经典表中非 0（多为 `2`）→ 有 `*_V1` |

对象编辑器对应：**Art - Model File - Extra Versions**（RoC / Frozen Throne）。

### 3.2 当前 Edition

| Edition id | 含义 | 模型后缀 |
|------------|------|----------|
| `roc` | 仅基模 | `""` → `Priest` |
| `tft` | **默认**；有 flags 则优先 TFT 变体 | `"_V1"` → `Priest_V1` |

ProjectSettings：

```text
warcraft3/content/active_edition = "tft" | "roc"
```

缺省 / 空 → `tft`。

### 3.3 解析算法（权威实现：`ContentPackRules` + `Wc3IdCatalog`）

```text
base = UnitUI.file（去 .mdx/.mdl）
flags = UnitUI.fileVerFlags

candidates =
  if active_edition != roc 且 flags != 0:
      [ base + suffix(edition), base ]   # tft → base_V1, base
  else:
      [ base ]

取第一个在 asset-converted 存在的 stem（.gltf / .glb / .scn）
再拼地图 variation 数字后缀（Priest0 等），与 _V1 正交
肖像：{resolved_stem}_Portrait / _portrait
```

| 正交概念 | 例子 |
|----------|------|
| Edition 后缀 | `Priest_V1`（TFT 模） |
| doo variation | `Tree0` / `Tree1`（随机样式） |

**禁止**把 `_V1` 塞进 `variation` 整型参数。

### 3.4 未来 DLC 模型版本

| 扩展点 | 约定 |
|--------|------|
| 新 edition id | 如 `dlc_reforged_skin` |
| 后缀表 | `ContentPackRules.model_version_suffix(edition)`；未知包可先用 `_V2` 或读 pack manifest |
| flags | 若暴雪/自研表扩展多 bit，在 `expansion_model_candidates` 按 bit→后缀展开 |
| 无磁盘文件 | 静默回退更低 edition / 基模 |

---

## 4. 落地清单

| 项 | 状态 |
|----|------|
| MPQ 同路径覆盖 | ✅ `tools/mpq-extract` |
| 运行时 lane | ✅ `AssetProvider` / `RuntimeAssets` |
| `fileVerFlags` → `*_V1` | ✅ `ContentPackRules` + `Wc3IdCatalog.converted_glb_path` / `portrait_glb_path` |
| `active_edition` 设置 | ✅ 读 ProjectSettings（默认 tft） |
| DLC 包注册 / manifest | 📋 后置（先文档约定） |
| 批量把已有场景重绑到 V1 | 随选模自动生效；无需重烤（磁盘已有 `*_V1.scn`） |

---

## 5. 验收

- `hmpr`（`fileVerFlags=2`）在 `active_edition=tft` 下解析到 `…/Priest/Priest_V1.gltf`（或 `.scn`）
- 同设置下肖像优先 `Priest_V1_portrait`
- `active_edition=roc` 时回退 `Priest` / `Priest_portrait`
- `hfoo`（flags=0）始终 `Footman`，不受 edition 影响

```bash
godot --headless --path . -s res://tests/unit/selftest_content_pack_rules.gd
```

---

## 6. 非目标

- 不在本规则里做 Reforged CASC
- 不强制删除 RoC 基模文件
- 不把 UnitFunc 的 `Melee_V0/` 目录前缀与模型 `_V1` 混用（那是 INI 查找根，另一套）
