extends Window
## 经典世界编辑器「工具面板」浮窗。可多开；顶部下拉切换面板类型。
## 地形贴图：运行时按地图 tileset 动态加载。
## 悬崖/高度/尺寸/形状图标：场景内引用 WorldEditUI 静态贴图。


signal tile_selected(index: int)
signal brush_settings_changed(size: int, shape: int)
signal apply_texture_changed(enabled: bool)
signal cliff_settings_changed(apply: bool, tool_id: String, type_idx: int)
## 特殊「纹理」：无 / 荒芜 / 边界 / 去除边界
signal special_texture_changed(kind: int)
signal doodad_selected(type_id: String, info: Dictionary)
## 放置时随机：旋转 / 对称缩放 / Z(高度) / XY 面（可多选组合）
signal doodad_place_random_changed(
	random_rotation: bool,
	random_scale_sym: bool,
	random_scale_z: bool,
	random_scale_xy: bool,
)
## 单位面板：选中类型 + 当前玩家色 owner
signal unit_selected(type_id: String, info: Dictionary, owner_id: int)
signal unit_owner_changed(owner_id: int)
## 图标网格重建后：可见 type_id 列表（供 Inspect 预读 GLB 字节）
signal unit_icons_ready(type_ids: PackedStringArray)
signal closed_by_user
## 面板获焦时主窗收不到快捷键，转发撤销/重做
signal edit_undo_requested
signal edit_redo_requested
signal escape_pressed ## 面板获焦时 Esc → 取消装饰物预览等
## 顶部下拉切换面板类型（地形/单位/装饰物…）时通知 Editor 切笔刷
signal palette_kind_changed(kind: int)

enum PaletteKind { TERRAIN, UNITS, DOODADS, REGIONS, CAMERAS }
enum BrushShape { CIRCLE, SQUARE }
enum HeightTool { RAISE, LOWER, PLATEAU, NOISE, SMOOTH }
## 特殊「纹理」：荒芜 / 边界 / 去除边界（与普通地表贴图互斥）
enum SpecialTexture { NONE, BLIGHT, BOUNDARY, BOUNDARY_REMOVE }

const KIND_KEYS := [
	"WESTRING_PALETTE_TERRAIN",
	"WESTRING_PALETTE_UNITS",
	"WESTRING_PALETTE_DOODADS",
	"WESTRING_PALETTE_REGIONS",
	"WESTRING_PALETTE_CAMERAS",
]

const HEIGHT_TOOL_KEYS := [
	"WESTRING_BRUSH_RAISE",
	"WESTRING_BRUSH_LOWER",
	"WESTRING_BRUSH_PLATEAU",
	"WESTRING_BRUSH_NOISE",
	"WESTRING_BRUSH_SMOOTH",
]

const TILE_ICON := 40
const CLIFF_ICON := 36
const TILE_ATLAS_COLS := 8
const TILE_ATLAS_ROWS := 4
## 对齐 WorldEditData [BrushSizes00/01]：1,2,3,5,8（不是 1–5 连续）
const BRUSH_SIZES := [1, 2, 3, 5, 8]
## 对应 TextureBrush / SquareSizeBrush 图标编号
const BRUSH_SIZE_ICON_IDX := [0, 1, 2, 4, 7]
const WE_UI := "res://assets/asset-converted/ReplaceableTextures/WorldEditUI/"
const SEL_BORDER := Color(1.0, 0.85, 0.15, 1.0)
const SEL_BORDER_W := 2
const DataScript := preload("res://editor/ui/world_edit_data.gd")

@onready var _kind_option: OptionButton = %KindOption
@onready var _pages: TabContainer = %Pages
@onready var _texture_check: CheckBox = %TextureCheck
@onready var _tile_grid: GridContainer = %TileGrid
@onready var _special_blight: TextureButton = %SpecialBlight
@onready var _special_boundary: TextureButton = %SpecialBoundary
@onready var _special_boundary_rm: TextureButton = %SpecialBoundaryRemove
@onready var _cliff_check: CheckBox = %CliffCheck
@onready var _cliff_dec_two: TextureButton = %CliffDecTwo
@onready var _cliff_dec_one: TextureButton = %CliffDecOne
@onready var _cliff_same_level: TextureButton = %CliffSameLevel
@onready var _cliff_inc_one: TextureButton = %CliffIncOne
@onready var _cliff_inc_two: TextureButton = %CliffIncTwo
@onready var _cliff_shallow: TextureButton = %CliffShallow
@onready var _cliff_deep: TextureButton = %CliffDeep
@onready var _cliff_ramp: TextureButton = %CliffRamp
@onready var _cliff_type_label: Label = %CliffTypeLabel
@onready var _cliff_type_grid: HBoxContainer = %CliffTypeGrid
@onready var _height_check: CheckBox = %HeightCheck
@onready var _size_label: Label = %SizeLabel
@onready var _shape_label: Label = %ShapeLabel
@onready var _placeholder: Label = %Placeholder
@onready var _doodad_page: VBoxContainer = %DoodadPage
@onready var _doodad_tileset_option: OptionButton = %DoodadTilesetOption
@onready var _doodad_category_option: OptionButton = %DoodadCategoryOption
@onready var _doodad_rand_rotation_btn: TextureButton = %DoodadRandRotationBtn
@onready var _doodad_rand_scale_sym_btn: TextureButton = %DoodadRandScaleSymBtn
@onready var _doodad_rand_scale_z_btn: TextureButton = %DoodadRandScaleZBtn
@onready var _doodad_rand_scale_xy_btn: TextureButton = %DoodadRandScaleXYBtn
@onready var _doodad_list: ItemList = %DoodadList
@onready var _doodad_size_label: Label = %DoodadSizeLabel
@onready var _doodad_shape_label: Label = %DoodadShapeLabel
@onready var _doodad_size1: TextureButton = %DoodadSize1
@onready var _doodad_size2: TextureButton = %DoodadSize2
@onready var _doodad_size3: TextureButton = %DoodadSize3
@onready var _doodad_size4: TextureButton = %DoodadSize4
@onready var _doodad_size5: TextureButton = %DoodadSize5
@onready var _doodad_shape_circle: TextureButton = %DoodadShapeCircle
@onready var _doodad_shape_square: TextureButton = %DoodadShapeSquare
@onready var _unit_page: VBoxContainer = %UnitPage
@onready var _unit_race_option: OptionButton = %UnitRaceOption
@onready var _unit_group_option: OptionButton = %UnitGroupOption
@onready var _unit_neutral_filter_row: HBoxContainer = %UnitNeutralFilterRow
@onready var _unit_tileset_option: OptionButton = %UnitTilesetOption
@onready var _unit_level_option: OptionButton = %UnitLevelOption
@onready var _unit_owner_option: OptionButton = %UnitOwnerOption
@onready var _unit_owner_color: ColorRect = %UnitOwnerColor
@onready var _unit_current_label: Label = %UnitCurrentLabel
@onready var _unit_sections: VBoxContainer = %UnitSections

@onready var _height_raise: TextureButton = %HeightRaise
@onready var _height_lower: TextureButton = %HeightLower
@onready var _height_plateau: TextureButton = %HeightPlateau
@onready var _height_noise: TextureButton = %HeightNoise
@onready var _height_smooth: TextureButton = %HeightSmooth

@onready var _size1: TextureButton = %Size1
@onready var _size2: TextureButton = %Size2
@onready var _size3: TextureButton = %Size3
@onready var _size4: TextureButton = %Size4
@onready var _size5: TextureButton = %Size5
@onready var _shape_circle: TextureButton = %ShapeCircle
@onready var _shape_square: TextureButton = %ShapeSquare

