class_name Wc3CliffTransCatalog
extends Resource

## CliffTrans / CityCliffTrans 模型目录（运行时扫盘，不检入 .tres 登记表）。
## 文件名：`{Family}{TAG}{variation}.glb`，TAG 四字角序为 TL → TR → BR → BL。
## 使用：`Wc3CliffTransCatalog.load_cliff_trans()` / `load_city_cliff_trans()`。
## 资源在 .gdignore 下，路径经 RuntimeAssets 解析磁盘。

const FAMILY_CLIFF_TRANS := "CliffTrans"
const FAMILY_CITY_CLIFF_TRANS := "CityCliffTrans"

## 文件名四字角序（与直崖 Cliffs 的 BL,TL,TR,BR 不同）。
const CORNER_TL := 0
const CORNER_TR := 1
const CORNER_BR := 2
const CORNER_BL := 3
const CORNER_NAMES: PackedStringArray = ["TL", "TR", "BR", "BL"]

## 单角合法字符。
const VALID_CHARS := "ABCHLX"

@export var family: String = FAMILY_CLIFF_TRANS
## tag（4 字）→ 已登记的变体号列表（升序）。例："AAHL" → [0]
@export var tag_variations: Dictionary = {}


## 从磁盘扫描 `Doodads/Terrain/{family}/` 并填充 tag_variations。
func rebuild_from_disk() -> int:
	tag_variations.clear()
	var rel_dir := "Doodads/Terrain/%s" % family
	var abs_dir := RuntimeAssets.project_abs(RuntimeAssets.converted_path(rel_dir))
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("Wc3CliffTransCatalog: 无法打开目录 %s" % abs_dir)
		return 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	var n := 0
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".gltf") or fname.ends_with(".glb")):
			var parsed: Dictionary = parse_basename(fname.get_basename())
			if bool(parsed.get("ok", false)) and str(parsed.get("family", "")) == family:
				var tag: String = str(parsed["tag"])
				var variation: int = int(parsed["variation"])
				_register_variation(tag, variation)
				n += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return n


func _register_variation(tag: String, variation: int) -> void:
	var arr: Array = tag_variations.get(tag, []) as Array
	if not arr.has(variation):
		arr.append(variation)
		arr.sort()
	tag_variations[tag] = arr


## 解析无扩展名基名，如 CliffTransAAHL0。
## 返回 { ok, family, tag, variation }。
static func parse_basename(basename: String) -> Dictionary:
	# Family 可能是 CliffTrans / CityCliffTrans
	var fam := ""
	var rest := ""
	if basename.begins_with(FAMILY_CITY_CLIFF_TRANS):
		fam = FAMILY_CITY_CLIFF_TRANS
		rest = basename.substr(FAMILY_CITY_CLIFF_TRANS.length())
	elif basename.begins_with(FAMILY_CLIFF_TRANS):
		fam = FAMILY_CLIFF_TRANS
		rest = basename.substr(FAMILY_CLIFF_TRANS.length())
	else:
		return {"ok": false}
	# rest = TAG + variation digits
	if rest.length() < 5:
		return {"ok": false}
	var tag := rest.substr(0, 4)
	var var_str := rest.substr(4)
	if not _is_valid_tag(tag):
		return {"ok": false}
	if not var_str.is_valid_int():
		return {"ok": false}
	return {
		"ok": true,
		"family": fam,
		"tag": tag,
		"variation": int(var_str),
	}


static func _is_valid_tag(tag: String) -> bool:
	if tag.length() != 4:
		return false
	for i in range(4):
		if VALID_CHARS.find(tag[i]) < 0:
			return false
	return true


## 四角状态 → TAG（顺序 TL, TR, BR, BL）。角可为单字符 String 或 StringName。
static func tag_from_corners(tl: String, tr: String, br: String, bl: String) -> String:
	var tag := (
		_normalize_char(tl)
		+ _normalize_char(tr)
		+ _normalize_char(br)
		+ _normalize_char(bl)
	)
	if not _is_valid_tag(tag):
		return ""
	return tag


## 数组版：corners[0..3] = TL,TR,BR,BL。
static func tag_from_corner_array(corners: Array) -> String:
	if corners.size() < 4:
		return ""
	return tag_from_corners(
		str(corners[0]), str(corners[1]), str(corners[2]), str(corners[3])
	)


static func _normalize_char(s: String) -> String:
	if s.is_empty():
		return ""
	return s.substr(0, 1).to_upper()


func has_tag(tag: String) -> bool:
	return tag_variations.has(tag) and not (tag_variations[tag] as Array).is_empty()


func list_tags() -> PackedStringArray:
	var keys: Array = tag_variations.keys()
	keys.sort()
	return PackedStringArray(keys)


func variations_for(tag: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not tag_variations.has(tag):
		return out
	for v in tag_variations[tag] as Array:
		out.append(int(v))
	return out


func max_variation(tag: String) -> int:
	var vs := variations_for(tag)
	if vs.is_empty():
		return -1
	return int(vs[vs.size() - 1])


## 夹到已登记变体；无登记时退回 0。
func clamp_variation(tag: String, variation: int) -> int:
	var vs := variations_for(tag)
	if vs.is_empty():
		return 0
	if vs.has(variation):
		return variation
	return int(vs[0])


## 逻辑文件名（无路径）：CliffTransAAHL0
func basename_for_tag(tag: String, variation: int = 0) -> String:
	if tag.length() != 4:
		return ""
	variation = clamp_variation(tag, variation)
	return "%s%s%d" % [family, tag, variation]


## res://assets/asset-converted/... 逻辑路径；优先 .gltf，回退 .glb。
func path_for_tag(tag: String, variation: int = 0) -> String:
	var base := basename_for_tag(tag, variation)
	if base.is_empty():
		return ""
	var stem := "Doodads/Terrain/%s/%s" % [family, base]
	var gltf := RuntimeAssets.converted_path(stem + ".gltf")
	if RuntimeAssets.file_exists(gltf):
		return gltf
	return RuntimeAssets.converted_path(stem + ".glb")


## 仅当目录中已登记（或磁盘存在）时返回路径，否则 ""。
func resolve_path_for_tag(tag: String, variation: int = 0) -> String:
	if not has_tag(tag) and not tag_variations.is_empty():
		# 已扫描过且无此 tag → 明确缺失
		return ""
	var path := path_for_tag(tag, variation)
	if path.is_empty():
		return ""
	if RuntimeAssets.file_exists(path):
		return path
	return ""


func path_for_corners(
	tl: String, tr: String, br: String, bl: String, variation: int = 0
) -> String:
	var tag := tag_from_corners(tl, tr, br, bl)
	if tag.is_empty():
		return ""
	return path_for_tag(tag, variation)


func resolve_path_for_corners(
	tl: String, tr: String, br: String, bl: String, variation: int = 0
) -> String:
	var tag := tag_from_corners(tl, tr, br, bl)
	if tag.is_empty():
		return ""
	return resolve_path_for_tag(tag, variation)


## 便捷：默认 CliffTrans 并扫描磁盘。
static func load_cliff_trans():
	var cat = new()
	cat.family = FAMILY_CLIFF_TRANS
	cat.rebuild_from_disk()
	return cat


static func load_city_cliff_trans():
	var cat = new()
	cat.family = FAMILY_CITY_CLIFF_TRANS
	cat.rebuild_from_disk()
	return cat
