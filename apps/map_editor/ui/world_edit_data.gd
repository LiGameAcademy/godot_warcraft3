extends RefCounted
class_name WorldEditData

## 解析经典编辑器 `UI/WorldEditData.txt`（地形集、地图尺寸档、默认值）。
##
## 权威路径：`assets/slk-exported/UI/WorldEditData.txt`（sync-data-assets）。
## 解析：AssetProvider overlay → converted → slk-exported（不读 .cache）。
## 同步：`node tools/sync-data-assets.mjs`
## 找不到时用脚本内置回退表，新建地图对话框仍可工作。


const LOGICAL_PATH := "UI/WorldEditData.txt"
const CAMERA_BORDER := 6 ## 兼容旧调用：每侧名义边距；实际默认补边见 Wc3Coords L6R6B4T8
## 编辑器图标落在视觉车道（ReplaceableTextures 等），不是 slk-exported
const CONVERTED_UI := "res://assets/asset-converted/"

var tilesets: Array = [] ## { id, name_key, blight }
var map_size_tiers: Array = [] ## { max_area, name_key } 升序
var default_map_size: Vector2i = Vector2i(64, 64)
var min_map_size: int = 64
var max_map_size: int = 256
var default_tileset: String = "L"
## 装饰物 / 可破坏物分类：{ id, name_key, icon, icon_res }
var doodad_categories: Array = [] ## [DoodadCategories] O/S/W/C/E/Z
var destructible_categories: Array = [] ## [DestructibleCategories] D/P/B
## 刷子表：{ id/key, name_key, icon }；icon 为 res://…png
var cliff_brushes: Array = [] ## [CliffBrushes] 0..4 → 第一行
var cliff_misc_brushes: Array = [] ## 浅水/深水/斜坡 → 第二行
var height_brushes: Array = []
var brush_shapes: Array = []
var brush_sizes_circle: Array = []
var brush_sizes_square: Array = []
var misc_brushes: Dictionary = {} ## Blight/Nothing/Unnothing/…


static func load_default():
	var d = new()
	d._load()
	return d


func size_options() -> PackedInt32Array:
	var out := PackedInt32Array()
	var v: int = mini(maxi(min_map_size, 32), max_map_size)
	# 与经典编辑器常用步进一致：64 起，每档 +32
	if min_map_size <= 64:
		v = 64
	while v <= max_map_size:
		out.append(v)
		v += 32
	if out.is_empty():
		out.append(64)
	return out


func playable_size(map_w: int, map_h: int) -> Vector2i:
	var c: Dictionary = Wc3Coords.default_camera_bounds_complements()
	return Vector2i(
		maxi(map_w - int(c.left) - int(c.right), 0),
		maxi(map_h - int(c.bottom) - int(c.top), 0),
	)


func size_desc_key(map_w: int, map_h: int) -> String:
	var area: int = map_w * map_h
	for tier in map_size_tiers:
		if area <= int(tier["max_area"]):
			return str(tier["name_key"])
	if map_size_tiers.is_empty():
		return "WESTRING_MAPSIZE_TINY"
	return str(map_size_tiers[map_size_tiers.size() - 1]["name_key"])


## 地形集字母对应的荒芜贴图逻辑路径（如 TerrainArt/Blight/Lords_Blight）。
func blight_path_for_tileset(tileset_letter: String) -> String:
	var letter := tileset_letter.strip_edges().to_upper()
	for ts in tilesets:
		if str(ts.get("id", "")) == letter:
			return str(ts.get("blight", "")).replace("\\", "/")
	return "TerrainArt/Blight/Lords_Blight"


## WorldEditData 图标路径 → asset-converted PNG。
static func icon_to_res(icon_logical: String) -> String:
	var p := icon_logical.strip_edges().replace("\\", "/")
	if p.is_empty():
		return ""
	if p.begins_with("res://"):
		return p
	if not p.ends_with(".png") and not p.ends_with(".blp"):
		p += ".png"
	elif p.ends_with(".blp"):
		p = p.substr(0, p.length() - 4) + ".png"
	return CONVERTED_UI.path_join(p)