var _kind: int = PaletteKind.TERRAIN
var _suppress_kind_signal: bool = false
var _tiles: Wc3TerrainTileCatalog
var _cliff_catalog: Wc3CliffCatalog
var _we_data: WorldEditData
var _tile_ids: PackedStringArray = PackedStringArray()
var _tile_buttons: Array = []
var _cliff_type_buttons: Array = []
var _cliff_type_ids: PackedStringArray = PackedStringArray()
var _selected_tile: int = 0
var _selected_cliff_type: int = 0
var _special_texture: int = SpecialTexture.NONE
var _brush_size: int = 1
var _brush_shape: int = BrushShape.CIRCLE
var _cliff_tool: int = 2 ## 默认「整平」= CliffBrushes index 2
var _cliff_tool_entries: Array = [] ## 合并 row1+row2 的配置项
var _height_tool: int = HeightTool.RAISE
var _apply_texture: bool = true
var _apply_cliff: bool = true
var _apply_height: bool = false
var _id_catalog: Wc3IdCatalog
var _doodad_entries: Array = []
var _selected_doodad_id: String = ""
var _map_tileset: String = "L" ## 当前地图主地形字母
## 放置随机（对齐 WE 装饰物面板四按钮）
var _doodad_rand_rotation: bool = true
var _doodad_rand_scale_sym: bool = false
var _doodad_rand_scale_z: bool = false
var _doodad_rand_scale_xy: bool = false
var _category_codes: PackedStringArray = PackedStringArray() ## Option 索引 → 分类码（含 ""=全部）
## 单位面板
var _unit_entries: Array = [] ## 当前筛选下全部条目（扁平，供选中查找）
var _unit_icon_buttons: Array = [] ## TextureButton
var _selected_unit_id: String = ""
var _unit_owner_id: int = 0 ## 默认玩家 1（索引 0）

var _cliff_buttons: Array = []
var _height_buttons: Array = []
var _size_buttons: Array = []
var _doodad_size_buttons: Array = []
var _size_circle_tex: Array = []
var _size_square_tex: Array = []
var _sel_style: StyleBoxFlat

## 经典 WE 玩家色（0–12）
const UNIT_PLAYER_COLORS: Array[Color] = [
	Color(1.00, 0.05, 0.05), # 红
	Color(0.05, 0.25, 1.00), # 蓝
	Color(0.10, 0.90, 0.90), # 青
	Color(0.55, 0.10, 0.85), # 紫
	Color(0.95, 0.90, 0.10), # 黄
	Color(1.00, 0.55, 0.05), # 橙
	Color(0.10, 0.80, 0.15), # 绿
	Color(0.95, 0.45, 0.70), # 粉
	Color(0.55, 0.55, 0.55), # 灰
	Color(0.45, 0.75, 1.00), # 淡蓝
	Color(0.10, 0.45, 0.10), # 暗绿
	Color(0.55, 0.30, 0.10), # 棕
	Color(0.12, 0.12, 0.12), # 黑/中立
]

const UNIT_ICON_PX := 40
const UNIT_ICON_COLS := 5
const UNIT_SECTION_ORDER := ["units", "heroes", "buildings", "special"]
const UNIT_SECTION_KEYS := {
	"units": "WESTRING_UNITS",
	"heroes": "WESTRING_UTYPE_HEROES",
	"buildings": "WESTRING_UTYPE_BUILDINGS",
	"special": "WESTRING_UTYPE_SPECIAL",
}


func _ready() -> void:
	# Windows + D3D12 下 unfocusable/transparent 会导致子窗口客户区不绘制（透出桌面）
	# 笔刷已用 DisplayServer 轮询悬停，面板获焦后仍可恢复预览，无需 unfocusable
	transparent = false
	unfocusable = false
	# 与 editor 一致：置顶常显；不设 transient（Windows 互斥）
	always_on_top = true
	_sel_style = _make_sel_style()
	close_requested.connect(_on_close_requested)
	_kind_option.item_selected.connect(_on_kind_selected)
	_texture_check.toggled.connect(_on_texture_toggled)
	_cliff_check.toggled.connect(_on_cliff_toggled)
	_height_check.toggled.connect(_on_height_toggled)
	_pages.tabs_visible = false
	if _we_data == null:
		_we_data = DataScript.load_default()
	_cache_size_textures()
	_wire_cliff_tool_buttons()
	_wire_static_tool_buttons()
	_wire_doodad_page()
	_wire_unit_page()
	_rebuild_kind_option()
	_apply_locale()
	_show_kind(_kind)
	_highlight_all_tools()
	EditorI18n.locale_changed.connect(func(_loc: String) -> void: _apply_locale())


var _doodad_page_wired: bool = false
var _unit_page_wired: bool = false


func _wire_doodad_page() -> void:
	if _doodad_page_wired:
		return
	_doodad_page_wired = true
	if _doodad_tileset_option != null:
		_doodad_tileset_option.item_selected.connect(_on_doodad_tileset)
	if _doodad_category_option != null:
		_doodad_category_option.item_selected.connect(_on_doodad_category)
	if _doodad_list != null:
		_doodad_list.item_selected.connect(_on_doodad_list_selected)
	_wire_doodad_place_rand_buttons()
	_doodad_size_buttons = [
		_doodad_size1, _doodad_size2, _doodad_size3, _doodad_size4, _doodad_size5,
	]
	for i in range(_doodad_size_buttons.size()):
		var btn: TextureButton = _doodad_size_buttons[i]
		if btn == null:
			continue
		_ensure_sel_frame(btn)
		btn.pressed.connect(_on_size_picked.bind(BRUSH_SIZES[i]))
	if _doodad_shape_circle != null:
		_ensure_sel_frame(_doodad_shape_circle)
		_doodad_shape_circle.pressed.connect(_on_shape_picked.bind(BrushShape.CIRCLE))
	if _doodad_shape_square != null:
		_ensure_sel_frame(_doodad_shape_square)
		_doodad_shape_square.pressed.connect(_on_shape_picked.bind(BrushShape.SQUARE))


func _wire_unit_page() -> void:
	if _unit_page_wired:
		return
	_unit_page_wired = true
	if _unit_race_option != null:
		_unit_race_option.item_selected.connect(_on_unit_race)
	if _unit_group_option != null:
		_unit_group_option.item_selected.connect(_on_unit_group)
	if _unit_owner_option != null:
		_unit_owner_option.item_selected.connect(_on_unit_owner)
	if _unit_tileset_option != null:
		_unit_tileset_option.item_selected.connect(_on_unit_tileset_or_level)
	if _unit_level_option != null:
		_unit_level_option.item_selected.connect(_on_unit_tileset_or_level)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	if k.ctrl_pressed and k.keycode == KEY_Z and not k.shift_pressed:
		edit_undo_requested.emit()
		set_input_as_handled()
	elif (
		(k.ctrl_pressed and k.keycode == KEY_Y)
		or (k.ctrl_pressed and k.shift_pressed and k.keycode == KEY_Z)
	):
		edit_redo_requested.emit()
		set_input_as_handled()
	elif k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
		escape_pressed.emit()
		set_input_as_handled()


func setup_we_data(data) -> void:
	_we_data = data if data != null else DataScript.load_default()
	if is_node_ready():
		_wire_cliff_tool_buttons()
		_highlight_cliff_tools()
		_refresh_section_labels()


func set_palette_kind(kind: int) -> void:
	_kind = clampi(kind, 0, KIND_KEYS.size() - 1)
	if is_node_ready():
		_show_kind(_kind)


func get_palette_kind() -> int:
	return _kind


func set_brush_settings(p_size: int, shape: int) -> void:
	_brush_size = _sanitize_brush_size(p_size)
	_brush_shape = BrushShape.CIRCLE if shape == BrushShape.CIRCLE else BrushShape.SQUARE
	if is_node_ready():
		_apply_size_button_textures()
		_highlight_size()
		_highlight_shape()
		_refresh_brush_labels()


func get_brush_size() -> int:
	return _brush_size


func get_brush_shape() -> int:
	return _brush_shape


static func _sanitize_brush_size(p_size: int) -> int:
	if p_size in BRUSH_SIZES:
		return p_size
	# 就近落到 WE 档位
	var best: int = BRUSH_SIZES[0]
	var best_d: int = absi(p_size - best)
	for s in BRUSH_SIZES:
		var d: int = absi(p_size - int(s))
		if d < best_d:
			best = int(s)
			best_d = d
	return best


