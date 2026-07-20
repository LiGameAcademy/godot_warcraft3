class_name MapModelCache
extends RefCounted
## 运行时 GLB 场景 / Mesh 缓存，供单位与装饰层共用。


var _scene_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}


func instance_glb(path: String) -> Node3D:
	if path.is_empty():
		return null
	if not _scene_cache.has(path):
		var loaded := RuntimeAssets.load_gltf_scene(path)
		if loaded == null:
			return null
		_scene_cache[path] = loaded
	return (_scene_cache[path] as Node3D).duplicate() as Node3D


func mesh_from_glb(path: String) -> Mesh:
	if path.is_empty():
		return null
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var root := instance_glb(path)
	if root == null:
		return null
	var mi := _find_mesh_instance(root)
	var m: Mesh = mi.mesh if mi else null
	root.free()
	if m:
		_mesh_cache[path] = m
	return m


func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n as MeshInstance3D
	for c in n.get_children():
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null
