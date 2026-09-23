extends RefCounted
## 兼容旧调用：文案已迁至 EditorI18n + editor/locale/editor_strings.csv。


static func load_default():
	return new()


func get_text(key: String, _fallback: String = "") -> String:
	return EditorI18n.t(key)
