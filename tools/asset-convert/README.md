# asset-convert

将经典 WC3 资产转为 Godot 可用格式：

1. **贴图** `BLP` → `PNG`（`war3-model` 解码 + `pngjs`）
2. **模型** `MDX`/`MDL` → `GLB`（`war3-model` 解析 + `@gltf-transform/core`）
3. **粒子** `ParticleEmitters2` → 同 stem 旁路 `*.pe2.json`（Godot 运行时挂 `GPUParticles3D`）
4. **光晕 Geoset** FilterMode Additive/AddAlpha → 材质名 `_fm3`/`_fm4`；可用 `npm run reconvert:additive` 批量重转

默认顺序：`textures → models`。模型会优先使用已转换的 PNG；缺失时再即时转 BLP。无 `pe2.json` 时会重新转换该模型。

### 批量重转 Additive 光晕

```bash
# 默认只扫 Doodads/**
npm run reconvert:additive
# 全库
node scripts/reconvert-additive-geosets.mjs --include "**/*"
# 仅列表
node scripts/reconvert-additive-geosets.mjs --list-only
```

### 导出可编辑 PE2 预制（.pe2.tscn）

输出到 **`assets/pe2-prefabs/`**（与 `asset-converted` 同级、逻辑子路径镜像），**可提交 git**。  
`pe2.json` / 贴图仍在 `asset-converted`（不入库）。

```bash
godot --headless --path ../.. -s res://tools/export_pe2_scenes.gd -- --include Doodads/ --force
```

`Wc3Pe2Particles.attach_to` 优先 `res://assets/pe2-prefabs/.../*.pe2.tscn`，没有再回退 JSON。

```bash
npm install
npm run convert -- --include "Units/Human/Footman/**" --include "Textures/**"
```

输出根目录默认：`../../assets/asset-converted`（`res://assets/asset-converted/...`，已 gitignore）。

## 已知问题与处理

- **UV**：MDX 的 `TVertices` 不要做 `1-V` 翻转。
- **队伍色**：优先选用带真实路径的材质层。
- **GeosetAnim**：站立时 alpha=0 的网格（如死亡内脏）默认 scale=0，并在动画中按帧显隐。
- **Transparent**：FilterMode=1 使用 MASK + cutoff 0.75，避免半透明碎片。
- **Additive / AddAlpha（FilterMode 3/4）**：glTF 无加法混合；材质名带 `_fm3`/`_fm4`，Godot `MapModelCache` 加载时改成 `BLEND_MODE_ADD`（否则 `Yellow_Glow*` 黑底会变成实心黑牌）。
- **动画**：每个 Sequence → 一条 glTF Animation；扁平 Armature + 等权蒙皮。
