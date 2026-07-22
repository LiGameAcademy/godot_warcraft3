extends Window
## 经典世界编辑器「工具面板」浮窗。可多开；顶部下拉切换面板类型。
## 目前仅「地形面板」可用（地表贴图列表）；其余类型为占位。


signal tile_selected(index: int)
signal closed_by_user

enum PaletteKind { TERRAIN, UNITS, DOODADS, REGIONS, CAMERAS }

const KIND_KEYS := [
	"WESTRING_PALETTE_TERRAIN",
	"WESTRING_PALETTE_UNITS",
	"WESTRING_PALETTE_DOODADS",
	"WESTRING_PALETTE_REGIONS",
	"WESTRING_PALETTE_CAMERAS",
]

@onready var _kind_option: OptionButton = %KindOption
@onready var _pages: TabContainer = %Pages
@onready var _texture_title: Label = %TextureTitle
@onready var _tile_list: ItemList = %TileList
@onready var _placeholder: Label = %Placeholder

var _kind: int = PaletteKind.TERRAIN
var _suppress_kind_signal: bool = false


func _ready() -> void:
	close_requested.connect(_on_close_requested)
	_kind_option.item_selected.connect(_on_kind_selected)
	_tile_list.item_selected.connect(_on_tile_item_selected)
	_pages.tabs_visible = false
	_rebuild_kind_option()
	_apply_locale()
	_show_kind(_kind)
	EditorI18n.locale_changed.connect(func(_loc: String) -> void: _apply_locale())


func set_palette_kind(kind: int) -> void:
	_kind = clampi(kind, 0, KIND_KEYS.size() - 1)
	if is_node_ready():
		_show_kind(_kind)


func get_palette_kind() -> int:
	return _kind


func rebuild_terrain(doc, tiles: Wc3TerrainTiles) -> void:
	_tile_list.clear()
	if doc == null or doc.is_empty():
		return
	var gs: Array = doc.ground_tilesets()
	for i in range(gs.size()):
		var tid: String = str(gs[i])
		_tile_list.add_item("%d  %s" % [i, EditorI18n.tile_display_name(tiles, tid)])
	doc.ensure_brush_index_valid()
	if gs.size() > 0:
		_tile_list.select(doc.brush_tile_index)


func _apply_locale() -> void:
	title = EditorI18n.t("WESTRING_TOOL_PALETTE")
	_texture_title.text = EditorI18n.t("EDITOR_PALETTE_TITLE")
	_rebuild_kind_option()
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
	# 0 = TerrainPage，1 = PlaceholderPage
	_pages.current_tab = 0 if _kind == PaletteKind.TERRAIN else 1
	if _kind != PaletteKind.TERRAIN:
		_placeholder.text = EditorI18n.t(
			"EDITOR_PALETTE_PLACEHOLDER_KIND",
			[EditorI18n.t(KIND_KEYS[_kind])]
		)


func _on_kind_selected(index: int) -> void:
	if _suppress_kind_signal:
		return
	_show_kind(index)


func _on_tile_item_selected(index: int) -> void:
	tile_selected.emit(index)


func _on_close_requested() -> void:
	closed_by_user.emit()
	queue_free()
