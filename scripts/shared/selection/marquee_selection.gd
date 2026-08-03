class_name MarqueeSelection
extends RefCounted
## 屏幕空间框选（编辑器 / 游戏共用）。纯逻辑，不含绘制。


signal changed(rect: Rect2, active: bool)

var active: bool = false
var start_screen: Vector2 = Vector2.ZERO
var end_screen: Vector2 = Vector2.ZERO
## 拖过此像素才算框选（避免单击误触发）
var drag_threshold_px: float = 4.0


func begin(screen_pos: Vector2) -> void:
	active = true
	start_screen = screen_pos
	end_screen = screen_pos
	changed.emit(get_rect(), true)


func update(screen_pos: Vector2) -> void:
	if not active:
		return
	end_screen = screen_pos
	changed.emit(get_rect(), true)


## 返回最终矩形；未超过阈值则视为单击（rect 面积为 0）。
func finish() -> Rect2:
	var r := get_rect()
	active = false
	changed.emit(r, false)
	if not exceeded_threshold():
		return Rect2()
	return r


func cancel() -> void:
	active = false
	start_screen = Vector2.ZERO
	end_screen = Vector2.ZERO
	changed.emit(Rect2(), false)


func exceeded_threshold() -> bool:
	return start_screen.distance_to(end_screen) >= drag_threshold_px


func get_rect() -> Rect2:
	var a := start_screen
	var b := end_screen
	var pos := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var size := Vector2(absf(a.x - b.x), absf(a.y - b.y))
	return Rect2(pos, size)


## 世界点投影到屏幕后是否落在框内（相机后方视为不在）。
static func world_in_rect(camera: Camera3D, world_pos: Vector3, rect: Rect2) -> bool:
	if camera == null or rect.size.x < 0.5 or rect.size.y < 0.5:
		return false
	if camera.is_position_behind(world_pos):
		return false
	return rect.has_point(camera.unproject_position(world_pos))
