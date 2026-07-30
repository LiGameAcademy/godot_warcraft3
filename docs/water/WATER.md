# 水体渲染（HiveWE / 官方对齐）

原则：**尽可能贴近原作效果与实现方式**；先对标官方管线，再谈风格化增强。

参考：

- [mdx-m3-viewer](https://github.com/flowtsohg/mdx-m3-viewer) `w3x/shaders/water.*`
- HiveWE `data/shaders/water.*`（几何/深度色同款；**未使用** `cells`）
- `Water.slk` → `assets/slk-exported/TerrainArt/Water.json`
- XGM：[Кастомизация воды](https://xgm.guru/p/wc3/Kastomizatsiya-vody-TEo)（`cells` = 贴图占几格）
- `UI/MiscData.txt` `[Water]`：`WavesDepth=25`、`DeepLevel=64`
- 经典 MDX：`Doodads/.../Water/Shoreline*.mdx`（自动岸线，仅 PE2，无网格）

---

## 官方实际在做什么

| 模块 | 做法 |
|------|------|
| 几何 | 每格一个 quad；四角任一有 `water` 标志才画（**含斜坡格**） |
| 高度 | `waterHeight + tileset.water_offset`（Icecrown `ISha.height = -0.7` → ×128 ≈ -89.6） |
| 深/浅色 | `depth = waterH - groundH`，浅/深色插值（DeepLevel=64） |
| **贴图缩放** | **`cells`：一张贴图覆盖 cells×cells 格**（ISha=`2`） |
| 贴图动画 | `Water00..N` 按 `texRate` 轮播 |
| **自动岸浪** | `Water.slk` → `shoreSFile/OC/IC` = **Shoreline\* MDX（仅 PE2）**；引擎按直边/内外角生成，不写 `.doo` |
| 出浪条件 | `WavesDepth=25`；地图 `waterWavesCliff` / `waterWavesRolling` |
| ShorelineWave | **手动装饰**网格模型，走 doodads，**不是**自动岸线字段 |

---

## 本仓库状态

### 已对齐

| 项 | 说明 |
|----|------|
| 水面网格 + 深度色 + 序列帧 | `wc3_water_*` / `wc3_water.gdshader` |
| UV × `cells` | `tile_xy / cells` |
| **斜坡下铺水** | `has_water_flag` 画水（HiveWE `water.vert`）；`is_surface_water_tile` 仅岸浪排除斜坡 |
| **WavesDepth 岸线过滤** | 岸边深度 &lt; 25 跳过 |
| **WavesDepth 等深线（激流）** | 深/浅邻格交界：深水侧朝浅水发射，水道对向泡沫 |
| **Shoreline S / OC / IC** | 直边/外角/内角分型；各用对应 MDX 主 PE2 |
| 贴图 | `Textures/ShorelineParticleXY.png` |
| 地图 flags | `waterWavesCliff` / `waterWavesRolling` |
| **Icecrown 贴图** | 嵌套 `War3x.mpq/I.mpq` → `I_Cliff*` / `I_Water*`（`tools/extract-icecrown-replaceables.mjs`）；无则回退 `N_*` |
| **PE2 着色** | 对齐 HiveWE：`frag = tex * color`；Additive ≈ `SRC_ALPHA, ONE`（预乘 + `blend_add`） |
| **PE2 参数** | 来自 `Shoreline0.mdx` 等：S `rate=0.8 life=4.5 scale=30/80/70`；稳态约 `rate*life` 个大软粒子 |

### HiveWE 对照结论（2026-07）

HiveWE **不实现**自动岸浪摆放（无 `shoreSFile` / `WavesDepth` 逻辑），只渲染已放置 MDX 的 PE2：

- `particle_emitter2.frag`：`frag_color = tex * v_color`
- Additive：`glBlendFunc(GL_SRC_ALPHA, GL_ONE)`
- XYQuad：贴地，朝向水平速度；spawn 在 `±0.5*length` 矩形

自动岸线仍是游戏/本仓库 `Wc3ShorelineBuilder` 的职责。稀碎感通常来自错误裁切 alpha / 缩尺度，而非粒子数量不够（S 稳态仅约 4 个，靠大 scale 软边叠成条）。

### 与原作差距（完善优先级）

| 优先级 | 项 | 现状 | 目标 |
|--------|----|------|------|
| **P1** | Water.slk `shore*` | 未读路径字段 | 恢复 `shoreDir` + `shoreS/OC/ICFile`（及 Var）选模 |
| **P1** | splash 第二发射器 | 仅主 PE2 | Shoreline / OC 的 splash 粒子 |
| **P2** | 真正 MDX 粒子 | Godot MultiMesh 模拟 | 解析 PE2 或预烘焙；节点朝向 / Emission |
| **P3** | 水面 shader 细项 | 序列帧 + 顶点色 | 对照 viewer/HiveWE 补雾、混合 |
| — | ShorelineWave 网格浪 | 不自动生成 | 地图 doodad 走装饰层 |

### 相关文件

- `scripts/map/presentation/water/wc3_water_mesh.gd` — 水面；斜坡下铺水
- `scripts/map/presentation/water/wc3_shoreline_builder.gd` — 放置点
- `scripts/map/presentation/water/wc3_shore_foam.gd` — MultiMesh 泡沫
- `shaders/wc3_shore_foam.gdshader` / `wc3_water.gdshader`
- `scripts/map/presentation/layers/map_water_layer.gd`
- `tests/water/selftest_shoreline.gd`

### 验收

```text
Water: tiles=… underRamp=…
Shore foam: S=… OC=… IC=… instances=…
```

斜坡/崖下应能看见水面伸入坡底；岸浪仍只落在开阔水面侧。

```bash
Godot_*_console.exe --headless --path . -s res://tests/water/selftest_shoreline.gd
```

---

## 不做

| 项 | 原因 |
|----|------|
| Gerstner / SSR 等风格化增强 | 偏离原作 |
| 把 ShorelineWave 塞进自动岸线 | 官方是手动装饰物 |
