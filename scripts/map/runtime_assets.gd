class_name RuntimeAssets
extends RefCounted
## 从被 .gdignore 的目录按需加载 PNG / GLB（避免编辑器导入数万资源卡死）。


static func project_abs(res_path: String) -> String:
	var p := res_path
	if p.begins_with("res://"):
		p = ProjectSettings.globalize_path(p)
	return p.replace("\\", "/")


static func file_exists(res_or_abs: String) -> bool:
	var abs := project_abs(res_or_abs)
	return FileAccess.file_exists(abs)


static func load_image(res_or_abs: String) -> Image:
	var abs := project_abs(res_or_abs)
	if not FileAccess.file_exists(abs):
		return null
	var img := Image.new()
	var err := img.load(abs)
	if err != OK:
		push_warning("RuntimeAssets: 无法加载图片 %s (%s)" % [abs, error_string(err)])
		return null
	return img


static func load_texture(res_or_abs: String) -> Texture2D:
	var img := load_image(res_or_abs)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


static func load_gltf_scene(res_or_abs: String) -> Node3D:
	var abs := project_abs(res_or_abs)
	if not FileAccess.file_exists(abs):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(abs, state)
	if err != OK:
		push_warning("RuntimeAssets: 无法加载 GLB %s (%s)" % [abs, error_string(err)])
		return null
	var scene := doc.generate_scene(state)
	if scene is Node3D:
		return scene as Node3D
	if scene:
		var wrap := Node3D.new()
		wrap.add_child(scene)
		return wrap
	return null