func set_apply_texture(enabled: bool) -> void:
	_apply_texture = enabled
	if is_node_ready():
		_texture_check.set_pressed_no_signal(_apply_texture)


func set_cliff_settings(p_apply: bool, tool_id: String, type_idx: int) -> void:
	_apply_cliff = p_apply
	_selected_cliff_type = maxi(type_idx, 0)
	if not tool_id.is_empty():
		for i in range(_cliff_tool_entries.size()):
			if str(_cliff_tool_entries[i].get("id", "")) == tool_id:
				_cliff_tool = i
				break
	if is_node_ready():
		_cliff_check.set_pressed_no_signal(_apply_cliff)
		_highlight_cliff_tools()
		_highlight_cliff_types()
		_refresh_section_labels()


func get_cliff_tool_id() -> String:
	if _cliff_tool >= 0 and _cliff_tool < _cliff_tool_entries.size():
		return str(_cliff_tool_entries[_cliff_tool].get("id", "2"))
	return "2"


func get_cliff_type_index() -> int:
	return _selected_cliff_type


func is_apply_cliff() -> bool:
	return _apply_cliff


func _emit_cliff_settings() -> void:
	cliff_settings_changed.emit(_apply_cliff, get_cliff_tool_id(), _selected_cliff_type)


func set_id_catalog(catalog: Wc3IdCatalog) -> void:
	_id_catalog = catalog
	if not is_node_ready():
		return
	if _kind == PaletteKind.DOODADS:
		_rebuild_doodad_tileset_option()
		_rebuild_doodad_category_option()
		_rebuild_doodad_list()
	elif _kind == PaletteKind.UNITS:
		_rebuild_unit_race_option()
		_rebuild_unit_group_option()
		_rebuild_unit_owner_option()
		_rebuild_unit_neutral_filters()
		_rebuild_unit_list()


## 当前地图主地形字母（如 L / I），用于装饰物 tileset 下拉默认值。
func set_map_tileset(tileset_letter: String) -> void:
	var letter := tileset_letter.strip_edges().to_upper()
	if letter.is_empty():
		letter = "L"
	_map_tileset = letter
	if not is_node_ready():
		return
	if _kind == PaletteKind.DOODADS:
		_rebuild_doodad_tileset_option()
		_rebuild_doodad_category_option()
		_rebuild_doodad_list()
	elif _kind == PaletteKind.UNITS:
		_rebuild_unit_neutral_filters()
		_rebuild_unit_list()


func get_selected_unit_id() -> String:
	return _selected_unit_id


func get_unit_owner_id() -> int:
	return _unit_owner_id


func set_unit_owner_id(owner_id: int) -> void:
	_unit_owner_id = clampi(owner_id, 0, 15)
	if _unit_owner_option != null and _unit_owner_option.item_count > 0:
		for i in range(_unit_owner_option.item_count):
			if int(_unit_owner_option.get_item_metadata(i)) == _unit_owner_id:
				_unit_owner_option.select(i)
				break


func rebuild_terrain(doc, tiles: Wc3TerrainTileCatalog, cliff_catalog: Wc3CliffCatalog = null) -> void:
	_tiles = tiles
	_cliff_catalog = cliff_catalog
	_tile_ids = PackedStringArray()
	if doc == null or doc.is_empty():
		_rebuild_tile_grid()
		_rebuild_cliff_type_grid([])
		_refresh_section_labels()
		return
	var gs: Array = doc.ground_tilesets()
	for tid in gs:
		_tile_ids.append(str(tid))
	doc.ensure_brush_index_valid()
	_selected_tile = doc.brush_tile_index
	_rebuild_tile_grid()
	_refresh_blight_icon(str(doc.heightfield.main_tileset if doc.heightfield else "L"))
	_rebuild_cliff_type_grid(doc.cliff_tilesets())
	_refresh_section_labels()
	_highlight_special()


func _cache_size_textures() -> void:
	_size_circle_tex.clear()
	_size_square_tex.clear()
	for icon_i in BRUSH_SIZE_ICON_IDX:
		_size_circle_tex.append(load("%sTextureBrush%02d.png" % [WE_UI, icon_i]))
		_size_square_tex.append(load("%sSquareSizeBrush%02d.png" % [WE_UI, icon_i]))


func _wire_static_tool_buttons() -> void:
	_height_buttons = [
		_height_raise, _height_lower, _height_plateau, _height_noise, _height_smooth,
	]
	_size_buttons = [_size1, _size2, _size3, _size4, _size5]
	for i in range(_height_buttons.size()):
		_height_buttons[i].pressed.connect(_on_height_tool_picked.bind(i))
	for i in range(_size_buttons.size()):
		_size_buttons[i].pressed.connect(_on_size_picked.bind(BRUSH_SIZES[i]))
	_shape_circle.pressed.connect(_on_shape_picked.bind(BrushShape.CIRCLE))
	_shape_square.pressed.connect(_on_shape_picked.bind(BrushShape.SQUARE))
	_special_blight.pressed.connect(_on_special_picked.bind(SpecialTexture.BLIGHT))
	_special_boundary.pressed.connect(_on_special_picked.bind(SpecialTexture.BOUNDARY))
	_special_boundary_rm.pressed.connect(_on_special_picked.bind(SpecialTexture.BOUNDARY_REMOVE))
	for btn in (
		_height_buttons
		+ _size_buttons
		+ [_shape_circle, _shape_square, _special_blight, _special_boundary, _special_boundary_rm]
	):
		_ensure_sel_frame(btn as Control)


## 悬崖工具用场景内静态按钮；tooltip / 文案仍来自 WorldEditData。
func _wire_cliff_tool_buttons() -> void:
	var buttons: Array = [
		_cliff_dec_two, _cliff_dec_one, _cliff_same_level, _cliff_inc_one, _cliff_inc_two,
		_cliff_shallow, _cliff_deep, _cliff_ramp,
	]
	var first_wire: bool = _cliff_buttons.is_empty()
	_cliff_buttons = buttons
	_cliff_tool_entries.clear()
	if _we_data != null:
		for e in _we_data.cliff_brushes:
			_cliff_tool_entries.append(e)
		for e in _we_data.cliff_misc_brushes:
			_cliff_tool_entries.append(e)
	for i in range(_cliff_buttons.size()):
		var btn: TextureButton = _cliff_buttons[i]
		_ensure_sel_frame(btn)
		if first_wire:
			btn.pressed.connect(_on_cliff_tool_picked.bind(i))
		if i < _cliff_tool_entries.size():
			var entry: Dictionary = _cliff_tool_entries[i]
			var name_key := str(entry.get("name_key", ""))
			btn.tooltip_text = (
				EditorI18n.t(name_key) if not name_key.is_empty() else str(entry.get("id", ""))
			)
			var icon_res := str(entry.get("icon_res", ""))
			if not icon_res.is_empty() and ResourceLoader.exists(icon_res):
				btn.texture_normal = load(icon_res) as Texture2D
	_cliff_tool = clampi(_cliff_tool, 0, maxi(_cliff_tool_entries.size() - 1, 0))
	if first_wire:
		for i in range(_cliff_tool_entries.size()):
			if str(_cliff_tool_entries[i].get("id", "")) == "2":
				_cliff_tool = i
				break


