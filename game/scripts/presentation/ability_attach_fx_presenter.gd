class_name AbilityAttachFxPresenter
extends RefCounted

## 单位附着特效（Present · 通用）：施法者 / Buff 受益 / 限时 buff 附着。
## 组合用法：Logic 读 AbilityFxCatalog 路径，本类负责 spawn / sync / 清理。
##
## 挂点：优先 `Wc3ModelScene.find_socket` / `overhead_anchor`（OverHead Ref），
## 无挂点再回退单位根 + AABB 顶。不改骨骼树、不建 BoneAttachment。
##
## `on_entity_root`：挂单位实体根、位置取挂点世界坐标（to_local）。
## 避免 FX 进入单位 MODEL_SCALE≈0.01 子树被二次缩小（光环 / 命中特效）。


static func sync_attach(
	host: Node3D,
	node_name: String,
	art_rel: String,
	active: bool,
	cache: MapModelCache = null,
	local_offset: Vector3 = Vector3(0.0, 0.5, 0.0),
	loop_stand: bool = true,
	attach_hint: String = "",
	scale: float = 1.0,
	on_entity_root: bool = false
) -> void:
	if host == null or not is_instance_valid(host) or node_name.is_empty():
		return
	var existing := _find_named(host, node_name)
	if not active or art_rel.is_empty():
		if existing != null:
			existing.queue_free()
		return
	if existing != null:
		# 旧实例挂在缩放子树下 → 重建到实体根
		if on_entity_root and existing.get_parent() != host:
			existing.queue_free()
		else:
			return
	var inst := _spawn(art_rel, cache)
	if inst == null:
		return
	inst.name = node_name
	_parent_fx(host, inst, attach_hint, local_offset, on_entity_root)
	if scale > 0.0 and not is_equal_approx(scale, 1.0):
		inst.scale = Vector3.ONE * scale
	if loop_stand:
		_try_play_loop(inst, art_rel)
	else:
		_try_play_once(inst, art_rel)


## 一次性附着 FX（Birth），到期 queue_free；不走 sync 常驻节点名。
static func spawn_timed(
	host: Node3D,
	art_rel: String,
	lifetime_sec: float,
	cache: MapModelCache = null,
	attach_hint: String = "origin",
	local_offset: Vector3 = Vector3(0.0, 0.05, 0.0),
	on_entity_root: bool = false
) -> Node3D:
	if host == null or not is_instance_valid(host) or art_rel.strip_edges().is_empty():
		return null
	var inst := _spawn(art_rel, cache)
	if inst == null:
		return null
	inst.name = "TimedAbilityFx"
	_parent_fx(host, inst, attach_hint, local_offset, on_entity_root)
	_try_play_once(inst, art_rel)
	var tree := host.get_tree()
	if tree != null:
		var dur := maxf(lifetime_sec, 0.35)
		tree.create_timer(dur).timeout.connect(
			func() -> void:
				if is_instance_valid(inst):
					inst.queue_free()
		)
	return inst


static func sync_beneficiaries(
	caster: Node3D,
	in_range: Array,
	art_rel: String,
	cache: MapModelCache,
	tracked: Dictionary,
	skip_caster: bool = true,
	local_offset: Vector3 = Vector3(0.0, 0.35, 0.0),
	on_entity_root: bool = false,
	attach_hint: String = "origin"
) -> void:
	if art_rel.is_empty():
		clear_beneficiaries(tracked)
		return
	var want: Dictionary = {}
	for n in in_range:
		if n is Node3D and is_instance_valid(n):
			if skip_caster and n == caster:
				continue
			want[(n as Node3D).get_instance_id()] = n
	for k in tracked.keys():
		if not want.has(k):
			var fx: Node = tracked[k]
			if fx != null and is_instance_valid(fx):
				fx.queue_free()
			tracked.erase(k)
	for id in want.keys():
		if tracked.has(id):
			var kept: Node = tracked[id]
			if (
				on_entity_root
				and kept is Node3D
				and is_instance_valid(kept)
				and (kept as Node3D).get_parent() != want[id]
			):
				kept.queue_free()
				tracked.erase(id)
			else:
				continue
		var unit: Node3D = want[id]
		var inst := _spawn(art_rel, cache)
		if inst == null:
			continue
		inst.name = "AbilityBeneficiaryFx"
		_parent_fx(unit, inst, attach_hint, local_offset, on_entity_root)
		_try_play_loop(inst, art_rel)
		tracked[id] = inst


