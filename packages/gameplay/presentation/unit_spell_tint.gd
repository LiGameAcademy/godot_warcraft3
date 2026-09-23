class_name UnitSpellTint
extends RefCounted

## 单位/建筑模型染色（Present）：material_overlay 叠霜蓝，瞄准提示与受击闪共用。

const META_SAVED := "unit_spell_tint_saved"
const SKIP_NAMES := {
	"SelectionRing": true,
	"DeathDropRing": true,
	"UberSplat": true,
	"DamageFloat": true,
	"SpellHitFx": true,
	"UnitHitFlash": true,
	"AbilityGroundFx": true,
	"TargetFlashRing": true,
}


## 对单位网格叠一层半透明染色；可重复调用（先清再染）。
static func apply(unit: Node3D, color: Color) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	clear(unit)
	var saved: Dictionary = {}
	for c in unit.find_children("*", "GeometryInstance3D", true, false):
		var gi := c as GeometryInstance3D
		if gi == null or not gi.visible:
			continue
		var nm := str(gi.name)
		if SKIP_NAMES.has(nm) or nm.begins_with("DamageFloat"):
			continue
		saved[gi.get_instance_id()] = gi.material_overlay
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.render_priority = 18
		mat.albedo_color = color
		gi.material_overlay = mat
	unit.set_meta(META_SAVED, saved)


static func clear(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if not unit.has_meta(META_SAVED):
		return
	var saved: Variant = unit.get_meta(META_SAVED)
	unit.remove_meta(META_SAVED)
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for c in unit.find_children("*", "GeometryInstance3D", true, false):
		var gi := c as GeometryInstance3D
		if gi == null:
			continue
		var id := gi.get_instance_id()
		if (saved as Dictionary).has(id):
			gi.material_overlay = (saved as Dictionary)[id] as Material


## 批量清理；nodes 里失效实例会跳过。
static func clear_many(nodes: Array) -> void:
	for n in nodes:
		if n is Node3D:
			clear(n as Node3D)
