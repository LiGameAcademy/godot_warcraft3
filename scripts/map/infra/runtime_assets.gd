class_name RuntimeAssets
extends RefCounted

## 运行时资源 I/O：只从磁盘加载（asset-converted 被 .gdignore）。
## 地图代码请用 converted_path / load_*；勿再手写 res://assets/asset-converted/ 前缀。
##
## 解析顺序（via resolve）：AssetProvider overlay → converted → .cache

const CONVERTED_RES_ROOT := "res://assets/asset-converted"
const SLK_RES_ROOT := "res://assets/slk-exported"
## 可提交的 PE2 粒子预制（路径镜像 asset-converted 逻辑子树，不含 Blizzard 贴图/网格）
const PE2_PREFABS_RES_ROOT := "res://assets/pe2-prefabs"
## 旧版独立目录（已弃用：.scn 现与 GLB 同目录）；resolve 仍作回退
const LEGACY_MODEL_SCENES_RES_ROOT := "res://assets/model-scenes"
## 懒烘焙回退（无法写入 asset-converted 时）
const MODEL_SCENES_USER_ROOT := "user://model-scenes"


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


## 逻辑路径（相对 asset-converted 子树）→ res://assets/pe2-prefabs/...
## 例：Doodads/.../Foo.glb → res://assets/pe2-prefabs/Doodads/.../Foo.pe2.tscn
static func pe2_prefab_path(relative_or_glb: String) -> String:
	var p := relative_or_res_to_logical(relative_or_glb)
	var lower := p.to_lower()
	if lower.ends_with(".glb"):
		p = p.substr(0, p.length() - 4) + ".pe2.tscn"
	elif lower.ends_with(".pe2.json"):
		p = p.substr(0, p.length() - ".pe2.json".length()) + ".pe2.tscn"
	elif not lower.ends_with(".pe2.tscn"):
		p = p + ".pe2.tscn"
	return PE2_PREFABS_RES_ROOT.path_join(p)


## 去掉 res://assets/asset-converted/ 等前缀，得到逻辑相对路径。
static func relative_or_res_to_logical(relative_or_res: String) -> String:
	var p := relative_or_res.replace("\\", "/")
	if p.begins_with("res://"):
		p = p.substr("res://".length())
	while p.begins_with("/"):
		p = p.substr(1)
	const PREFIXES: Array[String] = [
		"assets/asset-converted/",
		"asset-converted/",
		"assets/pe2-prefabs/",
		"pe2-prefabs/",
		"assets/model-scenes/",
		"model-scenes/",
	]
	for pre in PREFIXES:
		if p.begins_with(pre):
			return p.substr(pre.length())
	return p


## 逻辑 / GLB 路径 → 与 GLB 同目录的 .scn（asset-converted/.../Foo.scn）。
static func model_scene_path(relative_or_glb: String) -> String:
	var p := relative_or_res_to_logical(relative_or_glb)
	var lower := p.to_lower()
	if lower.ends_with(".glb"):
		p = p.substr(0, p.length() - 4) + ".scn"
	elif lower.ends_with(".scn"):
		pass
	else:
		p = p + ".scn"
	return CONVERTED_RES_ROOT.path_join(p)


## 旧独立目录路径（仅 resolve 回退用）。
static func legacy_model_scene_path(relative_or_glb: String) -> String:
	var p := relative_or_res_to_logical(relative_or_glb)
	var lower := p.to_lower()
	if lower.ends_with(".glb"):
		p = p.substr(0, p.length() - 4) + ".scn"
	elif not lower.ends_with(".scn"):
		p = p + ".scn"
	return LEGACY_MODEL_SCENES_RES_ROOT.path_join(p)


## 运行时懒烘焙落盘（user://），不进仓库。
static func model_scene_user_path(relative_or_glb: String) -> String:
	var p := relative_or_res_to_logical(relative_or_glb)
	var lower := p.to_lower()
	if lower.ends_with(".glb"):
		p = p.substr(0, p.length() - 4) + ".scn"
	elif not lower.ends_with(".scn"):
		p = p + ".scn"
	return MODEL_SCENES_USER_ROOT.path_join(p)


## 优先与 GLB 同目录 .scn → 旧 model-scenes/ → user:// 懒烘焙。
static func resolve_model_scene(relative_or_glb: String) -> String:
	var res_p := model_scene_path(relative_or_glb)
	if file_exists(res_p):
		return res_p
	var legacy_p := legacy_model_scene_path(relative_or_glb)
	if file_exists(legacy_p):
		return legacy_p
	var user_p := model_scene_user_path(relative_or_glb)
	if file_exists(user_p):
		return user_p
	return ""


## 加载已烘焙 PackedScene（.scn）；失败返回 null。
static func load_packed_scene(res_or_abs: String) -> PackedScene:
	if res_or_abs.is_empty():
		return null
	var res_path := res_or_abs
	if not res_path.begins_with("res://") and not res_path.begins_with("user://"):
		res_path = project_abs(res_or_abs)
		# 绝对路径 → 尽量 localize
		if res_path.begins_with(ProjectSettings.globalize_path("res://")):
			res_path = ProjectSettings.localize_path(res_path)
		elif res_path.begins_with(ProjectSettings.globalize_path("user://")):
			res_path = ProjectSettings.localize_path(res_path)
	if not file_exists(res_path) and not file_exists(project_abs(res_path)):
		return null
	var loaded: Resource = ResourceLoader.load(res_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	if loaded is PackedScene:
		return loaded as PackedScene
	# 部分环境下 gdignore / 未导入：再试绝对路径
	var disk := project_abs(res_path)
	if disk != res_path:
		loaded = ResourceLoader.load(disk, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded is PackedScene:
			return loaded as PackedScene
	return null


## 将根节点打包存为 .scn（目录自动创建）。
static func save_packed_scene(root: Node, res_or_user_path: String) -> Error:
	if root == null or res_or_user_path.is_empty():
		return ERR_INVALID_PARAMETER
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		return pack_err
	var disk := project_abs(res_or_user_path)
	DirAccess.make_dir_recursive_absolute(disk.get_base_dir())
	return ResourceSaver.save(packed, res_or_user_path)


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
	var bytes := FileAccess.get_file_as_bytes(disk_path)
	if bytes.is_empty():
		return null
	return load_gltf_scene_from_bytes(bytes, disk_path)


## 已读入内存的 GLB 字节 → 场景（主线程调用；纹理相对 base_dir 解析）。
static func load_gltf_scene_from_bytes(bytes: PackedByteArray, glb_res_or_abs: String) -> Node3D:
	if bytes.is_empty():
		return null
	var disk_path := project_abs(glb_res_or_abs)
	var base_dir := disk_path.get_base_dir()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, base_dir, state)
	if err != OK:
		push_warning(
			"RuntimeAssets: 无法解析 GLB buffer %s (%s)" % [disk_path, error_string(err)]
		)
		return null
	var scene := doc.generate_scene(state)
	if scene is Node3D:
		return scene as Node3D
	if scene:
		var root3d := Node3D.new()
		root3d.add_child(scene)
		return root3d
	return null
