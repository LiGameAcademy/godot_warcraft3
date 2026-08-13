class_name RuntimeAssets
extends RefCounted

## 运行时资源 I/O：只从磁盘加载。
## asset-converted/ 被 .gdignore 阻止 Godot auto-import，运行时直接 FileAccess 读 GLB/.scn。
## 地图代码请用 converted_path / load_*；勿再手写 res://assets/asset-converted/ 前缀。
##
## 解析顺序（via resolve）：AssetProvider overlay → converted → slk-exported。
## 不读 .cache/wc3-assets（extract 中间态；见 docs/architecture/ASSET_LANES.md）。

const CONVERTED_RES_ROOT := "res://assets/asset-converted"
const SLK_RES_ROOT := "res://assets/slk-exported"
## 可提交的 PE2 粒子预制（路径镜像 asset-converted 逻辑子树，不含 Blizzard 贴图/网格）
const PE2_PREFABS_RES_ROOT := "res://assets/pe2-prefabs"
## 可提交的模型视觉封装（继承 bake .scn + Pe2Root；无游戏逻辑）
const VISUALS_RES_ROOT := "res://assets/visuals"
## 旧版独立目录（已弃用：.scn 现与 GLB 同目录）；resolve 仍作回退
const LEGACY_MODEL_SCENES_RES_ROOT := "res://assets/model-scenes"
## 懒烘焙回退（无法写入 asset-converted 时）
const MODEL_SCENES_USER_ROOT := "user://model-scenes"

## 解析失败的 GLB 绝对路径 → 跳过重试（避免装饰扫描刷引擎 ERROR）。
static var _gltf_fail_cache: Dictionary = {}
## 磁盘绝对路径 → 是否 unsafe（避免反复读盘扫描）。
static var _scn_unsafe_cache: Dictionary = {}


static func project_abs(res_or_abs: String) -> String:
	var p := res_or_abs
	if p.begins_with("res://"):
		p = ProjectSettings.globalize_path(p)
	return p.replace("\\", "/")


## 读 UTF-8 文本；二进制/非法 UTF-8 直接拒绝，避免引擎 Unicode parsing ERROR 刷屏。
static func read_utf8_text(res_or_abs: String) -> String:
	var disk := project_abs(res_or_abs)
	if disk.is_empty() or not FileAccess.file_exists(disk):
		return ""
	var bytes := FileAccess.get_file_as_bytes(disk)
	if bytes.is_empty():
		return ""
	# PNG / GLB / 常见二进制魔数：勿走 UTF-8 解码
	if bytes.size() >= 4:
		# PNG: 89 50 4E 47
		if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
			return ""
		# glTF binary / GLB: glTF
		if bytes[0] == 0x67 and bytes[1] == 0x6C and bytes[2] == 0x54 and bytes[3] == 0x46:
			return ""
	# 全文件扫 NUL（JSON/配置不应含 0x00；误读其它二进制时在此拦下）
	for i in range(bytes.size()):
		if bytes[i] == 0:
			return ""
	# 非法 UTF-8 也会打引擎 ERROR；先校验再解码（切勿先调 get_string_from_utf8）
	if not _bytes_are_valid_utf8(bytes):
		return ""
	return bytes.get_string_from_utf8()


## 解析 JSON 文本。剥离 `\\u0000`（map-parse 空 FourCC），避免 Godot Unexpected NUL ERROR。
static func parse_json_text(text: String) -> Variant:
	if text.is_empty():
		return null
	if text.find("\\u0000") >= 0:
		text = text.replace("\\u0000", "")
	return JSON.parse_string(text)


