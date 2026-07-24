class_name PaintStrokeRecorder
extends RefCounted

## 笔划期间采集 before/after；结束时生成 PaintStrokeCommand。


const CAPTURE_RADIUS := 3 ## 悬崖外扩邻域

var _doc = null
var _before: Dictionary = {} ## index → snapshot
var _after: Dictionary = {}
var _affects_cliff: bool = false
var _active: bool = false


func begin(document) -> void:
	_doc = document
	_before.clear()
	_after.clear()
	_affects_cliff = false
	_active = true


func is_active() -> bool:
	return _active


func mark_cliff() -> void:
	_affects_cliff = true


## 绘制前：保证区域内顶点有 before。
func capture_before_at(ix: int, iy: int, radius: int = CAPTURE_RADIUS) -> void:
	if not _active or _doc == null or _doc.heightfield == null:
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


## 绘制后：写入 after（仅相对 before 有变化的）。
func capture_after_at(ix: int, iy: int, radius: int = CAPTURE_RADIUS) -> void:
	if not _active or _doc == null or _doc.heightfield == null:
		return
	var hf: Wc3Heightfield = _doc.heightfield
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = ix + dx
			var y: int = iy + dy
			if not hf.in_bounds(x, y):
				continue
			var i: int = hf.index_at(x, y)
			if not _before.has(i):
				continue
			var snap := EditorVertexSnapshot.capture(hf, x, y)
			if snap == null:
				continue
			var prev: EditorVertexSnapshot = _before[i] as EditorVertexSnapshot
			if prev != null and snap.equals_snap(prev):
				_after.erase(i)
			else:
				_after[i] = snap


func finish(label: String = "Paint") -> PaintStrokeCommand:
	_active = false
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
	_before.clear()
	_after.clear()
	_affects_cliff = false
