class_name Wc3Pe2Particles
extends RefCounted

## MDX ParticleEmitter2 旁路：读 `*.pe2.json`（与 GLB 同 stem），挂 GPUParticles3D。
## 坐标与网格一致（glTF/Y-up，落在 convert 的 MODEL_SCALE=0.01 节点下）。
## 可编辑预制在 `res://assets/pe2-prefabs/`（路径镜像 asset-converted，可提交 git）。
## v2：`active_sequences` — null/缺省=全程发射；数组=仅这些 WC3 Sequence 名下 emitting。

const PE2_ROOT_NAME := "Pe2Root"
const MODEL_SCALE := 0.01
const META_ACTIVE_SEQS := "pe2_active_sequences"
const META_ALWAYS_ON := "pe2_always_on"
const META_PIVOT := "pe2_pivot"
const META_PIVOT_BY_SEQ := "pe2_pivot_by_sequence"


static func pe2_path_from_glb(glb_path: String) -> String:
	var p := glb_path.replace("\\", "/")
	var lower := p.to_lower()
	if lower.ends_with(".gltf"):
		return p.substr(0, p.length() - 5) + ".pe2.json"
	if lower.ends_with(".glb"):
		return p.substr(0, p.length() - 4) + ".pe2.json"
	return p + ".pe2.json"


## GLB / 逻辑路径 → 可提交的 pe2 预制路径（assets/pe2-prefabs/...）。
static func pe2_tscn_path_from_glb(glb_path: String) -> String:
	return RuntimeAssets.pe2_prefab_path(glb_path)


static func load_payload(glb_path: String) -> Dictionary:
	var pe2_path := pe2_path_from_glb(glb_path)
	if pe2_path.is_empty() or not RuntimeAssets.file_exists(pe2_path):
		return {}
	var disk := RuntimeAssets.project_abs(pe2_path)
	var text := RuntimeAssets.read_utf8_text(disk)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func has_emitters(glb_path: String) -> bool:
	# 以 pe2.json 为准。pe2.tscn 虽可提交，但 ExtResource 常指向
	# asset-converted（.gdignore），ResourceLoader 必失败并刷屏。
	var data := load_payload(glb_path)
	var emitters: Array = data.get("emitters", [])
	return not emitters.is_empty()


## 从 pe2.json 构建可保存的 Pe2Root（供批量导出 .pe2.tscn / 运行时回退）。
static func build_root_from_glb(glb_path: String) -> Node3D:
	return build_root_from_payload(load_payload(glb_path))


static func build_root_from_payload(data: Dictionary) -> Node3D:
	var emitters: Array = data.get("emitters", []) if typeof(data) == TYPE_DICTIONARY else []
	if emitters.is_empty():
		return null
	var sequences: Array = data.get("sequences", []) if typeof(data) == TYPE_DICTIONARY else []
	var pe2_root := Node3D.new()
	pe2_root.name = PE2_ROOT_NAME
	for i in range(emitters.size()):
		var em: Variant = emitters[i]
		if typeof(em) != TYPE_DICTIONARY:
			continue
		var em_dict: Dictionary = (em as Dictionary).duplicate(true)
		_ensure_active_sequences(em_dict, sequences)
		var node := _make_emitter(em_dict, i)
		if node == null:
			continue
		pe2_root.add_child(node)
		node.owner = pe2_root
	if pe2_root.get_child_count() == 0:
		pe2_root.free()
		return null
	return pe2_root


## 挂到「带 MODEL_SCALE 的模型根」下（勿挂 GLTF 外包层，否则 pivot 变成百米级）。
## 优先实例化旁路 `.pe2.tscn`（可编辑预制），否则从 `.pe2.json` 动态构建。
## 返回发射器数量。
static func attach_to(root: Node3D, glb_path: String) -> int:
	if root == null or glb_path.is_empty():
		return 0
	# visuals 场景已内嵌 Pe2Root：用 pe2.json 刷新 active_sequences（修旧 bake 空数组），勿重复挂
	var existing := root.find_child(PE2_ROOT_NAME, true, false)
	if existing != null:
		_sync_active_seqs_from_payload(existing, load_payload(glb_path))
		apply_sequence(root, "Stand")
		return _count_particle_nodes(existing)
	var parent := _resolve_model_root(root)
	var pe2_root := _instantiate_prefab(glb_path)
	if pe2_root == null:
		pe2_root = build_root_from_glb(glb_path)
	if pe2_root == null:
		return 0
	# 找不到 0.01 根时（少见），自己补上 scale，避免粒子飞出地图
	if not _is_model_scale(parent.scale) and not _is_model_scale(pe2_root.scale):
		pe2_root.scale = Vector3.ONE * MODEL_SCALE
	parent.add_child(pe2_root)
	# 默认按「空闲 Stand」关闸；装饰物 always_on 不受影响
	apply_sequence(root, "Stand")
	return _count_particle_nodes(pe2_root)


