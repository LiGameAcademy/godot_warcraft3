# 小地图模块设计方案 / Minimap Module Design

> 最后更新：2026-08-01
> 状态：**Phase 1 + Phase 2 完成**；下一阶段见 **[minimap_phase3_design.md](PHASE3.md)**（讨论稿）

已完成：

- `scripts/map/minimap/map_minimap_utils.gd` — 坐标转换 + 颜色映射 + 视口梯形
- `scripts/map/minimap/map_minimap_raster.gd` — Heightfield → Image（当前为高度伪彩 fallback）
- `editor/ui/editor_inspect_window.gd` — 重构为使用 MapMinimapRaster；优先加载 `war3mapMap.png`
- `editor/scripts/editor.gd` — 迁移方法委托给 MapMinimapUtils

---

## 1. 背景与目标

### 1.1 现状

- **编辑器小地图**：已有初步实现于 `editor/ui/editor_inspect_window.gd`，仅限编辑器内使用
- **游戏内小地图**：尚未实现
- **问题**：现有实现紧耦合于编辑器 UI，无法在游戏运行时复用

### 1.2 目标

设计一个小地图模块，同时适用于：
- **地图编辑器**：嵌入编辑器 UI，作为地形编辑的导航辅助
- **游戏运行时**：显示在游戏 UI 上，跟随相机/单位移动

### 1.3 设计原则

1. **数据与表现分离** — 小地图数据层（Image/Texture）独立于渲染载体
2. **遵循现有架构** — 复用项目已有的 Layer 模式、Heightfield 数据结构、坐标转换工具
3. **可插拔** — 通过 Composition 挂载到 MapRoot 或编辑器窗口，不侵入原有逻辑
4. **性能优先** — 编辑器内增量更新，游戏内可选实时渲染模式

---

## 2. 核心概念

### 2.1 小地图数据源

小地图底层是一张 **rasterized Image**，来源于 `Wc3Heightfield`：

| 数据维度 | 值域 | 用途 |
|---|---|---|
| 地面高度 (layer_height) | 0–14 整数 | 决定像素灰度/颜色 |
| 水面标记 (FLAG_WATER) | bool | 蓝色叠加 |
| 斜坡标记 (FLAG_RAMP) | bool | 棕色叠加 |
| 地面纹理类型 | 0–N | 可选：按地表材质着色 |

### 2.2 两种渲染模式

| 模式 | 描述 | 适用场景 |
|---|---|---|
| **Static** | 基于 Heightfield 生成静态 Image，每次数值变化时重新 rasterize | 编辑器地形编辑过程中 |
| **Viewport** | 挂载到子 Viewport，用 3D 相机渲染简化场景 | 游戏运行时，跟随主相机 |

### 2.3 坐标系统

```
World (WC3 TileCoords)  ←→  Minimap UV [0,1]²
```

- `world_to_minimap_uv(wx, wy)` → `Vector2` (0~1)
- `minimap_uv_to_world(u, v)` → `Vector2` 世界坐标

该工具函数统一放置于 `MapMinimapUtils`，同时服务于两种模式。

---

## 3. 系统架构

### 3.1 文件结构

```
scripts/
└── map/
    └── minimap/
        ├── map_minimap_utils.gd      # 坐标转换 + 颜色映射（纯函数）
        ├── map_minimap_raster.gd     # Heightfield → Image rasterizer
        ├── map_minimap_layer.gd      # Node3D 载体（Static 模式）
        └── map_minimap_viewport.gd   # 子 Viewport 渲染（Runtime 模式）

editor/ui/
└── minimap/
    └── editor_minimap_panel.gd       # 编辑器内小地图 Panel（使用 Static 模式）
```

**注意**：目录结构还未创建，按此设计执行时会新建。

### 3.2 类图

```
Wc3Heightfield (数据源)
       │
       ▼
MapMinimapRaster
  - rasterize() → Image
  - update_dirty_region(rect) → 增量更新

MapMinimapUtils
  + world_to_minimap_uv(v: Vector2) → Vector2
  + minimap_uv_to_world(u: float, v: float) → Vector2
  + height_to_grayscale(layer_h: int) → Color
  + blend_terrain_color(img: Image, x, y, color)

MapMinimapLayer (Node3D)
  - raster: MapMinimapRaster
  - texture_rect: TextureRect
  - camera: Camera3D
  - viewport: Viewport
  + update()                    # 手动刷新（编辑器用）
  + set_camera(c: Camera3D)     # 绑定相机（运行时用）

MapMinimapViewport (Node3D)
  - viewport: SubViewport
  - camera: Camera3D
  - follow_mode: Enum
  + follow_target(node: Node3D)
```