## 读盘并解析 JSON 对象；失败返回空 Dictionary。
static func read_json_dict(res_or_abs: String) -> Dictionary:
	var text := read_utf8_text(res_or_abs)
	if text.is_empty():
		return {}
	var parsed: Variant = parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func _bytes_are_valid_utf8(bytes: PackedByteArray) -> bool:
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
			return false
		if i + need >= n:
			return false
		for j in range(1, need + 1):
			var cc := bytes[i + j]
			if cc < 0x80 or cc > 0xBF:
				return false
		# 过严排除一些 overlong / 非法码点即可满足「别误读二进制」
		i += need + 1
	return true


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
## 例：Doodads/.../Foo.gltf → res://assets/pe2-prefabs/Doodads/.../Foo.pe2.tscn
static func pe2_prefab_path(relative_or_glb: String) -> String:
	var p := relative_or_res_to_logical(relative_or_glb)
	var lower := p.to_lower()
	if lower.ends_with(".gltf"):
		p = p.substr(0, p.length() - 5) + ".pe2.tscn"
	elif lower.ends_with(".glb"):
		p = p.substr(0, p.length() - 4) + ".pe2.tscn"
	elif lower.ends_with(".pe2.json"):
		p = p.substr(0, p.length() - ".pe2.json".length()) + ".pe2.tscn"
	elif not lower.ends_with(".pe2.tscn"):
		p = p + ".pe2.tscn"
	return PE2_PREFABS_RES_ROOT.path_join(p)


## 逻辑 / 模型路径 → res://assets/visuals/.../Foo.tscn（继承 bake .scn 的视觉封装）。
static func visual_scene_path(relative_or_glb: String) -> String:
	var p := relative_or_res_to_logical(relative_or_glb)
	var lower := p.to_lower()
	if lower.ends_with(".gltf"):
		p = p.substr(0, p.length() - 5) + ".tscn"
	elif lower.ends_with(".glb") or lower.ends_with(".scn"):
		p = p.substr(0, p.length() - 4) + ".tscn"
	elif lower.ends_with(".tscn"):
		pass
	elif lower.ends_with(".pe2.tscn"):
		p = p.substr(0, p.length() - ".pe2.tscn".length()) + ".tscn"
	elif lower.ends_with(".pe2.json"):
		p = p.substr(0, p.length() - ".pe2.json".length()) + ".tscn"
	else:
		p = p + ".tscn"
	return VISUALS_RES_ROOT.path_join(p)


## 有 visuals 封装则返回其 res 路径，否则空。
static func resolve_visual_scene(relative_or_glb: String) -> String:
	var res_p := visual_scene_path(relative_or_glb)
	if file_exists(res_p):
		return res_p
	return ""


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
		"assets/visuals/",
		"visuals/",
		"assets/pe2-prefabs/",
		"pe2-prefabs/",
		"assets/model-scenes/",
		"model-scenes/",
	]
	for pre in PREFIXES:
		if p.begins_with(pre):
			return p.substr(pre.length())
	return p


## 逻辑 / 模型路径 → 与模型同目录的 .scn（asset-converted/.../Foo.scn）。
static func model_scene_path(relative_or_glb: String) -> String:
	var p := relative_or_res_to_logical(relative_or_glb)
	var lower := p.to_lower()
	if lower.ends_with(".gltf"):
		p = p.substr(0, p.length() - 5) + ".scn"
	elif lower.ends_with(".glb"):
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
	if lower.ends_with(".gltf"):
		p = p.substr(0, p.length() - 5) + ".scn"
	elif lower.ends_with(".glb"):
		p = p.substr(0, p.length() - 4) + ".scn"
	elif not lower.ends_with(".scn"):
		p = p + ".scn"
	return LEGACY_MODEL_SCENES_RES_ROOT.path_join(p)


## 运行时懒烘焙落盘（user://），不进仓库。
static func model_scene_user_path(relative_or_glb: String) -> String:
	var p := relative_or_res_to_logical(relative_or_glb)
	var lower := p.to_lower()
	if lower.ends_with(".gltf"):
		p = p.substr(0, p.length() - 5) + ".scn"
	elif lower.ends_with(".glb"):
		p = p.substr(0, p.length() - 4) + ".scn"
	elif not lower.ends_with(".scn"):
		p = p + ".scn"
	return MODEL_SCENES_USER_ROOT.path_join(p)


