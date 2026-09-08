class_name Wc3RibbonPresenter
extends RefCounted
## MDX RibbonEmitter → `Wc3RibbonEmitter`（`*.ribbon.json` sidecar）。
## bake:scn 写入 RibbonRoot；运行时由 `apply_sequence` / Animation `:ribbon_emitting` 闸。
## 层：presentation（`scripts/presentation/wc3_model/`）。

const RIBBON_ROOT_NAME := "RibbonRoot"
const META_PRESENTED := "wc3_ribbon_presented"

const _EmitterScript := preload("res://scripts/presentation/wc3_model/wc3_ribbon_emitter.gd")


static func ribbon_path_from_glb(glb_path: String) -> String:
	var p := glb_path.replace("\\", "/")
	var lower := p.to_lower()
	if lower.ends_with(".gltf"):
		return p.substr(0, p.length() - 5) + ".ribbon.json"
	if lower.ends_with(".glb"):
		return p.substr(0, p.length() - 4) + ".ribbon.json"
	return p + ".ribbon.json"


static func load_payload(glb_path: String) -> Dictionary:
	var rp := ribbon_path_from_glb(glb_path)
	if rp.is_empty() or not RuntimeAssets.file_exists(rp):
		return {}
	var text := RuntimeAssets.read_utf8_text(RuntimeAssets.project_abs(rp))
	if text.is_empty():
		return {}
	var parsed: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func has_ribbons(glb_path: String) -> bool:
	var data := load_payload(glb_path)
	if data.is_empty():
		return false
	var arr: Array = data.get("ribbons", []) as Array
	return not arr.is_empty()


## 构建 RibbonRoot（不入树）。失败返回 null。
static func build_root_from_glb(glb_path: String) -> Node3D:
	var data := load_payload(glb_path)
	var arr: Array = data.get("ribbons", []) as Array
	if arr.is_empty():
		return null
	var host := Node3D.new()
	host.name = RIBBON_ROOT_NAME
	host.set_meta(META_PRESENTED, true)
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var em := _make_emitter(item as Dictionary)
		if em != null:
			host.add_child(em)
	if host.get_child_count() == 0:
		host.free()
		return null
	return host


static func apply_sequence(root: Node, sequence_name: String) -> void:
	if root == null:
		return
	var want := sequence_name.strip_edges().to_lower().replace("_", " ")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if n.get_script() != _EmitterScript:
			continue
		if n.has_method("set_active_for_sequence"):
			n.call("set_active_for_sequence", want)


static func _make_emitter(d: Dictionary) -> MeshInstance3D:
	var em: MeshInstance3D = _EmitterScript.new() as MeshInstance3D
	em.name = str(d.get("name", "Ribbon")).strip_edges()
	if em.name.is_empty():
		em.name = "Ribbon"
	var color_arr: Array = d.get("color", [0.03, 0.46, 1.0]) as Array
	var alpha := float(d.get("alpha", 0.9))
	var col := Color(
		float(color_arr[0]) if color_arr.size() > 0 else 0.03,
		float(color_arr[1]) if color_arr.size() > 1 else 0.46,
		float(color_arr[2]) if color_arr.size() > 2 else 1.0,
		alpha
	)
	var tex_rel := str(d.get("texture", "")).strip_edges()
	var tex: Texture2D = null
	if not tex_rel.is_empty():
		tex = _load_ribbon_texture(tex_rel)
	em.call(
		"configure",
		float(d.get("life_span", 0.35)),
		float(d.get("emission_rate", 40.0)),
		float(d.get("height_above", 30.0)),
		float(d.get("height_below", 30.0)),
		col,
		tex
	)
	var pivot: Array = d.get("pivot", [0, 0, 0]) as Array
	if pivot.size() >= 3:
		em.position = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
	# active_sequences
	var raw: Variant = d.get("active_sequences", null)
	if raw == null:
		em.set_meta("wc3_ribbon_always_on", true)
		em.set("ribbon_emitting", true)
	elif raw is Array:
		var packed := PackedStringArray()
		for s in raw as Array:
			packed.append(str(s))
		em.set_meta("wc3_ribbon_active_sequences", packed)
		em.set_meta("wc3_ribbon_always_on", false)
		em.set("ribbon_emitting", false)
	# 缓存 translation keys 供 bake 写轨
	var trans: Variant = d.get("translation", null)
	if trans is Dictionary:
		em.set_meta("wc3_ribbon_translation", trans)
	return em


static func _load_ribbon_texture(tex_rel: String) -> Texture2D:
	var tex := RuntimeAssets.load_converted_texture(tex_rel)
	if tex == null:
		return null
	# bake 进 .scn：尽量内嵌，避免依赖 gitignore 贴图路径
	var img: Image = tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	var embedded := ImageTexture.create_from_image(img)
	embedded.resource_local_to_scene = true
	return embedded
