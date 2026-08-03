# 对战地图环境：天空 · 天气 · 光照 · 阴影

> 目标：在 Godot 中复刻 WC3 对战图观感（以 Echo Isles 等 Melee 图为验收）。  
> 状态：**设计方案**（尚未实现）  
> 配套：[ARCHITECTURE.md](ARCHITECTURE.md) · [ROADMAP.md](ROADMAP.md) · [../shader/README.md](../shader/README.md)  
> 最后更新：2026-08-03

---

## 0. 先认清 WC3 在做什么

经典 WC3 **不是**现代 PBR + 实时方向光阴影管线，而是几套**并行**的环境系统：

| 系统 | 权威数据 | 游戏里长什么样 |
|------|----------|----------------|
| **地表光照** | 贴图本身（prelit） | 地面/悬崖 **不吃**方向光；本项目 shader 已是 `unshaded` |
| **昼夜（DNC）** | 每 Tileset 的 Terrain/Unit `*.mdl` | 旋转的「日夜光模型」改环境色与单位受光 |
| **天空** | `Environment/Sky/*.mdl` | 大球/穹顶模型，跟镜头 |
| **天气** | `TerrainArt/Weather.slk` + 粒子贴图 | 全局或区域粒子（雨/雪/灰） |
| **雾** | `war3map.w3i` fog 字段 | 按**高度/距离**淡入，非体积雾 |
| **地形阴影** | `war3map.shd` | **烘焙**的 4×4 子格遮罩，叠在地表上 |
| **单位阴影** | 引擎 blob / 简单投影 | 与 SHD 不是同一套 |

本项目当前状态：

- 已有：`info.json`（fog / `globalWeather` / `customLightTileset`）、`WeatherEffectDef`、Sky/DNC 的 GLB 转换物、地面 `unshaded`
- 未做：环境层 Present、SHD 解析、天气粒子、昼夜驱动、雾着色

Echo Isles 样例（`assets/map-parsed/echoisles/info.json`）：

```text
mainGroundType     = "L"          # Lordaeron Summer
globalWeather      = "RAlr"       # Ashenvale Light Rain
fog.style          = 0            # 关（style≠0 才开）
customLightTileset = 空           # 用主地形 tileset 的 DNC
```

`RAlr`（`Weather.json`）：`rainTail` 贴图、`useFog=1`、高约 768、下落速度 −900、粒子数 880——典型「镜头上方雨帘」。

---

## 1. 设计原则（与现有架构对齐）

1. **地表继续 unshaded**  
   不把 `wc3_ground` / `wc3_cliff` 改成 lit 来「蹭」Godot 阴影。否则 cliff 顶缘过亮等问题会回来（见 shader 文档）。

2. **环境是独立 Present 层**  
   挂在 `MapRoot` 旁或之下：`MapEnvironmentLayer`（或 `game` 下 `EnvironmentDirector`），读 `info.json` + Catalog，不污染 Heightfield。

3. **数据驱动**  
   - 天气：`WeatherEffectDef`（已入库）  
   - 昼夜：Tileset → `terrain_dnc` / `unit_dnc`（HiveWE `Tileset` 字段）  
   - 天空：Tileset / 地图约定 → Sky GLB  
   - 雾 / 全局天气：`info.json`  
   - 阴影：解析 `war3map.shd` → 贴图

4. **游戏优先，编辑器菜单后置**  
   编辑器已有 View→Sky / Weather / Fog / Shadows 菜单项占位；实现时同一套 Layer，两边开关。

5. **分阶段交付**  
   先「像」、再「准」、最后「可交互昼夜」。

---

## 2. 目标场景树

```text
GameMain / EditorMain
├── WorldEnvironment          # Godot Environment：背景/环境光/高度雾（可选）
├── Sun (DirectionalLight3D)  # 仅照「可 lit」物体（单位可选）；默认不驱动地面
├── MapRoot
│   ├── Terrain / Cliffs …    # 仍 unshaded
│   └── Environment/          # 新建
│       ├── SkyDome           # 实例 Sky GLB，跟随相机 XZ
│       ├── WeatherParticles  # GPUParticles3D，按 WeatherEffectDef
│       ├── ShadowOverlay     # SHD → 地表 shader 乘色（或独立 decal 层）
│       └── DayNight          # 采样 DNC 或曲线，改 ambient / 单位光
└── RtsCamera
```

