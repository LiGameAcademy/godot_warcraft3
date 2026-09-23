class_name Wc3CliffCatalog
extends RefCounted

## 直崖 Catalog：CliffTypeDef（表列）+ 岩壁 PNG / Cliffs GLB 变体解析（资源映射）。
## 与 Wc3TerrainTileCatalog（地表）分离；斜坡目录见 ramp_model_dir + Wc3CliffTransCatalog。
## 变体上限不写死表：按磁盘探测 Cliffs{TAG}{n}.glb，结果缓存。

const VAR_PROBE_MAX := 8 ## WE 直崖变体通常 ≤3；探测上限留余量

## 仅缓存解析后的岩壁贴图路径
var _cliff_to_png: Dictionary[String, String] = {}
## "modelDir/TAG" → 该 TAG 最大变体下标（无文件则为 -1）
var _var_max_cache: Dictionary[String, int] = {}
## modelDir → PackedStringArray(TAG…)
var _tags_cache: Dictionary[String, PackedStringArray] = {}


func load_default() -> void:
	_cliff_to_png.clear()
	_var_max_cache.clear()
	_tags_cache.clear()
	_rebuild_cliff_png_cache()


## 悬崖类型：cliffID 第 2 字符为地形集字母（如 CLdi → L）。
func cliff_ids_for_tileset(tileset_letter: String) -> PackedStringArray:
	var letter := tileset_letter.strip_edges().to_upper()
	var store := _def_store()
	if store == null:
		return PackedStringArray()
	return store.find_ids(
		CliffTypeDef.TABLE_NAME,
		func(_id: String, row: Resource) -> bool:
			var d := row as CliffTypeDef
			return d != null and d.get_tileset_letter() == letter
	)


func png_for_cliff_id(cliff_id: String) -> String:
	return str(_cliff_to_png.get(cliff_id, ""))