func _clear_container_children(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()


func _make_sel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = SEL_BORDER
	s.set_border_width_all(SEL_BORDER_W)
	s.set_corner_radius_all(2)
	return s


func _ensure_sel_frame(btn: Control) -> Panel:
	var frame := btn.get_node_or_null("_SelFrame") as Panel
	if frame != null:
		return frame
	frame = Panel.new()
	frame.name = "_SelFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = -SEL_BORDER_W
	frame.offset_top = -SEL_BORDER_W
	frame.offset_right = SEL_BORDER_W
	frame.offset_bottom = SEL_BORDER_W
	if _sel_style != null:
		frame.add_theme_stylebox_override("panel", _sel_style)
	btn.add_child(frame)
	return frame


func _set_button_selected(btn: Control, on: bool) -> void:
	if btn is BaseButton:
		(btn as BaseButton).set_pressed_no_signal(on)
	var frame := _ensure_sel_frame(btn)
	frame.visible = on


func _make_icon_button(icon_res: String, px: int) -> TextureButton:
	var btn := TextureButton.new()
	btn.custom_minimum_size = Vector2(px, px)
	btn.toggle_mode = true
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	if not icon_res.is_empty() and ResourceLoader.exists(icon_res):
		btn.texture_normal = load(icon_res) as Texture2D
	_ensure_sel_frame(btn)
	return btn


func _apply_locale() -> void:
	title = EditorI18n.t("WESTRING_TOOL_PALETTE")
	_rebuild_kind_option()
	_refresh_section_labels()
	_refresh_brush_labels()
	if _doodad_rand_rotation_btn != null:
		_doodad_rand_rotation_btn.tooltip_text = EditorI18n.t("EDITOR_DOODAD_RAND_ROTATION")
	if _doodad_rand_scale_sym_btn != null:
		_doodad_rand_scale_sym_btn.tooltip_text = EditorI18n.t("EDITOR_DOODAD_RAND_SCALE_SYM")
	if _doodad_rand_scale_z_btn != null:
		_doodad_rand_scale_z_btn.tooltip_text = EditorI18n.t("EDITOR_DOODAD_RAND_SCALE_Z")
	if _doodad_rand_scale_xy_btn != null:
		_doodad_rand_scale_xy_btn.tooltip_text = EditorI18n.t("EDITOR_DOODAD_RAND_SCALE_XY")
	if _kind == PaletteKind.DOODADS:
		_rebuild_doodad_tileset_option()
		_rebuild_doodad_category_option()
		_rebuild_doodad_list()
	elif _kind == PaletteKind.UNITS:
		_rebuild_unit_race_option()
		_rebuild_unit_group_option()
		_rebuild_unit_owner_option()
		_rebuild_unit_neutral_filters()
		_rebuild_unit_list()
		_refresh_unit_current_label()
	elif _kind == PaletteKind.TERRAIN:
		_placeholder.text = EditorI18n.t("EDITOR_PALETTE_PLACEHOLDER")
	else:
		_placeholder.text = EditorI18n.t(
			"EDITOR_PALETTE_PLACEHOLDER_KIND",
			[EditorI18n.t(KIND_KEYS[_kind])]
		)


func _rebuild_kind_option() -> void:
	_suppress_kind_signal = true
	_kind_option.clear()
	for i in range(KIND_KEYS.size()):
		_kind_option.add_item(EditorI18n.t(KIND_KEYS[i]), i)
	_kind_option.select(_kind)
	_suppress_kind_signal = false


func _show_kind(kind: int) -> void:
	var prev: int = _kind
	_kind = clampi(kind, 0, KIND_KEYS.size() - 1)
	_suppress_kind_signal = true
	if _kind_option.selected != _kind:
		_kind_option.select(_kind)
	_suppress_kind_signal = false
	_pages.current_tab = 0 if _kind == PaletteKind.TERRAIN else 1
	var is_doodads := _kind == PaletteKind.DOODADS
	var is_units := _kind == PaletteKind.UNITS
	if _placeholder != null:
		_placeholder.visible = not is_doodads and not is_units
	if _doodad_page != null:
		_doodad_page.visible = is_doodads
	if _unit_page != null:
		_unit_page.visible = is_units
	if is_doodads:
		_rebuild_doodad_tileset_option()
		_rebuild_doodad_category_option()
		_rebuild_doodad_list()
	elif is_units:
		_rebuild_unit_race_option()
		_rebuild_unit_group_option()
		_rebuild_unit_owner_option()
		_rebuild_unit_neutral_filters()
		_rebuild_unit_list()
	elif _kind != PaletteKind.TERRAIN:
		_placeholder.text = EditorI18n.t(
			"EDITOR_PALETTE_PLACEHOLDER_KIND",
			[EditorI18n.t(KIND_KEYS[_kind])]
		)
	if prev != _kind:
		palette_kind_changed.emit(_kind)


func _rebuild_doodad_tileset_option() -> void:
	if _doodad_tileset_option == null:
		return
	var prev_id := _selected_doodad_tileset_id()
	_doodad_tileset_option.clear()
	var select_i := 0
	if _we_data != null:
		for i in range(_we_data.tilesets.size()):
			var ts: Dictionary = _we_data.tilesets[i]
			var tid := str(ts.get("id", "")).to_upper()
			var nk := str(ts.get("name_key", ""))
			var label := EditorI18n.t(nk) if not nk.is_empty() else tid
			var idx: int = _doodad_tileset_option.item_count
			_doodad_tileset_option.add_item(label, idx)
			_doodad_tileset_option.set_item_metadata(idx, tid)
			if tid == prev_id or (prev_id.is_empty() and tid == _map_tileset):
				select_i = idx
	if prev_id.is_empty() or prev_id == "*":
		for i in range(_doodad_tileset_option.item_count):
			if str(_doodad_tileset_option.get_item_metadata(i)) == _map_tileset:
				select_i = i
				break
	if _doodad_tileset_option.item_count > 0:
		_doodad_tileset_option.select(clampi(select_i, 0, _doodad_tileset_option.item_count - 1))


func _rebuild_doodad_category_option() -> void:
	if _doodad_category_option == null:
		return
	var prev := _selected_doodad_category_code()
	_doodad_category_option.clear()
	_category_codes = PackedStringArray()
	var select_i := 0
	var cats: Array = []
	if _we_data != null:
		for c in _we_data.doodad_categories:
			cats.append(c)
		for c2 in _we_data.destructible_categories:
			cats.append(c2)
	var ts := _selected_doodad_tileset_id()
	for c3 in cats:
		var code := str(c3.get("id", "")).to_upper()
		if code.is_empty():
			continue
		# 对齐 WE：当前地形集下无条目的分类不显示
		if not _doodad_category_has_entries(ts, code):
			continue
		var nk := str(c3.get("name_key", ""))
		var label := EditorI18n.t(nk) if not nk.is_empty() else code
		var idx: int = _doodad_category_option.item_count
		_doodad_category_option.add_item(label, idx)
		_category_codes.append(code)
		if code == prev:
			select_i = idx
	if _doodad_category_option.item_count > 0:
		_doodad_category_option.select(clampi(select_i, 0, _doodad_category_option.item_count - 1))


func _doodad_category_has_entries(tileset_letter: String, category_code: String) -> bool:
	if _id_catalog == null:
		return false
	return not _id_catalog.list_placeables_filtered(tileset_letter, category_code).is_empty()


func _rebuild_doodad_list() -> void:
	if _doodad_list == null:
		return
	_doodad_list.clear()
	_doodad_entries.clear()
	if _id_catalog == null:
		_doodad_list.add_item(EditorI18n.t("EDITOR_DOODAD_LIST_EMPTY"))
		return
	var ts := _selected_doodad_tileset_id()
	var cat := _selected_doodad_category_code()
	# 同时查装饰物 + 可破坏物（原作 WE 同一面板，无「来源」过滤）
	_doodad_entries = _id_catalog.list_placeables_filtered(ts, cat, true, true)
	if _doodad_entries.is_empty():
		_doodad_list.add_item(EditorI18n.t("EDITOR_DOODAD_LIST_EMPTY"))
		return
	_doodad_entries.sort_custom(_cmp_placeable_entries)
	var sel := 0
	for i in range(_doodad_entries.size()):
		var e: Dictionary = _doodad_entries[i]
		var id := str(e.get("id", ""))
		var display := _placeable_display_name(e)
		# 对齐 WE：列表只显示本地化名；四字符 ID 放 tooltip
		_doodad_list.add_item(display)
		_doodad_list.set_item_tooltip(i, "%s [%s]" % [display, id])
		if id == _selected_doodad_id:
			sel = i
	_doodad_list.select(sel)
	_on_doodad_list_selected(sel)


## 中文：按经典 WE 中文序；英文：按 SLK comment（英文名）序。
func _cmp_placeable_entries(a: Dictionary, b: Dictionary) -> bool:
	var ka := EditorI18n.placeable_sort_index(str(a.get("name_key", "")))
	var kb := EditorI18n.placeable_sort_index(str(b.get("name_key", "")))
	if ka >= 0 and kb >= 0 and ka != kb:
		return ka < kb
	var na := _placeable_display_name(a)
	var nb := _placeable_display_name(b)
	var by_name := na.nocasecmp_to(nb)
	if by_name != 0:
		return by_name < 0
	return str(a.get("id", "")).nocasecmp_to(str(b.get("id", ""))) < 0


## SLK Name（WESTRING_DOOD_* / WESTRING_DEST_*）→ 中文；缺省回退 comment。
func _placeable_display_name(e: Dictionary) -> String:
	var nk := str(e.get("name_key", ""))
	if nk.begins_with("WESTRING_"):
		var loc := EditorI18n.t(nk)
		if not loc.is_empty() and loc != nk and not loc.begins_with("WESTRING_"):
			return loc
	var fallback := str(e.get("name", ""))
	if not fallback.is_empty():
		return fallback
	return str(e.get("id", ""))


func _selected_doodad_tileset_id() -> String:
	if _doodad_tileset_option == null or _doodad_tileset_option.item_count <= 0:
		return _map_tileset
	var i: int = _doodad_tileset_option.selected
	var tid := str(_doodad_tileset_option.get_item_metadata(i))
	return tid if not tid.is_empty() else _map_tileset


func _selected_doodad_category_code() -> String:
	if _doodad_category_option == null:
		return ""
	var i: int = _doodad_category_option.selected
	if i < 0 or i >= _category_codes.size():
		return ""
	return _category_codes[i]


func _on_doodad_tileset(_index: int) -> void:
	_rebuild_doodad_category_option()
	_rebuild_doodad_list()


func _on_doodad_category(_index: int) -> void:
	_rebuild_doodad_list()


func _on_doodad_list_selected(index: int) -> void:
	if index < 0 or index >= _doodad_entries.size():
		return
	var e: Dictionary = _doodad_entries[index]
	_selected_doodad_id = str(e.get("id", ""))
	doodad_selected.emit(_selected_doodad_id, e)


## Esc 取消放置预览时：去掉列表高亮，不触发 doodad_selected。
func clear_doodad_selection() -> void:
	_selected_doodad_id = ""
	if _doodad_list != null:
		_doodad_list.deselect_all()


func _rebuild_unit_race_option() -> void:
	if _unit_race_option == null:
		return
	var prev := _selected_unit_race()
	_unit_race_option.clear()
	var select_i := 0
	var races := PackedStringArray()
	if _id_catalog != null:
		races = _id_catalog.list_unit_races()
	if races.is_empty():
		races = PackedStringArray(["human"])
	for i in range(races.size()):
		var rid := str(races[i])
		_unit_race_option.add_item(_unit_race_label(rid), i)
		_unit_race_option.set_item_metadata(i, rid)
		if rid == prev:
			select_i = i
	if _unit_race_option.item_count > 0:
		_unit_race_option.select(clampi(select_i, 0, _unit_race_option.item_count - 1))


func _rebuild_unit_group_option() -> void:
	if _unit_group_option == null:
		return
	var prev := _selected_unit_group()
	_unit_group_option.clear()
	# 对齐 WE：对战 / 战役（右侧下拉）
	const GROUPS := [
		["melee", "EDITOR_UNIT_SET_MELEE"],
		["campaign", "EDITOR_UNIT_SET_CAMPAIGN"],
	]
	var select_i := 0
	for i in range(GROUPS.size()):
		var gid := str(GROUPS[i][0])
		_unit_group_option.add_item(EditorI18n.t(str(GROUPS[i][1])), i)
		_unit_group_option.set_item_metadata(i, gid)
		if gid == prev or (prev == "standard" and gid == "melee"):
			select_i = i
	if _unit_group_option.item_count > 0:
		_unit_group_option.select(clampi(select_i, 0, _unit_group_option.item_count - 1))


func _rebuild_unit_owner_option() -> void:
	if _unit_owner_option == null:
		return
	var prev := _unit_owner_id
	_unit_owner_option.clear()
	var owners: Array = []
	for p in range(12):
		owners.append(p)
	owners.append(12)
	owners.append(15)
	var select_i := 0
	for i in range(owners.size()):
		var oid: int = int(owners[i])
		_unit_owner_option.add_item(_unit_owner_label(oid), i)
		_unit_owner_option.set_item_metadata(i, oid)
		if oid == prev:
			select_i = i
	if _unit_owner_option.item_count > 0:
		_unit_owner_option.select(clampi(select_i, 0, _unit_owner_option.item_count - 1))
		_unit_owner_id = int(_unit_owner_option.get_item_metadata(_unit_owner_option.selected))
	_refresh_unit_owner_swatch()


func _rebuild_unit_list() -> void:
	_rebuild_unit_icon_grids()


func _rebuild_unit_icon_grids() -> void:
	if _unit_sections == null:
		return
	for c in _unit_sections.get_children():
		_unit_sections.remove_child(c)
		c.queue_free()
	_unit_icon_buttons.clear()
	_unit_entries.clear()
	if _id_catalog == null:
		_refresh_unit_current_label()
		return
	var race := _selected_unit_race()
	var set_id := _selected_unit_group()
	var ts := "*"
	var lv := -1
	if race == "neutral":
		ts = _selected_unit_tileset_id()
		lv = _selected_unit_level()
	var sections: Dictionary = _id_catalog.list_units_palette_sections(race, set_id, ts, lv)
	var keep_sel := _selected_unit_id
	var found_sel := false
	for sec_id in UNIT_SECTION_ORDER:
		var entries: Array = sections.get(sec_id, []) as Array
		if entries.is_empty():
			continue
		var title := Label.new()
		var key := str(UNIT_SECTION_KEYS.get(sec_id, sec_id))
		title.text = EditorI18n.t(key)
		if title.text == key or title.text.begins_with("WESTRING_"):
			match sec_id:
				"units":
					title.text = "单位"
				"heroes":
					title.text = "英雄"
				"buildings":
					title.text = "建筑"
				"special":
					title.text = "特殊"
		elif sec_id == "special" and title.text.begins_with("特殊"):
			title.text = "特殊" # WE 用「特殊」，非「特殊的」
		_unit_sections.add_child(title)
		var grid := GridContainer.new()
		grid.columns = UNIT_ICON_COLS
		grid.add_theme_constant_override("h_separation", 2)
		grid.add_theme_constant_override("v_separation", 2)
		_unit_sections.add_child(grid)
		for e in entries:
			var info: Dictionary = e
			_unit_entries.append(info)
			var id := str(info.get("id", ""))
			var btn := _make_unit_icon_button(info)
			grid.add_child(btn)
			_unit_icon_buttons.append(btn)
			if id == keep_sel:
				found_sel = true
				_set_button_selected(btn, true)
	if not found_sel:
		_selected_unit_id = ""
	_refresh_unit_current_label()
	# 保持选中时再 emit，方便切种族后若仍在列表则同步
	if found_sel and not _selected_unit_id.is_empty():
		for e2 in _unit_entries:
			if str(e2.get("id", "")) == _selected_unit_id:
				unit_selected.emit(_selected_unit_id, e2, _unit_owner_id)
				break
	var ready_ids := PackedStringArray()
	for e3 in _unit_entries:
		var tid := str(e3.get("id", ""))
		if not tid.is_empty():
			ready_ids.append(tid)
	unit_icons_ready.emit(ready_ids)


func _make_unit_icon_button(info: Dictionary) -> TextureButton:
	var btn := TextureButton.new()
	btn.custom_minimum_size = Vector2(UNIT_ICON_PX, UNIT_ICON_PX)
	btn.toggle_mode = true
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	var id := str(info.get("id", ""))
	btn.set_meta("unit_id", id)
	var display := _unit_display_name(info)
	btn.tooltip_text = "%s [%s]" % [display, id]
	var tex: Texture2D = null
	if _id_catalog != null:
		tex = _id_catalog.unit_art_texture(id)
	if tex != null:
		btn.texture_normal = tex
	else:
		# 无图标时画色块占位
		var img := Image.create(UNIT_ICON_PX, UNIT_ICON_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.22, 0.22, 0.25, 1))
		btn.texture_normal = ImageTexture.create_from_image(img)
	_ensure_sel_frame(btn)
	btn.pressed.connect(_on_unit_icon_pressed.bind(btn, info))
	return btn