## 按当前 WC3 Sequence 名开关发射器（建筑 Birth / Stand Work / Death 等）。
## sequence_name 可用空格或下划线；叶子名匹配即可。
static func apply_sequence(root: Node, sequence_name: String) -> void:
	if root == null:
		return
	var pe2 := root.find_child(PE2_ROOT_NAME, true, false)
	if pe2 == null:
		return
	var want := _normalize_seq_key(sequence_name)
	_apply_sequence_to_node(pe2, want)


static func _apply_sequence_to_node(n: Node, want_key: String) -> void:
	if n is GPUParticles3D:
		var p := n as GPUParticles3D
		# 缺 meta 默认关：避免旧 prefab / 半成品节点被当成火盆全程喷
		var always: bool = bool(p.get_meta(META_ALWAYS_ON, false))
		if always:
			p.emitting = true
		else:
			var seqs: PackedStringArray = p.get_meta(META_ACTIVE_SEQS, PackedStringArray()) as PackedStringArray
			p.emitting = _seqs_match(seqs, want_key)
		_apply_pivot_for_sequence(p, want_key)
	for c in n.get_children():
		_apply_sequence_to_node(c, want_key)


## Stand Work 等会移动发射器（兵营门光）；按 pivot_by_sequence 改 position。
static func _apply_pivot_for_sequence(p: GPUParticles3D, want_key: String) -> void:
	var by_seq: Variant = p.get_meta(META_PIVOT_BY_SEQ, {})
	var fallback: Variant = p.get_meta(META_PIVOT, p.position)
	var pos := _pivot_from_meta(fallback)
	if by_seq is Dictionary and not want_key.is_empty():
		var d: Dictionary = by_seq as Dictionary
		for k in d.keys():
			if _normalize_seq_key(str(k)) == want_key:
				pos = _pivot_from_meta(d[k])
				break
	p.position = pos


