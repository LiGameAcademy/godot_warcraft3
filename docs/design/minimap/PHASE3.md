# 小地图 Phase 3 设计：纹理采样光栅 + 存盘 + 视口框

> 日期：2026-08-01  
> 状态：**已实现**（自测 `tests/unit/selftest_minimap_raster.gd` 绿）；等效 FOV / Nearest 待手测微调  
> 前置：Phase 1–2 已完成（`MapMinimapUtils` / `MapMinimapRaster` / `EditorInspectWindow`）  
> 总纲：[minimap_design.md](MINIMAP.md) · 待办：[roadmap/TODO.md](../../roadmap/TODO.md)「小地图」  
> 对照：HiveWE `terrain.ixx` `minimap_image()` · `ground_texture.ixx` `minimap_color`

---

## 0. 已拍板结论

| # | 议题 | 决定 |
|---|------|------|
| A | 底图像素色 | 地表贴图最低 mip / 块平均色（HiveWE） |
| B | 工作分辨率 | **实时 1 像素 / tilepoint**；UI 再缩放 |
| C | 存盘 | resize → **256×256** `war3mapMap.png`；默认 **Nearest**（见 §0.1） |
| D | 模式 | 默认 LIVE 光栅；可选 GAME_PREVIEW 读磁盘 PNG |
| E | 视口黄框 | **等效 FOV**（初值 **50°**，可导出调参）；保留 footprint 作细调 |
| F | 装饰物 | 不进底图；图标走 MMP |
| G | 不可玩区 | **沿用**现有 `darkened(0.55)` |
| H | `corner_texture` | 抽到 Logic（或共享纯函数），Present / Raster 共用 |
| I | 水色 v1 | **简化**：`FLAG_WATER` → 固定浅蓝叠；完整 `waterH>groundH` 深浅进 TODO 备忘 |
| J | 刷新时机 | 见 §3.8（与地形 Mesh rebuild 同节流；松手强制全量） |

### 0.1 存盘插值：Nearest vs Bilinear

把 tilepoint 图（如 161×161）拉到 256×256 时：

| | **Nearest（邻近）** | **Bilinear（双线性）** |
|--|---------------------|------------------------|
| 做法 | 每个目标像素取最近源像素，不混合 | 按周围 4 像素加权混合 |
| 观感 | 色块硬、格子感强，像像素图放大 | 边缘发糊、过渡软，像照片缩放 |
| 适合 | **小地图 / WE 风**（每格本就是纯色） | 照片、渐变 UI |
| 风险 | 放大比例非整数时可能略锯齿 | 崖灰/水面边界被「抹灰」，不如 HiveWE/WE 利落 |

**默认 Nearest**：底图像素本就是离散地表格色，模糊没有信息增益。若肉眼觉得锯齿刺眼再改 Bilinear 做 A/B。

---

## 1. 现状与缺口

### 1.1 已有能力

- UI：`editor/ui/editor_inspect_window.tscn` — `MinimapTex` + `MinimapOverlay` + 三勾选
- 加载：优先 `war3mapMap.png` / `.tga`；否则 `MapMinimapRaster` **高度伪彩** fallback
- 叠加：MMP 图标、相机视口四角梯形（可出图外灰边）
- 工具：`MapMinimapUtils.compute_camera_minimap_uv_quad(..., footprint_scale=0.52)`

### 1.2 缺口（本阶段）

1. **自定义图 / 编辑中**没有「像 WE 一样」的地表色底图  
2. **存盘**不写 `war3mapMap.png`（`MapDocument.save_json` 只写 heightfield + doodads）  
3. **黄框**目测偏大，算法需校准或收紧

### 1.3 官方资源事实（Lost Temple）

| 项 | 值 |
|----|-----|
| tilepoint | 161×161 |
| map tiles | 160×160 |
| `war3mapMap.png` | **256×256** RGBA |
| `minimap.json` | `canvasSize: 256`，图标坐标在此画布上 |

→ 游戏/选图用的小地图是 **固定 256 画布**；HiveWE 编辑器实时图是 **tilepoint 尺寸**，两套分辨率。

---

## 2. HiveWE 算法（权威参考）

### 2.1 每类地表一个 `minimap_color`

`ground_texture.ixx`：

1. 把地表 atlas 切成 `tile_size×tile_size` 的 Texture2DArray  
2. `glGenerateTextureMipmap`  
3. 读 **最低 mip（1×1）** → `minimap_color`（×255 存成 0–255）

