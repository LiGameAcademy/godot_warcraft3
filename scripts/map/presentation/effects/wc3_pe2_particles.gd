class_name Wc3Pe2Particles
extends RefCounted

## MDX ParticleEmitter2 → GPUParticles3D（JSON 映射的唯一实现）。
## 管线：convert-mdx.js `writePe2Sidecar` → `*.pe2.json`
##        → 本文件 `_make_emitter`
##        → bake:scn `scripts/tool/wc3_scn_pe2.gd` 写 `:emitting` 轨
## 弃用：`export_pe2_scenes.gd`（单独 pe2.tscn，默认不再调用）。
## 坐标与网格一致（glTF/Y-up，落在 convert 的 MODEL_SCALE=0.01 节点下）。
## v2：`active_sequences` — null/缺省=全程发射；数组=仅这些 WC3 Sequence 名下 emitting。
## 层：presentation（特效节点）。

const PE2_ROOT_NAME := "Pe2Root"
const MODEL_SCALE := 0.01
const META_ACTIVE_SEQS := "pe2_active_sequences"
const META_ALWAYS_ON := "pe2_always_on"
const META_PIVOT := "pe2_pivot"
const META_PIVOT_BY_SEQ := "pe2_pivot_by_sequence"
const META_VIS_KEYS := "pe2_visibility_keys"
const META_RATE_KEYS := "pe2_emission_rate_keys"
const META_STATIC_RATE := "pe2_static_rate"
## 有 Visibility/Rate 脉冲：emitting 交给 AnimationPlayer 轨，勿整段强开。
const META_PULSE := "pe2_pulse"
## 已挂 BoneAttachment：position 跟骨，勿再用世界 pivot_by_sequence。
const META_BONE_BOUND := "pe2_bone_bound"
## MDX ParticleEmitter2.Flags（与 Magos / war3-model 一致）
const FLAG_LINE_EMITTER := 0x20000
const FLAG_XY_QUAD := 0x100000
## FrameFlags：bit0=Head，bit1=Tail；也有导出写成枚举 0/1/2。
## 仅 2/3 或 bit1 当 Tail，避免把 Head-only 的 1 拧成拖尾（ArchMage 普攻火花）。


static func pe2_path_from_glb(glb_path: String) -> String:
	var p := glb_path.replace("\\", "/")
	var lower := p.to_lower()
	if lower.ends_with(".gltf"):
		return p.substr(0, p.length() - 5) + ".pe2.json"
	if lower.ends_with(".glb"):
		return p.substr(0, p.length() - 4) + ".pe2.json"
	return p + ".pe2.json"


## 无共同祖先时 `get_path_to` 会引擎 ERROR；先探测再取路径。
static func _safe_path_to(from: Node, to: Node) -> NodePath:
	if from == null or to == null:
		return NodePath()
	var walk: Node = from
	var seen: Dictionary = {}
	while walk != null:
		seen[walk] = true
		walk = walk.get_parent()
	walk = to
	while walk != null:
		if seen.has(walk):
			return from.get_path_to(to)
		walk = walk.get_parent()
	return NodePath()


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
	var parsed: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func has_emitters(glb_path: String) -> bool:
	# 以 pe2.json 为准。pe2.tscn 虽可提交，但 ExtResource 常指向
	# asset-converted（.gdignore），ResourceLoader 必失败并刷屏。
	var data := load_payload(glb_path)
	var emitters: Array = data.get("emitters", [])
	return not emitters.is_empty()


## 从 pe2.json 构建 Pe2Root（bake:scn 打进场景；运行时仅作旧 .scn 回退）。
static func build_root_from_glb(glb_path: String) -> Node3D:
	return build_root_from_payload(load_payload(glb_path))


static func build_root_from_payload(data: Dictionary) -> Node3D:
	var emitters: Array = data.get("emitters", []) if typeof(data) == TYPE_DICTIONARY else []
	if emitters.is_empty():
		return null
	var sequences: Array = data.get("sequences", []) if typeof(data) == TYPE_DICTIONARY else []
	var pe2_root := Node3D.new()
	pe2_root.name = PE2_ROOT_NAME
	var tex_cache: Dictionary = {}
	for i in range(emitters.size()):
		var em: Variant = emitters[i]
		if typeof(em) != TYPE_DICTIONARY:
			continue
		var em_dict: Dictionary = (em as Dictionary).duplicate(true)
		_ensure_active_sequences(em_dict, sequences)
		var node := _make_emitter(em_dict, i, tex_cache)
		if node == null:
			continue
		pe2_root.add_child(node)
		node.owner = pe2_root
	if pe2_root.get_child_count() == 0:
		pe2_root.free()
		return null
	return pe2_root


