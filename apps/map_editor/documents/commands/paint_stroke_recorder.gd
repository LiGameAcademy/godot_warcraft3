class_name PaintStrokeRecorder
extends RefCounted

## 笔划期间采集 before/after；结束时生成 PaintStrokeCommand。


const CAPTURE_RADIUS := 3 ## 悬崖外扩邻域

var _doc = null
var _before: Dictionary = {} ## index → snapshot
var _after: Dictionary = {}
var _affects_cliff: bool = false
var _active: bool = false
## begin(full_heightfield=true) 时：整图 before；finish 时再扫一遍 after（含级联远端）。
var _full_heightfield: bool = false


func begin(document, full_heightfield: bool = false) -> void:
	_doc = document
	_before.clear()
	_after.clear()
	_affects_cliff = false
	_active = true
	_full_heightfield = full_heightfield

	# 悬崖 / 斜坡等「级联传播」操作应记下整张 heightfield before，
	# 否则 cliff 邻接 clamp / ramp 改到笔刷外会漏快照。
	# 禁止 capture_before_at(..., 999999)：会按半径嵌套空转 ~4e12 次卡死。
	if full_heightfield:
		_capture_all_before()


func is_active() -> bool:
	return _active


func mark_cliff() -> void:
	_affects_cliff = true


## 绘制前：保证区域内顶点有 before。
func capture_before_at(ix: int, iy: int, radius: int = CAPTURE_RADIUS) -> void:
	if not _active or _doc == null or _doc.heightfield == null:
		return
	# 整图模式 begin 已采全图；局部再采只会空转 has() 检查，直接跳过。
	if _full_heightfield:
		return
	var hf: Wc3Heightfield = _doc.heightfield
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = ix + dx
			var y: int = iy + dy
			if not hf.in_bounds(x, y):
				continue
			var i: int = hf.index_at(x, y)
			if _before.has(i):
				continue
			var snap := EditorVertexSnapshot.capture(hf, x, y)
			if snap != null:
				_before[i] = snap


## 仅采集给定顶点（半径 0）；用于斜坡 marked 精确快照。
func capture_before_points(points: Array[Vector2i]) -> void:
	for p in points:
		capture_before_at(p.x, p.y, 0)


func capture_after_points(points: Array[Vector2i]) -> void:
	for p in points:
		capture_after_at(p.x, p.y, 0)


## 绘制后：写入 after（仅相对 before 有变化的）。
func capture_after_at(ix: int, iy: int, radius: int = CAPTURE_RADIUS) -> void:
	if not _active or _doc == null or _doc.heightfield == null:
		return
	# 整图模式由 finish() 统一扫 after，避免笔划中重复全图对比。
	if _full_heightfield:
		return
	var hf: Wc3Heightfield = _doc.heightfield
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = ix + dx
			var y: int = iy + dy
			_capture_after_vertex(hf, x, y)


func finish(label: String = "Paint") -> PaintStrokeCommand:
	if _full_heightfield:
		_capture_all_after()
	_active = false
	_full_heightfield = false
	if _after.is_empty():
		_before.clear()
		return null
	# 只保留真正改过的 before
	var trimmed_before: Dictionary = {}
	for i in _after.keys():
		if _before.has(i):
			trimmed_before[i] = _before[i]
	var cmd := PaintStrokeCommand.new(trimmed_before, _after.duplicate(), _affects_cliff, label)
	_before.clear()
	_after.clear()
	return cmd


func cancel() -> void:
	_active = false
	_full_heightfield = false
	_before.clear()
	_after.clear()
	_affects_cliff = false


## 按地图尺寸遍历（O(w·h)），勿用超大 radius。
func _capture_all_before() -> void:
	if _doc == null or _doc.heightfield == null:
		return
	var hf: Wc3Heightfield = _doc.heightfield
	var w: int = hf.width
	var h: int = hf.height
	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			if _before.has(i):
				continue
			var snap := EditorVertexSnapshot.capture(hf, x, y)
			if snap != null:
				_before[i] = snap


## 整图 after：与 before 对比，记下所有被级联改动的顶点。
func _capture_all_after() -> void:
	if _doc == null or _doc.heightfield == null:
		return
	var hf: Wc3Heightfield = _doc.heightfield
	var w: int = hf.width
	var h: int = hf.height
	for y in range(h):
		for x in range(w):
			_capture_after_vertex(hf, x, y)


func _capture_after_vertex(hf: Wc3Heightfield, x: int, y: int) -> void:
	if not hf.in_bounds(x, y):
		return
	var i: int = hf.index_at(x, y)
	if not _before.has(i):
		return
	var snap := EditorVertexSnapshot.capture(hf, x, y)
	if snap == null:
		return
	var prev: EditorVertexSnapshot = _before[i] as EditorVertexSnapshot
	if prev != null and snap.equals_snap(prev):
		_after.erase(i)
	else:
		_after[i] = snap