等价于：对该 tile 变体 0 做「整块平均色」。Godot 侧不必走 GPU mip：对第一块 tile 像素做 `get_average_color()` / 手写平均即可。

### 2.2 `Terrain::minimap_image()`（逐 tilepoint）

对每个 `(i, j)`：

```
若 本角或 左/下/左下 任一为 cliff → 灰 (128,128,128,255)
否则 → ground_textures[real_tile_texture(i,j)]->minimap_color

若 corner_water 且 waterH > groundH：
  深 (Δh > 0.5)：color = color * 0.5625 + (0,0,80,112)
  浅：            color = color * 0.75   + (0,0,48,64)

写入图像时 Y 翻转：(height-1-j)
```

- 尺寸：`width × height`（tilepoint，含边界点）  
- **不含** doodad / unit（图标另层）  
- `real_tile_texture`：邻近 romp/cliff → `cliff_to_ground`；blight → blight 槽；否则 `ground_textures[i]`  
  （本仓库已有等价：`MapTerrainLayer.corner_texture` + `Wc3CliffLogic.is_cliff_tile`）

### 2.3 HiveWE 浮动小地图 **不画** 视口黄框

黄框是我们为对齐 **World Editor** 加的；HiveWE 的 `Minimap` 只显示纹理 + 点击跳转。校准应对 WE，不能从 HiveWE 抄视口算法。

---

## 3. 本仓库落地设计

### 3.1 分层归属

| 层 | 职责 | 建议 API |
|----|------|----------|
| **Catalog** | tileset 索引 → `minimap_color` | `Wc3GroundTileCatalog.build_minimap_colors(ground_tilesets, tiles) → PackedColorArray` |
| **Logic / Raster（纯数据）** | Heightfield + colors → `Image` | 扩展 `MapMinimapRaster`（或新建 `MapMinimapTerrainRaster`，二选一见下） |
| **Editor** | 刷新时机、双模式切换、存盘挂钩 | `EditorInspectWindow` + `MapDocument.save_*` + 笔刷 dirty |

禁止：在 UI 脚本里 `load` PNG 算平均色；颜色表走 Catalog。

### 3.2 Catalog：`build_minimap_colors`

```text
for each ground_tilesets[i]:
  img = RuntimeAssets.load_image(png)
  # atlas：tile_size = height/4；取左上角变体 0（与 HiveWE layer 0 一致）
  sample = blit/crop (0,0)-(tile_size,tile_size)
  colors[i] = average_rgba(sample)   # 或 generate_mipmaps 后 get_pixel(0,0)
```

缓存：按 `(main_tileset, groundTilesets fingerprint)` 缓存在 Catalog 或 Raster 实例上，换图才重建。

### 3.3 Raster：对齐 HiveWE 着色

伪代码（tilepoint 循环）：

```gdscript
func rasterize_terrain(hf, colors, cliff_to_ground, romp_mask) -> Image:
    img = Image.create(hf.width, hf.height, false, FORMAT_RGBA8)
    for j in hf.height:
        for i in hf.width:
            if _is_cliff_corner_neighborhood(hf, i, j):
                col = Color8(128, 128, 128)
            else:
                tex_i = real_tile_texture(...)  # 复用 corner_texture 规则
                col = colors[tex_i]
            if water_visible(hf, i, j):
                dh = final_water_h - final_ground_h
                if dh > 0.5: col = col * 0.5625 + Color(0, 0, 80/255.0, 112/255.0) # 注意预乘语义
                else:        col = col * 0.75   + Color(0, 0, 48/255.0, 64/255.0)
            if unplayable: col = col.darkened(0.55)  # 保留现有 WE 观感增强（HiveWE 无此步，可开关）
            img.set_pixel(i, hf.height - 1 - j, col)
    return img
```

**水位高度**：用现有 `heights` / `layer_heights` / `water_heights` 对齐 HiveWE：

- `final_ground ≈ height + layer - 2`（WC3 单位，与 `Wc3Heightfield` / 文档一致）  
- `final_water ≈ water_height + water_offset`（offset 从 `Wc3WaterParams` 取，缺省按 HiveWE 默认）

**崖邻域**：HiveWE 查 `corner_cliff`；我们用 `Wc3CliffLogic.is_cliff_tile` 对 `(i-1,j)` / `(i,j-1)` / `(i-1,j-1)` / 以角为 BL 的格做邻域 OR（与 `is_cliff_tile_corner` 对齐）。

