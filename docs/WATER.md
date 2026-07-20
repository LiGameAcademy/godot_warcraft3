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
| 几何 | 每格一个 quad；四角任一有 `water` 标志才画 |
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
| **斜坡不画水** | `Wc3WaterMesh.is_surface_water_tile`：有 water 标志但 `is_ramp_tile` → 跳过 |
| **Shoreline 泡沫（近似）** | 单套 PE2 参数 + 单个 MultiMesh；水平 XYQuad；Additive + 深度测试 |
| 贴图 | `Textures/ShorelineParticleXY.png` |
| 地图 flags | `waterWavesCliff` / `waterWavesRolling` |

### 与原作差距（完善优先级）

| 优先级 | 项 | 现状 | 目标 |
|--------|----|------|------|
| **P0** | WavesDepth | 未读 `MiscData` / 未按深度过滤 | 深度 &lt; 25/128 不出浪（对齐官方） |
| **P0** | S / OC / IC 分型 | 直边与角共用一套参数 | 按边类型选 Shoreline / OutsideCorner / InsideCorner |
| **P1** | Water.slk `shore*` | 字段已删、不读 | 恢复读取 `shoreDir` + `shoreS/OC/ICFile`（及 Var） |
| **P1** | PE2 参数分档 | 硬编码 Shoreline0 近似 | 从对应 MDX（或导出表）取 Length/Speed/Life/Scale/Emission |
| **P2** | 真正 MDX 粒子 | Godot MultiMesh 模拟 | 解析 PE2 或预烘焙粒子描述，尽量复刻节点朝向/splash |
| **P3** | 水面 shader 细项 | 序列帧 + 顶点色 | 对照 viewer/HiveWE 补雾、混合、过滤方式 |
| — | ShorelineWave 网格浪 | 已删自动管线 | **不**做自动生成；地图里若有 doodad 则走装饰层 |

### 相关文件

- `scripts/map/wc3_water_mesh.gd` — 水面；斜坡跳过
- `scripts/map/wc3_shoreline_builder.gd` — 放置点
- `scripts/map/wc3_shore_foam.gd` — MultiMesh 泡沫
- `shaders/wc3_shore_foam.gdshader` / `wc3_water.gdshader`
- `scripts/map/map_water_layer.gd`
- `tools/selftest_shoreline.gd`

### 验收

```text
Water: tiles=… skipRamp=…
Shore foam: emitters=… instances=…
```

斜坡底部应见水面边界与朝岸泡沫；斜坡 mesh 下不应再铺一层水。

```bash
Godot_*_console.exe --headless --path . -s res://tools/selftest_shoreline.gd
```

---

## 不做

| 项 | 原因 |
|----|------|
| Gerstner / SSR 等风格化增强 | 偏离原作 |
| 把 ShorelineWave 塞进自动岸线 | 官方是手动装饰物 |
