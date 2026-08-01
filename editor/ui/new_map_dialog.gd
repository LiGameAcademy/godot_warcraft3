extends Window
## 「创建新地图」对话框：布局见同目录 `new_map_dialog.tscn`。
## 文案全部走 EditorI18n key；场景里文本为 key 占位。


signal confirmed(options: Dictionary)

const DataScript := preload("res://editor/ui/world_edit_data.gd")
const TILE_ICON := 48
## WC3 地表 BLP 图集：8 列 × 4 行，预览取左上角第 1 格。
const TILE_ATLAS_COLS := 8
const TILE_ATLAS_ROWS := 4

@onready var _width_opt: OptionButton = %WidthOpt
@onready var _height_opt: OptionButton = %HeightOpt
@onready var _play_w: Label = %PlayW
@onready var _play_h: Label = %PlayH
@onready var _size_desc: Label = %SizeDesc
@onready var _tileset_opt: OptionButton = %TilesetOpt
@onready var _tile_label: Label = %TileLabel
@onready var _tile_grid: GridContainer = %TileGrid
@onready var _cliff_opt: OptionButton = %CliffOpt
@onready var _water_label: Label = %WaterLabel
@onready var _water_none: TextureButton = %WaterNone
@onready var _water_shallow: TextureButton = %WaterShallow
@onready var _water_deep: TextureButton = %WaterDeep
@onready var _random_check: CheckBox = %RandomCheck
@onready var _ok_btn: Button = %OkBtn
@onready var _cancel_btn: Button = %CancelBtn

var _data
var _tiles: Wc3TerrainTileCatalog
var _cliff_catalog: Wc3CliffCatalog

var _tile_ids: PackedStringArray = PackedStringArray()
var _selected_tile: int = 0
var _water_mode: int = 0 ## 0 无 / 1 浅 / 2 深
var _tile_buttons: Array = []
var _water_buttons: Array = []

func _ready() -> void:
	hide()

## 初始化对话框
## [param tiles] Wc3TerrainTileCatalog
## [param cliff_catalog] Wc3CliffCatalog
## [param _strings] String (optional)
## [param data] WorldEditData (optional)
func setup(
	tiles: Wc3TerrainTileCatalog,
	cliff_catalog: Wc3CliffCatalog = null,
	_strings = null,
	data = null
) -> void:
	_tiles = tiles
	_cliff_catalog = cliff_catalog
	_data = data if data != null else DataScript.load_default()
	_wire_signals()
	_water_buttons = [_water_none, _water_shallow, _water_deep]
	_highlight_water()
	_apply_strings()
	_populate()
	_refresh_playable()
	_on_tileset_changed(_tileset_opt.selected)
	if not EditorI18n.locale_changed.is_connected(_on_locale_changed):
		EditorI18n.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_loc: String) -> void:
	_apply_strings()
	_populate()
	_refresh_playable()
	_refresh_tile_label()
	_on_water_picked(_water_mode)


func _wire_signals() -> void:
	if close_requested.is_connected(hide):
		return
	close_requested.connect(hide)
	_ok_btn.pressed.connect(_on_ok)
	_cancel_btn.pressed.connect(hide)
	_width_opt.item_selected.connect(func(_i: int) -> void: _refresh_playable())
	_height_opt.item_selected.connect(func(_i: int) -> void: _refresh_playable())
	_tileset_opt.item_selected.connect(_on_tileset_changed)
	_water_none.pressed.connect(_on_water_picked.bind(0))
	_water_shallow.pressed.connect(_on_water_picked.bind(1))
	_water_deep.pressed.connect(_on_water_picked.bind(2))