### 3.4 分辨率策略（议题 B / C）

```text
编辑实时 Image  ──1:1 tilepoint──►  UI TextureRect（KEEP_ASPECT）
        │
        │ save / export
        ▼
   resize → 256×256 PNG  ──►  map_dir/war3mapMap.png
        │
        └── 与 minimap.json canvasSize=256、MMP 图标 UV 一致
```

- **实时**：1:1 便于脏区更新、颜色与格子一一对应。  
- **存盘**：一律输出 256×256（非方图则 **contain + 居中 pad** 或 **stretch**——建议 **stretch**，与多数官方图一致；Lost Temple 本就方图）。  
- 加载官方图时：继续直接显示 256×256；切换「编辑实时」才用 1:1 光栅。

若拍板「工作图也固定 256」：实现更简单，但脏区映射要多一次 tile→pixel 换算；大地图会糊。

### 3.5 文件与类改动（建议最小集）

```text
scripts/map/catalog/wc3_ground_tile_catalog.gd
  + build_minimap_colors(...)

scripts/map/minimap/map_minimap_raster.gd
  + setup_terrain_colors / rasterize 改走 HiveWE 路径
  + 保留旧高度伪彩为 debug 开关（optional）

scripts/map/minimap/map_minimap_utils.gd
  + footprint 默认值 / 等效 FOV 参数（§4）

editor/ui/editor_inspect_window.gd
  + 模式：GAME_PREVIEW | LIVE_EDIT
  + refresh 接 Catalog colors
  + 可选：暴露 footprint_scale 调试

editor/scripts/map_document.gd
  + save 时 bake_war3map_map() → war3mapMap.png

editor/scripts/editor.gd / terrain_brush
  + 笔刷结束后 mark_dirty + 节流刷新（如 100–200ms）
```

**不新建** `EditorMinimapPanel`（现有 Inspect 窗已承担）；游戏 HUD 仍后置。

### 3.6 存盘挂钩

在 `MapDocument.save_json`（及将来「导出地图」）成功路径：

1. 若有 `MapMinimapRaster` 最新 Image → 用它  
2. 否则现场 `rasterize_terrain` 一次  
3. `img.resize(256, 256, INTERPOLATE_BILINEAR)`（或 Nearest，观感可 A/B）  
4. `img.save_png(map_dir.path_join("war3mapMap.png"))`  
5. **暂不**回写 `.w3x` / BLP（后置）

菜单已有 `file_export_minimap` 入口：可绑定「仅导出 PNG、不改地形 JSON」。

### 3.7 刷新策略（概要）

| 触发 | 行为 |
|------|------|
| 打开地图 | LIVE：全量光栅；GAME_PREVIEW：磁盘 PNG |
| 地形笔刷 / undo-redo | 见 §3.8 |
| 换 tileset | 重建 `minimap_colors` + 全量 |
| 保存 / export | bake 256 PNG（Nearest） |

增量：第一版 **脏区标记后仍全量重绘**（161²～256² 足够快）；真 rect blit 后置。

### 3.8 实时更新时机（已拍板倾向）

与现有 `TerrainBrush` Mesh rebuild 对齐，**不要每帧、也不要每个格子立刻光栅**：

```text
笔刷按下/拖动中
  └─ 与 Mesh 同节流（现 REBUILD_INTERVAL_MS）→ 标记 dirty → 全量/脏区光栅 → 更新 Texture
笔刷松开 / 命令入栈完成
  └─ 强制刷新一次（与 _request_rebuild(true) 同拍）
Undo / Redo（should_rebuild）
  └─ 历史 rebuild 结束后刷新
打开地图 / 换 tileset
  └─ 全量
装饰物笔刷
  └─ 不刷新底图（图标层另议；v1 可不碰）
仅相机移动
  └─ 只重绘 Overlay 黄框，不重跑 Raster
```

理由：小地图是导航示意，拖动中 10～15 Hz 级跟上 Mesh 即可；跟 Mesh 同信号可少一套节流状态。若拖动中仍卡，再把小地图节流拆成更长间隔（例如 200–300ms），松手仍强制一帧。

HiveWE：`terrain_brush` / undo 末尾 `update_minimap()`——偏「操作段落结束」；我们加拖动中节流，编辑手感更好。

---

## 4. 视口黄框（议题 E）

### 4.1 当前算法

