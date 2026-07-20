class_name MapCliffLayer
extends Node3D
## 悬崖 / 斜坡层：官方 GLB + 地形集 Cliff 贴图 + groundHeight 变形。
## 着色与地面同为 unshaded，避免顶缘被方向光抬亮。


var _mesh_cache: Dictionary = {} # "glb|tex_idx" -> Mesh
var _shader: Shader
var _height_tex: Texture2D
var _hf_meta: Dictionary = {}
var last_placed: int = 0


func build(hf: Dictionary, tiles: Wc3TerrainTiles) -> void:
	_clear_children()
	last_placed = 0
	_mesh_cache.clear()

	_hf_meta = HeightfieldMeshBuilder.read_heightfield_meta(hf)
	_height_tex = Wc3CliffHeightMap.build_texture(hf)
	_shader = load("res://shaders/wc3_cliff.gdshader") as Shader

	var collected := Wc3CliffBuilder.collect_instances(hf, tiles)
	if collected.is_empty():
		return

	var groups: Array = collected.get("groups", [])
	var cliff_tilesets: Array = collected.get("cliff_tilesets", [])
	var tex_cache: Dictionary = {}

	for g in groups:
		var glb: String = str(g["glb"])
		var tex_idx: int = int(g["cliff_tex_index"])
		var transforms: Array = g["transforms"]
		if transforms.is_empty():
			continue

		if not tex_cache.has(tex_idx):
			var png := tiles.png_for_cliff_index(cliff_tilesets, tex_idx)
			tex_cache[tex_idx] = RuntimeAssets.load_texture(png) if not png.is_empty() else null
			print("Cliff tex[%d] %s → %s (%s)" % [
				tex_idx,
				str(cliff_tilesets[tex_idx]) if tex_idx < cliff_tilesets.size() else "?",
				png,
				"ok" if tex_cache[tex_idx] else "FAIL",
			])

		var mat := _cliff_material(tex_cache[tex_idx])
		var mesh := _mesh_with_material(glb, tex_idx, mat)
		if mesh == null:
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cliff_%s_%d" % [glb.get_file().get_basename(), tex_idx]
		mmi.multimesh = mm
		# 不投射/接收阴影，避免与 unshaded 地面亮度再次分叉
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		last_placed += transforms.size()

	print(
		"Cliffs: placed=%d (cliff=%d ramp=%d) missing=%d groups=%d"
		% [
			last_placed,
			int(collected.get("placed_cliffs", 0)),
			int(collected.get("placed_ramps", 0)),
			int(collected.get("missing", 0)),
			groups.size(),
		]
	)


func _cliff_material(tex: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("height_map", _height_tex)
	mat.set_shader_parameter("center_offset", _hf_meta.get("center", Vector2.ZERO))
	mat.set_shader_parameter(
		"map_size",
		Vector2(float(_hf_meta.get("width", 1)), float(_hf_meta.get("height", 1)))
	)
	mat.set_shader_parameter("world_scale", Wc3Coords.WORLD_SCALE)
	mat.set_shader_parameter("albedo_scale", 1.0)
	if tex:
		mat.set_shader_parameter("cliff_albedo", tex)
	return mat


func _mesh_with_material(glb: String, tex_idx: int, mat: Material) -> Mesh:
	var key := "%s|%d" % [glb, tex_idx]
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var root := RuntimeAssets.load_gltf_scene(glb)
	if root == null:
		return null

	var src_mi := _find_mesh_instance(root)
	if src_mi == null or src_mi.mesh == null:
		root.free()
		return null

	var dup: ArrayMesh = src_mi.mesh.duplicate() as ArrayMesh
	root.free()
	if dup == null:
		return null

	for s in range(dup.get_surface_count()):
		dup.surface_set_material(s, mat)

	_mesh_cache[key] = dup
	return dup


func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n as MeshInstance3D
	for c in n.get_children():
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null


func _clear_children() -> void:
	for c in get_children():
		c.queue_free()