## 应用字符串
func _apply_strings() -> void:
	title = EditorI18n.t("EDITOR_NEWMAP_TITLE")
	%SizeTitle.text = EditorI18n.label("WESTRING_NEWMAP_SIZE")
	%WidthLabel.text = EditorI18n.label("WESTRING_NEWMAP_SIZEX")
	%HeightLabel.text = EditorI18n.label("WESTRING_NEWMAP_SIZEY")
	%PlayTitle.text = EditorI18n.label("WESTRING_NEWMAP_PLAYSIZE")
	%PlayWLabel.text = EditorI18n.label("WESTRING_NEWMAP_PLAYSIZEX")
	%PlayHLabel.text = EditorI18n.label("WESTRING_NEWMAP_PLAYSIZEY")
	%DescLabel.text = EditorI18n.label("WESTRING_NEWMAP_SIZEDESC")
	%TerrainTitle.text = EditorI18n.t("EDITOR_NEWMAP_TERRAIN_SECTION")
	%CliffLabel.text = EditorI18n.label("WESTRING_NEWMAP_DEFCLIFF")
	_random_check.text = EditorI18n.t("WESTRING_RANDOMHEIGHT")
	_ok_btn.text = EditorI18n.strip_accel(EditorI18n.t("WESTRING_OK"))
	_cancel_btn.text = EditorI18n.t("WESTRING_CANCEL")
	_on_water_picked(_water_mode)


## 填充选项
func _populate() -> void:
	var prev_w: int = int(_width_opt.get_selected_id()) if _width_opt.item_count > 0 else 0
	var prev_h: int = int(_height_opt.get_selected_id()) if _height_opt.item_count > 0 else 0
	var prev_ts: String = ""
	if _tileset_opt.item_count > 0 and _tileset_opt.selected >= 0:
		prev_ts = str(_tileset_opt.get_item_metadata(_tileset_opt.selected))
	var prev_cliff: int = int(_cliff_opt.get_selected_id()) if _cliff_opt.item_count > 0 else 2

	_width_opt.clear()
	_height_opt.clear()
	var opts: PackedInt32Array = _data.size_options()
	var def_w: int = prev_w if prev_w > 0 else int(_data.default_map_size.x)
	var def_h: int = prev_h if prev_h > 0 else int(_data.default_map_size.y)
	var sel_w := 0
	var sel_h := 0
	for i in range(opts.size()):
		var v: int = opts[i]
		_width_opt.add_item(str(v), v)
		_height_opt.add_item(str(v), v)
		if v == def_w:
			sel_w = i
		if v == def_h:
			sel_h = i
	_width_opt.select(sel_w)
	_height_opt.select(sel_h)

	_cliff_opt.clear()
	for lv in range(0, 15):
		_cliff_opt.add_item(str(lv), lv)
	_cliff_opt.select(clampi(prev_cliff, 0, 14))

	_tileset_opt.clear()
	var def_ts: String = prev_ts if not prev_ts.is_empty() else str(_data.default_tileset)
	var sel_ts := 0
	for i in range(_data.tilesets.size()):
		var ts: Dictionary = _data.tilesets[i]
		var id := str(ts["id"])
		var label := EditorI18n.t(str(ts["name_key"]))
		if label == str(ts["name_key"]):
			label = id
		_tileset_opt.add_item(label)
		_tileset_opt.set_item_metadata(i, id)
		if id == def_ts:
			sel_ts = i
	_tileset_opt.select(sel_ts)


## 地形集变化
func _on_tileset_changed(index: int) -> void:
	if index < 0 or _tiles == null:
		return
	var letter: String = str(_tileset_opt.get_item_metadata(index))
	_tile_ids = _tiles.tile_ids_for_tileset(letter)
	_selected_tile = 0
	_rebuild_tile_grid()
	_refresh_tile_label()


## 重建地形集网格
func _rebuild_tile_grid() -> void:
	for c in _tile_grid.get_children():
		c.queue_free()
	_tile_buttons.clear()
	for i in range(_tile_ids.size()):
		var tid: String = _tile_ids[i]
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(TILE_ICON, TILE_ICON)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_SCALE
		btn.tooltip_text = tid
		var tex := _load_tile_tex(tid)
		if tex != null:
			btn.texture_normal = tex
		else:
			btn.texture_normal = _make_swatch(Color(0.4, 0.4, 0.4), Color(0.25, 0.25, 0.25), TILE_ICON)
		btn.pressed.connect(_on_tile_picked.bind(i))
		_tile_grid.add_child(btn)
		_tile_buttons.append(btn)
	_highlight_tiles()


## 地形集选择
func _on_tile_picked(index: int) -> void:
	_selected_tile = index
	_highlight_tiles()
	_refresh_tile_label()


