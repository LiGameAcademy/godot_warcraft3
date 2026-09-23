class_name AutocastButtonOverlay
extends Control

## 命令格自动施法覆盖层（Present）。
## 原作：图标本体干净；开自动时叠 `UI/Feedback/Autocast/UI-ModalButtonOn.mdx`
## （四角金色粒子沿边游走）。本控件用独立 TextureRect/粒子近似该层，不烘焙进图标。

enum State { HIDDEN, CAPABLE_OFF, ON }

const CORNER := 9
const THICK := 2
const SPARK := 5

var _state: int = State.HIDDEN
var _phase: float = 0.0
var _static_root: Control = null
var _spark_root: Control = null
var _sparks: Array[ColorRect] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_nodes()
	_apply_visual()
	set_process(false)


func set_autocast_state(capable: bool, active: bool) -> void:
	var next := State.HIDDEN
	if capable and active:
		next = State.ON
	elif capable:
		next = State.CAPABLE_OFF
	if next == _state:
		return
	_state = next
	_apply_visual()


func _ensure_nodes() -> void:
	if _static_root == null:
		_static_root = Control.new()
		_static_root.name = "StaticCorners"
		_static_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_static_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_static_root)
		_build_l_corners(_static_root, Color(0.55, 0.55, 0.58, 0.9))
	if _spark_root == null:
		_spark_root = Control.new()
		_spark_root.name = "SparkRing"
		_spark_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spark_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_spark_root)
		_sparks.clear()
		for i in range(4):
			var s := ColorRect.new()
			s.name = "Spark%d" % i
			s.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s.color = Color(1.0, 0.9, 0.25, 1.0)
			s.size = Vector2(SPARK, SPARK)
			_spark_root.add_child(s)
			_sparks.append(s)
		_build_l_corners(_spark_root, Color(1.0, 0.85, 0.2, 1.0))


func _build_l_corners(host: Control, col: Color) -> void:
	var specs: Array = [
		[0, 0, CORNER, THICK], [0, 0, THICK, CORNER],
		[1, 0, -CORNER, THICK], [1, 0, -THICK, CORNER],
		[0, 1, CORNER, -THICK], [0, 1, THICK, -CORNER],
		[1, 1, -CORNER, -THICK], [1, 1, -THICK, -CORNER],
	]
	for s in specs:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.color = col
		r.anchor_left = float(s[0])
		r.anchor_right = float(s[0])
		r.anchor_top = float(s[1])
		r.anchor_bottom = float(s[1])
		var w := int(s[2])
		var h := int(s[3])
		if w < 0:
			r.offset_left = float(w)
			r.offset_right = 0.0
		else:
			r.offset_left = 0.0
			r.offset_right = float(w)
		if h < 0:
			r.offset_top = float(h)
			r.offset_bottom = 0.0
		else:
			r.offset_top = 0.0
			r.offset_bottom = float(h)
		host.add_child(r)


func _apply_visual() -> void:
	_ensure_nodes()
	visible = _state != State.HIDDEN
	_static_root.visible = _state == State.CAPABLE_OFF
	_spark_root.visible = _state == State.ON
	set_process(_state == State.ON)
	if _state == State.ON:
		_update_sparks(0.0)


func _process(delta: float) -> void:
	if _state != State.ON:
		return
	_phase = fmod(_phase + delta * 1.15, 1.0)
	_update_sparks(_phase)


func _update_sparks(t: float) -> void:
	var sz := size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	# 四颗火花沿矩形边顺时针游走（近似 ModalButtonOn 粒子）
	for i in range(_sparks.size()):
		var u := fmod(t + float(i) * 0.25, 1.0)
		var p := _point_on_rect(sz, u)
		var s := _sparks[i]
		s.position = p - s.size * 0.5
		var pulse := 0.65 + 0.35 * sin((_phase + float(i) * 0.5) * TAU)
		s.modulate = Color(1, 1, 1, pulse)


func _point_on_rect(sz: Vector2, u: float) -> Vector2:
	var peri := 2.0 * (sz.x + sz.y)
	var d := clampf(u, 0.0, 0.999) * peri
	if d < sz.x:
		return Vector2(d, 0.0)
	d -= sz.x
	if d < sz.y:
		return Vector2(sz.x, d)
	d -= sz.y
	if d < sz.x:
		return Vector2(sz.x - d, sz.y)
	d -= sz.x
	return Vector2(0.0, sz.y - d)
