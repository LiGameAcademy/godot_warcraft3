extends RefCounted

## Model/portrait path resolution from explicit catalog row data.

static func model_base_path(info: Dictionary) -> String:
	var file: String = str(info.get("file", "")).replace("\\", "/")
	if file.is_empty() or file == "_":
		return ""
	if file.to_lower().ends_with(".mdx") or file.to_lower().ends_with(".mdl"):
		file = file.substr(0, file.length() - 4)
	return file


## UnitUI.fileVerFlags（0 = 仅基模；非 0 = 有 expansion 变体如 _V1）。
static func model_file_ver_flags(info: Dictionary) -> int:
	return int(info.get("file_ver_flags", 0))


## 按内容包 Edition 解析模型 stem（可含 _V1）；再交给 converted_glb_path 拼 variation。
## 见 docs/data/CONTENT_PACKS.md · ContentPackRules。
static func resolve_model_stem(info: Dictionary) -> String:
	var base: String = model_base_path(info)
	if base.is_empty():
		return ""
	var flags: int = model_file_ver_flags(info)
	for stem: String in ContentPackRules.expansion_model_candidates(base, flags):
		if _converted_stem_exists(stem):
			return stem
	return base


static func _converted_stem_exists(stem: String) -> bool:
	if stem.is_empty():
		return false
	for ext: String in [".gltf", ".glb", ".scn"]:
		var p: String = RuntimeAssets.converted_path(stem + ext)
		if RuntimeAssets.file_exists(p):
			return true
	return false


## 解析已转换模型（优先 .gltf 外链贴图，回退旧 .glb）。
## 先按 ContentPackRules 选 Edition stem，再拼地图 variation 数字后缀。
static func converted_glb_path(info: Dictionary, variation: int = 0) -> String:
	var base: String = resolve_model_stem(info)
	if base.is_empty():
		return ""
	var stems: PackedStringArray = []
	if variation > 0:
		stems.append("%s%d" % [base, variation])
	stems.append(base)
	stems.append("%s0" % base)
	for stem: String in stems:
		for ext: String in [".gltf", ".glb"]:
			var p: String = RuntimeAssets.converted_path(stem + ext)
			if RuntimeAssets.file_exists(p):
				return p
	return _scan_converted_model_file(base, variation)


## 目录扫描：SLK 路径大小写 / AltarofKings vs AltarOfKings 与磁盘不一致时兜底。
static func _scan_converted_model_file(base: String, variation: int = 0) -> String:
	var dir_logical: String = base.get_base_dir()
	var stem_want: String = base.get_file().to_lower()
	var disk_dir: String = _resolve_converted_dir(dir_logical)
	if disk_dir.is_empty():
		return ""
	var da: DirAccess = DirAccess.open(disk_dir)
	if da == null:
		return ""
	var want_var: String = str(variation) if variation > 0 else ""
	var found_plain: String = ""
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = da.get_next()
			continue
		var lower: String = fname.to_lower()
		if not (lower.ends_with(".gltf") or lower.ends_with(".glb")):
			fname = da.get_next()
			continue
		var file_stem: String = lower.get_basename()
		if file_stem == stem_want or file_stem == stem_want + "0":
			da.list_dir_end()
			return RuntimeAssets.converted_path("%s/%s" % [dir_logical, fname])
		if want_var.is_empty() and file_stem.begins_with(stem_want):
			found_plain = fname
		elif not want_var.is_empty() and file_stem == stem_want + want_var:
			da.list_dir_end()
			return RuntimeAssets.converted_path("%s/%s" % [dir_logical, fname])
		fname = da.get_next()
	da.list_dir_end()
	if not found_plain.is_empty():
		return RuntimeAssets.converted_path("%s/%s" % [dir_logical, found_plain])
	return ""


static func _resolve_converted_dir(dir_logical: String) -> String:
	var direct: String = RuntimeAssets.project_abs(RuntimeAssets.converted_path(dir_logical))
	if not direct.is_empty() and DirAccess.dir_exists_absolute(direct):
		return direct
	# 在 Buildings/* / Units/* 下按末级目录名大小写无关匹配
	var leaf: String = dir_logical.get_file().to_lower()
	if leaf.is_empty():
		return ""
	for root: String in ["Buildings", "Units", "buildings", "units"]:
		var root_abs: String = RuntimeAssets.project_abs(RuntimeAssets.converted_path(root))
		if root_abs.is_empty() or not DirAccess.dir_exists_absolute(root_abs):
			continue
		var root_da: DirAccess = DirAccess.open(root_abs)
		if root_da == null:
			continue
		root_da.list_dir_begin()
		var race: String = root_da.get_next()
		while race != "":
			if race.begins_with("."):
				race = root_da.get_next()
				continue
			var race_path: String = "%s/%s" % [root, race]
			var race_abs: String = RuntimeAssets.project_abs(RuntimeAssets.converted_path(race_path))
			if DirAccess.dir_exists_absolute(race_abs):
				var race_da: DirAccess = DirAccess.open(race_abs)
				if race_da != null:
					race_da.list_dir_begin()
					var folder: String = race_da.get_next()
					while folder != "":
						if folder.begins_with("."):
							folder = race_da.get_next()
							continue
						if folder.to_lower() == leaf:
							race_da.list_dir_end()
							root_da.list_dir_end()
							return RuntimeAssets.project_abs(
								RuntimeAssets.converted_path("%s/%s" % [race_path, folder])
							)
						folder = race_da.get_next()
					race_da.list_dir_end()
			race = root_da.get_next()
		root_da.list_dir_end()
	return ""


## 肖像模型路径（*_Portrait / *_portrait）；无则空串。
## 与 body 共用 resolve_model_stem（TFT 下 Priest → Priest_V1_portrait）。
static func portrait_glb_path(info: Dictionary) -> String:
	var base: String = resolve_model_stem(info)
	if base.is_empty():
		return ""
	var dir: String = base.get_base_dir()
	var stem: String = base.get_file()
	var stems: PackedStringArray = [
		"%s/%s_Portrait" % [dir, stem],
		"%s/%s_portrait" % [dir, stem],
	]
	# 常见大小写变体（Peasant vs peasant）
	if stem != stem.to_lower():
		stems.append("%s/%s_Portrait" % [dir, stem.to_lower()])
		stems.append("%s/%s_portrait" % [dir, stem.to_lower()])
	for s: String in stems:
		for ext: String in [".gltf", ".glb"]:
			var p: String = RuntimeAssets.converted_path(s + ext)
			if RuntimeAssets.file_exists(p):
				return p
	# 目录扫描兜底（大小写不一致时）
	var disk_dir: String = _resolve_converted_dir(dir)
	if disk_dir.is_empty():
		return ""
	var da: DirAccess = DirAccess.open(disk_dir)
	if da == null:
		return ""
	da.list_dir_begin()
	var fname: String = da.get_next()
	var want: String = stem.to_lower()
	while fname != "":
		var lower: String = fname.to_lower()
		if lower.ends_with("_portrait.gltf") or lower.ends_with("_portrait.glb"):
			var name_stem: String = lower.get_basename().trim_suffix("_portrait")
			# 精确匹配 stem（含 _V1）；勿用 begins_with，避免 Priest 误吃 Priest_V1_portrait
			if name_stem == want:
				var rel: String = "%s/%s" % [dir, fname]
				var found: String = RuntimeAssets.converted_path(rel)
				if RuntimeAssets.file_exists(found):
					da.list_dir_end()
					return found
		fname = da.get_next()
	da.list_dir_end()
	return ""