## 挂到「带 MODEL_SCALE 的模型根」下（勿挂 GLTF 外包层，否则 pivot 变成百米级）。
## 已有 Pe2Root（bake 进 .scn）则只同步 meta；否则从 pe2.json 动态构建。
## 若 Pe2Root 缺发射器（旧 bake / 残缺 scn）则拆掉重建，避免 :emitting 轨悬空刷警告。
## 返回发射器数量。
static func attach_to(root: Node3D, glb_path: String) -> int:
	if root == null or glb_path.is_empty():
		return 0
	var payload := load_payload(glb_path)
	var existing := root.find_child(PE2_ROOT_NAME, true, false)
	if existing != null:
		if _pe2_root_complete(existing, payload):
			_sync_active_seqs_from_payload(existing, payload)
			apply_sequence(root, "Stand")
			return _count_particle_nodes(existing)
		# 残缺：拆掉后按 payload 重建
		var ep := existing.get_parent()
		if ep != null:
			ep.remove_child(existing)
		existing.free()
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
	# 绑骨发射器（与 bake:scn 同一套）
	bind_emitters_to_bones(root, pe2_root)
	# 默认按「空闲 Stand」关闸；装饰物 always_on 不受影响
	apply_sequence(root, "Stand")
	return _count_particle_nodes(pe2_root)


## Pe2Root 是否覆盖 payload 中全部发射器名（绑骨后可能不在 Pe2Root 下，故扫整棵 root 祖先）。
static func _pe2_root_complete(pe2_root: Node, payload: Dictionary) -> bool:
	if pe2_root == null:
		return false
	var emitters: Array = payload.get("emitters", []) if typeof(payload) == TYPE_DICTIONARY else []
	if emitters.is_empty():
		return true
	var host: Node = pe2_root.get_parent()
	if host == null:
		host = pe2_root
	var present: Dictionary = {}
	for n in host.find_children("*", "GPUParticles3D", true, false):
		present[str(n.name)] = true
	for em in emitters:
		if typeof(em) != TYPE_DICTIONARY:
			continue
		var nm := str((em as Dictionary).get("name", "")).strip_edges()
		if nm.is_empty():
			continue
		if not present.has(nm):
			return false
	return true


## 把 pe2_bone 发射器挂到 BoneAttachment3D（跟杖尖等）。bake 与运行时回退共用。
static func bind_emitters_to_bones(root: Node, pe2_root: Node) -> int:
	if root == null or pe2_root == null:
		return 0
	var skeleton: Skeleton3D = null
	for c in root.find_children("*", "Skeleton3D", true, false):
		if c is Skeleton3D:
			skeleton = c as Skeleton3D
			break
	if skeleton == null:
		return 0
	var n := 0
	var particles: Array[GPUParticles3D] = []
	_collect_gpu_particles(pe2_root, particles)
	for p in particles:
		if not bool(p.get_meta(META_BONE_BOUND, false)):
			continue
		var bone := str(p.get_meta("pe2_bone", "")).strip_edges()
		if bone.is_empty() or skeleton.find_bone(bone) < 0:
			p.set_meta(META_BONE_BOUND, false)
			continue
		var old_parent := p.get_parent()
		if old_parent != null:
			old_parent.remove_child(p)
		p.owner = null
		# 已有 Attach_* / Tip：粒子跟杖尖同一 Transform，勿另建 BA + local_pivot
		var tip := find_attachment_tip_for_bone(root, bone)
		if tip != null:
			tip.add_child(p)
			p.transform = Transform3D.IDENTITY
			if p.has_meta(META_PIVOT_BY_SEQ):
				p.remove_meta(META_PIVOT_BY_SEQ)
			n += 1
			continue
		var local_pos := p.position
		var ba := BoneAttachment3D.new()
		ba.name = "BA_%s" % p.name
		ba.bone_name = bone
		ba.use_external_skeleton = true
		pe2_root.add_child(ba)
		var skel_path := _safe_path_to(ba, skeleton)
		if skel_path.is_empty():
			ba.queue_free()
			continue
		ba.external_skeleton = skel_path
		ba.add_child(p)
		p.position = local_pos
		if p.has_meta(META_PIVOT_BY_SEQ):
			p.remove_meta(META_PIVOT_BY_SEQ)
		n += 1
	return n