### 3.3 数据流

```
编辑场景:
Wc3Heightfield ──→ MapMinimapRaster ──→ Image ──→ ImageTexture ──→ TextureRect (编辑器 Panel)

游戏场景 A (Static):
Wc3Heightfield ──→ MapMinimapRaster ──→ Image ──→ ImageTexture ──→ TextureRect (游戏 HUD)

游戏场景 B (Viewport):
SubViewport (简化3D渲染) ──→ ViewportTexture ──→ TextureRect (游戏 HUD)
                    ↑
              Camera3D (跟随玩家单位)
```

---

## 4. 核心模块详细设计

### 4.1 MapMinimapUtils

纯函数工具集，不持有状态：

```gdscript
class_name MapMinimapUtils
extends RefCounted

## WC3 世界坐标 → 小地图 UV [0,1]
static func world_to_minimap_uv(world_pos: Vector2, hf: Wc3Heightfield) -> Vector2:
    var tx := (world_pos.x - hf.center_offset.x) / (hf.width * hf.tile_size)
    var ty := (world_pos.y - hf.center_offset.y) / (hf.height * hf.tile_size)
    return Vector2(tx, ty)

## 小地图 UV → WC3 世界坐标
static func minimap_uv_to_world(u: float, v: float, hf: Wc3Heightfield) -> Vector2:
    var wx := hf.center_offset.x + u * hf.width * hf.tile_size
    var wy := hf.center_offset.y + v * hf.height * hf.tile_size
    return Vector2(wx, wy)

## 高度值 → 灰度/颜色（可扩展为材质色）
static func layer_height_to_color(layer_h: int, is_water: bool, is_ramp: bool) -> Color:
    if is_water:
        return COLOR_WATER.lerp(COLOR_DEEP_WATER, clampf(layer_h / 14.0, 0.0, 1.0))
    if is_ramp:
        return COLOR_RAMP
    # 高度渐变：深棕 → 浅棕 → 浅绿
    var t := clampf(layer_h / 14.0, 0.0, 1.0)
    return COLOR_LOW.lerp(COLOR_HIGH, t)

## 小地图点击坐标 → 世界坐标（供相机跳转用）
static func minimap_click_to_world(click_uv: Vector2, hf: Wc3Heightfield) -> Vector2:
    return minimap_uv_to_world(click_uv.x, click_uv.y, hf)
```

### 4.2 MapMinimapRaster

负责将 Heightfield 光栅化为 Image：

```gdscript
class_name MapMinimapRaster
extends RefCounted

var _hf: Wc3Heightfield
var _img: Image
var _dirty_rects: Array[Rect2i] = []  # 增量更新用

func _init(hf: Wc3Heightfield, width: int, height: int):
    _hf = hf
    _img = Image.create(width, height, false, Image.FORMAT_RGBA8)

## 全量光栅化
func rasterize() -> Image:
    for y in range(_hf.height):
        for x in range(_hf.width):
            _raster_pixel(x, y)
    return _img

## 增量光栅化（仅重绘 dirty region）
func rasterize_dirty() -> Image:
    for rect in _dirty_rects:
        for py in range(rect.position.y, rect.position.y + rect.size.y):
            for px in range(rect.position.x, rect.position.x + rect.size.x):
                _raster_pixel(px, py)
    _dirty_rects.clear()
    return _img

## 标记某区域需要更新
func mark_dirty(rect: Rect2i):
    _dirty_rects.push_back(rect)

func _raster_pixel(wx: int, wy: int):
    var layer_h := _hf.get_layer_height(wx, wy)
    var is_water := _hf.get_flag(wx, wy, Wc3Heightfield.FLAG_WATER)
    var is_ramp := _hf.get_flag(wx, wy, Wc3Heightfield.FLAG_RAMP)
    var color := MapMinimapUtils.layer_height_to_color(layer_h, is_water, is_ramp)
    # Map minimap pixel (wx, wy) to image pixel
    var ix := int(float(wx) / _hf.width * _img.get_width())
    var iy := int(float(wy) / _hf.height * _img.get_height())
    _img.set_pixel(ix, iy, color)
```

### 4.3 MapMinimapLayer（Static 模式载体）

