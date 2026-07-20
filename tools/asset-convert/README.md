# asset-convert

将经典 WC3 资产转为 Godot 可用格式：

1. **贴图** `BLP` → `PNG`（`war3-model` 解码 + `pngjs`）
2. **模型** `MDX`/`MDL` → `GLB`（`war3-model` 解析 + `@gltf-transform/core`）

默认顺序：`textures → models`。模型会优先使用已转换的 PNG；缺失时再即时转 BLP。

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
- **动画**：每个 Sequence → 一条 glTF Animation；扁平 Armature + 等权蒙皮。
