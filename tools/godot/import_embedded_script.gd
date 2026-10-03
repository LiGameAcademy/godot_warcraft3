extends RefCounted

## 导出后压缩脚本不一定保留 source_code；由打包步骤保留源码副本。
static func create(template: GDScript) -> GDScript:
	var source: String = template.source_code
	if source.is_empty():
		var source_path: String = template.resource_path + ".source"
		if not FileAccess.file_exists(source_path):
			return null
		source = FileAccess.get_file_as_string(source_path)
	if source.is_empty():
		return null
	var embedded: GDScript = GDScript.new()
	embedded.source_code = source
	if embedded.reload() != OK:
		return null
	return embedded