func _on_unit_icon_pressed(btn: TextureButton, info: Dictionary) -> void:
	_selected_unit_id = str(info.get("id", ""))
	for b in _unit_icon_buttons:
		if b is TextureButton:
			var tb := b as TextureButton
			var on := tb == btn
			tb.set_pressed_no_signal(on)
			_set_button_selected(tb, on)
	_refresh_unit_current_label()
	unit_selected.emit(_selected_unit_id, info, _unit_owner_id)


func _refresh_unit_current_label() -> void:
	if _unit_current_label == null:
		return
	if _selected_unit_id.is_empty():
		_unit_current_label.text = EditorI18n.t(
			"EDITOR_UNIT_CURRENT_FMT",
			[EditorI18n.t("WESTRING_NONE")]
		)
		return
	var name_str := _selected_unit_id
	for e in _unit_entries:
		if str(e.get("id", "")) == _selected_unit_id:
			name_str = _unit_display_name(e)
			break
	_unit_current_label.text = EditorI18n.t("EDITOR_UNIT_CURRENT_FMT", [name_str])


func _refresh_unit_owner_swatch() -> void:
	if _unit_owner_color == null:
		return
	var idx := _unit_owner_id
	if idx == 15:
		idx = 0 # 敌对用红色示意
	elif idx > 12:
		idx = 12
	idx = clampi(idx, 0, UNIT_PLAYER_COLORS.size() - 1)
	_unit_owner_color.color = UNIT_PLAYER_COLORS[idx]


