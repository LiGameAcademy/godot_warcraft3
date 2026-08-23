extends Node
## 编辑器多语言门面：CSV（zh_CN / en）为主；中文下可用 WorldEditStrings 覆盖。
## 勿在 project.godot 注册 *.translation：二进制翻译资源会刷 Unicode NUL ERROR；
## 文案以 CSV + 本脚本 _tables 为准，TranslationServer 仅同步 locale 字符串。
## MPQ 文案：`assets/slk-exported/UI/`（经 AssetProvider：converted → slk-exported）。
## 同步：`node tools/sync-data-assets.mjs`


signal locale_changed(locale: String)

const CSV_PATH := "res://editor/locale/editor_strings.csv"
const ZH_NAME_SORT_PATH := "res://editor/locale/westring_name_sort_zh.json"
const CONFIG_PATH := "user://editor_locale.cfg"
const SUPPORTED := ["zh_CN", "en"]

var _mpq: Dictionary = {} ## WESTRING_* from classic client (optional)
var _tables: Dictionary = {} ## locale → { key → text }
var _zh_name_sort: Dictionary = {} ## WESTRING_DOOD_/DEST_ → 中文排序序号
var _locale: String = "zh_CN"


func _ready() -> void:
	_load_csv()
	_load_zh_name_sort()
	_load_mpq_overlay()
	var saved := _read_saved_locale()
	if not saved.is_empty():
		set_locale(saved, false)
	else:
		set_locale(_detect_default_locale(), false)


func get_locale() -> String:
	return _locale


func set_locale(locale: String, notify: bool = true) -> void:
	var loc := _normalize_locale(locale)
	if not SUPPORTED.has(loc):
		loc = "en"
	var changed := loc != _locale
	_locale = loc
	TranslationServer.set_locale(loc)
	_write_saved_locale(loc)
	if notify and changed:
		locale_changed.emit(loc)
	elif notify and not changed:
		# 再次点击同一语言也刷新一次 UI（避免「没反应」的错觉）
		locale_changed.emit(loc)


func t(key: String, args: Array = []) -> String:
	if key.is_empty():
		return ""
	var msg := strip_accel(_lookup(key))
	if args.size() > 0:
		return msg % args
	return msg


func label(key: String) -> String:
	return t("EDITOR_NEWMAP_LABEL_COLON", [t(key)])


## 地表贴图显示名：WESTRING_TILE_* + 不可建造后缀（Terrain.slk buildable=0）。
func tile_display_name(tiles, tile_id: String) -> String:
	var tid := str(tile_id)
	if tid.is_empty():
		return ""
	var name_str := tid
	if tiles != null:
		var key: String = str(tiles.name_key_for_tile_id(tid))
		if key.begins_with("WESTRING_"):
			name_str = t(key)
			if name_str == key:
				name_str = tid
		else:
			var raw: String = str(tiles.display_name_for_tile_id(tid))
			name_str = raw if not raw.is_empty() else tid
		if not tiles.is_buildable(tid):
			name_str = t("EDITOR_TILE_UNBUILDABLE_FMT", [name_str, t("WESTRING_UNBUILDABLE")])
	return name_str


## 去掉 Windows/WE 加速键标记：`&F` → 隐藏；`&&` → 字面 `&`。
func strip_accel(s: String) -> String:
	if s.find("&") < 0:
		return s
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "&":
			if i + 1 < s.length() and s[i + 1] == "&":
				out += "&"
				i += 2
			else:
				i += 1
		else:
			out += s[i]
			i += 1
	return out


func _lookup(key: String) -> String:
	# 经典 WE 面板文案：CSV 短标签优先（避免 GameStrings「洛丹伦的夏天」「圆周」等长文案）
	if _locale == "zh_CN" and _tables.has("zh_CN"):
		var zh_table: Dictionary = _tables["zh_CN"]
		if zh_table.has(key) and (
			key.begins_with("WESTRING_LOCALE_")
			or key.begins_with("WESTRING_BRUSH")
		):
			return str(zh_table[key])
	# 中文 + MPQ 官方文案（装饰物名等）
	if _locale == "zh_CN" and _mpq.has(key):
		var resolved := _resolve_mpq(key)
		if not resolved.is_empty() and not resolved.begins_with("WESTRING_"):
			return resolved
	# CSV 表（不依赖 TranslationServer 的 locale 匹配）
	if _tables.has(_locale):
		var table: Dictionary = _tables[_locale]
		if table.has(key):
			return str(table[key])
	if _locale != "en" and _tables.has("en"):
		var en_table: Dictionary = _tables["en"]
		if en_table.has(key):
			return str(en_table[key])
	return key


