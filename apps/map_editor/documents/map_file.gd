extends RefCounted
## One versioned editor document. Never writes into the imported map directory.
const FORMAT := "godot-wc3-map"
const VERSION := 1


static func read_map_dir(directory: String) -> Dictionary:
	directory = ContentPaths.resolve(directory)
	var data := {"format": FORMAT, "version": VERSION,
		"source": {"name": directory.get_file(), "directory": directory}}
	var warnings: Array[String] = []
	var files := {"terrain": "terrain-heightfield.json", "units": "units.json",
		"doodads": "doodads.json", "info": "info.json", "pathing": "pathing.json"}
	for key in files:
		var path: String = directory.path_join(files[key])
		if key == "pathing" and not FileAccess.file_exists(path):
			data[key] = null
			warnings.append("缺少 pathing.json：编辑器将根据地形合成寻路网格，原始寻路限制无法还原。")
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {"error": FileAccess.get_open_error(), "message": "无法读取地图数据：" + path}
		var json := JSON.new()
		if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
			return {"error": ERR_PARSE_ERROR, "message": "地图数据格式无效：" + path}
		data[key] = json.data
	var problem := validate(data)
	if not problem.is_empty():
		return {"error": ERR_INVALID_DATA, "message": directory + "：" + problem}
	return {"error": OK, "data": data, "warnings": warnings}


static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "message": "无法读取地图：" + path}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"error": ERR_PARSE_ERROR, "message": "地图 JSON 无效：" + json.get_error_message()}
	var problem := validate(json.data)
	if not problem.is_empty():
		return {"error": ERR_INVALID_DATA, "message": problem}
	return {"error": OK, "data": json.data}