func _unit_display_name(e: Dictionary) -> String:
	var key := str(e.get("name_key", ""))
	if key.begins_with("WESTRING_"):
		var loc := EditorI18n.t(key)
		if not loc.is_empty() and loc != key and not loc.begins_with("WESTRING_"):
			return loc
	var n := str(e.get("name", ""))
	if not n.is_empty():
		return n
	return str(e.get("id", ""))


func _unit_race_label(race_id: String) -> String:
	var key := "WESTRING_RACE_OTHER"
	if _id_catalog != null and _id_catalog.has_method("unit_palette_race_name_key"):
		key = _id_catalog.unit_palette_race_name_key(race_id)
	var loc := EditorI18n.t(key)
	if loc.is_empty() or loc == key or loc.begins_with("WESTRING_") or loc.begins_with("EDITOR_"):
		return race_id.capitalize()
	return loc


func _unit_owner_label(owner_id: int) -> String:
	if owner_id == 12:
		return EditorI18n.t("WESTRING_NEUTRAL_PASSIVE")
	if owner_id == 15:
		return EditorI18n.t("WESTRING_NEUTRAL_HOSTILE")
	var color_key := "WESTRING_UNITCOLOR_%02d" % owner_id
	var cname := EditorI18n.t(color_key)
	if cname == color_key or cname.begins_with("WESTRING_"):
		cname = str(owner_id + 1)
	return EditorI18n.t("EDITOR_UNIT_OWNER_PLAYER_FMT", [owner_id + 1, cname])


func _selected_unit_race() -> String:
	if _unit_race_option == null or _unit_race_option.item_count <= 0:
		return "human"
	return str(_unit_race_option.get_item_metadata(_unit_race_option.selected))


func _selected_unit_group() -> String:
	if _unit_group_option == null or _unit_group_option.item_count <= 0:
		return "melee"
	return str(_unit_group_option.get_item_metadata(_unit_group_option.selected))


func _rebuild_unit_neutral_filters() -> void:
	var is_neutral := _selected_unit_race() == "neutral"
	if _unit_neutral_filter_row != null:
		_unit_neutral_filter_row.visible = is_neutral
	if not is_neutral:
		return
	_rebuild_unit_tileset_option()
	_rebuild_unit_level_option()


func _rebuild_unit_tileset_option() -> void:
	if _unit_tileset_option == null:
		return
	var prev := _selected_unit_tileset_id()
	_unit_tileset_option.clear()
	var select_i := 0
	# 与装饰物一致：用 WorldEditData 地形集列表；默认当前地图主地形
	if _we_data != null:
		for i in range(_we_data.tilesets.size()):
			var ts: Dictionary = _we_data.tilesets[i]
			var tid := str(ts.get("id", "")).to_upper()
			var label := EditorI18n.t(str(ts.get("name_key", tid)))
			if label.is_empty() or label == str(ts.get("name_key", "")) or label.begins_with("WESTRING_"):
				label = tid
			var idx: int = _unit_tileset_option.item_count
			_unit_tileset_option.add_item(label, idx)
			_unit_tileset_option.set_item_metadata(idx, tid)
			if tid == prev or (prev.is_empty() and tid == _map_tileset):
				select_i = idx
	if _unit_tileset_option.item_count <= 0:
		_unit_tileset_option.add_item(_map_tileset, 0)
		_unit_tileset_option.set_item_metadata(0, _map_tileset)
	else:
		# 无 prev 时优先地图主地形
		if prev.is_empty() or prev == "*":
			for i2 in range(_unit_tileset_option.item_count):
				if str(_unit_tileset_option.get_item_metadata(i2)) == _map_tileset:
					select_i = i2
					break
	_unit_tileset_option.select(clampi(select_i, 0, maxi(_unit_tileset_option.item_count - 1, 0)))


func _rebuild_unit_level_option() -> void:
	if _unit_level_option == null:
		return
	var prev := _selected_unit_level()
	_unit_level_option.clear()
	# WE：任何等级 + 1..10（偶见更高，列到 15）
	_unit_level_option.add_item(EditorI18n.t("EDITOR_UNIT_ANY_LEVEL"), 0)
	_unit_level_option.set_item_metadata(0, -1)
	var select_i := 0
	for lv in range(1, 16):
		var idx: int = _unit_level_option.item_count
		_unit_level_option.add_item(EditorI18n.t("EDITOR_UNIT_LEVEL_FMT", [lv]), idx)
		_unit_level_option.set_item_metadata(idx, lv)
		if lv == prev:
			select_i = idx
	if prev < 0:
		select_i = 0
	_unit_level_option.select(clampi(select_i, 0, maxi(_unit_level_option.item_count - 1, 0)))


func _selected_unit_tileset_id() -> String:
	if _unit_tileset_option == null or _unit_tileset_option.item_count <= 0:
		return _map_tileset if not _map_tileset.is_empty() else "L"
	return str(_unit_tileset_option.get_item_metadata(_unit_tileset_option.selected))


func _selected_unit_level() -> int:
	if _unit_level_option == null or _unit_level_option.item_count <= 0:
		return -1
	return int(_unit_level_option.get_item_metadata(_unit_level_option.selected))


func _on_unit_race(_index: int) -> void:
	_rebuild_unit_neutral_filters()
	_rebuild_unit_icon_grids()


func _on_unit_group(_index: int) -> void:
	_rebuild_unit_icon_grids()


func _on_unit_tileset_or_level(_index: int) -> void:
	_rebuild_unit_icon_grids()


func _on_unit_owner(_index: int) -> void:
	if _unit_owner_option == null:
		return
	_unit_owner_id = int(_unit_owner_option.get_item_metadata(_unit_owner_option.selected))
	_refresh_unit_owner_swatch()
	unit_owner_changed.emit(_unit_owner_id)
	if not _selected_unit_id.is_empty():
		for e in _unit_entries:
			if str(e.get("id", "")) == _selected_unit_id:
				unit_selected.emit(_selected_unit_id, e, _unit_owner_id)
				break


func clear_unit_selection() -> void:
	_selected_unit_id = ""
	for b in _unit_icon_buttons:
		if b is TextureButton:
			_set_button_selected(b as TextureButton, false)
	_refresh_unit_current_label()