static func _pivot_from_meta(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if raw is PackedFloat32Array and (raw as PackedFloat32Array).size() >= 3:
		var pf: PackedFloat32Array = raw as PackedFloat32Array
		return Vector3(pf[0], pf[1], pf[2])
	return Vector3.ZERO


static func _normalize_seq_key(s: String) -> String:
	var leaf := s.strip_edges()
	var slash := leaf.rfind("/")
	if slash >= 0:
		leaf = leaf.substr(slash + 1)
	return leaf.replace("_", "").replace(" ", "").replace("-", "").to_lower()


static func _seqs_match(seqs: PackedStringArray, want_key: String) -> bool:
	if want_key.is_empty():
		return false
	for s in seqs:
		if _normalize_seq_key(str(s)) == want_key:
			return true
	return false


static func _prefab_exists(glb_path: String) -> bool:
	var tscn := pe2_tscn_path_from_glb(glb_path)
	if tscn.is_empty():
		return false
	if ResourceLoader.exists(tscn):
		return true
	return RuntimeAssets.file_exists(tscn)


static func _instantiate_prefab(_glb_path: String) -> Node3D:
	# 运行时禁用 pe2.tscn：全部 162 个预制的粒子贴图 ExtResource 落在
	# asset-converted/（.gdignore），Godot 报 No loader / Parse Error 刷屏。
	# 粒子改由 pe2.json + RuntimeAssets.load_converted_texture 构建。
	return null


static func _count_particle_nodes(root: Node) -> int:
	if root == null:
		return 0
	var n := 0
	if root is GPUParticles3D:
		n += 1
	for c in root.get_children():
		n += _count_particle_nodes(c)
	return n


## GLTF 常外包一层：InstanceRoot(scale≈1) → brazierOmni(scale=0.01)。PE2 必须挂后者。
static func resolve_model_root(instance_root: Node3D) -> Node3D:
	return _resolve_model_root(instance_root)


## GLTF 常外包一层：InstanceRoot(scale≈1) → brazierOmni(scale=0.01)。PE2 必须挂后者。
static func _resolve_model_root(instance_root: Node3D) -> Node3D:
	if _is_model_scale(instance_root.scale):
		return instance_root
	for c in instance_root.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if n.name == PE2_ROOT_NAME:
			continue
		if _is_model_scale(n.scale):
			return n
	return instance_root


static func _is_model_scale(s: Vector3) -> bool:
	return (
		absf(s.x - MODEL_SCALE) < 1e-3
		and absf(s.y - MODEL_SCALE) < 1e-3
		and absf(s.z - MODEL_SCALE) < 1e-3
	)


static func _make_emitter(em: Dictionary, index: int) -> GPUParticles3D:
	var life: float = maxf(0.05, float(em.get("life_span", 0.5)))
	var rate: float = maxf(0.0, float(em.get("emission_rate", 1.0)))
	# rate=0 的死亡爆发轨仍可能有 animated keys；amount 至少给一点，靠 emitting 开关
	var amount: int = clampi(ceili(maxf(rate, 8.0) * life * 1.35), 1, 256)
	var p := GPUParticles3D.new()
	p.name = str(em.get("name", "PE2_%d" % index))
	p.amount = amount
	p.lifetime = life
	p.preprocess = minf(life, 0.85)
	p.visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 200, 160))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = true

	var pivot: Array = em.get("pivot", [0, 0, 0]) as Array
	if pivot.size() >= 3:
		p.position = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
	p.set_meta(META_PIVOT, p.position)
	var by_seq_raw: Variant = em.get("pivot_by_sequence", null)
	if by_seq_raw is Dictionary:
		var store: Dictionary = {}
		for k in (by_seq_raw as Dictionary).keys():
			var arr: Variant = (by_seq_raw as Dictionary)[k]
			if arr is Array and (arr as Array).size() >= 3:
				var a: Array = arr as Array
				store[str(k)] = Vector3(float(a[0]), float(a[1]), float(a[2]))
		if not store.is_empty():
			p.set_meta(META_PIVOT_BY_SEQ, store)

	var scale_seg: Array = em.get("particle_scaling", [10, 10, 10]) as Array
	var s0 := maxf(0.1, float(scale_seg[0]) if scale_seg.size() > 0 else 10.0)
	var s1 := maxf(0.1, float(scale_seg[1]) if scale_seg.size() > 1 else s0)
	var s2 := maxf(0.1, float(scale_seg[2]) if scale_seg.size() > 2 else s1)

	var tex_rel := str(em.get("texture", ""))
	var tex: Texture2D = null
	if not tex_rel.is_empty():
		tex = _load_pe2_texture(tex_rel)

	var filter_mode: int = int(em.get("filter_mode", 0))
	var rows: int = maxi(1, int(em.get("rows", 1)))
	var cols: int = maxi(1, int(em.get("columns", 1)))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 粒子色 / color_ramp 写在 INSTANCE 顶点色上，必须开启
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	# Particle Billboard 才能启用序列帧
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if tex != null:
		mat.albedo_texture = tex
	# WC3 FilterMode: 0 Blend, 1 Additive；火焰/光晕用 ADD，黑底灰贴图才看得见
	if filter_mode == 1:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if rows > 1 or cols > 1:
		mat.particles_anim_h_frames = cols
		mat.particles_anim_v_frames = rows
		mat.particles_anim_loop = false

	# 材质挂在 Mesh 上（GPUParticles3D 的 material_override 对粒子 billboard 不可靠）
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat
	p.draw_pass_1 = quad

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = clampf(float(em.get("latitude", 0.0)), 0.0, 180.0)
	proc.flatness = 0.15
	var speed: float = maxf(0.0, float(em.get("speed", 0.0)))
	var variation: float = clampf(float(em.get("variation", 0.0)), 0.0, 1.0)
	proc.initial_velocity_min = speed * (1.0 - variation * 0.5)
	proc.initial_velocity_max = speed * (1.0 + variation * 0.5)
	var grav: float = float(em.get("gravity", 0.0))
	# WC3 gravity 沿 −Z；glTF 为 −Y
	proc.gravity = Vector3(0, -grav, 0)
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var half_w := maxf(0.5, float(em.get("width", 1.0)) * 0.5)
	var half_l := maxf(0.5, float(em.get("length", 1.0)) * 0.5)
	proc.emission_box_extents = Vector3(half_w, 0.5, half_l)
	# 三段缩放：用起止近似中段（略放大，编辑器预览更容易看见）
	const SCALE_VIS := 1.35
	proc.scale_min = minf(s0, s2) * 0.85 * SCALE_VIS
	proc.scale_max = maxf(s0, s1) * 1.05 * SCALE_VIS
	proc.scale_curve = _scale_curve(s0, s1, s2, float(em.get("time_middle", 0.5)))
	proc.color = Color.WHITE
	proc.color_ramp = _color_ramp(em)

	if rows > 1 or cols > 1:
		# speed=1 → 生命周期内播完整张表；用 life_span_uv 帧跨度估比例
		var uv_life: Array = em.get("life_span_uv", [0, 0, 1]) as Array
		var start_f := float(uv_life[0]) if uv_life.size() > 0 else 0.0
		var end_f := float(uv_life[1]) if uv_life.size() > 1 else float(rows * cols - 1)
		var total_frames := float(rows * cols)
		var span := maxf(1.0, absf(end_f - start_f) + 1.0)
		var speed_n := clampf(span / total_frames, 0.15, 1.0)
		proc.anim_speed_min = speed_n
		proc.anim_speed_max = speed_n
		proc.anim_offset_min = start_f / total_frames
		proc.anim_offset_max = start_f / total_frames

	p.process_material = proc
	_bind_sequence_meta(p, em)
	return p


