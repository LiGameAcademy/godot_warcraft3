class_name Wc3IdCatalog
extends RefCounted
## Stable public catalog API. Data loading, palette rules and model lookup are separate.
const DataLoader: GDScript = preload("wc3_catalog_data.gd")
const Palette: GDScript = preload("wc3_catalog_palette.gd")
const Models: GDScript = preload("wc3_catalog_models.gd")
const UNIT_PALETTE_RACE_BUCKETS: Array[Dictionary] = Palette.UNIT_PALETTE_RACE_BUCKETS
var _units: Dictionary = {}
var _destructables: Dictionary = {}
var _doodads: Dictionary = {}

func load_default() -> void:
	var loader: RefCounted = DataLoader.new(_units, _destructables, _doodads, _def_store())
	loader.load_default()

func lookup(type_id: String) -> Dictionary:
	if _units.has(type_id):
		return _units[type_id]
	if _destructables.has(type_id):
		return _destructables[type_id]
	if _doodads.has(type_id):
		return _doodads[type_id]
	return {"id": type_id, "name": type_id, "file": "", "kind": "unknown", "num_var": 1}


func unit_count() -> int:
	return _units.size()


func doodad_count() -> int:
	return _doodads.size()


func destructable_count() -> int:
	return _destructables.size()


func list_placeables(include_doodads: bool = true, include_destructables: bool = true) -> Array:
	return Palette.list_placeables(_doodads, _destructables, include_doodads, include_destructables)

func list_placeables_filtered(tileset_letter: String = "", category_code: String = "",
	include_doodads: bool = true, include_destructables: bool = true) -> Array:
	return Palette.list_placeables_filtered(_doodads, _destructables, tileset_letter,
		category_code, include_doodads, include_destructables)

func list_units_filtered(race: String = "", group: String = "standard") -> Array:
	return Palette.list_units_filtered(_units, race, group)

func list_unit_races() -> PackedStringArray:
	return Palette.list_unit_races(_units)

func unit_palette_race_name_key(palette_race_id: String) -> String:
	return Palette.unit_palette_race_name_key(palette_race_id)

static func unit_palette_section(entry: Dictionary) -> String:
	return Palette.unit_palette_section(entry)

func list_units_palette_sections(race: String, set_id: String = "melee",
	tileset_letter: String = "*", level: int = -1) -> Dictionary:
	return Palette.list_units_palette_sections(_units, race, set_id, tileset_letter, level)

func model_base_path(type_id: String) -> String:
	return Models.model_base_path(lookup(type_id))

func model_file_ver_flags(type_id: String) -> int:
	return Models.model_file_ver_flags(lookup(type_id))

func resolve_model_stem(type_id: String) -> String:
	return Models.resolve_model_stem(lookup(type_id))

func converted_glb_path(type_id: String, variation: int = 0) -> String:
	return Models.converted_glb_path(lookup(type_id), variation)

func portrait_glb_path(type_id: String) -> String:
	return Models.portrait_glb_path(lookup(type_id))

## 命令按钮图标（Art → converted png）。
func unit_art_texture(type_id: String) -> Texture2D:
	var info: Dictionary = lookup(type_id)
	var art: String = str(info.get("art", "")).replace("\\", "/")
	if art.is_empty():
		return null
	var lower: String = art.to_lower()
	if lower.ends_with(".tga") or lower.ends_with(".blp"):
		art = art.substr(0, art.length() - 4) + ".png"
	elif not lower.ends_with(".png"):
		art = art + ".png"
	return RuntimeAssets.load_converted_texture(art)


func _def_store() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## 从 pathTex 文件名解析寻路格尺寸，如 `PathTextures\4x4Default.tga` → (4,4)。
## 无法解析（none / 异形图）返回 Vector2i.ZERO。
static func parse_path_tex_cells(path_tex: String) -> Vector2i:
	var s: String = path_tex.replace("\\", "/").get_file()
	if s.is_empty() or s.to_lower() == "none" or s == "_":
		return Vector2i.ZERO
	var re: RegEx = RegEx.new()
	if re.compile("(\\d+)x(\\d+)") != OK:
		return Vector2i.ZERO
	var m: RegExMatch = re.search(s)
	if m == null:
		return Vector2i.ZERO
	var w: int = int(m.get_string(1))
	var h: int = int(m.get_string(2))
	if w <= 0 or h <= 0:
		return Vector2i.ZERO
	return Vector2i(w, h)


## 选中环直径（WC3 单位）。
## 优先级：doodad selSize → pathTex 脚印 → UnitBalance.collision×2 → UnitUI.scale(Selection Scale)×基线 → 1 格。
## UnitUI 无 selSize；单位尺寸主要看 collision / Selection Scale。HiveWE 选框另用模型 bounds_radius。
const UNIT_SELECTION_SCALE_BASE: float = 72.0


static func selection_diameter_wc3(info: Dictionary) -> float:
	var sel: float = float(info.get("sel_size", 0.0))
	if sel > 1.0:
		return sel
	var cells: Vector2i = parse_path_tex_cells(str(info.get("path_tex", "")))
	if cells != Vector2i.ZERO:
		return float(maxi(cells.x, cells.y)) * Wc3Coords.PATHING_CELL
	var collision: float = float(info.get("collision", 0.0))
	var from_col: float = collision * 2.0 if collision > 0.0 else 0.0
	# UnitUI.scale = Art - Selection Scale；1.0 为默认，不当作 ×72（否则农民圈≈2 格）
	var sel_scale: float = float(info.get("def_scale", 0.0))
	var from_scale: float = sel_scale * UNIT_SELECTION_SCALE_BASE if sel_scale > 1.0 else 0.0
	var diam: float = maxf(from_col, from_scale)
	if diam > 1.0:
		return diam
	return Wc3Coords.PATHING_CELL

## 放置默认朝向：fixedRot≥0 用固定角；-1（自由旋转）用 WE 默认 270°。
static func default_facing_deg(info: Dictionary) -> float:
	var fr: float = float(info.get("fixed_rot", -1.0))
	if fr >= 0.0:
		return fposmod(fr, 360.0)
	return 270.0


## 预览相机距离（WE「距离」框，WC3 单位）。
## 经验对齐：常见 visRadius=50 → 400；大物件跟 selSize；瀑布 visRadius=100 → 800。
static func preview_distance_wc3(info: Dictionary) -> float:
	var vis: float = float(info.get("vis_radius", 50.0))
	var from_vis: float = vis * 8.0 if vis > 0.0 else 400.0
	var sel: float = float(info.get("sel_size", 0.0))
	var from_sel: float = sel if sel > 1.0 else 0.0
	var foot: float = selection_diameter_wc3(info)
	return maxf(maxf(from_vis, from_sel), foot * 2.0)
