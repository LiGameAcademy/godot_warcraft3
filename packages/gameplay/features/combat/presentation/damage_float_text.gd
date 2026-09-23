class_name DamageFloatText
extends Node3D

## 受击飘字（Present）。挂在目标单位上，只读 Pipeline 结算，不改生命。

const RISE_GODOT := 0.62
const DURATION := 0.9
const PIXEL_SIZE := 0.006
const FONT_SIZE := 56
const OUTLINE_SIZE := 14
const Y_PAD := 0.28
const META_SEQ := "dmg_float_seq"
const HIT_COLOR := Color(1.0, 0.92, 0.32, 1.0)
const KILL_COLOR := Color(1.0, 0.32, 0.22, 1.0)
const SPELL_COLOR := Color(0.45, 0.82, 1.0, 1.0)
const SPELL_KILL_COLOR := Color(0.35, 0.55, 1.0, 1.0)
const SKIP_VISUAL := {
	"SelectionRing": true,
	"DeathDropRing": true,
}

var _elapsed: float = 0.0
var _start_y: float = 0.0
var _label: Label3D = null


static func spawn(target: Node3D, result: Dictionary) -> DamageFloatText:
	if target == null or not is_instance_valid(target):
		return null
	if not bool(result.get("ok", false)):
		return null
	var node := DamageFloatText.new()
	node.name = "DamageFloat"
	target.add_child(node)
	var seq := int(target.get_meta(META_SEQ, 0))
	target.set_meta(META_SEQ, seq + 1)
	node.play(
		float(result.get("amount", 0.0)),
		bool(result.get("killed", false)),
		seq,
		str(result.get("source_kind", "")) == "spell"
		or str(result.get("atk_type", "")).to_lower() == "magic"
	)
	return node


func play(amount: float, killed: bool, seq: int = 0, spell: bool = false) -> void:
	_ensure_label()
	_label.text = _format_amount(amount)
	if spell:
		_label.modulate = SPELL_KILL_COLOR if killed else SPELL_COLOR
	else:
		_label.modulate = KILL_COLOR if killed else HIT_COLOR
	var side := 1.0 if (seq % 2) == 0 else -1.0
	_start_y = _estimate_anchor_y(get_parent() as Node3D) + Y_PAD + float(seq % 5) * 0.1
	position = Vector3(side * (0.06 + float(seq % 3) * 0.05), _start_y, 0.0)
	_elapsed = 0.0
	set_process(true)


func _ensure_label() -> void:
	if _label != null:
		return
	_label = Label3D.new()
	_label.name = "DamageFloatLabel"
	_label.font_size = FONT_SIZE
	_label.pixel_size = PIXEL_SIZE
	_label.outline_size = OUTLINE_SIZE
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label.render_priority = 16
	add_child(_label)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / DURATION, 0.0, 1.0)
	position.y = _start_y + RISE_GODOT * t
	if _label != null:
		var c := _label.modulate
		c.a = 1.0 - t * t
		_label.modulate = c
	if t >= 1.0:
		queue_free()


static func _format_amount(amount: float) -> String:
	var rounded := roundf(amount * 10.0) / 10.0
	if is_equal_approx(rounded, roundf(rounded)):
		return str(int(roundf(rounded)))
	return "%.1f" % rounded


static func _estimate_anchor_y(node: Node3D) -> float:
	if node == null:
		return 1.4
	var aabb := AABB()
	var first := true
	for c in node.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var nm := str(vi.name)
		if SKIP_VISUAL.has(nm) or nm.begins_with("DamageFloat"):
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
		return 1.4
	return maxf(aabb.end.y, 0.8)
