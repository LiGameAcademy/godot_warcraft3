class_name CombatProjectileOrigin
extends RefCounted
## 只修正表现起点；ProjectileService 的弹道/命中规则不查询动画。
static func weapon_start_wc3(attacker: Node3D, fallback_wc3: Vector3) -> Vector3:
	if not is_instance_valid(attacker):
		return fallback_wc3
	var unit: Unit = Unit.of(attacker)
	var model: Node3D = unit.model_node() if unit != null else attacker.get_node_or_null("Model") as Node3D
	if model == null:
		return fallback_wc3
	var socket: Node3D = _weapon_socket(model)
	if socket == null or not socket.is_inside_tree():
		return fallback_wc3
	# 发射帧骨骼已采样，挂点需要同步到这个姿态，而不是上一帧。
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		(node as Skeleton3D).force_update_all_bone_transforms()
	return Wc3Coords.godot_to_wc3(socket.global_position)

static func _weapon_socket(model: Node3D) -> Node3D:
	# Native BA 是骨骼原点；带 import_socket 的 Tip 才是 MDX pivot。
	for node: Node in model.find_children("*", "Node3D", true, false):
		var name: String = str(node.get_meta("import_socket", "")).replace(" ", "").replace("_", "").to_lower()
		if name in ["weapon", "weaponref"]:
			return node as Node3D
	var legacy: Wc3ModelScene = Wc3ModelScene.find_on(model)
	return legacy.find_socket("weapon") if legacy != null else null