## active_sequences=null → 全程；数组 → 仅这些 Sequence。
## 空数组 + visibility 脉冲：按 pe2.sequences 重推断（火枪 Flame 旧旁路常漏）。
static func _bind_sequence_meta(p: GPUParticles3D, em: Dictionary) -> void:
	var raw: Variant = em.get("active_sequences", null)
	if raw == null and not em.has("active_sequences"):
		var has_tracks: bool = em.has("visibility_keys") or em.has("emission_rate_keys")
		var rate := float(em.get("emission_rate", 0.0))
		if has_tracks or rate <= 0.01:
			p.set_meta(META_ALWAYS_ON, false)
			p.set_meta(META_ACTIVE_SEQS, PackedStringArray())
			p.emitting = false
			return
		# 旧旁路且像火盆：仍全程（重转后会有显式 null / 数组）
		p.set_meta(META_ALWAYS_ON, true)
		p.emitting = true
		return
	if raw == null:
		# 显式 null = 全程
		p.set_meta(META_ALWAYS_ON, true)
		p.emitting = true
		return
	var packed := PackedStringArray()
	if raw is Array:
		for s in raw as Array:
			var t := str(s).strip_edges()
			if not t.is_empty():
				packed.append(t)
	p.set_meta(META_ALWAYS_ON, false)
	p.set_meta(META_ACTIVE_SEQS, packed)
	# 默认关，等 apply_sequence / attach 末尾 Stand
	p.emitting = false


## 若 active_sequences 为空数组，用 visibility 脉冲帧重推断。
static func _ensure_active_sequences(em: Dictionary, sequences: Array) -> void:
	var raw: Variant = em.get("active_sequences", null)
	if raw == null:
		return
	if not (raw is Array) or not (raw as Array).is_empty():
		return
	var inferred := _infer_active_sequences(em, sequences)
	if not inferred.is_empty():
		em["active_sequences"] = inferred


static func _sync_active_seqs_from_payload(pe2_root: Node, data: Dictionary) -> void:
	if pe2_root == null or data.is_empty():
		return
	var sequences: Array = data.get("sequences", [])
	var emitters: Array = data.get("emitters", [])
	var by_name: Dictionary = {}
	for em in emitters:
		if typeof(em) != TYPE_DICTIONARY:
			continue
		var em_dict: Dictionary = (em as Dictionary).duplicate(true)
		_ensure_active_sequences(em_dict, sequences)
		by_name[str(em_dict.get("name", ""))] = em_dict
	_sync_active_seqs_node(pe2_root, by_name)


static func _sync_active_seqs_node(n: Node, by_name: Dictionary) -> void:
	if n is GPUParticles3D:
		var p := n as GPUParticles3D
		var em: Variant = by_name.get(p.name, null)
		if em is Dictionary:
			_bind_sequence_meta(p, em as Dictionary)
	for c in n.get_children():
		_sync_active_seqs_node(c, by_name)


