extends Window
## 经典世界编辑器「工具面板」浮窗。可多开；顶部下拉切换面板类型。
## 地形贴图：运行时按地图 tileset 动态加载。
## 悬崖/高度/尺寸/形状图标：场景内引用 WorldEditUI 静态贴图。


signal tile_selected(index: int)
signal brush_settings_changed(size: int, shape: int)
signal apply_texture_changed(enabled: bool)
signal cliff_settings_changed(apply: bool, tool_id: String, type_idx: int)
signal closed_by_user

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
const DataScript := preload("res://editor/scripts/ui/world_edit_data.gd")

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
var _tiles: Wc3TerrainTiles
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

var _cliff_buttons: Array = []
var _height_buttons: Array = []
var _size_buttons: Array = []
var _size_circle_tex: Array = []
var _size_square_tex: Array = []
var _sel_style: StyleBoxFlat


func _ready() -> void:
	# Windows + D3D12 下 unfocusable/transparent 会导致子窗口客户区不绘制（透出桌面）
	# 笔刷已用 DisplayServer 轮询悬停，面板获焦后仍可恢复预览，无需 unfocusable
	transparent = false
	unfocusable = false
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
	_rebuild_kind_option()
	_apply_locale()
	_show_kind(_kind)
	_highlight_all_tools()
	EditorI18n.locale_changed.connect(func(_loc: String) -> void: _apply_locale())


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


func rebuild_terrain(doc, tiles: Wc3TerrainTiles) -> void:
	_tiles = tiles
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
	_refresh_blight_icon(str(doc.hf.get("mainTileset", "L")))
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
	if _kind == PaletteKind.TERRAIN:
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
	_kind = clampi(kind, 0, KIND_KEYS.size() - 1)
	_suppress_kind_signal = true
	if _kind_option.selected != _kind:
		_kind_option.select(_kind)
	_suppress_kind_signal = false
	_pages.current_tab = 0 if _kind == PaletteKind.TERRAIN else 1
	if _kind != PaletteKind.TERRAIN:
		_placeholder.text = EditorI18n.t(
			"EDITOR_PALETTE_PLACEHOLDER_KIND",
			[EditorI18n.t(KIND_KEYS[_kind])]
		)


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
	_size_label.text = EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_BRUSHSIZE"), str(_brush_size)],
	)
	var shape_key := (
		"WESTRING_BRUSH_CIRCLE" if _brush_shape == BrushShape.CIRCLE else "WESTRING_BRUSH_SQUARE"
	)
	_shape_label.text = EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_BRUSHSHAPE"), EditorI18n.t(shape_key)],
	)


func _apply_size_button_textures() -> void:
	var texs: Array = _size_circle_tex if _brush_shape == BrushShape.CIRCLE else _size_square_tex
	for i in range(_size_buttons.size()):
		if i < texs.size() and texs[i] != null:
			_size_buttons[i].texture_normal = texs[i]


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


func _highlight_shape() -> void:
	_set_button_selected(_shape_circle, _brush_shape == BrushShape.CIRCLE)
	_set_button_selected(_shape_square, _brush_shape == BrushShape.SQUARE)


func _on_kind_selected(index: int) -> void:
	if _suppress_kind_signal:
		return
	_show_kind(index)


func _on_tile_picked(index: int) -> void:
	_selected_tile = index
	_special_texture = SpecialTexture.NONE
	_highlight_tiles()
	_highlight_special()
	_refresh_section_labels()
	tile_selected.emit(index)


func _on_special_picked(kind: int) -> void:
	# 再点一次已选中的特殊纹理 → 取消，回到普通贴图
	if _special_texture == kind:
		_special_texture = SpecialTexture.NONE
	else:
		_special_texture = kind
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
	if _tiles == null:
		return null
	# WE：悬崖类型图标用 Cliffs.slk 的 groundTile（泥土/草地地表 atlas），不是崖壁 PNG
	var ground_id: String = _tiles.ground_tile_for_cliff_id(cliff_id)
	if not ground_id.is_empty():
		var ground_path: String = _tiles.png_for_tile_id(ground_id)
		if not ground_path.is_empty():
			var ground_img := RuntimeAssets.load_image(ground_path)
			if ground_img != null:
				return ImageTexture.create_from_image(_atlas_first_cell(ground_img))
	# 缺 groundTile 时回退：裁崖壁贴图左上角
	var path: String = _tiles.png_for_cliff_id(cliff_id)
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
