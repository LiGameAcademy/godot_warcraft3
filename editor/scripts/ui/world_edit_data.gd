extends RefCounted
## 解析经典编辑器 `UI/WorldEditData.txt`（地形集、地图尺寸档、默认值）。
##
## 解析顺序（AssetProvider / RuntimeAssets）：
##   1. `assets/asset-converted/UI/WorldEditData.txt`（推荐：sync-editor-assets 同步）
##   2. `.cache/wc3-assets/UI/WorldEditData.txt`（MPQ 解包缓存）
## 同步命令：`node tools/sync-editor-assets.mjs`
## 找不到时用脚本内置回退表，新建地图对话框仍可工作。


const LOGICAL_PATH := "UI/WorldEditData.txt"
const CAMERA_BORDER := 6 ## 每侧镜头边距格数 → 可用区域 = 尺寸 - 12

var tilesets: Array = [] ## { id, name_key, blight }
var map_size_tiers: Array = [] ## { max_area, name_key } 升序
var default_map_size: Vector2i = Vector2i(64, 64)
var min_map_size: int = 64
var max_map_size: int = 256
var default_tileset: String = "L"


static func load_default():
	var d = (load("res://editor/scripts/ui/world_edit_data.gd") as GDScript).new()
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
	var border := CAMERA_BORDER * 2
	return Vector2i(maxi(map_w - border, 0), maxi(map_h - border, 0))


func size_desc_key(map_w: int, map_h: int) -> String:
	var area: int = map_w * map_h
	for tier in map_size_tiers:
		if area <= int(tier["max_area"]):
			return str(tier["name_key"])
	if map_size_tiers.is_empty():
		return "WESTRING_MAPSIZE_TINY"
	return str(map_size_tiers[map_size_tiers.size() - 1]["name_key"])


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


func _resolve(logical: String) -> String:
	var abs_path := RuntimeAssets.resolve(logical)
	if not abs_path.is_empty():
		return abs_path
	var guess := ProjectSettings.globalize_path("res://").path_join(".cache/wc3-assets").path_join(logical)
	if FileAccess.file_exists(guess):
		return guess
	return ""


func _apply_fallback() -> void:
	tilesets = [
		{"id": "L", "name_key": "WESTRING_LOCALE_LORDAERON_SUMMER", "blight": ""},
		{"id": "F", "name_key": "WESTRING_LOCALE_LORDAERON_FALL", "blight": ""},
		{"id": "W", "name_key": "WESTRING_LOCALE_LORDAERON_WINTER", "blight": ""},
		{"id": "B", "name_key": "WESTRING_LOCALE_BARRENS", "blight": ""},
		{"id": "A", "name_key": "WESTRING_LOCALE_ASHENVALE", "blight": ""},
		{"id": "C", "name_key": "WESTRING_LOCALE_FELWOOD", "blight": ""},
		{"id": "N", "name_key": "WESTRING_LOCALE_NORTHREND", "blight": ""},
		{"id": "Y", "name_key": "WESTRING_LOCALE_CITYSCAPE", "blight": ""},
		{"id": "X", "name_key": "WESTRING_LOCALE_DALARAN", "blight": ""},
		{"id": "V", "name_key": "WESTRING_LOCALE_VILLAGE", "blight": ""},
		{"id": "Q", "name_key": "WESTRING_LOCALE_VILLAGEFALL", "blight": ""},
		{"id": "D", "name_key": "WESTRING_LOCALE_DUNGEON", "blight": ""},
		{"id": "G", "name_key": "WESTRING_LOCALE_DUNGEON2", "blight": ""},
		{"id": "Z", "name_key": "WESTRING_LOCALE_RUINS", "blight": ""},
		{"id": "I", "name_key": "WESTRING_LOCALE_ICECROWN", "blight": ""},
		{"id": "O", "name_key": "WESTRING_LOCALE_OUTLAND", "blight": ""},
		{"id": "K", "name_key": "WESTRING_LOCALE_BLACKCITADEL", "blight": ""},
		{"id": "J", "name_key": "WESTRING_LOCALE_DALARANRUINS", "blight": ""},
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