挂载到 MapRoot，与其他 Layer 同级：

```gdscript
class_name MapMinimapLayer
extends Node3D

signal clicked(uv: Vector2)  # 小地图被点击时发出

var raster: MapMinimapRaster
var texture_rect: TextureRect
var _camera: Camera3D
var _img_texture: ImageTexture

func _init():
    texture_rect = TextureRect.new()
    texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    add_child(texture_rect)

## 初始化（外部调用）
func setup(hf: Wc3Heightfield, width: int = 512, height: int = 512):
    raster = MapMinimapRaster.new(hf, width, height)
    var img := raster.rasterize()
    _img_texture = ImageTexture.create_from_image(img)
    texture_rect.texture = _img_texture

## 地形变更后调用（连接 Heightfield.changed 信号）
func on_heightfield_changed(dirty_rect: Rect2i):
    raster.mark_dirty(dirty_rect)
    var img := raster.rasterize_dirty()
    _img_texture.update(img)

## 绑定相机用于计算视口矩形
func set_camera(cam: Camera3D):
    _camera = cam
    _camera.moved.connect(_on_camera_moved)

func _on_camera_moved():
    if _camera == null:
        return
    # 计算相机视口在小地图上的 UV 矩形，覆盖到 texture_rect 上（可选 UI 叠加）

## 获取当前视口 UV 矩形
func get_viewport_uv_rect() -> Rect2:
    # 复用 editor_inspect_window.gd 中的逻辑，迁移到此处
    ...
```

### 4.4 MapMinimapViewport（运行时模式）

通过子 Viewport 渲染简化 3D 场景：

```gdscript
class_name MapMinimapViewport
extends Node3D

enum FollowMode { NONE, CAMERA, UNIT }

var viewport: SubViewport
var camera: Camera3D
var follow_mode := FollowMode.CAMERA
var _follow_target: Node3D

func _init():
    viewport = SubViewport.new()
    viewport.size = Vector2i(512, 512)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)

    camera = Camera3D.new()
    camera.fov = 90.0
    viewport.add_child(camera)

## 绑定要跟随的目标节点
func follow_target(node: Node3D, mode: FollowMode = FollowMode.CAMERA):
    _follow_target = node
    follow_mode = mode

func _process(delta):
    if _follow_target == null:
        return
    match follow_mode:
        FollowMode.CAMERA:
            # 同步主相机 transform 到 minimap 相机
            pass
        FollowMode.UNIT:
            camera.position = _follow_target.position + Vector3(0, 50, 0)
            camera.look_at(_follow_target.position)
```

### 4.5 EditorMinimapPanel（编辑器集成）

编辑器内的小地图 Panel，挂在编辑器窗口上：

```gdscript
class_name EditorMinimapPanel
extends Panel

signal viewport_clicked(world_pos: Vector2)

var _raster: MapMinimapRaster
var _texture: ImageTexture
var _doc: MapDocument

func setup(doc: MapDocument):
    _doc = doc
    var hf := doc.heightfield
    _raster = MapMinimapRaster.new(hf, 512, 512)
    var img := _raster.rasterize()
    _texture = ImageTexture.create_from_image(img)
    var tex_rect := TextureRect.new()
    tex_rect.texture = _texture
    tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(tex_rect)

    # 连接高度场变更信号
    hf.changed.connect(_on_hf_changed)

    # 连接主编辑器相机移动信号
    var editor := _find_editor()
    if editor and editor.camera:
        editor.camera.moved.connect(_update_viewport_rect)

func _on_hf_changed(dirty_rect: Rect2i):
    _raster.mark_dirty(dirty_rect)
    var img := _raster.rasterize_dirty()
    _texture.update(img)

func _update_viewport_rect():
    # 绘制当前视口矩形覆盖
    ...

func _on_gui_input(event: InputEvent):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var uv := get_local_mouse_position() / size
        var world_pos := MapMinimapUtils.minimap_uv_to_world(uv.x, uv.y, _doc.heightfield)
        viewport_clicked.emit(world_pos)
```

---

## 5. 集成点

### 5.1 MapRoot（游戏场景）

```gdscript
# scenes/map/map_root.tscn 或 map_loader.gd 中

# 方案 A：Static 模式（推荐，性能好）
var minimap_layer: MapMinimapLayer

func _ready():
    minimap_layer = MapMinimapLayer.new()
    minimap_layer.setup(heightfield, 512, 512)
    minimap_layer.set_camera(main_camera)
    add_child(minimap_layer)

# 方案 B：Viewport 模式（需要实时渲染时）
var minimap_viewport: MapMinimapViewport
```

