extends MeshInstance3D
## Embedded in the SCN. Endpoints are animated in model space; history is world space.
@export var below: Vector3 = Vector3.ZERO
@export var above: Vector3 = Vector3.ZERO
@export var emitting: bool = false
@export var ribbon_alpha: float = 1.0
@export var slot: int = 0
@export var clock: float = 0.0
@export var clip: String = ""
@export var life_span: float = 0.5
@export var emission_rate: float = 30.0
@export var tint: Color = Color.WHITE
@export var columns: int = 1
@export var rows: int = 1
var _points: Array[Dictionary] = []
var _clock: float = -1.0
var _clip: String = ""
var _remainder: float = 0.0
var _below: Vector3 = Vector3.ZERO
var _above: Vector3 = Vector3.ZERO

func _ready() -> void:
	process_priority = 100
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_delta: float) -> void:
	update_trail()

func reset_history() -> void:
	_points.clear()
	_remainder = 0.0
	mesh = null
	_clock = clock
	_clip = clip
	_below = global_transform * below
	_above = global_transform * above

func update_trail() -> void:
	var elapsed: float = clock - _clock
	# Seek/backwards/clip changes must not connect unrelated poses. A pause freezes history.
	if _clock < 0.0 or clip != _clip or elapsed < 0.0 or elapsed > 0.25:
		reset_history()
		return
	if elapsed <= 0.0:
		return
	var next_below: Vector3 = global_transform * below
	var next_above: Vector3 = global_transform * above
	for point: Dictionary in _points:
		point.age = float(point.age) + elapsed
	while not _points.is_empty() and float(_points[0].age) > life_span:
		_points.pop_front()
	if emitting and emission_rate > 0.0:
		var interval: float = 1.0 / emission_rate
		var next: float = interval - _remainder
		while next <= elapsed + 0.000001:
			var weight: float = clampf(next / elapsed, 0.0, 1.0)
			_points.append({"below": _below.lerp(next_below, weight), "above": _above.lerp(next_above, weight), "age": maxf(0.0, elapsed-next)})
			next += interval
		_remainder = fposmod(_remainder + elapsed, interval)
	else:
		_remainder = 0.0
	_clock = clock
	_below = next_below
	_above = next_above
	_rebuild()

func _rebuild() -> void:
	if _points.size() < 2:
		mesh = null
		return
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inverse: Transform3D = global_transform.affine_inverse()
	var cell: int = clampi(slot, 0, columns * rows - 1)
	var color: Color = Color(tint, tint.a * ribbon_alpha)
	for index: int in range(_points.size()-1):
		for corner: int in [0, 1, 3, 0, 3, 2]:
			var point: Dictionary = _points[index + (1 if corner >= 2 else 0)]
			var top: bool = corner % 2 == 1
			var u: float = (float(cell % columns) + clampf(float(point.age) / life_span, 0.0, 1.0)) / columns
			var v: float = (floorf(float(cell) / columns) + (1.0 if top else 0.0)) / rows
			surface.set_color(color)
			surface.set_uv(Vector2(u, v))
			surface.add_vertex(inverse * (point.above if top else point.below))
	mesh = surface.commit()