func ground_tile_for_cliff_id(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.ground_tile if d != null else ""


func cliff_model_dir(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.cliff_model_dir if d != null else "Cliffs"


func ramp_model_dir(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.ramp_model_dir if d != null else "CliffTrans"


func png_for_cliff_index(cliff_tilesets: Array, index: int) -> String:
	if index < 0 or index >= cliff_tilesets.size():
		return ""
	return png_for_cliff_id(str(cliff_tilesets[index]))


## 表行：DefStore → CliffTypeDef。
func get_def(cliff_id: String) -> CliffTypeDef:
	return _cliff_def(cliff_id)


## —— 资源映射：Cliffs / CityCliffs 模型（优先 .gltf）——

static func glb_path(model_dir: String, tag: String, variation: int) -> String:
	var stem := "Doodads/Terrain/%s/%s%s%d" % [model_dir, model_dir, tag, variation]
	var gltf := RuntimeAssets.converted_path(stem + ".gltf")
	if RuntimeAssets.file_exists(gltf):
		return gltf
	return RuntimeAssets.converted_path(stem + ".glb")


## 该 TAG 磁盘上最大变体下标；无任何文件返回 -1。
func max_variation(model_dir: String, tag: String) -> int:
	if model_dir == "CliffTrans" or model_dir == "CityCliffTrans":
		return 0 if RuntimeAssets.file_exists(glb_path(model_dir, tag, 0)) else -1
	var key := "%s/%s" % [model_dir, tag]
	if _var_max_cache.has(key):
		return int(_var_max_cache[key])
	var max_v := -1
	for v in range(VAR_PROBE_MAX):
		if RuntimeAssets.file_exists(glb_path(model_dir, tag, v)):
			max_v = v
		elif max_v >= 0:
			break
	_var_max_cache[key] = max_v
	return max_v


func clamp_variation(model_dir: String, tag: String, variation: int) -> int:
	if model_dir == "CliffTrans" or model_dir == "CityCliffTrans":
		return 0
	var max_v: int = max_variation(model_dir, tag)
	if max_v < 0:
		return 0
	return mini(maxi(variation, 0), max_v)


## 直崖变体选型（Catalog / 资源映射层）。
## W3E cliff_variation 为 0–7；0 也是合法变体（不是「未赋值」）。
## 挂模：夹紧存盘值。真随机由笔刷写入 cliffVariations（random_variation_byte）。
func pick_cliff_variation(
	model_dir: String, tag: String, stored: int, _ix: int = 0, _iy: int = 0
) -> int:
	var max_v: int = max_variation(model_dir, tag)
	if max_v <= 0:
		return 0
	return clampi(stored, 0, max_v)


## 笔刷落盘：在已知 TAG 时从 [0..max] 均匀随机。
func random_variation(model_dir: String, tag: String) -> int:
	var max_v: int = max_variation(model_dir, tag)
	if max_v <= 0:
		return 0
	return randi() % (max_v + 1)


## 笔刷落盘：W3E 角点 3bit 变体字段（0–7），挂模时再按 TAG clamp。
static func random_variation_byte() -> int:
	return randi() % 8


## 稳定空间哈希（调试/迁移用；主路径用存盘随机，避免同墙 010101 条纹）。
func spatial_variation(model_dir: String, tag: String, ix: int, iy: int) -> int:
	var max_v: int = max_variation(model_dir, tag)
	if max_v <= 0:
		return 0
	# 充分混合，减轻相邻 ix 对 max_v=1 时的严格交替
	var h: int = ix * 0x9e3779b1
	h = (h ^ (h >> 16)) * 0x85ebca6b
	h = h ^ (iy * 0xc2b2ae35)
	h = (h ^ (h >> 13)) * 0x27d4eb2d
	h = h ^ tag.hash()
	return absi(h) % (max_v + 1)


## cliffTilesets 下标 → groundTilesets 下标；无映射为 -1。
func build_cliff_to_ground_map(cliff_tilesets: Array, ground_tilesets: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(cliff_tilesets.size())
	out.fill(-1)
	for i in range(cliff_tilesets.size()):
		var ground_id := ground_tile_for_cliff_id(str(cliff_tilesets[i]))
		if ground_id.is_empty():
			continue
		for gi in range(ground_tilesets.size()):
			if str(ground_tilesets[gi]) == ground_id:
				out[i] = gi
				break
	return out


func resolve_glb(model_dir: String, tag: String, variation: int) -> String:
	if tag.is_empty():
		return ""
	variation = clamp_variation(model_dir, tag, variation)
	var path := glb_path(model_dir, tag, variation)
	if RuntimeAssets.file_exists(path):
		return path
	path = glb_path(model_dir, tag, 0)
	if RuntimeAssets.file_exists(path):
		return path
	if model_dir == "CityCliffTrans":
		return resolve_glb("CliffTrans", tag, variation)
	return ""


## 扫描 converted 目录得到该 modelDir 下全部 TAG（供自测 / 调试）。
func list_model_tags(model_dir: String) -> PackedStringArray:
	if _tags_cache.has(model_dir):
		return _tags_cache[model_dir]
	var found: Dictionary = {}
	var prefix := model_dir
	var dir_rel := "Doodads/Terrain/%s" % model_dir
	var abs_dir := RuntimeAssets.project_abs(RuntimeAssets.converted_path(dir_rel))
	var da := DirAccess.open(abs_dir)
	if da != null:
		da.list_dir_begin()
		var fname := da.get_next()
		while fname != "":
			if not da.current_is_dir() and fname.begins_with(prefix) and (fname.ends_with(".gltf") or fname.ends_with(".glb")):
				var stem := fname.get_basename().substr(prefix.length())
				# stem = TAG + variationDigit(s)；TAG 恒 4 字符 A–C
				if stem.length() >= 5:
					var tag := stem.substr(0, 4)
					if _is_cliff_tag(tag):
						found[tag] = true
			fname = da.get_next()
		da.list_dir_end()
	var out := PackedStringArray()
	for t in found.keys():
		out.append(str(t))
	out.sort()
	_tags_cache[model_dir] = out
	return out


static func _is_cliff_tag(tag: String) -> bool:
	if tag.length() != 4:
		return false
	for i in range(4):
		var c := tag.unicode_at(i)
		if c < 65 or c > 67: # A–C
			return false
	return true


## —— 资源映射：Def 列 → converted PNG ——

func _rebuild_cliff_png_cache() -> void:
	var store := _def_store()
	if store == null:
		AppLog.warn(AppLog.Layer.CATALOG, "CliffCatalog", "DefStore 不可用，无法解析悬崖贴图")
		return
	store.ensure_table(CliffTypeDef.TABLE_NAME)
	for id in store.get_ids(CliffTypeDef.TABLE_NAME):
		var d: CliffTypeDef = store.get_row(CliffTypeDef.TABLE_NAME, id) as CliffTypeDef
		if d == null or d.tex_dir.is_empty() or d.tex_file.is_empty():
			AppLog.warn(AppLog.Layer.CATALOG, "CliffCatalog", "悬崖类型定义不可用，无法解析悬崖贴图：%s" % id)
			continue
		_cliff_to_png[id] = resolve_cliff_png(d.tex_dir, d.tex_file, id)
	AppLog.debug(
		AppLog.Layer.CATALOG,
		"CliffCatalog",
		"cliff png cache count=%d" % _cliff_to_png.size()
	)


func _cliff_def(cliff_id: String) -> CliffTypeDef:
	var store := _def_store()
	if store == null:
		return null
	return store.get_row(CliffTypeDef.TABLE_NAME, cliff_id) as CliffTypeDef


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## cliffID 如 CIsn → 优先 I_Cliff1.png；缺则按 tileset 回退。
static func resolve_cliff_png(dir: String, tex_file: String, cliff_id: String) -> String:
	var tileset := ""
	if cliff_id.length() >= 2:
		tileset = cliff_id.substr(1, 1).to_upper()
	var alt := tileset_texture_fallback(tileset)
	var candidates: Array[String] = []
	for ts in [tileset, alt]:
		if ts.is_empty():
			continue
		candidates.append("%s/%s_%s.png" % [dir, ts, tex_file])
		candidates.append("%s/%s_%s.png" % [dir, ts, tex_file.to_lower()])
		candidates.append("%s/%s%s.png" % [dir, ts, tex_file])
	candidates.append("%s/%s.png" % [dir, tex_file])
	candidates.append("%s/%s.png" % [dir, tex_file.to_lower()])
	for c in candidates:
		var res_path := RuntimeAssets.converted_path(c)
		if RuntimeAssets.file_exists(res_path):
			return res_path
	return RuntimeAssets.converted_path(candidates[candidates.size() - 1])


## 地形集贴图字母回退（无独立 MPQ 前缀时）。崖壁/水面帧共用。
static func tileset_texture_fallback(tileset: String) -> String:
	match tileset:
		"I":
			return "N" # Icecrown → Northrend
		"L":
			return "" # 走无前缀 Cliff0/1
		_:
			return ""
