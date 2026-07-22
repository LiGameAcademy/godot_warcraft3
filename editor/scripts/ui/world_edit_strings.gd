extends RefCounted
## 读取经典 UI/WorldEditStrings.txt（中文客户端文案）。


const LOGICAL_PATH := "UI/WorldEditStrings.txt"

var _map: Dictionary = {} ## key → display string


static func load_default():
	var s = (load("res://editor/scripts/ui/world_edit_strings.gd") as GDScript).new()
	s._load()
	return s


func get_text(key: String, fallback: String = "") -> String:
	if _map.has(key):
		return str(_map[key])
	if not fallback.is_empty():
		return fallback
	return key


func _load() -> void:
	_apply_fallback()
	var abs_path := RuntimeAssets.resolve(LOGICAL_PATH)
	if abs_path.is_empty():
		# 直接碰 cache（无 AssetProvider 时）
		var guess := ProjectSettings.globalize_path("res://").path_join(".cache/wc3-assets").path_join(LOGICAL_PATH)
		if FileAccess.file_exists(guess):
			abs_path = guess
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		push_warning("WorldEditStrings: 未找到 %s，使用内置回退文案" % LOGICAL_PATH)
		return
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	# 去 BOM
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
		# 去掉外层引号
		if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
			v = v.substr(1, v.length() - 2)
		_map[k] = v


## 无 MPQ 解包时仍能显示中文菜单名。
func _apply_fallback() -> void:
	var fb := {
		"WESTRING_MENU_FILE": "文件(&F)",
		"WESTRING_MENU_EDIT": "编辑(&E)",
		"WESTRING_MENU_VIEW": "察看(&V)",
		"WESTRING_MENU_LAYER": "层面(&L)",
		"WESTRING_MENU_SCENARIO": "情节(&S)",
		"WESTRING_MENU_TOOLS": "工具(&T)",
		"WESTRING_MENU_ADVANCED": "高级(&A)",
		"WESTRING_MENU_MODULE": "模块(&M)",
		"WESTRING_MENU_WINDOW": "窗口(&W)",
		"WESTRING_MENU_HELP": "帮助(&H)",
		"WESTRING_MENU_NEW": "创建新地图(&N)…",
		"WESTRING_MENU_OPEN": "打开地图(&O)…",
		"WESTRING_MENU_CLOSE": "关闭地图(&C)",
		"WESTRING_MENU_SAVE": "保存地图(&S)",
		"WESTRING_MENU_SAVEAS": "地图另存为...(&A)",
		"WESTRING_MENU_TESTMAP": "测试地图(&T)",
		"WESTRING_MENU_EXIT": "退出(&X)",
		"WESTRING_MENU_UNDO": "撤消(&U)",
		"WESTRING_MENU_REDO": "重做(&R)",
		"WESTRING_MENU_CUT": "剪切(&T)",
		"WESTRING_MENU_COPY": "复制(&C)",
		"WESTRING_MENU_PASTE": "粘帖(&P)",
		"WESTRING_MENU_CLEAR": "清除(&E)",
		"WESTRING_MENU_SELECTALL": "全选(&A)",
		"WESTRING_MENU_TERRAIN": "地形(&T)",
		"WESTRING_MENU_DOODADS": "地形装饰物(&D)",
		"WESTRING_MENU_UNITS": "单位(&U)",
		"WESTRING_MENU_REGIONS": "设定区域(&R)",
		"WESTRING_MENU_CAMERAS": "镜头(&C)",
		"WESTRING_MENU_MODULE_TERRAIN": "地形编辑器(&T)",
		"WESTRING_MENU_MODULE_SCRIPTS": "开关编辑器(&R)",
		"WESTRING_MENU_MODULE_SOUND": "声音编辑器(&N)",
		"WESTRING_MENU_OBJECTEDITOR": "物体编辑器(&O)",
		"WESTRING_MENU_MODULE_CAMPAIGN": "战役编辑器(&C)",
		"WESTRING_MENU_OBJECTMANAGER": "物体管理器(&O)",
		"WESTRING_MENU_IMPORTMANAGER": "输入管理器(&I)",
		"WESTRING_MENU_MODULE_AI": "AI编辑器(&A)",
		"WESTRING_MENU_TOOLBAR": "工具条(&T)",
		"WESTRING_MENU_MINIMAP": "微缩地图(&M)",
		"WESTRING_MENU_ABOUT": "关于魔兽争霸III地图编辑器(&A)...",
		"WESTRING_APPNAME": "魔兽争霸III地图编辑器",
	}
	for k in fb:
		_map[k] = fb[k]