static func clear_beneficiaries(tracked: Dictionary) -> void:
	for k in tracked.keys():
		var fx: Node = tracked[k]
		if fx != null and is_instance_valid(fx):
			fx.queue_free()
	tracked.clear()


static func sync_caster_abil(
	host: Node3D,
	abil_id: String,
	active: bool,
	cache: MapModelCache = null,
	node_name: String = "",
	on_entity_root: bool = false
) -> void:
	var nn := node_name if not node_name.is_empty() else "AbilityCasterFx_%s" % abil_id.strip_edges()
	var art := AbilityFxCatalog.caster_art(abil_id) if active else ""
	var attach := AbilityFxCatalog.target_attach(abil_id)
	if attach.is_empty():
		attach = "origin"
	var fallback := Vector3(0.0, 0.05, 0.0) if on_entity_root else Vector3(0.0, 0.6, 0.0)
	sync_attach(host, nn, art, active, cache, fallback, true, attach, 1.0, on_entity_root)


static func sync_buff_beneficiaries_for_abil(
	caster: Node3D,
	in_range: Array,
	abil_id: String,
	cache: MapModelCache,
	tracked: Dictionary,
	skip_caster: bool = true,
	on_entity_root: bool = false
) -> void:
	var attach := AbilityFxCatalog.target_attach(abil_id)
	if attach.is_empty():
		attach = "origin"
	sync_beneficiaries(
		caster,
		in_range,
		AbilityFxCatalog.buff_beneficiary_art(abil_id),
		cache,
		tracked,
		skip_caster,
		Vector3.ZERO if on_entity_root else Vector3(0.0, 0.35, 0.0),
		on_entity_root,
		attach
	)


## 解析挂点父节点：优先 Wc3ModelScene 插座，否则单位根 + 偏移。
## 对外别名（弹道命中 / SpellHit 等复用）。
static func resolve_attach(
	host: Node3D,
	attach_hint: String = "origin",
	fallback_offset: Vector3 = Vector3(0.0, 0.5, 0.0)
) -> Dictionary:
	return _resolve_parent(host, attach_hint, fallback_offset)


static func _parent_fx(
	host: Node3D,
	inst: Node3D,
	attach_hint: String,
	local_offset: Vector3,
	on_entity_root: bool
) -> void:
	if on_entity_root:
		var sock_place := _resolve_parent(host, attach_hint, local_offset)
		var sock: Node3D = sock_place.get("parent", null) as Node3D
		var world := host.global_position + local_offset
		if sock != null and is_instance_valid(sock) and sock != host:
			world = sock.global_position
			var lp: Vector3 = sock_place.get("local_pos", Vector3.ZERO) as Vector3
			if lp.length_squared() > 0.0001:
				world = sock.to_global(lp)
		host.add_child(inst)
		inst.global_position = world
		return
	var place := _resolve_parent(host, attach_hint, local_offset)
	var parent: Node3D = place.get("parent", host) as Node3D
	if parent == null or not is_instance_valid(parent):
		parent = host
	parent.add_child(inst)
	inst.position = place.get("local_pos", local_offset) as Vector3