## 同骨 MDX 挂点上的 Tip（优先 Weapon / Staff）。
static func find_attachment_tip_for_bone(root: Node, bone: String) -> Node3D:
	if root == null or bone.is_empty():
		return null
	var want := bone.strip_edges().to_lower()
	var fallback: Node3D = null
	for n in root.find_children("*", "BoneAttachment3D", true, false):
		var ba := n as BoneAttachment3D
		if ba == null:
			continue
		if str(ba.bone_name).strip_edges().to_lower() != want:
			continue
		var tip := ba.get_node_or_null("Tip") as Node3D
		if tip == null:
			continue
		var key := str(ba.name).replace(" ", "").replace("-", "").replace("_", "").to_lower()
		if key.contains("weapon") or key.contains("staff"):
			return tip
		if fallback == null:
			fallback = tip
	return fallback


static func _collect_gpu_particles(n: Node, out: Array[GPUParticles3D]) -> void:
	if n is GPUParticles3D:
		out.append(n as GPUParticles3D)
	for c in n.get_children():
		_collect_gpu_particles(c, out)


## 按当前 WC3 Sequence 名开关发射器（建筑 Birth / Stand Work / Death 等）。
## sequence_name 可用空格或下划线；叶子名匹配即可。
## 有 vis/rate 脉冲：Stand/Walk/Birth 直接开；Attack 等先关，交给 Animation :emitting 轨。
## 顺带闸 Ribbon（同一 Sequence 语义）。preload 避免 class_name 缓存未就绪时的编译序问题。
static func apply_sequence(root: Node, sequence_name: String) -> void:
	if root == null:
		return
	var want := _normalize_seq_key(sequence_name)
	# 绑骨后粒子可能在 Pe2Root 外的 BoneAttachment 下
	for n in root.find_children("*", "GPUParticles3D", true, false):
		if not (n is GPUParticles3D):
			continue
		var p := n as GPUParticles3D
		if not p.has_meta(META_ACTIVE_SEQS) and not p.has_meta(META_ALWAYS_ON):
			continue
		_apply_sequence_to_particle(p, want)
	const _Ribbon := preload("res://scripts/presentation/wc3_model/wc3_ribbon_presenter.gd")
	_Ribbon.apply_sequence(root, sequence_name)


static func emitting_for_sequence(p: GPUParticles3D, sequence_name: String) -> bool:
	if p == null:
		return false
	if bool(p.get_meta(META_ALWAYS_ON, false)):
		return true
	var seqs: PackedStringArray = p.get_meta(META_ACTIVE_SEQS, PackedStringArray()) as PackedStringArray
	return _seqs_match(seqs, _normalize_seq_key(sequence_name))


static func pivot_for_sequence(p: GPUParticles3D, sequence_name: String) -> Vector3:
	var fallback: Variant = p.position
	if p != null:
		fallback = p.get_meta(META_PIVOT, p.position)
	var pos := _pivot_from_meta(fallback)
	var by_seq: Variant = p.get_meta(META_PIVOT_BY_SEQ, {}) if p != null else {}
	var want := _normalize_seq_key(sequence_name)
	if by_seq is Dictionary and not want.is_empty():
		var d: Dictionary = by_seq as Dictionary
		for k in d.keys():
			if _normalize_seq_key(str(k)) == want:
				return _pivot_from_meta(d[k])
	return pos


static func _apply_sequence_to_particle(p: GPUParticles3D, want_key: String) -> void:
	var in_seq := emitting_for_sequence(p, want_key)
	var pulse := bool(p.get_meta(META_PULSE, false))
	if bool(p.get_meta(META_ALWAYS_ON, false)):
		p.emitting = true
	elif not in_seq:
		# 切出本 Sequence：立刻关
		p.emitting = false
	elif pulse:
		# Stand/Walk 等常驻：直接开。否则 autoplay 后再 apply_sequence 会盖掉
		# Animation :emitting 轨在 t=0 的开闸，粒子一直灭（水元素脚底水花）。
		# Birth 召唤爆发：运行时同样常被后置 apply 盖灭，直接开。
		# Attack 等仍先关，交给 Animation 轨按 vis/rate 开。
		if _is_ambient_loop_key(want_key) or want_key.begins_with("birth"):
			p.emitting = true
		else:
			p.emitting = false
	else:
		p.emitting = true
	# 绑骨发射器跟 BoneAttachment，勿写世界空间 pivot
	if bool(p.get_meta(META_BONE_BOUND, false)):
		return
	p.position = pivot_for_sequence(p, want_key)