### 5.2 MapLoader（地形重建时刷新）

```gdscript
# scripts/map/presentation/map_loader.gd

# 当地形重建完成后刷新小地图
func _on_rebuild_complete():
    if minimap_layer:
        minimap_layer.on_heightfield_changed(Rect2i(0, 0, hf.width, hf.height))
```

### 5.3 Editor（编辑器集成）

```gdscript
# editor/scripts/editor.gd 或 map_document.gd

# MapDocument 变更时通知小地图
func _on_doc_changed():
    minimap_panel._on_hf_changed(last_dirty_rect)
```

---

## 6. 配置参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `minimap_width` | 512 | 小地图纹理宽度（pixels） |
| `minimap_height` | 512 | 小地图纹理高度（pixels） |
| `update_mode` | `ON_HEIGHTFIELD_CHANGE` | 刷新策略：即时 / 定时 / 手动 |
| `water_depth_enabled` | `true` | 是否按水深着色 |
| `ramp_color_enabled` | `true` | 是否标记斜坡 |

---

## 7. 设计决策（已确认）

1. **小地图比例**：
   - **推荐方案**：按地图实际宽高比，较小边固定为预设像素数（如 256px），较大边按比例拉伸
   - 示例：1024×512 地图 → 最小边 256 → 小地图 512×256
   - 编辑器内可拖拽缩放，游戏内按 HUD 布局自适应

2. **地面纹理着色**：
   - 需要区分大致颜色（草地、荒地、雪地等）
   - 映射表：`ground_texture_id → Color`，在 `MapMinimapUtils` 中以 `static func` 或配置 `Dictionary` 实现
   - 颜色权重：地面纹理 60% + 高度渐变 40%，水/斜坡覆盖之

3. **增量更新边界**：按 `Rect2i` 单位，暂不做调整，以实际效果为准

4. **Draw Distance**：
   - 编辑器：较大（方便看全局），通过 `camera.far = 10000+` 控制
   - 游戏运行时：较小以保证性能，通过 `minimap_camera.far = map_diag * 0.3` 控制
   - 配置接口暴露到 `MapMinimapViewport` 的 `draw_distance_scale: float` 参数

5. **UI 控件抽象**：
   - 核心渲染组件（`MapMinimapLayer` / `MapMinimapViewport`）只负责输出 `Texture`
   - 最小 UI 控件：`MapMinimapControl`（继承 `Control`），只含 `TextureRect` + 视口矩形覆盖 + 点击信号
   - 组合模式：`MapMinimapControl` + `EditorMinimapPanel`（编辑器）/ `GameMinimapHud`（游戏）
   - 先实现编辑器小地图，游戏内按需调整，不提前过度设计

---

## 8. 实现顺序（推荐）

### Phase 1：基础设施
1. 新建 `scripts/map/minimap/` 目录
2. 实现 `MapMinimapUtils`（坐标转换 + 颜色映射）
3. 实现 `MapMinimapRaster`（全量光栅化）
4. 用 GUT 单元测试验证 raster 输出

### Phase 2：Static 模式（编辑器）
5. 实现 `MapMinimapLayer`
6. 在 `editor/ui/` 下新建 `minimap/` 目录
7. 实现 `EditorMinimapPanel`
8. 集成到编辑器主窗口，验证点击跳转相机

### Phase 3：Static 模式（游戏 HUD）
9. 将 `MapMinimapLayer` 集成到 MapRoot
10. 处理 `MapLoader.rebuild_terrain_only()` 时的增量更新
11. 在游戏主场景中验证显示

### Phase 4：Viewport 模式（游戏运行时，可选）

1. 实现 `MapMinimapViewport`
2. 添加 follow target 逻辑
3. 性能调优：draw distance、分辨率
4. 游戏 HUD 集成（**按需实现，不提前过度设计**）

---

## 9. 参考文件

- `editor/ui/editor_inspect_window.gd` — 现有小地图实现（参考坐标转换逻辑）
- `scripts/map/data/wc3_heightfield.gd` — 高度场数据结构
- `scripts/map/data/wc3_coords.gd` — 坐标转换参考
- `scripts/map/presentation/map_build_context.gd` — Layer 构建上下文
- `scripts/map/presentation/layers/map_debug_grid_layer.gd` — Layer 模式参考