## 解析挂点父节点：优先 Wc3ModelScene 插座，否则单位根 + 偏移。
static func _resolve_parent(
	host: Node3D,
	attach_hint: String,
	fallback_offset: Vector3
) -> Dictionary:
	var hint := attach_hint.strip_edges().to_lower()
	var scene := Wc3ModelScene.find_on(host)
	if scene != null:
		var sock: Node3D = null
		if not hint.is_empty():
			sock = scene.find_socket(hint)
		# chest 未命中时回退 origin（命中 FX 挂躯干，勿漂世界坐标）
		if sock == null and (hint == "chest" or hint == "chestref"):
			sock = scene.find_socket("origin")
		if sock == null and hint.is_empty():
			sock = scene.find_socket("origin")
			if sock == null:
				sock = scene.overhead_anchor()
		if sock != null and is_instance_valid(sock):
			return {"parent": sock, "local_pos": Vector3.ZERO}
	if hint == "overhead" or hint == "overheadref":
		return {
			"parent": host,
			"local_pos": Vector3(0.0, _estimate_height(host), 0.0),
		}
	return {"parent": host, "local_pos": fallback_offset}


static func _find_named(host: Node3D, node_name: String) -> Node3D:
	var direct := host.get_node_or_null(node_name) as Node3D
	if direct != null:
		return direct
	return host.find_child(node_name, true, false) as Node3D


static func _spawn(art_rel: String, cache: MapModelCache) -> Node3D:
	if art_rel.is_empty():
		return null
	var path := RuntimeAssets.converted_path(art_rel)
	var inst: Node3D = null
	if cache != null:
		inst = cache.instance_glb(path)
	if inst == null and ResourceLoader.exists(path):
		var packed := load(path)
		if packed is PackedScene:
			inst = (packed as PackedScene).instantiate() as Node3D
	if inst == null:
		return null
	if cache != null:
		cache.prepare_fx_model(inst)
	return inst


static func _try_play_loop(root: Node, art_rel: String) -> void:
	var ap := AnimPlayback.find_animation_player(root)
	if ap != null:
		ap.active = true
		# 光环 / 常驻附着：Stand 强制 LOOP（双环扩张靠骨骼 scale 循环）
		var resolved := AnimPlayback.resolve(root, "Stand", ap)
		if resolved.is_empty():
			var names := ap.get_animation_list()
			if not names.is_empty():
				resolved = str(names[0])
		if not resolved.is_empty():
			AnimPlayback.play(root, resolved, 0.0, null, 1, ap)
	if art_rel.is_empty():
		return
	var path := RuntimeAssets.converted_path(art_rel)
	if Wc3Pe2Particles.has_emitters(path):
		Wc3Pe2Particles.attach_to(root, path)
	Wc3Pe2Particles.apply_sequence(root, "Stand")


static func _try_play_once(root: Node, art_rel: String) -> void:
	var ap := AnimPlayback.find_animation_player(root)
	var pick := "Birth"
	if ap != null:
		ap.active = true
		var names := ap.get_animation_list()
		if not names.is_empty():
			pick = str(names[0])
			for n in names:
				var leaf := str(n)
				var slash := leaf.rfind("/")
				if slash >= 0:
					leaf = leaf.substr(slash + 1)
				var low := leaf.to_lower()
				if low.begins_with("birth"):
					pick = str(n)
					break
			ap.play(pick)
	if art_rel.is_empty():
		return
	var path := RuntimeAssets.converted_path(art_rel)
	if Wc3Pe2Particles.has_emitters(path):
		Wc3Pe2Particles.attach_to(root, path)
	var seq_leaf := pick
	var slash2 := seq_leaf.rfind("/")
	if slash2 >= 0:
		seq_leaf = seq_leaf.substr(slash2 + 1)
	Wc3Pe2Particles.apply_sequence(root, seq_leaf)


static func _estimate_height(node: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for c in node.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var nm := str(vi.name)
		if nm.begins_with("DamageFloat") or nm.contains("Fx") or nm.contains("Attach"):
			continue
		var local := vi.get_aabb()
		var xf: Transform3D = node.global_transform.affine_inverse() * vi.global_transform
		var la := xf * local
		if first:
			aabb = la
			first = false
		else:
			aabb = aabb.merge(la)
	if first:
		return 1.2
	return maxf(aabb.end.y, 0.8)
