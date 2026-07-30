class_name RuntimeAssets
extends RefCounted

## 运行时资源 I/O：只从磁盘加载（asset-converted 被 .gdignore）。
## 地图代码请用 converted_path / load_*；勿再手写 res://assets/asset-converted/ 前缀。
##
## 解析顺序（via resolve）：AssetProvider overlay → converted → .cache

const CONVERTED_RES_ROOT := "res://assets/asset-converted"
const SLK_RES_ROOT := "res://assets/slk-exported"


static func project_abs(res_or_abs: String) -> String:
	var p := res_or_abs
	if p.begins_with("res://"):
		p = ProjectSettings.globalize_path(p)
	return p.replace("\\", "/")


## 相对路径 → res://assets/asset-converted/...
## 已是 res:// 则原样返回。
static func converted_path(relative_or_res: String) -> String:
	var p := relative_or_res.replace("\\", "/")
	if p.begins_with("res://"):
		return p
	while p.begins_with("/"):
		p = p.substr(1)
	if p.begins_with("assets/asset-converted/"):
		return "res://" + p
	if p.begins_with("asset-converted/"):
		return "res://assets/" + p
	return CONVERTED_RES_ROOT.path_join(p)


static func slk_path(relative_or_res: String) -> String:
	var p := relative_or_res.replace("\\", "/")
	if p.begins_with("res://"):
		return p
	while p.begins_with("/"):
		p = p.substr(1)
	if p.begins_with("assets/slk-exported/"):
		return "res://" + p
	if p.begins_with("slk-exported/"):
		return "res://assets/" + p
	return SLK_RES_ROOT.path_join(p)


## 逻辑路径 → 绝对磁盘路径。优先 Autoload AssetProvider（含 converted + cache）。
static func resolve(logical_path: String) -> String:
	var logical := logical_path.replace("\\", "/")
	while logical.begins_with("/"):
		logical = logical.substr(1)

	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var ap := tree.root.get_node_or_null("/root/AssetProvider")
		if ap and ap.has_method("resolve"):
			var from_ap: String = str(ap.call("resolve", logical))
			if not from_ap.is_empty():
				return from_ap

	# 无 Autoload 或未命中：converted → .cache/wc3-assets
	var conv := converted_path(logical)
	var disk_path := project_abs(conv)
	if FileAccess.file_exists(disk_path):
		return disk_path
	var cache_guess := ProjectSettings.globalize_path("res://").path_join(".cache/wc3-assets").path_join(logical)
	cache_guess = cache_guess.replace("\\", "/")
	if FileAccess.file_exists(cache_guess):
		return cache_guess
	return ""

## 文件是否存在
## [param res_or_abs] 资源或绝对路径
## [return bool] 文件是否存在
static func file_exists(res_or_abs: String) -> bool:
	var disk_path := project_abs(res_or_abs)
	return FileAccess.file_exists(disk_path)


static func load_image(res_or_abs: String) -> Image:
	var disk_path := project_abs(res_or_abs)
	if not FileAccess.file_exists(disk_path):
		return null
	var img := Image.new()
	var err := img.load(disk_path)
	if err != OK:
		push_warning("RuntimeAssets: 无法加载图片 %s (%s)" % [disk_path, error_string(err)])
		return null
	return img


static func load_texture(res_or_abs: String) -> Texture2D:
	var img := load_image(res_or_abs)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


static func load_converted_texture(relative: String) -> Texture2D:
	return load_texture(converted_path(relative))


static func load_gltf_scene(res_or_abs: String) -> Node3D:
	var disk_path := project_abs(res_or_abs)
	if not FileAccess.file_exists(disk_path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(disk_path, state)
	if err != OK:
		push_warning("RuntimeAssets: 无法加载 GLB %s (%s)" % [disk_path, error_string(err)])
		return null
	var scene := doc.generate_scene(state)
	if scene is Node3D:
		return scene as Node3D
	if scene:
		var root3d := Node3D.new()
		root3d.add_child(scene)
		return root3d
	return null