func _load() -> void:
	_apply_fallback()
	var abs_path := _resolve(LOGICAL_PATH)
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		push_warning("WorldEditData: 未找到 %s，使用内置回退" % LOGICAL_PATH)
		return
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	var section := ""
	tilesets.clear()
	map_size_tiers.clear()
	doodad_categories.clear()
	destructible_categories.clear()
	cliff_brushes.clear()
	cliff_misc_brushes.clear()
	height_brushes.clear()
	brush_shapes.clear()
	brush_sizes_circle.clear()
	brush_sizes_square.clear()
	misc_brushes.clear()
	var misc_raw: Dictionary = {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		match section:
			"TileSets":
				if key.length() != 1:
					continue
				var parts: PackedStringArray = val.split(",")
				var name_key := parts[0].strip_edges() if parts.size() > 0 else ""
				var blight := parts[1].strip_edges() if parts.size() > 1 else ""
				tilesets.append({"id": key.to_upper(), "name_key": name_key, "blight": blight})
			"DoodadCategories":
				doodad_categories.append(_parse_brush_entry(key.to_upper(), val))
			"DestructibleCategories":
				destructible_categories.append(_parse_brush_entry(key.to_upper(), val))
			"MapSizes":
				if key.begins_with("Size") and key.length() >= 6:
					var parts2: PackedStringArray = val.split(",")
					if parts2.size() >= 2:
						map_size_tiers.append({
							"max_area": int(parts2[0]),
							"name_key": parts2[1].strip_edges(),
						})
			"WorldEditMisc":
				match key:
					"DefaultMapSize":
						var xy: PackedStringArray = val.split(",")
						if xy.size() >= 2:
							default_map_size = Vector2i(int(xy[0]), int(xy[1]))
					"MinimumMapSize":
						min_map_size = int(val)
					"MaximumMapSize":
						max_map_size = int(val)
					"DefaultTileset":
						default_tileset = val.strip_edges().to_upper()
			"CliffBrushes":
				cliff_brushes.append(_parse_brush_entry(key, val))
			"HeightBrushes":
				height_brushes.append(_parse_brush_entry(key, val))
			"BrushShapes":
				brush_shapes.append(_parse_brush_entry(key, val))
			"BrushSizes00":
				brush_sizes_circle.append(_parse_brush_entry(key, val))
			"BrushSizes01":
				brush_sizes_square.append(_parse_brush_entry(key, val))
			"MiscBrushes":
				misc_raw[key] = _parse_brush_entry(key, val)
	# 悬崖第二行：浅水、深水、斜坡（对齐经典 WE 面板）
	for mk in ["ShallowWater", "DeepWater", "Ramp"]:
		if misc_raw.has(mk):
			cliff_misc_brushes.append(misc_raw[mk])
	misc_brushes = misc_raw
	if doodad_categories.is_empty() or destructible_categories.is_empty():
		_apply_category_fallback()


func _parse_brush_entry(id_key: String, val: String) -> Dictionary:
	var parts: PackedStringArray = val.split(",")
	var name_key := parts[0].strip_edges() if parts.size() > 0 else ""
	var icon := parts[1].strip_edges() if parts.size() > 1 else ""
	return {
		"id": id_key,
		"name_key": name_key,
		"icon": icon,
		"icon_res": icon_to_res(icon),
	}


func _resolve(logical: String) -> String:
	# 仅 assets/（converted → slk-exported）；缺文件跑 sync-data-assets / bootstrap
	return RuntimeAssets.resolve(logical)


func _apply_fallback() -> void:
	tilesets = [
		{"id": "L", "name_key": "WESTRING_LOCALE_LORDAERON_SUMMER", "blight": "TerrainArt\\Blight\\Lords_Blight"},
		{"id": "F", "name_key": "WESTRING_LOCALE_LORDAERON_FALL", "blight": "TerrainArt\\Blight\\Lordf_Blight"},
		{"id": "W", "name_key": "WESTRING_LOCALE_LORDAERON_WINTER", "blight": "TerrainArt\\Blight\\Lordw_Blight"},
		{"id": "B", "name_key": "WESTRING_LOCALE_BARRENS", "blight": "TerrainArt\\Blight\\Barrens_Blight"},
		{"id": "A", "name_key": "WESTRING_LOCALE_ASHENVALE", "blight": "TerrainArt\\Blight\\Ashen_Blight"},
		{"id": "C", "name_key": "WESTRING_LOCALE_FELWOOD", "blight": "TerrainArt\\Blight\\Felwood_Blight"},
		{"id": "N", "name_key": "WESTRING_LOCALE_NORTHREND", "blight": "TerrainArt\\Blight\\North_Blight"},
		{"id": "Y", "name_key": "WESTRING_LOCALE_CITYSCAPE", "blight": "TerrainArt\\Blight\\Village_Blight"},
		{"id": "X", "name_key": "WESTRING_LOCALE_DALARAN", "blight": "TerrainArt\\Blight\\Village_Blight"},
		{"id": "V", "name_key": "WESTRING_LOCALE_VILLAGE", "blight": "TerrainArt\\Blight\\Village_Blight"},
		{"id": "Q", "name_key": "WESTRING_LOCALE_VILLAGEFALL", "blight": "TerrainArt\\Blight\\VillageFall_Blight"},
		{"id": "D", "name_key": "WESTRING_LOCALE_DUNGEON", "blight": "TerrainArt\\Blight\\Cave_Blight"},
		{"id": "G", "name_key": "WESTRING_LOCALE_DUNGEON2", "blight": "TerrainArt\\Blight\\Dungeon_Blight"},
		{"id": "Z", "name_key": "WESTRING_LOCALE_RUINS", "blight": "TerrainArt\\Blight\\Ruins_Blight"},
		{"id": "I", "name_key": "WESTRING_LOCALE_ICECROWN", "blight": "TerrainArt\\Blight\\Ice_Blight"},
		{"id": "O", "name_key": "WESTRING_LOCALE_OUTLAND", "blight": "TerrainArt\\Blight\\Outland_Blight"},
		{"id": "K", "name_key": "WESTRING_LOCALE_BLACKCITADEL", "blight": "TerrainArt\\Blight\\Citadel_Blight"},
		{"id": "J", "name_key": "WESTRING_LOCALE_DALARANRUINS", "blight": "TerrainArt\\Blight\\DRuins_Blight"},
	]
	map_size_tiers = [
		{"max_area": 7500, "name_key": "WESTRING_MAPSIZE_TINY"},
		{"max_area": 13500, "name_key": "WESTRING_MAPSIZE_SMALL"},
		{"max_area": 22000, "name_key": "WESTRING_MAPSIZE_MEDIUM"},
		{"max_area": 32500, "name_key": "WESTRING_MAPSIZE_LARGE"},
		{"max_area": 45000, "name_key": "WESTRING_MAPSIZE_HUGE"},
		{"max_area": 99999, "name_key": "WESTRING_MAPSIZE_EPIC"},
	]
	default_map_size = Vector2i(64, 64)
	min_map_size = 64
	max_map_size = 256
	default_tileset = "L"
	cliff_brushes = [
		_parse_brush_entry("0", "WESTRING_DECTWO,ReplaceableTextures\\WorldEditUI\\CliffBrush07"),
		_parse_brush_entry("1", "WESTRING_DECONE,ReplaceableTextures\\WorldEditUI\\CliffBrush06"),
		_parse_brush_entry("2", "WESTRING_SAMELEVEL,ReplaceableTextures\\WorldEditUI\\CliffBrush02"),
		_parse_brush_entry("3", "WESTRING_INCONE,ReplaceableTextures\\WorldEditUI\\CliffBrush03"),
		_parse_brush_entry("4", "WESTRING_INCTWO,ReplaceableTextures\\WorldEditUI\\CliffBrush04"),
	]
	cliff_misc_brushes = [
		_parse_brush_entry("ShallowWater", "WESTRING_SHALLOWWATER,ReplaceableTextures\\WorldEditUI\\CliffBrush01"),
		_parse_brush_entry("DeepWater", "WESTRING_DEEPWATER,ReplaceableTextures\\WorldEditUI\\CliffBrush00"),
		_parse_brush_entry("Ramp", "WESTRING_BRUSH_RAMP,ReplaceableTextures\\WorldEditUI\\RampBrush00"),
	]
	height_brushes = [
		_parse_brush_entry("0", "WESTRING_BRUSH_RAISE,ReplaceableTextures\\WorldEditUI\\HeightBrush00"),
		_parse_brush_entry("1", "WESTRING_BRUSH_LOWER,ReplaceableTextures\\WorldEditUI\\HeightBrush04"),
		_parse_brush_entry("2", "WESTRING_BRUSH_PLATEAU,ReplaceableTextures\\WorldEditUI\\HeightBrush01"),
		_parse_brush_entry("3", "WESTRING_BRUSH_NOISE,ReplaceableTextures\\WorldEditUI\\HeightBrush03"),
		_parse_brush_entry("4", "WESTRING_BRUSH_SMOOTH,ReplaceableTextures\\WorldEditUI\\HeightBrush02"),
	]
	misc_brushes = {
		"Blight": _parse_brush_entry("Blight", "WESTRING_BLIGHT,TerrainArt\\Blight\\Lords_Blight"),
		"Nothing": _parse_brush_entry("Nothing", "WESTRING_NOTHINGTILE,ReplaceableTextures\\WorldEditUI\\BoundaryPlace"),
		"Unnothing": _parse_brush_entry("Unnothing", "WESTRING_REMOVENOTHINGTILE,ReplaceableTextures\\WorldEditUI\\BoundaryRemove"),
	}
	_apply_category_fallback()


func _apply_category_fallback() -> void:
	if doodad_categories.is_empty():
		doodad_categories = [
			_parse_brush_entry("O", "WESTRING_DTYPE_PROPS,ReplaceableTextures\\WorldEditUI\\Doodad-Prop"),
			_parse_brush_entry("S", "WESTRING_DTYPE_STRUCTURES,ReplaceableTextures\\WorldEditUI\\Doodad-Structures"),
			_parse_brush_entry("W", "WESTRING_DTYPE_WATER,ReplaceableTextures\\WorldEditUI\\Doodad-Water"),
			_parse_brush_entry("C", "WESTRING_DTYPE_CLIFF,ReplaceableTextures\\WorldEditUI\\Doodad-Cliff"),
			_parse_brush_entry("E", "WESTRING_DTYPE_ENVIRONMENT,ReplaceableTextures\\WorldEditUI\\Doodad-Environment"),
			_parse_brush_entry("Z", "WESTRING_DTYPE_CINEMATIC,ReplaceableTextures\\WorldEditUI\\Doodad-Cinematic"),
		]
	if destructible_categories.is_empty():
		destructible_categories = [
			_parse_brush_entry("D", "WESTRING_DTYPE_DESTRUCTABLE,ReplaceableTextures\\WorldEditUI\\Doodad-Destructible"),
			_parse_brush_entry("P", "WESTRING_DTYPE_PATHING,ReplaceableTextures\\WorldEditUI\\Doodad-Destructible"),
			_parse_brush_entry("B", "WESTRING_DTYPE_BRIDGE,ReplaceableTextures\\WorldEditUI\\Doodad-Bridge"),
		]