## 水位选择
func _on_water_picked(water_mode: int) -> void:
	_water_mode = water_mode
	_highlight_water()
	var water_name := EditorI18n.t("WESTRING_NONE")
	if water_mode == 1:
		water_name = EditorI18n.t("EDITOR_WATER_SHALLOW")
	elif water_mode == 2:
		water_name = EditorI18n.t("EDITOR_WATER_DEEP")
	_water_label.text = EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_NEWMAP_DEFWATER"), water_name],
	)


func _highlight_tiles() -> void:
	for i in range(_tile_buttons.size()):
		var btn: TextureButton = _tile_buttons[i]
		btn.modulate = Color(1.25, 1.25, 1.25) if i == _selected_tile else Color.WHITE


func _highlight_water() -> void:
	for i in range(_water_buttons.size()):
		var btn: TextureButton = _water_buttons[i]
		btn.modulate = Color(1.3, 1.3, 1.3) if i == _water_mode else Color(0.85, 0.85, 0.85)


func _refresh_tile_label() -> void:
	var empty := EditorI18n.t("EDITOR_NEWMAP_EMPTY")
	if _selected_tile < 0 or _selected_tile >= _tile_ids.size():
		_tile_label.text = EditorI18n.t(
			"EDITOR_NEWMAP_VALUE",
			[EditorI18n.t("WESTRING_NEWMAP_DEFTILE"), empty],
		)
		return
	var tid: String = _tile_ids[_selected_tile]
	_tile_label.text = EditorI18n.t(
		"EDITOR_NEWMAP_VALUE",
		[EditorI18n.t("WESTRING_NEWMAP_DEFTILE"), EditorI18n.tile_display_name(_tiles, tid)],
	)


func _refresh_playable() -> void:
	var w: int = int(_width_opt.get_selected_id())
	var h: int = int(_height_opt.get_selected_id())
	if w <= 0:
		w = 64
	if h <= 0:
		h = 64
	var play: Vector2i = _data.playable_size(w, h)
	_play_w.text = str(play.x)
	_play_h.text = str(play.y)
	_size_desc.text = EditorI18n.t(_data.size_desc_key(w, h))


func _on_ok() -> void:
	var w: int = int(_width_opt.get_selected_id())
	var h: int = int(_height_opt.get_selected_id())
	var letter: String = str(_tileset_opt.get_item_metadata(_tileset_opt.selected))
	var ground: Array = []
	for tid in _tile_ids:
		ground.append(tid)
	var cliffs: Array = []
	if _cliff_catalog != null:
		for cid in _cliff_catalog.cliff_ids_for_tileset(letter):
			cliffs.append(cid)
	if cliffs.is_empty():
		cliffs = ["C%sdi" % letter, "C%sgr" % letter]
	var tile_index: int = clampi(_selected_tile, 0, maxi(ground.size() - 1, 0))
	var name_key := str(_data.tilesets[_tileset_opt.selected]["name_key"])
	var ts_name := EditorI18n.t(name_key)
	if ts_name == name_key:
		ts_name = letter
	var opts := {
		"width": w,
		"height": h,
		"main_tileset": letter,
		"main_tileset_name": ts_name,
		"ground_tilesets": ground,
		"cliff_tilesets": cliffs,
		"default_tile_index": tile_index,
		"cliff_level": int(_cliff_opt.get_selected_id()),
		"water_mode": _water_mode,
		"random_height": _random_check.button_pressed,
	}
	confirmed.emit(opts)
	hide()


func _load_tile_tex(tile_id: String) -> Texture2D:
	var path: String = _tiles.png_for_tile_id(tile_id)
	if path.is_empty():
		return null
	var img := RuntimeAssets.load_image(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(_atlas_first_cell(img))


## 取 8×4 图集左上角一格（纯色底砖），避免整张过渡表缩进图标。
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

func _make_swatch(c0: Color, c1: Color, px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in range(px):
		for x in range(px):
			var edge := x < 2 or y < 2 or x >= px - 2 or y >= px - 2
			img.set_pixel(x, y, Color(0.1, 0.1, 0.1) if edge else c0.lerp(c1, float(y) / float(px)))
	return ImageTexture.create_from_image(img)