可选：把 `WorldEnvironment` + `Sun` 也收进 `MapEnvironmentLayer.setup(info, tileset)`，避免 game_main / editor 各写一份。

---

## 3. 天空（Sky）

### 3.1 WC3 语义

- 资源：`Environment/Sky/<Name>/<Name>.mdl`（本地已有对应 `.glb`，如 `LordaeronSummerSky`）。
- 行为：天空盒/穹顶跟相机水平移动；不参与碰撞；通常不受天气粒子深度排序困扰（画在远处）。

### 3.2 Godot 方案（推荐）

| 方案 | 说明 | 选用 |
|------|------|------|
| **A. 实例 Sky GLB** | 与官方资源一致；跟 `RtsCamera` 同步 XZ | **首选** |
| B. `Sky` + `PanoramaSkyMaterial` | 需从 MDX 烘 panorama | 后期优化包体时再用 |
| C. 纯程序渐变 `ProceduralSkyMaterial` | 快但不像 WC3 | 仅占位 |

实现要点：

```text
1. 由 mainGroundType / customLightTileset 查表 → sky 路径
   L → Environment/Sky/LordaeronSummerSky/LordaeronSummerSky.glb
2. 实例化后 scale 拉大（覆盖远裁面），Y 固定或微抬
3. 每帧：sky.global_position.xz = camera.look_at.xz
4. cast_shadow = OFF；layers 可与单位分离
```

Tileset→Sky 映射表可先硬编码常见字母（L/F/W/A/…），再从 `WorldEditData` / HiveWE tileset 表补全。

---

## 4. 天气（Weather）

### 4.1 数据

`WeatherEffectDef` 已从 `TerrainArt/Weather.json` 加载。关键字段：

| 字段 | 用途 |
|------|------|
| `tex_dir` + `tex_file` | 粒子贴图（如 `ReplaceableTextures/Weather/rainTail`） |
| `em_rate` / `particles` / `lifespan` | 发射率、容量、寿命 |
| `veloc` / `accel` / `ang_x`/`ang_y` | 速度与方向锥 |
| `height` | 相对地面/相机的生成高度 |
| 颜色/缩放三段 | 粒子色与尺寸曲线 |
| `use_fog` | 是否叠加雾感（可提高 Environment fog 密度） |
| `ambient_sound` | 环境音（后期） |

地图入口：`info.globalWeather`（四字符 ID）。区域天气（触发器 `AddWeatherEffect`）远期再做。

### 4.2 Godot 方案

使用 **`GPUParticles3D`**（或 `CPUParticles3D` 做第一版）：

```text
MapWeatherEffect
  ├── 读 WeatherEffectDef
  ├── 加载粒子贴图（asset-converted 路径规则同 Catalog）
  ├── 发射盒：跟随相机上方的 AABB（宽≈视距，高≈ height * WORLD_SCALE）
  ├── process_material：重力/初速对齐 veloc（注意 WC3 Y-up → Godot Y-up，地图水平为 XZ）
  └── 材质：按 alphaMode 选 mix/add；颜色用 ColorRamp 近似 start/mid/end
```

验收（Echo Isles）：开 `RAlr` 后镜头移动时始终有细雨；关天气则无粒子。

区域天气：同一套节点，绑定 Region AABB；Melee 图可先只做全局。

---

## 5. 光照与昼夜（Lighting / DNC）

### 5.1 WC3 语义

HiveWE 导出脚本等价于：

```text
SetDayNightModels(tileset.terrain_dnc, tileset.unit_dnc)
```

默认 Lordaeron：

```text
Environment/DNC/DNCLordaeron/DNCLordaeronTerrain/...
Environment/DNC/DNCLordaeron/DNCLordaeronUnit/...
```

DNC 模型是**带动画的灯光几何**，引擎按游戏时间采样，改变环境与单位受光。  
`customLightTileset` 非空时，用该字母对应 tileset 的 DNC，而不是主地形。

### 5.2 与「地面 unshaded」的关系

| 物体 | 光照策略 |
|------|----------|
| 地面 / 悬崖 / 水 | **不**跟 DirectionalLight；靠贴图 + SHD +（可选）全局 multiply tint |
| 天空 | 自发光/unshaded 模型 |
| 单位 / 装饰（可选）| 可用弱 DirectionalLight + 低强度 ambient，或保持 unshaded + 队伍色 |