func _wire_doodad_place_rand_buttons() -> void:
	var pairs: Array = [
		[_doodad_rand_rotation_btn, "_doodad_rand_rotation"],
		[_doodad_rand_scale_sym_btn, "_doodad_rand_scale_sym"],
		[_doodad_rand_scale_z_btn, "_doodad_rand_scale_z"],
		[_doodad_rand_scale_xy_btn, "_doodad_rand_scale_xy"],
	]
	for p in pairs:
		var btn: TextureButton = p[0]
		if btn == null:
			continue
		_ensure_sel_frame(btn)
		var prop: String = str(p[1])
		btn.set_pressed_no_signal(bool(get(prop)))
		_set_button_selected(btn, bool(get(prop)))
		btn.toggled.connect(_on_doodad_place_rand_toggled.bind(prop))


func _on_doodad_place_rand_toggled(on: bool, prop: String) -> void:
	set(prop, on)
	var btn: TextureButton = null
	match prop:
		"_doodad_rand_rotation":
			btn = _doodad_rand_rotation_btn
		"_doodad_rand_scale_sym":
			btn = _doodad_rand_scale_sym_btn
		"_doodad_rand_scale_z":
			btn = _doodad_rand_scale_z_btn
		"_doodad_rand_scale_xy":
			btn = _doodad_rand_scale_xy_btn
	if btn != null:
		_set_button_selected(btn, on)
	doodad_place_random_changed.emit(
		_doodad_rand_rotation,
		_doodad_rand_scale_sym,
		_doodad_rand_scale_z,
		_doodad_rand_scale_xy,
	)


func get_doodad_place_random() -> Dictionary:
	return {
		"rotation": _doodad_rand_rotation,
		"scale_sym": _doodad_rand_scale_sym,
		"scale_z": _doodad_rand_scale_z,
		"scale_xy": _doodad_rand_scale_xy,
	}


func set_doodad_place_random(
	rotation: bool,
	scale_sym: bool,
	scale_z: bool,
	scale_xy: bool,
) -> void:
	_doodad_rand_rotation = rotation
	_doodad_rand_scale_sym = scale_sym
	_doodad_rand_scale_z = scale_z
	_doodad_rand_scale_xy = scale_xy
	if _doodad_rand_rotation_btn != null:
		_doodad_rand_rotation_btn.set_pressed_no_signal(rotation)
		_set_button_selected(_doodad_rand_rotation_btn, rotation)
	if _doodad_rand_scale_sym_btn != null:
		_doodad_rand_scale_sym_btn.set_pressed_no_signal(scale_sym)
		_set_button_selected(_doodad_rand_scale_sym_btn, scale_sym)
	if _doodad_rand_scale_z_btn != null:
		_doodad_rand_scale_z_btn.set_pressed_no_signal(scale_z)
		_set_button_selected(_doodad_rand_scale_z_btn, scale_z)
	if _doodad_rand_scale_xy_btn != null:
		_doodad_rand_scale_xy_btn.set_pressed_no_signal(scale_xy)
		_set_button_selected(_doodad_rand_scale_xy_btn, scale_xy)


func _rebuild_tile_grid() -> void:
	_clear_container_children(_tile_grid)
	_tile_buttons.clear()
	for i in range(_tile_ids.size()):
		var tid: String = _tile_ids[i]
		var btn := _make_icon_button("", TILE_ICON)
		btn.toggle_mode = false
		btn.tooltip_text = EditorI18n.tile_display_name(_tiles, tid)
		var tex := _load_tile_tex(tid)
		if tex != null:
			btn.texture_normal = tex
		btn.pressed.connect(_on_tile_picked.bind(i))
		_tile_grid.add_child(btn)
		_tile_buttons.append(btn)
	_highlight_tiles()


func _rebuild_cliff_type_grid(cliff_ids: Array) -> void:
	_clear_container_children(_cliff_type_grid)
	_cliff_type_buttons.clear()
	_cliff_type_ids = PackedStringArray()
	for i in range(cliff_ids.size()):
		var cid: String = str(cliff_ids[i])
		_cliff_type_ids.append(cid)
		var btn := _make_icon_button("", CLIFF_ICON)
		var name_key := "WESTRING_CLIFF_%s" % cid
		var localized := EditorI18n.t(name_key)
		btn.tooltip_text = localized if localized != name_key else cid
		var tex := _load_cliff_tex(cid)
		if tex != null:
			btn.texture_normal = tex
		btn.pressed.connect(_on_cliff_type_picked.bind(i))
		_cliff_type_grid.add_child(btn)
		_cliff_type_buttons.append(btn)
	if _cliff_type_buttons.size() > 0:
		_selected_cliff_type = clampi(_selected_cliff_type, 0, _cliff_type_buttons.size() - 1)
	_highlight_cliff_types()
	_refresh_cliff_type_label()


func _refresh_section_labels() -> void:
	var tile_name := EditorI18n.t("WESTRING_NONE")
	match _special_texture:
		SpecialTexture.BLIGHT:
			tile_name = EditorI18n.t("WESTRING_BLIGHT")
		SpecialTexture.BOUNDARY:
			tile_name = EditorI18n.t("WESTRING_TILE_BOUNDARY")
		SpecialTexture.BOUNDARY_REMOVE:
			tile_name = EditorI18n.t("EDITOR_TILE_BOUNDARY_REMOVE")
		_:
			if _selected_tile >= 0 and _selected_tile < _tile_ids.size():
				tile_name = EditorI18n.tile_display_name(_tiles, _tile_ids[_selected_tile])
	_texture_check.text = EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_APPLYTEXTURE"), tile_name],
	)
	_texture_check.set_pressed_no_signal(_apply_texture)
	_special_blight.tooltip_text = EditorI18n.t("WESTRING_BLIGHT")
	_special_boundary.tooltip_text = EditorI18n.t("WESTRING_TILE_BOUNDARY")
	_special_boundary_rm.tooltip_text = EditorI18n.t("EDITOR_TILE_BOUNDARY_REMOVE")

	var cliff_name := EditorI18n.t("WESTRING_NONE")
	if _cliff_tool >= 0 and _cliff_tool < _cliff_tool_entries.size():
		var ck := str(_cliff_tool_entries[_cliff_tool].get("name_key", ""))
		cliff_name = EditorI18n.t(ck) if not ck.is_empty() else ck
	_cliff_check.text = EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_APPLYCLIFF"), cliff_name],
	)
	_cliff_check.set_pressed_no_signal(_apply_cliff)

	var height_name := EditorI18n.t("WESTRING_NONE")
	if _apply_height:
		height_name = EditorI18n.t(
			HEIGHT_TOOL_KEYS[clampi(_height_tool, 0, HEIGHT_TOOL_KEYS.size() - 1)]
		)
	_height_check.text = EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_APPLYHEIGHT"), height_name],
	)
	_height_check.set_pressed_no_signal(_apply_height)
	_refresh_cliff_type_label()


func _refresh_cliff_type_label() -> void:
	var name_str := EditorI18n.t("WESTRING_NONE")
	if _selected_cliff_type >= 0 and _selected_cliff_type < _cliff_type_ids.size():
		var cid: String = _cliff_type_ids[_selected_cliff_type]
		var key := "WESTRING_CLIFF_%s" % cid
		var localized := EditorI18n.t(key)
		name_str = localized if localized != key else cid
	_cliff_type_label.text = EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_BRUSH_CLIFFTYPE"), name_str],
	)


func _refresh_brush_labels() -> void:
	var size_text := EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_BRUSHSIZE"), str(_brush_size)],
	)
	_size_label.text = size_text
	if _doodad_size_label != null:
		_doodad_size_label.text = size_text
	var shape_key := (
		"WESTRING_BRUSH_CIRCLE" if _brush_shape == BrushShape.CIRCLE else "WESTRING_BRUSH_SQUARE"
	)
	var shape_text := EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_BRUSHSHAPE"), EditorI18n.t(shape_key)],
	)
	_shape_label.text = shape_text
	if _doodad_shape_label != null:
		_doodad_shape_label.text = shape_text


