class_name BrillianceAuraPresenter
extends RefCounted

## 辉煌光环表现（Present）：施法者 Brilliance + 受益单位 GeneralAuraTarget。

const ABIL_ID := "AHab"
const CASTER_ART := "Abilities/Spells/Human/Brilliance/Brilliance.mdl"
const BENEFICIARY_ART := "Abilities/Spells/Other/GeneralAuraTarget/GeneralAuraTarget.mdl"
const ATTACH_NODE := "BrillianceAuraAttach"


static func sync_caster(host: Node3D, active: bool, cache: MapModelCache) -> void:
	if host == null or not is_instance_valid(host):
		return
	var existing := host.get_node_or_null(ATTACH_NODE) as Node3D
	if not active:
		if existing != null:
			existing.queue_free()
		return
	if existing != null:
		return
	var art := CombatQuery.normalize_model_art(CASTER_ART)
	var inst := _spawn(art, cache)
	if inst == null:
		return
	inst.name = ATTACH_NODE
	host.add_child(inst)
	inst.position = Vector3(0.0, 0.6, 0.0)
	_try_play_loop(inst, art)


static func sync_beneficiaries(
	host: Node3D,
	in_range: Array,
	cache: MapModelCache,
	tracked: Dictionary
) -> void:
	var want: Dictionary = {}
	for n in in_range:
		if n is Node3D and is_instance_valid(n):
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
		if unit == host:
			continue
		var art := CombatQuery.normalize_model_art(BENEFICIARY_ART)
		var inst := _spawn(art, cache)
		if inst == null:
			continue
		inst.name = "BrillianceBeneficiaryFx"
		unit.add_child(inst)
		inst.position = Vector3(0.0, 0.35, 0.0)
		_try_play_loop(inst, art)
		tracked[id] = inst


static func clear_beneficiaries(tracked: Dictionary) -> void:
	for k in tracked.keys():
		var fx: Node = tracked[k]
		if fx != null and is_instance_valid(fx):
			fx.queue_free()
	tracked.clear()


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
	if not art_rel.is_empty():
		var path := RuntimeAssets.converted_path(art_rel)
		if Wc3Pe2Particles.has_emitters(path):
			Wc3Pe2Particles.attach_to(root, path)
		Wc3Pe2Particles.apply_sequence(root, "Stand")