## Stand / Walk（含 Stand 2/3、Walk …）视为常驻循环序列。
static func _is_ambient_loop_key(want_key: String) -> bool:
	if want_key.is_empty():
		return false
	if want_key.begins_with("stand"):
		# Stand Work / Stand Upgrade / Stand Ready 等建造态仍走脉冲轨
		if (
			want_key.contains("work")
			or want_key.contains("upgrade")
			or want_key.contains("ready")
		):
			return false
		return true
	if want_key.begins_with("walk"):
		return true
	return false


## 兼容旧调用（仅 Pe2Root 子树）。
static func _apply_sequence_to_node(n: Node, want_key: String) -> void:
	if n is GPUParticles3D:
		_apply_sequence_to_particle(n as GPUParticles3D, want_key)
	for c in n.get_children():
		_apply_sequence_to_node(c, want_key)


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


static func _make_emitter(em: Dictionary, index: int, tex_cache: Dictionary) -> GPUParticles3D:
	var life: float = maxf(0.05, float(em.get("life_span", 0.5)))
	var rate: float = maxf(0.0, float(em.get("emission_rate", 1.0)))
	var frame_flags_early: int = int(em.get("frame_flags", 0))
	var has_tail := (
		frame_flags_early == 2 or frame_flags_early == 3 or (frame_flags_early & 2) != 0
	)
	# Godot 连续发射：同时存活数 ≈ rate × life。勿再 ×1.35（施工烟会叠成一团火）。
	# rate=0 的死亡爆发仍可能有 animated keys；amount 至少给一点，靠 emitting 开关。
	var amount: int = clampi(ceili((rate if rate > 0.01 else 8.0) * life), 1, 256)
	var flight_trail := has_tail and _em_is_flight_trail(em)
	# 飞行曳迹（Stand 青尾 / Birth-only 水滴）原作 rate 偏低 → 略增存活数
	if flight_trail and rate < 100.0:
		amount = clampi(maxi(amount * 3 + 8, amount + 14), 1, 72)
	var p := GPUParticles3D.new()
	p.name = str(em.get("name", "PE2_%d" % index))
	p.amount = amount
	p.lifetime = life
	p.preprocess = 0.12 if flight_trail else 0.0
	p.visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 200, 160))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = true

	var pivot: Array = em.get("pivot", [0, 0, 0]) as Array
	# 绑骨时优先 local_pivot（父骨局部）；否则用静态 PivotPoint
	var local_piv: Variant = em.get("local_pivot", null)
	if local_piv is Array and (local_piv as Array).size() >= 3:
		pivot = local_piv as Array
	if pivot.size() >= 3:
		p.position = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
	p.set_meta(META_PIVOT, p.position)
	var bone_name := str(em.get("bone", "")).strip_edges()
	if not bone_name.is_empty():
		p.set_meta(META_BONE_BOUND, true)
		p.set_meta("pe2_bone", bone_name)
	var by_seq_raw: Variant = em.get("pivot_by_sequence", null)
	if by_seq_raw is Dictionary and bone_name.is_empty():
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
		if tex_cache.has(tex_rel):
			tex = tex_cache[tex_rel] as Texture2D
		else:
			tex = _load_pe2_texture(tex_rel)
			tex_cache[tex_rel] = tex

	var filter_mode: int = int(em.get("filter_mode", 0))
	var rows: int = maxi(1, int(em.get("rows", 1)))
	var cols: int = maxi(1, int(em.get("columns", 1)))
	var flags: int = int(em.get("flags", 0))
	var frame_flags: int = frame_flags_early
	var xy_quad := (flags & FLAG_XY_QUAD) != 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 粒子色 / color_ramp 写在 INSTANCE 顶点色上，必须开启
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	# Particle Billboard 才能启用序列帧；XY Quad 跟发射器平面，不朝相机转
	if xy_quad:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	else:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if tex != null:
		mat.albedo_texture = tex
	# WC3 FilterMode: 0 Blend, 1 Additive。Additive 仍走粒子 Alpha（200→100→0），
	# 关掉 TRANSPARENCY 会把施工烟加成一团不透明亮斑。
	if filter_mode == 1:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	var tail_len := maxf(0.0, float(em.get("tail_length", 0.0)))
	if has_tail:
		# WC3 TailLength 是模型单位，再乘中段缩放才接近原作拉长
		var aspect := clampf(maxf(tail_len, 0.35) * s1 / maxf(s0, 0.1), 1.8, 5.0)
		quad.size = Vector2(1.0, aspect)
	else:
		quad.size = Vector2(1, 1)
	quad.material = mat
	p.draw_pass_1 = quad

	var proc := ParticleProcessMaterial.new()
	var speed_raw: float = float(em.get("speed", 0.0))
	# WC3 允许负 Speed（反向喷）；Godot 用方向符号 + |speed|
	var speed_sign := -1.0 if speed_raw < 0.0 else 1.0
	var speed: float = absf(speed_raw)
	proc.direction = Vector3(0, speed_sign, 0)
	proc.spread = clampf(float(em.get("latitude", 0.0)), 0.0, 180.0)
	proc.flatness = 0.15
	var variation: float = clampf(float(em.get("variation", 0.0)), 0.0, 1.0)
	proc.initial_velocity_min = speed * (1.0 - variation * 0.5)
	proc.initial_velocity_max = speed * (1.0 + variation * 0.5)
	var grav: float = float(em.get("gravity", 0.0))
	# WC3 gravity 沿 −Z；glTF 为 −Y
	proc.gravity = Vector3(0, -grav, 0)
	var width_u := maxf(0.0, float(em.get("width", 0.0)))
	var length_u := maxf(0.0, float(em.get("length", 0.0)))
	if width_u < 0.02 and length_u < 0.02:
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	else:
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		var half_w := maxf(0.01, width_u * 0.5)
		var half_l := maxf(0.01, length_u * 0.5)
		# LineEmitter：沿 Length 的细线，不要挤成正方盒
		if (flags & FLAG_LINE_EMITTER) != 0:
			half_w = maxf(0.01, width_u * 0.5)
			proc.emission_box_extents = Vector3(half_l, 0.01, half_w)
		else:
			proc.emission_box_extents = Vector3(half_w, 0.01, half_l)
	if has_tail:
		proc.particle_flag_align_y = true
	if bool(em.get("squirt", false)):
		p.explosiveness = 1.0
	# 三段缩放：scale_min=s0，曲线乘 s1/s0、s2/s0
	# Additive 短火花略放大，避免 Clouds 贴图在 Godot 里发灰发淡
	var scale_boost := 1.35 if filter_mode == 1 and life < 0.6 else 1.0
	if flight_trail:
		scale_boost *= 1.65
	proc.scale_min = s0 * scale_boost
	proc.scale_max = s0 * scale_boost
	proc.scale_curve = _scale_curve(s0, s1, s2, float(em.get("time_middle", 0.5)))
	proc.color = Color.WHITE
	proc.color_ramp = _color_ramp(em, filter_mode == 1)

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
	_mark_local(tex)
	_mark_local(mat)
	_mark_local(quad)
	_mark_local(proc)
	_bind_sequence_meta(p, em)
	var vis_v: Variant = em.get("visibility_keys", [])
	var rate_v: Variant = em.get("emission_rate_keys", [])
	p.set_meta(META_VIS_KEYS, vis_v if typeof(vis_v) == TYPE_ARRAY else [])
	p.set_meta(META_RATE_KEYS, rate_v if typeof(rate_v) == TYPE_ARRAY else [])
	p.set_meta(META_STATIC_RATE, float(em.get("emission_rate", 0.0)))
	var has_pulse := (
		(typeof(vis_v) == TYPE_ARRAY and not (vis_v as Array).is_empty())
		or (typeof(rate_v) == TYPE_ARRAY and not (rate_v as Array).is_empty())
	)
	p.set_meta(META_PULSE, has_pulse and not bool(p.get_meta(META_ALWAYS_ON, false)))
	# 火盆等全程发射需要预填，否则进场景是空的；施工烟一开就 preprocess 会瞬间灌满。
	if bool(p.get_meta(META_ALWAYS_ON, false)):
		p.preprocess = minf(life, 0.85)
	return p


