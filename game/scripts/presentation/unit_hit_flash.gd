class_name UnitHitFlash
extends Node

## 受击闪色（Present）：短暂霜蓝 material_overlay，对齐「单位闪一下」。

const LIFETIME := 0.22
const SPELL_COLOR := Color(0.35, 0.78, 1.0, 0.48)
const HIT_COLOR := Color(1.0, 0.92, 0.55, 0.42)
const META_GATE := "unit_hit_flash_t"

var _age: float = 0.0
var _host: Node3D = null
var _base_color := SPELL_COLOR


static func flash(unit: Node3D, spell: bool = true) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var now_ms := Time.get_ticks_msec()
	if unit.has_meta(META_GATE) and now_ms - int(unit.get_meta(META_GATE)) < 70:
		return
	unit.set_meta(META_GATE, now_ms)
	var existing := unit.get_node_or_null("UnitHitFlash") as UnitHitFlash
	if existing != null:
		existing._restart(spell)
		return
	var fx := UnitHitFlash.new()
	fx.name = "UnitHitFlash"
	unit.add_child(fx)
	fx._start(spell)


func _start(spell: bool) -> void:
	_host = get_parent() as Node3D
	_base_color = SPELL_COLOR if spell else HIT_COLOR
	UnitSpellTint.apply(_host, _base_color)
	_age = 0.0
	set_process(true)


func _restart(spell: bool) -> void:
	_base_color = SPELL_COLOR if spell else HIT_COLOR
	if _host != null and is_instance_valid(_host):
		UnitSpellTint.apply(_host, _base_color)
	_age = 0.0


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	_fade_overlays(1.0 - t)
	if t >= 1.0:
		if _host != null and is_instance_valid(_host):
			UnitSpellTint.clear(_host)
		queue_free()


func _fade_overlays(alpha_mul: float) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	for c in _host.find_children("*", "GeometryInstance3D", true, false):
		var gi := c as GeometryInstance3D
		if gi == null:
			continue
		var mat := gi.material_overlay as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_color = Color(
			_base_color.r, _base_color.g, _base_color.b, _base_color.a * alpha_mul
		)


func _exit_tree() -> void:
	if _host != null and is_instance_valid(_host):
		UnitSpellTint.clear(_host)