## 优先与 GLB 同目录 .scn → 旧 model-scenes/ → user:// 懒烘焙。
## 含 gdignore 外链贴图的坏 .scn 视为不存在，便于改走 glTF / 懒烘焙覆盖。
## 注意：大体积嵌入贴图 .scn 仍优先（实测 ResourceLoader ~0.4s，同模型 glTF 常 10s+）。
static func resolve_model_scene(relative_or_glb: String) -> String:
	for p in [
		model_scene_path(relative_or_glb),
		legacy_model_scene_path(relative_or_glb),
		model_scene_user_path(relative_or_glb),
	]:
		if file_exists(p) and not is_packed_scene_unsafe_for_resource_loader(p):
			return p
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
	# asset-converted 有 .gdignore：.scn 若外链其中 PNG，
	# ResourceLoader 会刷 "No loader found" / Failed loading。跳过改走 glTF。
	if is_packed_scene_unsafe_for_resource_loader(res_path):
		return null
	var loaded: Resource = ResourceLoader.load(res_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	if loaded is PackedScene:
		return loaded as PackedScene
	return null


## true = 不要走 ResourceLoader（会因 gdignore 贴图外链报错）。
static func is_packed_scene_unsafe_for_resource_loader(res_or_abs: String) -> bool:
	var lower := res_or_abs.replace("\\", "/").to_lower()
	if not lower.ends_with(".scn") and not lower.ends_with(".tscn"):
		return false
	var disk := project_abs(res_or_abs)
	if disk.is_empty() or not FileAccess.file_exists(disk):
		return false
	if _scn_unsafe_cache.has(disk):
		return bool(_scn_unsafe_cache[disk])
	# 只读文件头：ExtResource 路径通常在前部；切勿全文件 GDScript 扫描（10MB 级可达数秒）
	var f := FileAccess.open(disk, FileAccess.READ)
	if f == null:
		_scn_unsafe_cache[disk] = false
		return false
	var probe_len := mini(int(f.get_length()), 65536)
	var bytes := f.get_buffer(probe_len)
	f.close()
	var unsafe := false
	if not bytes.is_empty():
		unsafe = (
			_bytes_has_ascii(bytes, "res://assets/asset-converted/")
			or _bytes_has_ascii(bytes, "pe2.tscn")
		)
	_scn_unsafe_cache[disk] = unsafe
	return unsafe


## 兼容旧名
static func _packed_scene_unsafe_for_resource_loader(res_or_abs: String) -> bool:
	return is_packed_scene_unsafe_for_resource_loader(res_or_abs)


static func _packed_scene_refs_gdignored_converted(res_or_abs: String) -> bool:
	return is_packed_scene_unsafe_for_resource_loader(res_or_abs)


static func _bytes_has_ascii(bytes: PackedByteArray, needle: String) -> bool:
	if needle.is_empty() or bytes.is_empty():
		return false
	# 用 String.find 比双重 GDScript 循环快一个数量级（仅用于小 probe）
	var hay := bytes.get_string_from_utf8()
	if hay.is_empty():
		# 含 NUL 时 utf8 可能失败：退回 ascii 宽松解码
		hay = bytes.get_string_from_ascii()
	return hay.find(needle) >= 0


## 将根节点打包存为 .scn（目录自动创建）。
## 打包前临时清空指向 asset-converted 的 resource_path，避免写出 ResourceLoader 无法解析的外链。
static func save_packed_scene(root: Node, res_or_user_path: String) -> Error:
	if root == null or res_or_user_path.is_empty():
		return ERR_INVALID_PARAMETER
	var cleared: Array = []
	_clear_asset_converted_resource_paths(root, cleared)
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	_restore_resource_paths(cleared)
	if pack_err != OK:
		return pack_err
	var disk := project_abs(res_or_user_path)
	DirAccess.make_dir_recursive_absolute(disk.get_base_dir())
	return ResourceSaver.save(packed, res_or_user_path)


static func _clear_asset_converted_resource_paths(node: Node, cleared: Array) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override != null:
			_clear_material_converted_paths(mi.material_override, cleared)
		var surf_count := mi.get_surface_override_material_count()
		for si in range(surf_count):
			_clear_material_converted_paths(mi.get_surface_override_material(si), cleared)
		if mi.mesh != null:
			_maybe_clear_res_path(mi.mesh, cleared)
			for si2 in range(mi.mesh.get_surface_count()):
				_clear_material_converted_paths(mi.get_active_material(si2), cleared)
				_clear_material_converted_paths(mi.mesh.surface_get_material(si2), cleared)
	elif node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.material_override != null:
			_clear_material_converted_paths(gi.material_override, cleared)
	for c in node.get_children():
		_clear_asset_converted_resource_paths(c, cleared)


static func _clear_material_converted_paths(mat: Material, cleared: Array) -> void:
	if mat == null:
		return
	_maybe_clear_res_path(mat, cleared)
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		_maybe_clear_res_path(bm.albedo_texture, cleared)
		_maybe_clear_res_path(bm.normal_texture, cleared)
		_maybe_clear_res_path(bm.metallic_texture, cleared)
		_maybe_clear_res_path(bm.roughness_texture, cleared)
		_maybe_clear_res_path(bm.emission_texture, cleared)
		_maybe_clear_res_path(bm.ao_texture, cleared)
		_maybe_clear_res_path(bm.heightmap_texture, cleared)
		_maybe_clear_res_path(bm.orm_texture, cleared)
	elif mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		_maybe_clear_res_path(sm.shader, cleared)
		for pname in sm.get_property_list():
			if typeof(pname) != TYPE_DICTIONARY:
				continue
			var pn := str(pname.get("name", ""))
			if pn.is_empty() or not pn.begins_with("shader_parameter/"):
				continue
			var val: Variant = sm.get(pn)
			if val is Resource:
				_maybe_clear_res_path(val as Resource, cleared)


static func _maybe_clear_res_path(res: Resource, cleared: Array) -> void:
	if res == null:
		return
	var p := str(res.resource_path).replace("\\", "/")
	if p.is_empty():
		return
	if not p.begins_with("res://assets/asset-converted/") and not p.contains("/asset-converted/"):
		return
	cleared.append({"res": res, "path": p})
	res.resource_path = ""


static func _restore_resource_paths(cleared: Array) -> void:
	for item in cleared:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var res: Resource = item.get("res") as Resource
		var path := str(item.get("path", ""))
		if res != null and not path.is_empty():
			res.resource_path = path


## 逻辑路径 → 绝对磁盘路径。优先 Autoload AssetProvider（converted + slk-exported）。
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

	# 无 Autoload 或未命中：converted → slk-exported（不读 .cache）
	var conv := converted_path(logical)
	var disk_path := project_abs(conv)
	if FileAccess.file_exists(disk_path):
		return disk_path
	var data_disk := project_abs(slk_path(logical))
	if FileAccess.file_exists(data_disk):
		return data_disk
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
	if disk_path.is_empty() or not FileAccess.file_exists(disk_path):
		return null
	if _gltf_fail_cache.has(disk_path):
		return null
	# 方案 B：.gltf 必须走 append_from_file，才能解析外部 images[].uri（共享 Textures/）
	var lower := disk_path.to_lower()
	if lower.ends_with(".gltf"):
		return _load_gltf_from_file(disk_path)
	var bytes := FileAccess.get_file_as_bytes(disk_path)
	if not _is_plausible_gltf_bytes(bytes):
		_gltf_fail_cache[disk_path] = true
		return null
	return load_gltf_scene_from_bytes(bytes, disk_path)


## 磁盘 .gltf（+ .bin + 外部 PNG URI）→ 场景。
static func _load_gltf_from_file(disk_path: String) -> Node3D:
	if _gltf_fail_cache.has(disk_path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(disk_path, state)
	if err != OK:
		_gltf_fail_cache[disk_path] = true
		return null
	var scene := doc.generate_scene(state)
	if scene is Node3D:
		return scene as Node3D
	if scene:
		var root3d := Node3D.new()
		root3d.add_child(scene)
		return root3d
	_gltf_fail_cache[disk_path] = true
	return null


## 已读入内存的 GLB 字节 → 场景（主线程调用；纹理相对 base_dir 解析）。
## 注意：.gltf JSON 不要走这条（外部 URI 从 buffer 无法可靠解析）；若误传 .gltf 会改走文件加载。
static func load_gltf_scene_from_bytes(bytes: PackedByteArray, glb_res_or_abs: String) -> Node3D:
	var disk_path := project_abs(glb_res_or_abs)
	var lower := disk_path.to_lower()
	# 误把 .gltf JSON 当 GLB 字节解析会 fail→黑名单，导致永久粉胶囊
	if lower.ends_with(".gltf"):
		return load_gltf_scene(glb_res_or_abs)
	if _gltf_fail_cache.has(disk_path):
		return null
	if not _is_plausible_gltf_bytes(bytes):
		if not disk_path.is_empty():
			_gltf_fail_cache[disk_path] = true
		return null
	var base_dir := disk_path.get_base_dir()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	# 坏文件在校验阶段拦掉；仍失败则记黑名单，避免装饰扫描反复打引擎 ERROR。
	var err := doc.append_from_buffer(bytes, base_dir, state)
	if err != OK:
		if not disk_path.is_empty():
			_gltf_fail_cache[disk_path] = true
		return null
	var scene := doc.generate_scene(state)
	if scene is Node3D:
		return scene as Node3D
	if scene:
		var root3d := Node3D.new()
		root3d.add_child(scene)
		return root3d
	if not disk_path.is_empty():
		_gltf_fail_cache[disk_path] = true
	return null


## 清除误入的 GLTF 失败黑名单（例如曾把 .gltf 当 GLB 解析）。
static func clear_gltf_fail_cache() -> void:
	_gltf_fail_cache.clear()


## GLB 魔数 `glTF`；空 BIN / 坏 chunk 在校验阶段拦掉，避免引擎「Buffer 0」ERROR。
## JSON .gltf 请走 append_from_file，不在此校验通过。
static func is_plausible_gltf_bytes(bytes: PackedByteArray) -> bool:
	return _is_plausible_gltf_bytes(bytes)


static func _is_plausible_gltf_bytes(bytes: PackedByteArray) -> bool:
	if bytes.size() < 20:
		return false
	# Binary GLB：magic = 'glTF'
	if bytes[0] == 0x67 and bytes[1] == 0x6C and bytes[2] == 0x54 and bytes[3] == 0x46:
		return _glb_chunks_look_ok(bytes)
	# JSON .gltf：字节路径不支持（需 append_from_file）
	return false


## 校验 GLB chunk：必须有 JSON；若有 BIN 则长度 > 0（空 BIN → Godot「Buffer 0 has no data」）。
static func _glb_chunks_look_ok(bytes: PackedByteArray) -> bool:
	var declared: int = (
		bytes[8] | (bytes[9] << 8) | (bytes[10] << 16) | (bytes[11] << 24)
	)
	if declared < 20 or declared > bytes.size() + 64:
		return false
	var limit: int = mini(declared, bytes.size())
	var offset := 12
	var has_json := false
	var has_bin := false
	var bin_len := 0
	while offset + 8 <= limit:
		var chunk_len: int = (
			bytes[offset]
			| (bytes[offset + 1] << 8)
			| (bytes[offset + 2] << 16)
			| (bytes[offset + 3] << 24)
		)
		var chunk_type: int = (
			bytes[offset + 4]
			| (bytes[offset + 5] << 8)
			| (bytes[offset + 6] << 16)
			| (bytes[offset + 7] << 24)
		)
		offset += 8
		if chunk_len < 0 or offset + chunk_len > limit:
			return false
		# 0x4E4F534A = JSON；0x004E4942 = BIN
		if chunk_type == 0x4E4F534A:
			has_json = true
			if chunk_len < 2:
				return false
		elif chunk_type == 0x004E4942:
			has_bin = true
			bin_len = chunk_len
		offset += chunk_len
		# 4 字节对齐
		offset = (offset + 3) & ~3
	if not has_json:
		return false
	# 有 BIN chunk 但长度为 0 → 引擎必报 Buffer 0；无 BIN 也可能是纯 JSON 嵌入，仍可能炸，一律要求 BIN>0
	if not has_bin or bin_len <= 0:
		return false
	return true
