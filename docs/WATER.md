# 水体渲染（HiveWE / 官方对齐）

原则：**先复刻官方外观，再考虑增强与重构。**  
增强项只记在「远期」一节，不直接实现。

参考：

- [mdx-m3-viewer](https://github.com/flowtsohg/mdx-m3-viewer) `w3x/shaders/water.*`
- HiveWE `data/shaders/water.*`（几何/深度色同款；**未使用** `cells`）
- `Water.slk` → `assets/slk-exported/TerrainArt/Water.json`
- XGM：[Кастомизация воды](https://xgm.guru/p/wc3/Kastomizatsiya-vody-TEo)（`cells` = 贴图占几格）
- `UI/MiscData.txt` `[Water]`：`WavesDepth=25`、`DeepLevel=64`

---

## 官方实际在做什么

| 模块 | 做法 |
|------|------|
| 几何 | 每格一个 quad；四角任一有 `water` 标志才画 |
| 高度 | `waterHeight + tileset.water_offset`（Icecrown `ISha.height = -0.7` → ×128 ≈ -89.6） |
| 深/浅色 | `depth = waterH - groundH`，浅/深色插值（DeepLevel=64） |
| **贴图缩放** | **`cells`：一张贴图覆盖 cells×cells 格**（ISha=`2`） |
| 贴图动画 | `Water00..N` 按 `texRate` 轮播 |
| **自动岸浪** | `Water.slk` → `shoreSFile/OC/IC` = **Shoreline\* MDX（仅 PE2，无网格）**；引擎按直边/内外角生成，不写 `.doo` |
| 出浪条件 | `WavesDepth=25`；地图 `waterWavesCliff` / `waterWavesRolling` |
| ShorelineWave | **手动装饰**网格模型，**不是**自动岸线字段 |

---

## 本仓库状态

### 已完成

| 项 | 说明 |
|----|------|
| 水面网格 + 深度色 + 序列帧 | `wc3_water_*` / `wc3_water.gdshader` |
| UV × `cells` | `tile_xy / cells` |
| **斜坡不画水** | `Wc3WaterMesh.is_surface_water_tile`：有 water 标志但 `is_ramp_tile` → 跳过（水面停在坡底） |
| **Shoreline 泡沫** | 每岸点 **3 层** `MeshInstance3D`；细分网格新月弧；偏航抖动；相位/周期/摆动 instance 错开 |
| 尺寸 | `QuadMesh` 边长 `QUAD_METERS≈3.2`（Godot 米），不靠粒子 `scale * WORLD_SCALE` |
| 拓扑 | 直边 S、外角 OC、内角 IC；另补 WavesDepth 等深线；岸线判定与水面格一致 |
| 贴图 | `Textures/ShorelineParticleXY.png` |

### 有意不做 / 降级

| 项 | 说明 |
|----|------|
| ShorelineWave 网格浪 | 非官方自动管线；`MapWaterLayer.build_shore_mesh_waves=false` |
| 完整 MDX PE2 粒子系统 | 用定向四边形 + shader 近似（每实例独立朝向，避免共享 emission 失败） |

### 相关文件

- `scripts/map/wc3_water_mesh.gd` — 水面；斜坡跳过
- `scripts/map/wc3_shoreline_builder.gd` — 放置点
- `scripts/map/wc3_shore_foam.gd` — MultiMesh 泡沫
- `shaders/wc3_shore_foam.gdshader`
- `scripts/map/map_water_layer.gd`
- `tools/selftest_shoreline.gd`

### 验收

控制台：

```text
Water: tiles=… skipRamp=…
Shore foam: points=… (S=… OC=… IC=…) …
```

斜坡底部应见水面边界与朝岸泡沫；斜坡 mesh 下不应再铺一层水。

自测：

```bash
Godot_*_console.exe --headless --path . -s res://tools/selftest_shoreline.gd
```

---

## 远期（只文档）

- 更完整的 PE2（splash 发射器、XYQuad、Length 线发射）
- `shore_mask` / stylized 泡沫 shader
- Gerstner / SSR（不做）