`MapMinimapUtils.compute_camera_minimap_uv_quad`：

1. 取主视口四角屏幕点 → 射线打到 **观察点高度地面平面**  
2. 世界坐标 → 小地图 UV（可出 0..1）  
3. 朝观察点 UV 按 `footprint_scale`（默认 **0.52**）收缩

### 4.2 为什么偏大

1. Godot `Camera3D` 默认 **FOV ≈ 75°**，WE 编辑/游戏视野更窄 → 投影 footprint 天然偏大  
2. `0.52` 仍可能大于 WE 黄框「示意可见区」的习惯尺寸  
3. 用 **整窗可见矩形**（含非 3D 区域）会略放大；若有 UI 占边，应用 3D 视口 `get_visible_rect()`（已尽量如此）  
4. 俯仰接近水平时，远角射线打平面会极远 → 偶发巨大梯形（已有 `t < 0.05` 与 fallback 矩形）

HiveWE **无此框**；应对 WE 手感，不是抄 HiveWE。

### 4.3 建议改法（可组合）

**已选 E2：等效 FOV（初值 50°）**

```text
effective_fov = min(cam.fov, 50°)   # @export / 常量，手测后再改
```

实现：仅用于四角射线方向；真实编辑相机 FOV 不动。可保留 `footprint_scale` 作二次细调（初值可先回到 `1.0` 或略小于 1，避免双重收缩过度）。

参数暴露：`MapMinimapUtils` 常量 + Editor `@export` / Inspect 调试，便于对 WE 手调。

### 4.4 验收

同一观察距离下，黄框大致覆盖「屏幕中央能看清编辑的地形块」，外圈留边；旋转 yaw 时梯形朝向与 3D 一致；拉远/拉近大致线性缩放。

---

## 5. UI / 模式

| 模式 | 底图来源 | 用途 |
|------|----------|------|
| **LIVE_EDIT**（默认） | 纹理采样光栅 | 刷地形立刻反映 |
| **GAME_PREVIEW** | `war3mapMap.png` | 对齐 WE「察看游戏小地图」 |

勾选可放在现有 `MinimapChecks` 下新增一项；或复用菜单。图标三勾选逻辑保留。

---

## 6. 实现顺序

1. **Catalog** `build_minimap_colors` + 小自测  
2. **Logic**：抽出 `real_tile_texture` / `corner_texture` 纯函数供 Present + Raster  
3. **Raster** HiveWE 着色（崖灰；水色 v1 简化；Y 翻转；不可玩区压暗）  
4. **Inspect** 默认 LIVE；可选 GAME_PREVIEW；接 §3.8 刷新  
5. **Save / Export** 256 PNG + Nearest  
6. **视口** 等效 FOV=50°（可调）  
7. （后置）水色完整深浅；真增量 dirty rect；BLP/w3x  

不在本阶段：游戏 HUD、迷雾、单位点。

---

## 7. 开放问题（已关闭 / 残留）

| # | 状态 |
|---|------|
| 1 分辨率 | ✅ 实时 1:1、存盘 256 |
| 2 插值 | ✅ 默认 Nearest（可 A/B） |
| 3 压暗 | ✅ 沿用 |
| 4 视口 | ✅ 等效 FOV 初值 50° |
| 5 corner_texture 上提 | ✅ 可行，实现时做 |
| 6 水色简化 | ✅ v1 简化；完整版进 TODO |
| 刷新时机 | ✅ §3.8 |

残留：手测后调等效 FOV；存盘 Nearest 若不满再试 Bilinear。

---

## 8. 参考路径

| 资源 | 路径 |
|------|------|
| HiveWE 光栅 | `D:\GameMaker\HiveWE\src\base\terrain.ixx` ≈ L833–871 |
| HiveWE mip 色 | `D:\GameMaker\HiveWE\src\resources\ground_texture.ixx` ≈ L95–96 |
| HiveWE real_tile | 同 `terrain.ixx` ≈ L711–743 |
| 本仓 TODO | `docs/roadmap/TODO.md`「小地图」 |
| 水色摘录 | `docs/hivewe/WATER_DEEP_ANALYSIS.md` §7 |
| 现 UI | `editor/ui/editor_inspect_window.tscn` / `.gd` |
| 现光栅 | `scripts/map/minimap/map_minimap_raster.gd` |
| 官方样例 | `assets/map-parsed/losttemple/war3mapMap.png`（256²） |