static func _mark_local(res: Resource) -> void:
	if res != null:
		res.resource_local_to_scene = true
		res.resource_path = ""


## 飞行曳迹（非 Death 脉冲）：Stand，或无 Stand 时的 Birth（水元素弹）。
static func _em_is_flight_trail(em: Dictionary) -> bool:
	var raw: Variant = em.get("active_sequences", null)
	if raw == null:
		return false
	if not (raw is Array):
		return false
	var has_stand := false
	var has_birth := false
	var has_death := false
	for s in raw as Array:
		var t := str(s).strip_edges().to_lower()
		if t.contains("stand"):
			has_stand = true
		if t.contains("birth"):
			has_birth = true
		if t.contains("death"):
			has_death = true
	if has_death:
		return false
	return has_stand or has_birth


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
## Blizzard 等只有 Birth 的 PE2：convert 偶尔把 active 留成空数组（vis 全程=1），
## 应当**默认 = 全 Sequence** 而非关闸；否则「暴风雪只看见一闪，粒子全灭」。
static func _ensure_active_sequences(em: Dictionary, sequences: Array) -> void:
	var raw: Variant = em.get("active_sequences", null)
	if raw == null:
		return
	if not (raw is Array) or not (raw as Array).is_empty():
		return
	var inferred := _infer_active_sequences(em, sequences)
	if not inferred.is_empty():
		em["active_sequences"] = inferred
		return
	# 推断不到（如 vis 默认=1 的老转包）→ 兜底走全程
	var all: Array = []
	for s in sequences:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var nm := str((s as Dictionary).get("name", "")).strip_edges()
		if not nm.is_empty():
			all.append(nm)
	if not all.is_empty():
		em["active_sequences"] = all


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