**不要**为了「有影子」把全图改成 lit。

### 5.3 Godot 实现分档

**P0 — 静态氛围（先做）**

- 按 tileset 设 `WorldEnvironment`：`ambient_light_color/energy`、背景色  
- 一盏 `DirectionalLight3D`：固定俯角（对标午间），`light_energy` 适中，**只影响**开启阴影/受光的单位层  
- 地面可加统一 `albedo_scale` 微调（已有）

**P1 — 曲线昼夜（推荐主路径）**

- `DayNightController`：`time_of_day ∈ [0,1)`（对标 WC3 游戏时间）  
- 用 Gradient / Curve 资源（按 tileset 或通用）驱动：  
  - `ambient` 色与强度  
  - `DirectionalLight` 方向（绕 Y 转）与颜色（黎明橙 / 正午白 / 黄昏红 / 夜晚蓝）  
  - 可选：全局地表 tint（shader uniform）模拟「天光变暗」  
- Melee Bootstrap「对战昼夜设置」只写 `DayNightController` 开关与初始时刻  

**P2 — 忠实 DNC 模型（可选增强）**

- 实例 Terrain/Unit DNC GLB，播放其动画时间轴  
- 若转换后灯光节点可用：绑定到 Godot Light；否则仍用动画采样的颜色写回 P1 曲线  

P2 工作量大、收益主要在「和 WE 预览像素级接近」，对战可玩性优先用 P1。

---

## 6. 雾（Fog）

### 6.1 数据（w3i → info.json）

```json
"fog": {
  "style": 0,
  "startZ": 3000,
  "endZ": 5000,
  "density": 0.5,
  "color": [0, 0, 0, 255]
}
```

- `style == 0`：关  
- Z 为 WC3 高度单位 → `* WORLD_SCALE` 进 Godot  
- 经典实现偏**高度雾 / 距离雾**，不是 Godot `FogVolume`

### 6.2 Godot 方案

| 方案 | 适用 |
|------|------|
| `Environment.fog_*` + `fog_height_*`（Godot 4） | **首选**：对齐 startZ/endZ/density/color |
| 自定义全屏/地表 shader | 需与 unshaded 管线精细对齐时 |

注意：地面 shader 写了 `fog_disabled`——若用 Environment 雾，**天空与单位**会吃雾，地面可能不吃。两种策略：

1. **接受**：雾主要罩远景天空/单位（近看地表仍清晰）——接近部分 WE 观感  
2. **统一**：去掉 ground/cliff 的 `fog_disabled`，或在 fragment 里手写高度雾（与 Environment 二选一，避免叠两层）

推荐实现顺序：先 Environment 高度雾 + 天空；再视验收决定是否给地面开雾。

天气 `useFog=1`（如 RAlr）：在已有雾上提高 `density` 或加一层淡灰 ambient。

---

## 7. 阴影（Shadows）

分清三种「影子」，不要混成一种技术。

### 7.1 地形烘焙阴影 — `war3map.shd`（核心）

格式摘要：

- 无头：长度 = `16 * map_width * map_height`（每地形格 4×4 字节）  
- 字节：`0x00` 无影，`0xFF` 有影  
- 来源：WE「计算阴影」；Echo Isles 的 w3x 内含 `war3map.shd`（解析管线需导出到 `map-parsed/.../shadow.json` 或 `.bin`）

**Godot 方案（与 unshaded 兼容）：**

```text
1. 解析 SHD → Image(R8) 或 Texture2D，尺寸 (width*4, height*4)
2. 传入 wc3_ground（及可选 cliff）uniform：shadow_map + origin/cell_size
3. fragment：albedo *= mix(1.0, shadow_tint, sample)
```

这与现有 `pathing_map_tex` 调试叠色同一套路（见 `wc3_debug_grid.gdshaderinc`）。

编辑器 View→Shadows：开关该 uniform。

### 7.2 实时灯光阴影（单位）

- `DirectionalLight3D.shadow_enabled = true`  
- 仅对**单位 Mesh** `cast_shadow = ON`；地形 `OFF`（已是）  
- Mobile 渲染器注意级联阴影性能；RTS 俯视可缩小范围、降分辨率  

