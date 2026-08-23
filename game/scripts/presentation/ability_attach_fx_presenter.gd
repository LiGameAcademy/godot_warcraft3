class_name AbilityAttachFxPresenter
extends RefCounted

## 单位附着特效（Present · 通用）：施法者 / Buff 受益 / 限时 buff 附着。
## 组合用法：Logic 读 AbilityFxCatalog 路径，本类负责 spawn / sync / 清理。


static func sync_attach(
	host: Node3D,
	node_name: String,
	art_rel: String,
	active: bool,
	cache: MapModelCache = null,
	local_offset: Vector3 = Vector3(0.0, 0.5, 0.0),
	loop_stand: bool = true
) -> void:
	if host == null or not is_instance_valid(host) or node_name.is_empty():
		return
	var existing := host.get_node_or_null(node_name) as Node3D
	if not active or art_rel.is_empty():
		if existing != null:
			existing.queue_free()
		return
	if existing != null:
		return
	var inst := _spawn(art_rel, cache)
	if inst == null:
		return
	inst.name = node_name
	host.add_child(inst)
	inst.position = local_offset
	if loop_stand:
		_try_play_loop(inst, art_rel)


static func sync_beneficiaries(
	caster: Node3D,
	in_range: Array,
	art_rel: String,
	cache: MapModelCache,
	tracked: Dictionary,
	skip_caster: bool = true,
	local_offset: Vector3 = Vector3(0.0, 0.35, 0.0)
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
			continue
		var unit: Node3D = want[id]
		var inst := _spawn(art_rel, cache)
		if inst == null:
			continue
		inst.name = "AbilityBeneficiaryFx"
		unit.add_child(inst)
		inst.position = local_offset
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
	node_name: String = ""
) -> void:
	var nn := node_name if not node_name.is_empty() else "AbilityCasterFx_%s" % abil_id.strip_edges()
	var art := AbilityFxCatalog.caster_art(abil_id) if active else ""
	sync_attach(host, nn, art, active, cache, Vector3(0.0, 0.6, 0.0))


static func sync_buff_beneficiaries_for_abil(
	caster: Node3D,
	in_range: Array,
	abil_id: String,
	cache: MapModelCache,
	tracked: Dictionary
) -> void:
	sync_beneficiaries(
		caster,
		in_range,
		AbilityFxCatalog.buff_beneficiary_art(abil_id),
		cache,
		tracked,
		true
	)


static func _spawn(art_rel: String, cache: MapModelCache) -> Node3D:
	if art_rel.is_empty():
		return null
	var path := RuntimeAssets.converted_path(art_rel)
	if cache != null:
		var n := cache.instance_glb(path)
		if n != null:
			return n
	if ResourceLoader.exists(path):
		var packed := load(path)
		if packed is PackedScene:
			return (packed as PackedScene).instantiate() as Node3D
	return null


static func _try_play_loop(root: Node, art_rel: String) -> void:
	var ap := AnimPlayback.find_animation_player(root)
	if ap != null:
		ap.active = true
		var names := ap.get_animation_list()
		if not names.is_empty():
			ap.play(str(names[0]))
	if art_rel.is_empty():
		return
	var path := RuntimeAssets.converted_path(art_rel)
	if Wc3Pe2Particles.has_emitters(path):
		Wc3Pe2Particles.attach_to(root, path)
	Wc3Pe2Particles.apply_sequence(root, "Stand")