## 与 convert-mdx sampleTrackInSequence 一致：只看 [start,end] 内的 key。
## 区间无 key → default（Visibility=1，Rate=0）。禁止跨 Sequence carry-in
## （Stand Work 烟 vis 全在别的段写 0，本段无 key，carry-in 会永远不喷）。
static func _sample_track(
	keys: Array, frame: int, start: int, end: int, default_v: float
) -> float:
	if keys.is_empty():
		return default_v
	var in_seq: Array = []
	for k in keys:
		if typeof(k) != TYPE_DICTIONARY:
			continue
		var fr := int((k as Dictionary).get("frame", 0))
		if fr >= start and fr <= end:
			in_seq.append(k)
	if in_seq.is_empty():
		return default_v
	var first_fr := int((in_seq[0] as Dictionary).get("frame", 0))
	if frame < first_fr:
		return default_v
	var value := default_v
	for k2 in in_seq:
		var fr2 := int((k2 as Dictionary).get("frame", 0))
		if fr2 <= frame:
			value = float((k2 as Dictionary).get("value", default_v))
		else:
			break
	return value


## 磁盘 ImageTexture（无 resource_path），bake 进 .scn 时内嵌，不链 asset-converted。
static func _load_pe2_texture(tex_rel: String) -> Texture2D:
	var tex: Texture2D = RuntimeAssets.load_converted_texture(tex_rel)
	if tex == null:
		return null
	if tex.resource_path.is_empty() and tex is ImageTexture:
		tex.resource_local_to_scene = true
		return tex
	var img := tex.get_image()
	if img == null:
		return tex
	var embedded := ImageTexture.create_from_image(img)
	embedded.resource_local_to_scene = true
	return embedded


static func _segment_color(em: Dictionary, idx: int, additive_boost: bool = false) -> Color:
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
	# Additive + 软云贴图在 Godot 里偏淡：略抬 RGB（仍夹到 1）
	if additive_boost:
		rgb *= 1.45
		rgb.x = minf(rgb.x, 1.0)
		rgb.y = minf(rgb.y, 1.0)
		rgb.z = minf(rgb.z, 1.0)
		alpha = minf(1.0, alpha * 1.15)
	return Color(rgb.x, rgb.y, rgb.z, alpha)


static func _color_ramp(em: Dictionary, additive_boost: bool = false) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, float(em.get("time_middle", 0.5)), 1.0])
	g.colors = PackedColorArray([
		_segment_color(em, 0, additive_boost),
		_segment_color(em, 1, additive_boost),
		_segment_color(em, 2, additive_boost),
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
