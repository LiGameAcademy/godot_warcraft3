class_name MapLog
extends Object

## 地图模块调试日志：分层 + 彩色 print_rich。
## 用法：MapLog.info(MapLog.Layer.PRESENT, "Terrain", "gaps=%d" % n)

enum Layer { DATA, CATALOG, LOGIC, PRESENT, EDITOR }
enum Level { DEBUG, INFO, WARN, ERROR }

## 低于此级别的日志不输出。
static var min_level: Level = Level.DEBUG

## 调试日志
static func debug(layer: Layer, tag: String, msg: String) -> void:
	_emit(Level.DEBUG, layer, tag, msg)

## 信息日志
static func info(layer: Layer, tag: String, msg: String) -> void:
	_emit(Level.INFO, layer, tag, msg)

## 警告日志
static func warn(layer: Layer, tag: String, msg: String) -> void:
	_emit(Level.WARN, layer, tag, msg)
	push_warning("[%s/%s] %s" % [_layer_name(layer), tag, msg])

## 错误日志
static func error(layer: Layer, tag: String, msg: String) -> void:
	_emit(Level.ERROR, layer, tag, msg)
	push_error("[%s/%s] %s" % [_layer_name(layer), tag, msg])

## 发出日志
static func _emit(level: Level, layer: Layer, tag: String, msg: String) -> void:
	if int(level) < int(min_level):
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


static func _layer_name(layer: Layer) -> String:
	match layer:
		Layer.DATA:
			return "Data"
		Layer.CATALOG:
			return "Catalog"
		Layer.LOGIC:
			return "Logic"
		Layer.PRESENT:
			return "Present"
		Layer.EDITOR:
			return "Editor"
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
