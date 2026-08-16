class_name TargetFlashFx
extends RefCounted

## 目标确认反馈：优先走单位上的 Interactable；仅保留模型闪烁工具。

const RING_COLOR := Color(1.0, 0.92, 0.15, 1.0)
const FLASH_EMISSION := Color(1.0, 0.88, 0.12)
const DEFAULT_DURATION := 0.65
const DEFAULT_DIAM := 1.1


## 黄环 + 模型闪烁（树木右键等）。
static func flash_target(
	host: Node3D,
	duration: float = DEFAULT_DURATION,
	diameter: float = DEFAULT_DIAM,
	flash_model: bool = true
) -> void:
	if host == null or not is_instance_valid(host):
		return
	flash_ring(host, duration, diameter)
	if flash_model:
		flash_model_emission(host, duration)


## 兼容旧名
static func flash_on(
	host: Node3D,
	duration: float = DEFAULT_DURATION,
	diameter: float = DEFAULT_DIAM
) -> MeshInstance3D:
	flash_ring(host, duration, diameter)
	return host.get_node_or_null("SelectionRing") as MeshInstance3D


static func flash_ring(
	host: Node3D,
	duration: float = DEFAULT_DURATION,
	diameter: float = DEFAULT_DIAM
) -> MeshInstance3D:
	InteractionSetup.attach(host)
	var ic := InteractionSetup.get_interactable(host)
	if ic != null:
		ic.flash(duration, false)
		return host.get_node_or_null("SelectionRing") as MeshInstance3D
	var ring := host.get_node_or_null("SelectionRing") as SelectionRing
	if ring != null:
		ring.play_interact_flash(diameter, duration, RING_COLOR)
	return ring


## 模型 emissive 闪两下（原作点选反馈感）。
static func flash_model_emission(host: Node3D, duration: float = DEFAULT_DURATION) -> void:
	if host == null or not is_instance_valid(host):
		return
	var tree := host.get_tree()
	if tree == null:
		return
	var touched: Array = [] ## { mi, mat, prev_override }
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var nm := str(mi.name)
		if nm == "TargetFlashRing" or nm == "SelectionRing" or nm == "DeathDropRing":
			continue
		if _is_under_named(mi, "Pe2Root"):
			continue
		var prev_override: Material = mi.material_override
		var base_mat: Material = prev_override
		if base_mat == null:
			base_mat = mi.get_active_material(0)
		var flash_mat: BaseMaterial3D = null
		if base_mat is BaseMaterial3D:
			flash_mat = (base_mat as BaseMaterial3D).duplicate() as BaseMaterial3D
		else:
			# ShaderMaterial 等：临时换成可发光材质做闪烁
			flash_mat = StandardMaterial3D.new()
			flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flash_mat.albedo_color = Color(1.0, 0.9, 0.25, 1.0)
		if flash_mat == null:
			continue
		flash_mat.emission_enabled = true
		flash_mat.emission = FLASH_EMISSION
		flash_mat.emission_energy_multiplier = 0.0
		mi.material_override = flash_mat
		touched.append({"mi": mi, "mat": flash_mat, "prev_override": prev_override})
	if touched.is_empty():
		return
	var half := maxf(duration * 0.25, 0.08)
	var tw := tree.create_tween()
	# 亮 → 暗 → 亮 → 暗
	for _pulse in range(2):
		tw.tween_method(
			func(e: float) -> void: _set_emission_energy(touched, e),
			0.0,
			3.2,
			half
		).set_ease(Tween.EASE_OUT)
		tw.tween_method(
			func(e: float) -> void: _set_emission_energy(touched, e),
			3.2,
			0.0,
			half
		).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _restore_materials(touched))


static func _set_emission_energy(touched: Array, energy: float) -> void:
	for rec in touched:
		var mat: Variant = rec.get("mat", null)
		if mat is BaseMaterial3D:
			(mat as BaseMaterial3D).emission_energy_multiplier = energy


static func _restore_materials(touched: Array) -> void:
	for rec in touched:
		var mi: MeshInstance3D = rec.get("mi", null) as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		mi.material_override = rec.get("prev_override", null) as Material


static func _is_under_named(n: Node, root_name: String) -> bool:
	var p := n.get_parent()
	while p != null:
		if str(p.name) == root_name:
			return true
		p = p.get_parent()
	return false