func _apply_size_button_textures() -> void:
	var texs: Array = _size_circle_tex if _brush_shape == BrushShape.CIRCLE else _size_square_tex
	for i in range(_size_buttons.size()):
		if i < texs.size() and texs[i] != null:
			_size_buttons[i].texture_normal = texs[i]
	for i in range(_doodad_size_buttons.size()):
		if i < texs.size() and texs[i] != null and _doodad_size_buttons[i] != null:
			_doodad_size_buttons[i].texture_normal = texs[i]

func _highlight_all_tools() -> void:
	_highlight_tiles()
	_highlight_special()
	_highlight_cliff_tools()
	_highlight_height_tools()
	_highlight_cliff_types()
	_apply_size_button_textures()
	_highlight_size()
	_highlight_shape()


func _highlight_tiles() -> void:
	var use_tile: bool = _special_texture == SpecialTexture.NONE
	for i in range(_tile_buttons.size()):
		_set_button_selected(_tile_buttons[i], use_tile and i == _selected_tile)


func _highlight_special() -> void:
	_set_button_selected(_special_blight, _special_texture == SpecialTexture.BLIGHT)
	_set_button_selected(_special_boundary, _special_texture == SpecialTexture.BOUNDARY)
	_set_button_selected(_special_boundary_rm, _special_texture == SpecialTexture.BOUNDARY_REMOVE)


func _highlight_cliff_tools() -> void:
	for i in range(_cliff_buttons.size()):
		_set_button_selected(_cliff_buttons[i], i == _cliff_tool)


func _highlight_height_tools() -> void:
	for i in range(_height_buttons.size()):
		_set_button_selected(_height_buttons[i], i == _height_tool)


func _highlight_cliff_types() -> void:
	for i in range(_cliff_type_buttons.size()):
		_set_button_selected(_cliff_type_buttons[i], i == _selected_cliff_type)


func _highlight_size() -> void:
	for i in range(_size_buttons.size()):
		_set_button_selected(_size_buttons[i], BRUSH_SIZES[i] == _brush_size)
	for i in range(_doodad_size_buttons.size()):
		if _doodad_size_buttons[i] != null:
			_set_button_selected(_doodad_size_buttons[i], BRUSH_SIZES[i] == _brush_size)


func _highlight_shape() -> void:
	_set_button_selected(_shape_circle, _brush_shape == BrushShape.CIRCLE)
	_set_button_selected(_shape_square, _brush_shape == BrushShape.SQUARE)
	if _doodad_shape_circle != null:
		_set_button_selected(_doodad_shape_circle, _brush_shape == BrushShape.CIRCLE)
	if _doodad_shape_square != null:
		_set_button_selected(_doodad_shape_square, _brush_shape == BrushShape.SQUARE)


func _on_kind_selected(index: int) -> void:
	if _suppress_kind_signal:
		return
	_show_kind(index)


func _on_tile_picked(index: int) -> void:
	_selected_tile = index
	var cleared_special: bool = _special_texture != SpecialTexture.NONE
	_special_texture = SpecialTexture.NONE
	_highlight_tiles()
	_highlight_special()
	_refresh_section_labels()
	tile_selected.emit(index)
	if cleared_special:
		special_texture_changed.emit(_special_texture)


func _on_special_picked(kind: int) -> void:
	# 再点一次已选中的特殊纹理 → 取消，回到普通贴图
	if _special_texture == kind:
		_special_texture = SpecialTexture.NONE
	else:
		_special_texture = kind
	_highlight_tiles()
	_highlight_special()
	_refresh_section_labels()
	special_texture_changed.emit(_special_texture)


func get_special_texture() -> int:
	return _special_texture


func set_special_texture(kind: int) -> void:
	_special_texture = clampi(kind, 0, SpecialTexture.BOUNDARY_REMOVE)
	_highlight_tiles()
	_highlight_special()
	_refresh_section_labels()


func _refresh_blight_icon(tileset_letter: String) -> void:
	var logical := "TerrainArt/Blight/Lords_Blight"
	if _we_data != null:
		logical = _we_data.blight_path_for_tileset(tileset_letter)
	var path := DataScript.icon_to_res(logical)
	if path.is_empty() or not ResourceLoader.exists(path):
		path = "res://assets/asset-converted/TerrainArt/Blight/Lords_Blight.png"
	var img := RuntimeAssets.load_image(path)
	if img == null:
		return
	_special_blight.texture_normal = ImageTexture.create_from_image(_atlas_first_cell(img))


func _on_cliff_type_picked(index: int) -> void:
	_selected_cliff_type = index
	_highlight_cliff_types()
	_refresh_cliff_type_label()
	_emit_cliff_settings()


func _on_cliff_tool_picked(tool_id: int) -> void:
	_cliff_tool = tool_id
	_apply_cliff = true
	_highlight_cliff_tools()
	_refresh_section_labels()
	_emit_cliff_settings()


func _on_height_tool_picked(tool_id: int) -> void:
	_height_tool = tool_id
	_apply_height = true
	_highlight_height_tools()
	_refresh_section_labels()


func _on_texture_toggled(pressed: bool) -> void:
	_apply_texture = pressed
	apply_texture_changed.emit(pressed)


func _on_cliff_toggled(pressed: bool) -> void:
	_apply_cliff = pressed
	_refresh_section_labels()
	_emit_cliff_settings()


func _on_height_toggled(pressed: bool) -> void:
	_apply_height = pressed
	_refresh_section_labels()


func _on_size_picked(p_size: int) -> void:
	_brush_size = _sanitize_brush_size(p_size)
	_highlight_size()
	_refresh_brush_labels()
	brush_settings_changed.emit(_brush_size, _brush_shape)


func _on_shape_picked(shape: int) -> void:
	_brush_shape = shape
	_apply_size_button_textures()
	_highlight_shape()
	_highlight_size()
	_refresh_brush_labels()
	brush_settings_changed.emit(_brush_size, _brush_shape)


func _on_close_requested() -> void:
	closed_by_user.emit()
	queue_free()


func _load_tile_tex(tile_id: String) -> Texture2D:
	if _tiles == null:
		return null
	var path: String = _tiles.png_for_tile_id(tile_id)
	if path.is_empty():
		return null
	var img := RuntimeAssets.load_image(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(_atlas_first_cell(img))


func _load_cliff_tex(cliff_id: String) -> Texture2D:
	if _cliff_catalog == null and _tiles == null:
		return null
	# WE：悬崖类型图标用 Cliffs.slk 的 groundTile（泥土/草地地表 atlas），不是崖壁 PNG
	var ground_id := ""
	if _cliff_catalog != null:
		ground_id = _cliff_catalog.ground_tile_for_cliff_id(cliff_id)
	if not ground_id.is_empty() and _tiles != null:
		var ground_path: String = _tiles.png_for_tile_id(ground_id)
		if not ground_path.is_empty():
			var ground_img := RuntimeAssets.load_image(ground_path)
			if ground_img != null:
				return ImageTexture.create_from_image(_atlas_first_cell(ground_img))
	# 缺 groundTile 时回退：裁崖壁贴图左上角
	var path := ""
	if _cliff_catalog != null:
		path = _cliff_catalog.png_for_cliff_id(cliff_id)
	if path.is_empty():
		return null
	var img := RuntimeAssets.load_image(path)
	if img == null:
		return null
	var side: int = int(mini(img.get_width(), img.get_height()) / 2.0)
	if side < 8:
		return ImageTexture.create_from_image(img)
	return ImageTexture.create_from_image(img.get_region(Rect2i(0, 0, side, side)))


func _atlas_first_cell(img: Image) -> Image:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < TILE_ATLAS_COLS or h < TILE_ATLAS_ROWS:
		return img
	var cell_w: int = int(w / float(TILE_ATLAS_COLS))
	var cell_h: int = int(h / float(TILE_ATLAS_ROWS))
	if cell_w <= 0 or cell_h <= 0:
		return img
	return img.get_region(Rect2i(0, 0, cell_w, cell_h))