## 与 convert-mdx activeSequencesForEmitter 对齐：采 vis 脉冲帧，勿只采 Sequence 中点。
static func _infer_active_sequences(em: Dictionary, sequences: Array) -> Array:
	var out: Array = []
	var vis_keys: Array = em.get("visibility_keys", []) as Array
	var rate_keys: Array = em.get("emission_rate_keys", []) as Array
	var static_rate := float(em.get("emission_rate", 0.0))
	var has_anim_rate := not rate_keys.is_empty()
	for s in sequences:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var interval: Array = (s as Dictionary).get("interval", [0, 0]) as Array
		var start := int(interval[0]) if interval.size() > 0 else 0
		var end := int(interval[1]) if interval.size() > 1 else start
		var mid := int((start + end) / 2)
		var frames: Dictionary = {mid: true, start: true, end: true}
		for k in vis_keys:
			if typeof(k) != TYPE_DICTIONARY:
				continue
			var fr := int((k as Dictionary).get("frame", 0))
			if fr >= start and fr <= end:
				frames[fr] = true
		for k in rate_keys:
			if typeof(k) != TYPE_DICTIONARY:
				continue
			var fr2 := int((k as Dictionary).get("frame", 0))
			if fr2 >= start and fr2 <= end:
				frames[fr2] = true
		var hit := false
		for fr3 in frames.keys():
			var vis := _sample_track(vis_keys, int(fr3), start, end, 1.0)
			var rate := (
				_sample_track(rate_keys, int(fr3), start, end, 0.0)
				if has_anim_rate
				else static_rate
			)
			if vis >= 0.5 and rate > 0.01:
				hit = true
				break
		if hit:
			var nm := str((s as Dictionary).get("name", "")).strip_edges()
			if not nm.is_empty():
				out.append(nm)
	return out


static func _sample_track(
	keys: Array, frame: int, start: int, end: int, default_v: float
) -> float:
	if keys.is_empty():
		return default_v
	var best: Variant = null
	for k in keys:
		if typeof(k) != TYPE_DICTIONARY:
			continue
		var fr := int((k as Dictionary).get("frame", 0))
		if fr < start:
			best = k
			continue
		if fr > end:
			break
		if fr <= frame:
			best = k
		else:
			break
	if best == null:
		for k2 in keys:
			if typeof(k2) != TYPE_DICTIONARY:
				continue
			var fr2 := int((k2 as Dictionary).get("frame", 0))
			if fr2 >= start and fr2 <= end:
				return float((k2 as Dictionary).get("value", default_v))
		return default_v
	return float((best as Dictionary).get("value", default_v))


## 优先 res:// 已导入贴图（便于 .pe2.tscn 保存 ExtResource）；否则磁盘 ImageTexture。
static func _load_pe2_texture(tex_rel: String) -> Texture2D:
	var res_path := RuntimeAssets.converted_path(tex_rel)
	if ResourceLoader.exists(res_path):
		var res: Resource = ResourceLoader.load(res_path)
		if res is Texture2D:
			return res as Texture2D
	return RuntimeAssets.load_converted_texture(tex_rel)


static func _segment_color(em: Dictionary, idx: int) -> Color:
	var segs: Array = em.get("segment_color", []) as Array
	var alphas: Array = em.get("alpha", [255, 255, 255]) as Array
	var rgb := Vector3(1, 1, 1)
	if idx < segs.size() and segs[idx] is Array:
		var a: Array = segs[idx]
		if a.size() >= 3:
			rgb = Vector3(float(a[0]), float(a[1]), float(a[2]))
	var alpha := 1.0
	if idx < alphas.size():
		alpha = clampf(float(alphas[idx]) / 255.0, 0.0, 1.0)
	return Color(rgb.x, rgb.y, rgb.z, alpha)


static func _color_ramp(em: Dictionary) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, float(em.get("time_middle", 0.5)), 1.0])
	g.colors = PackedColorArray([
		_segment_color(em, 0),
		_segment_color(em, 1),
		_segment_color(em, 2),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


static func _scale_curve(s0: float, s1: float, s2: float, mid: float) -> CurveTexture:
	var c := Curve.new()
	var m := clampf(mid, 0.05, 0.95)
	var denom := maxf(s0, 0.001)
	c.add_point(Vector2(0.0, s0 / denom))
	c.add_point(Vector2(m, s1 / denom))
	c.add_point(Vector2(1.0, s2 / denom))
	var tex := CurveTexture.new()
	tex.curve = c
	return tex
