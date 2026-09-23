class_name AppLog
extends Object

## 全项目调试日志：分层 + 彩色 print_rich + 配置开关。
## 配置：res://game/config/debug_log.json（可被 user://debug_log.json 覆盖）
## 用法：AppLog.info(AppLog.Layer.PRESENT, "Terrain", "gaps=%d" % n)

enum Layer { DATA, CATALOG, LOGIC, PRESENT, EDITOR, LOAD, GAME, GM }
enum Level { DEBUG, INFO, WARN, ERROR }

const CONFIG_RES := "res://game/config/debug_log.json"
const CONFIG_USER := "user://debug_log.json"

## 低于此级别的日志不输出。默认 WARN：安静模式；细查时改 debug_log.json → DEBUG。
static var min_level: Level = Level.WARN
## layer_name → bool
static var _layer_on: Dictionary = {}
static var _config_loaded: bool = false


## 热路径拼字符串前先问：避免 `%` 格式化白干。
static func enabled(level: Level, layer: Layer = Layer.PRESENT) -> bool:
	_ensure_config()
	return int(level) >= int(min_level) and _layer_enabled(layer)


## 调试日志
static func debug(layer: Layer, tag: String, msg: String) -> void:
	_emit(Level.DEBUG, layer, tag, msg)


## 信息日志
static func info(layer: Layer, tag: String, msg: String) -> void:
	_emit(Level.INFO, layer, tag, msg)


## 警告日志
static func warn(layer: Layer, tag: String, msg: String) -> void:
	if not enabled(Level.WARN, layer):
		return
	_emit(Level.WARN, layer, tag, msg)
	push_warning("[%s/%s] %s" % [_layer_name(layer), tag, msg])


## 错误日志
static func error(layer: Layer, tag: String, msg: String) -> void:
	_emit(Level.ERROR, layer, tag, msg)
	push_error("[%s/%s] %s" % [_layer_name(layer), tag, msg])


static func reload_config() -> void:
	_config_loaded = false
	_ensure_config()


static func set_layer_enabled(layer: Layer, on: bool) -> void:
	_ensure_config()
	_layer_on[_layer_name(layer)] = on


static func is_layer_enabled(layer: Layer) -> bool:
	_ensure_config()
	return _layer_enabled(layer)


static func _emit(level: Level, layer: Layer, tag: String, msg: String) -> void:
	if not enabled(level, layer):
		return
	print_rich(
		"[color=%s][%s][/color][color=%s][%s][/color] [color=%s]%s[/color] %s"
		% [
			_level_color(level),
			_level_name(level),
			_layer_color(layer),
			_layer_name(layer),
			"#c8c8c8",
			tag,
			msg,
		]
	)


static func _layer_enabled(layer: Layer) -> bool:
	var key := _layer_name(layer)
	if _layer_on.has(key):
		return bool(_layer_on[key])
	return true


static func _ensure_config() -> void:
	if _config_loaded:
		return
	_config_loaded = true
	_layer_on = {
		"DATA": true,
		"CATALOG": true,
		"LOGIC": true,
		"PRESENT": true,
		"EDITOR": true,
		"LOAD": true,
		"GAME": true,
		"GM": true,
	}
	_apply_config_file(str(ProjectSettings.get_setting("warcraft3/log_config", CONFIG_RES)))
	_apply_config_file(CONFIG_USER)


static func _apply_config_file(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	# 勿用 get_file_as_string：含 NUL 的误读会刷引擎 Unicode ERROR。
	var text := _read_utf8_safe(path)
	if text.is_empty():
		return
	# 去 BOM / NUL 转义
	if text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	# _read_utf8_safe 已拒绝 NUL；不要构造非法的 NUL 字符串。
	var data: Variant = JSON.parse_string(text.replace("\\u0000", ""))
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	var ml := str(d.get("min_level", "")).strip_edges().to_upper()
	match ml:
		"DEBUG":
			min_level = Level.DEBUG
		"INFO":
			min_level = Level.INFO
		"WARN", "WARNING":
			min_level = Level.WARN
		"ERROR":
			min_level = Level.ERROR
	var layers: Variant = d.get("layers", {})
	if typeof(layers) == TYPE_DICTIONARY:
		for k in (layers as Dictionary).keys():
			_layer_on[str(k).to_upper()] = bool((layers as Dictionary)[k])


static func _read_utf8_safe(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	for i in range(bytes.size()):
		if bytes[i] == 0:
			return ""
	# 简单 UTF-8 校验：遇非法则放弃，避免 get_string_from_utf8 刷 ERROR
	var i := 0
	var n := bytes.size()
	while i < n:
		var c := bytes[i]
		if c <= 0x7F:
			i += 1
			continue
		var need := 0
		if c >= 0xC2 and c <= 0xDF:
			need = 1
		elif c >= 0xE0 and c <= 0xEF:
			need = 2
		elif c >= 0xF0 and c <= 0xF4:
			need = 3
		else:
			return ""
		if i + need >= n:
			return ""
		for j in range(1, need + 1):
			var cc := bytes[i + j]
			if cc < 0x80 or cc > 0xBF:
				return ""
		i += need + 1
	return bytes.get_string_from_utf8()


static func _layer_name(layer: Layer) -> String:
	match layer:
		Layer.DATA:
			return "DATA"
		Layer.CATALOG:
			return "CATALOG"
		Layer.LOGIC:
			return "LOGIC"
		Layer.PRESENT:
			return "PRESENT"
		Layer.EDITOR:
			return "EDITOR"
		Layer.LOAD:
			return "LOAD"
		Layer.GAME:
			return "GAME"
		Layer.GM:
			return "GM"
		_:
			return "?"


static func _layer_color(layer: Layer) -> String:
	match layer:
		Layer.DATA:
			return "#6cb6ff"
		Layer.CATALOG:
			return "#c678dd"
		Layer.LOGIC:
			return "#e5c07b"
		Layer.PRESENT:
			return "#98c379"
		Layer.EDITOR:
			return "#56b6c2"
		Layer.LOAD:
			return "#61afef"
		Layer.GAME:
			return "#d19a66"
		Layer.GM:
			return "#e06c75"
		_:
			return "#aaaaaa"


static func _level_name(level: Level) -> String:
	match level:
		Level.DEBUG:
			return "DBG"
		Level.INFO:
			return "INF"
		Level.WARN:
			return "WRN"
		Level.ERROR:
			return "ERR"
		_:
			return "?"


static func _level_color(level: Level) -> String:
	match level:
		Level.DEBUG:
			return "#7f848e"
		Level.INFO:
			return "#abb2bf"
		Level.WARN:
			return "#e5c07b"
		Level.ERROR:
			return "#e06c75"
		_:
			return "#ffffff"