## 中文面板排序键（与经典中文 WE 列表顺序一致）；英文返回 -1 由调用方按显示名比。
func placeable_sort_index(name_key: String) -> int:
	if _locale != "zh_CN" or name_key.is_empty():
		return -1
	if _zh_name_sort.has(name_key):
		return int(_zh_name_sort[name_key])
	return -1


func _load_zh_name_sort() -> void:
	_zh_name_sort.clear()
	if not FileAccess.file_exists(ZH_NAME_SORT_PATH):
		return
	var text := RuntimeAssets.read_utf8_text(ZH_NAME_SORT_PATH)
	if text.is_empty():
		return
	var parsed: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_zh_name_sort = parsed as Dictionary


func _resolve_mpq(key: String) -> String:
	var cur := key
	for _i in range(4):
		if not _mpq.has(cur):
			return cur
		var v := str(_mpq[cur])
		if v.begins_with("WESTRING_"):
			cur = v
			continue
		return v
	return cur


func _load_csv() -> void:
	_tables.clear()
	if not FileAccess.file_exists(CSV_PATH):
		push_warning("EditorI18n: missing %s" % CSV_PATH)
		return
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		return
	var header := _parse_csv_line(f.get_line())
	if header.size() < 2 or header[0] != "keys":
		push_warning("EditorI18n: bad CSV header")
		return
	var locale_cols: Array[String] = []
	for i in range(1, header.size()):
		var loc := str(header[i])
		locale_cols.append(loc)
		_tables[loc] = {}
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges().is_empty():
			continue
		var cols := _parse_csv_line(line)
		if cols.is_empty():
			continue
		var key := cols[0]
		for i in range(locale_cols.size()):
			var loc: String = locale_cols[i]
			var val := cols[i + 1] if i + 1 < cols.size() else key
			(_tables[loc] as Dictionary)[key] = val


func _parse_csv_line(line: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var cur := ""
	var in_quotes := false
	var i := 0
	while i < line.length():
		var ch := line[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					cur += "\""
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			cur += ch
			i += 1
			continue
		if ch == "\"":
			in_quotes = true
			i += 1
			continue
		if ch == ",":
			out.append(cur)
			cur = ""
			i += 1
			continue
		cur += ch
		i += 1
	out.append(cur)
	return out


func _load_mpq_overlay() -> void:
	_mpq.clear()
	_merge_mpq_file("UI/WorldEditStrings.txt")
	_merge_mpq_file("UI/WorldEditGameStrings.txt")


func _merge_mpq_file(logical: String) -> void:
	# 仅 assets/slk-exported（或 converted）；不回退 .cache
	var abs_path := RuntimeAssets.resolve(logical)
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		return
	var text := RuntimeAssets.read_utf8_text(abs_path)
	if text.is_empty():
		return
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.is_empty() or s.begins_with("//") or s.begins_with("["):
			continue
		var eq := s.find("=")
		if eq <= 0:
			continue
		var k := s.substr(0, eq).strip_edges()
		var v := s.substr(eq + 1).strip_edges()
		if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
			v = v.substr(1, v.length() - 2)
		_mpq[k] = v


func _detect_default_locale() -> String:
	var os_loc := OS.get_locale()
	if os_loc.begins_with("zh"):
		return "zh_CN"
	return "en"


func _normalize_locale(locale: String) -> String:
	var loc := locale.strip_edges()
	if loc.begins_with("zh"):
		return "zh_CN"
	if loc.begins_with("en"):
		return "en"
	return loc


func _read_saved_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return ""
	return str(cfg.get_value("i18n", "locale", ""))


func _write_saved_locale(locale: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("i18n", "locale", locale)
	cfg.save(CONFIG_PATH)
