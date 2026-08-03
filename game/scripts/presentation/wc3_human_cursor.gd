class_name Wc3HumanCursor
extends Node

## 人族鼠标光标（HumanCursor.png 图集）。
## 32×32 格，8 列 × 4 行；第 1 行空白。
## 用 Input.set_custom_mouse_cursor 逐帧切换，保证点击热区正确。

const SHEET_PATH := "res://assets/asset-converted/UI/Cursor/HumanCursor.png"
const CELL := 32
const COLS := 8

enum Mode {
	IDLE, ## 默认指向手（8 帧循环）
	TARGET, ## 白瞄准圈（攻击/技能点目标）
	ALLY, ## 青瞄准圈（友方）
	INVALID, ## 禁止
	SELECT, ## 静态选择手
	HAND_ALT_A, ## 备用手势
	HAND_ALT_B, ## 备用手势
	MOVE, ## 移动指令箭头（短动画后回 IDLE）
}

@export var fps: float = 12.0
@export var move_flash_loops: int = 2
@export var enabled: bool = true

var _sheet: Texture2D
var _atlas: AtlasTexture
var _mode: int = Mode.IDLE
var _frame: int = 0
var _accum: float = 0.0
var _move_frames_left: int = 0
var _active: bool = false


func _ready() -> void:
	if not enabled:
		return
	var src := load(SHEET_PATH) as Texture2D
	if src == null:
		push_error("Wc3HumanCursor: 无法加载 %s" % SHEET_PATH)
		return
	# 转 ImageTexture，避免压缩贴图在系统光标上发糊
	var img: Image = src.get_image()
	if img == null:
		push_error("Wc3HumanCursor: get_image() 失败")
		return
	_sheet = ImageTexture.create_from_image(img)
	_atlas = AtlasTexture.new()
	_atlas.atlas = _sheet
	_atlas.filter_clip = true
	_active = true
	set_mode(Mode.IDLE)
	set_process(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not enabled:
		return
	# 阶段 A：右键闪移动箭头（阶段 D 改由命令层调用 flash_move）
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			flash_move()



func _exit_tree() -> void:
	_restore_system_cursor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN and _active:
		_apply_frame()


func get_mode() -> int:
	return _mode


func set_mode(mode: int) -> void:
	if not _active:
		return
	_mode = mode
	_frame = 0
	_accum = 0.0
	if mode == Mode.MOVE:
		_move_frames_left = maxi(move_flash_loops, 1) * _mode_frame_count(Mode.MOVE)
	else:
		_move_frames_left = 0
	_apply_frame()


## 右键下移动令时闪一下蓝色箭头，然后回到 IDLE。
func flash_move() -> void:
	set_mode(Mode.MOVE)


func _process(delta: float) -> void:
	if not _active or not enabled:
		return
	var n := _mode_frame_count(_mode)
	if n <= 1:
		return
	_accum += delta
	var step := 1.0 / maxf(fps, 1.0)
	while _accum >= step:
		_accum -= step
		_frame = (_frame + 1) % n
		if _mode == Mode.MOVE:
			_move_frames_left -= 1
			if _move_frames_left <= 0:
				set_mode(Mode.IDLE)
				return
		_apply_frame()


func _apply_frame() -> void:
	var cell := _mode_cell(_mode, _frame)
	_atlas.region = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
	var hotspot := _mode_hotspot(_mode)
	# 每次提交副本，避免部分平台缓存旧 region
	var frame_tex := _atlas.duplicate() as AtlasTexture
	Input.set_custom_mouse_cursor(frame_tex, Input.CURSOR_ARROW, hotspot)
	Input.set_custom_mouse_cursor(frame_tex, Input.CURSOR_POINTING_HAND, hotspot)
	Input.set_custom_mouse_cursor(frame_tex, Input.CURSOR_MOVE, hotspot)
	Input.set_custom_mouse_cursor(frame_tex, Input.CURSOR_CROSS, hotspot)


func _restore_system_cursor() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_MOVE)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_CROSS)


static func _mode_frame_count(mode: int) -> int:
	match mode:
		Mode.IDLE, Mode.TARGET:
			return 8
		Mode.MOVE:
			return 3
		_:
			return 1


static func _mode_cell(mode: int, frame: int) -> Vector2i:
	match mode:
		Mode.IDLE:
			return Vector2i(clampi(frame, 0, 7), 0)
		Mode.TARGET:
			return Vector2i(clampi(frame, 0, 7), 2)
		Mode.SELECT:
			return Vector2i(0, 3)
		Mode.ALLY:
			return Vector2i(1, 3)
		Mode.INVALID:
			return Vector2i(2, 3)
		Mode.HAND_ALT_A:
			return Vector2i(3, 3)
		Mode.HAND_ALT_B:
			return Vector2i(4, 3)
		Mode.MOVE:
			return Vector2i(5 + clampi(frame, 0, 2), 3)
		_:
			return Vector2i(0, 0)


static func _mode_hotspot(mode: int) -> Vector2:
	match mode:
		Mode.IDLE, Mode.SELECT:
			return Vector2(6, 4) ## 指尖
		Mode.HAND_ALT_A:
			return Vector2(15, 6)
		Mode.HAND_ALT_B:
			return Vector2(5, 5)
		Mode.TARGET, Mode.ALLY, Mode.INVALID:
			return Vector2(16, 16) ## 准心
		Mode.MOVE:
			return Vector2(3, 1) ## 箭头尖
		_:
			return Vector2(0, 0)