### 7.3 Blob 阴影（可选）

- 单位脚下透明圆片 / Decal——WC3 单位常见廉价影  
- 与 SHD、实时影可并存；近景单位用 blob 往往更稳  

**不要**指望「只开 DirectionalLight 阴影」复刻悬崖投射到地面的经典暗斑——那主要是 **SHD**。

---

## 8. 模块与文件规划

```text
scripts/map/
├── data/wc3_shadow_map.gd          # SHD 解析 / from_dict
├── catalog/…                       # tileset → sky/dnc 路径表（可进 DefStore）
└── presentation/layers/
    └── map_environment_layer.gd    # setup(info, tileset_id, map_dir)

assets/map-parsed/<map>/
├── info.json                       # 已有 fog / weather / light
└── shadow.bin 或 shadow.json       # 待解析管线导出

game/scripts/…（可选）
└── day_night_controller.gd         # 若希望游戏侧控制昼夜进度
```

解析管线（`tools`）：从 w3x 抽出 `war3map.shd` → 写入 map-parsed（与 heightfield 同级）。

---

## 9. 分阶段验收

| 阶段 | 内容 | 验收 |
|------|------|------|
| **E0** | Sky GLB 跟随相机 + tileset 预设 ambient | Echo Isles 有夏日天空穹顶 |
| **E1** | 全局天气 `RAlr` 粒子 | 雨帘跟随镜头；可开关 |
| **E2** | Environment 高度雾读 info | style≠0 的图可见雾；Echo（style=0）默认无雾 |
| **E3** | SHD → 地面乘暗 | 悬崖/建筑投影暗斑与 WE 大致同位 |
| **E4** | DayNight 曲线 + Melee 昼夜开关 | 时间滑动时天光/方向光变化；地面可乘 tint |
| **E5** | 单位弱实时影或 blob | 选中单位脚下有影，不拖垮帧率 |
| **E6** | DNC 模型忠实采样（可选） | 与 WE 预览对比通过 |

建议插入 ROADMAP：**阶段 A 完成后穿插 E0–E1**（观感收益大、不挡 Melee）；E3 与 pathing overlay 类似，属 Present 增强；E4 对接 Melee「对战昼夜」。

---

## 10. 风险与非目标

| 风险 | 缓解 |
|------|------|
| 开 lit 毁地表风格 | 坚持 unshaded + SHD/tint |
| 粒子数 800+ 移动端卡 | 按距离缩放 amount；Mobile 降级 |
| Sky GLB 材质透明乱序 | 与酒馆同套路：scissor / 排序 |
| SHD 未进 map-parsed | 先做解析导出，再接 shader |
| DNC 转换丢 Light | 以曲线昼夜为主，DNC 为增强 |

**本方案不做：**

- Reforged 级体积云 / GI  
- 把天气做成全屏后期雨滴（可后期加一层 UI）  
- 编辑器内重算 SHD（可调用外部工具或远期移植）

---

## 11. 关键锚点（现有代码 / 资产）

| 项 | 路径 |
|----|------|
| 地图环境字段 | `assets/map-parsed/echoisles/info.json` |
| 天气定义 | `scripts/definitions/terrain_art/weather_effect_def.gd` · `assets/slk-exported/TerrainArt/Weather.json` |
| Sky GLB | `assets/asset-converted/Environment/Sky/**` |
| DNC GLB | `assets/asset-converted/Environment/DNC/**` |
| 地表 unshaded / fog_disabled | `docs/shader/README.md` · `assets/shaders/wc3_*.gdshader` |
| 编辑器菜单占位 | `editor/ui/menu_bar.gd`（view_sky / weather / fog / shadows） |
| HiveWE DNC 字段 | `HiveWE/src/base/tilesets.ixx`（`terrain_dnc` / `unit_dnc`） |
| SHD 格式 | Hive 文档：`16*w*h` 字节，每格 4×4 |

---

## 12. 一句话总结

> **天空用 Sky GLB 跟随相机；天气用 Weather.slk 驱动粒子；光照用 Ambient + 可选方向光曲线（地表保持 unshaded）；阴影以 war3map.shd 乘地表为主，单位另加廉价影。**  

这样既复刻 Melee 观感，又不推翻现有地形管线。