static func write(path: String, data: Dictionary) -> Error:
	if not validate(data).is_empty():
		return ERR_INVALID_DATA
	var destination := ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if err != OK:
		return err
	# Same-directory rename commits only a completely written document.
	var temporary := destination + ".tmp-" + str(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	err = file.get_error()
	file.close()
	if err == OK:
		err = DirAccess.rename_absolute(temporary, destination)
	if err != OK:
		DirAccess.remove_absolute(temporary)
	return err


static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "地图根节点必须是对象"
	var d: Dictionary = value
	if d.get("format") != FORMAT or d.get("version") != VERSION:
		return "不支持的地图格式或版本（需要 godot-wc3-map v1）"
	if d.has("importWarnings"):
		if not d.importWarnings is Array:
			return "导入警告字段无效"
		for warning in d.importWarnings:
			if not warning is String:
				return "导入警告条目无效"
	for key in ["terrain", "units", "doodads", "info"]:
		if not d.get(key) is Dictionary:
			return "地图缺少有效字段：" + key
	for key in ["playableWidth", "playableHeight"]:
		if d.info.has(key) and (not _integer(d.info[key]) or d.info[key] < 0):
			return "地图信息尺寸无效：" + key
	if d.info.has("cameraBoundsComplements"):
		var bounds: Variant = d.info.cameraBoundsComplements
		if not bounds is Dictionary:
			return "地图边界无效"
		for key in ["left", "right", "top", "bottom"]:
			if not _integer(bounds.get(key)) or bounds[key] < 0:
				return "地图边界数值无效：" + key
	var terrain: Dictionary = d.terrain
	for key in ["tilepointWidth", "tilepointHeight"]:
		if not _integer(terrain.get(key)) or terrain[key] < 3 or terrain[key] > 513:
			return "地图尺寸无效：" + key
	var count: int = int(terrain.tilepointWidth) * int(terrain.tilepointHeight)
	if terrain.get("mapWidth") != terrain.tilepointWidth - 1 or terrain.get("mapHeight") != terrain.tilepointHeight - 1:
		return "地图格尺寸与顶点数不一致"
	if terrain.has("cliffs") and not terrain.cliffs is Array:
		return "悬崖数组无效"
	for key in ["heights", "groundTextures", "groundVariations", "cliffVariations", "cliffTextures", "layerHeights", "waterHeights", "flagsPacked"]:
		if not terrain.get(key) is Array or terrain[key].size() != count:
			return "地形数组长度无效：" + key
		for number in terrain[key]:
			if not _number(number):
				return "地形数组包含无效数值：" + key
			if key not in ["heights", "waterHeights"] and not _integer(number):
				return "地形索引/标记必须为整数：" + key
	for key in ["groundTilesets", "cliffTilesets"]:
		if not terrain.get(key) is Array or terrain[key].is_empty():
			return "缺少地形材质目录：" + key
		for id in terrain[key]:
			if not id is String:
				return "材质 ID 必须是字符串"
	for index in terrain.groundTextures:
		if index < 0 or index >= terrain.groundTilesets.size():
			return "地表材质索引越界"
	if not _number(terrain.get("tileSize")) or terrain.tileSize <= 0:
		return "地形格尺寸无效"
	if not _vector(terrain.get("centerOffset"), ["x", "y"]):
		return "地形原点无效"
	for group in ["units", "doodads"]:
		var block: Dictionary = d[group]
		if not block.get(group) is Array:
			return "缺少对象数组：" + group
		var seen := {}
		for row in block[group]:
			if not row is Dictionary:
				return "对象记录无效：" + group
			var id_key := "typeId" if group == "units" else "id"
			if not row.get(id_key) is String or row[id_key].is_empty():
				return "对象缺少原始 ID"
			if not _integer(row.get("creationNumber")) or row.creationNumber < 0 or seen.has(row.creationNumber):
				return "对象实例编号无效或重复"
			seen[row.creationNumber] = true
			if not _vector(row.get("position"), ["x", "y", "z"]) or not _vector(row.get("scale"), ["x", "y", "z"]) or not _number(row.get("angle")):
				return "对象位置、缩放或朝向无效"
			for key in ["variation", "flags", "owner", "player", "life", "hitPoints", "manaPoints", "goldAmount", "heroLevel", "strength", "agility", "intelligence", "itemTablePtr", "customColor", "waygate", "targetAcquisition", "angleDegrees"]:
				if row.has(key) and not _number(row[key]):
					return "对象数值无效：" + key
			for key in ["inventory", "abilities", "droppedItemSets", "unknown"]:
				if row.has(key) and not row[key] is Array:
					return "对象列表无效：" + key
			if row.has("random") and not row.random is Dictionary:
				return "随机对象字段无效"
		for key in ["formatVersion", "subversion", "count", "_bytesRemaining"]:
			if block.has(key) and not _integer(block[key]):
				return "对象列表元数据无效：" + key
		if block.has("count") and block.count != block[group].size():
			return "对象数量与数组不一致"
		if block.has("specialDoodads") and not block.specialDoodads is Array:
			return "特殊装饰物列表无效"
	if d.get("pathing") != null:
		var p: Variant = d.pathing
		if not p is Dictionary:
			return "寻路数据无效"
		if not _integer(p.get("formatVersion")):
			return "寻路版本无效"
		for key in ["width", "height"]:
			if not _integer(p.get(key)) or p[key] <= 0 or p[key] > 2048:
				return "寻路尺寸无效"
		if not _number(p.get("cellSize")) or p.cellSize <= 0 or not _vector(p.get("origin"), ["x", "y"]):
			return "寻路原点或格尺寸无效"
		if not p.get("cellsBase64") is String or Marshalls.base64_to_raw(p.cellsBase64).size() != int(p.width) * int(p.height):
			return "寻路数组无效"
	return ""


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))


static func _vector(value: Variant, axes: Array) -> bool:
	if not value is Dictionary:
		return false
	for axis in axes:
		if not _number(value.get(axis)):
			return false
	return true


## Keep opaque fields alongside edited known fields, matching objects by stable ID.
static func merge(original: Dictionary, current: Dictionary) -> Dictionary:
	var result := original.duplicate(true)
	for key in current:
		if current[key] is Dictionary and result.get(key) is Dictionary:
			result[key] = merge(result[key], current[key])
		elif key in ["units", "doodads"] and current[key] is Array and result.get(key) is Array:
			var old := {}
			for row in result[key]:
				if row is Dictionary:
					old[int(row.get("creationNumber", -1))] = row
			var rows: Array = []
			for row in current[key]:
				rows.append(merge(old.get(int(row.get("creationNumber", -1)), {}), row))
			result[key] = rows
		else:
			result[key] = current[key]
	return result
