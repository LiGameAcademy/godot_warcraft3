class_name Wc3GameCursor
extends Node

## 对战鼠标光标（按种族切换图集）。
## 四族 `*Cursor.png` 同为 32×32、8 列 × 4 行；第 0 行 IDLE 指向手。
## 用 Input.set_custom_mouse_cursor 逐帧切换，保证点击热区正确。

const CELL := 32
const COLS := 8
const CURSOR_DIR := "UI/Cursor"

## race_id（与 MeleeRacePreview / GameSession.local_race 对齐）→ 图集文件名
const RACE_SHEETS := {
	"human": "HumanCursor.png",
	"orc": "OrcCursor.png",
	"undead": "UndeadCursor.png",
	"nightelf": "NightElfCursor.png",
}

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
## 初始种族；开局后可由 GameDirector.set_race() 覆盖
@export var race: String = "human"
## true：本节点自己吃右键闪 MOVE（开发期）；正式应由命令层调 flash_move
@export var auto_flash_move_on_rmb: bool = false

var _sheet: Texture2D
var _atlas: AtlasTexture
## mode*100+frame → 预烘焙 ImageTexture（CPU），避免每帧 Atlas 走 GPU 读回
var _frame_cache: Dictionary = {}
var _cursor_broken: bool = false
var _mode: int = Mode.IDLE
var _frame: int = 0
var _accum: float = 0.0
var _move_frames_left: int = 0
var _active: bool = false
var _race_id: String = "human"
## true：MOVE 动画循环直至取消（行动面板瞄准），不自动回 IDLE
var _move_sticky: bool = false


func _ready() -> void:
	if not enabled:
		return
	set_race(race)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not enabled or not auto_flash_move_on_rmb:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			flash_move()


func _exit_tree() -> void:
	_restore_system_cursor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN and _active:
		_apply_frame()


func get_race() -> String:
	return _race_id


func get_mode() -> int:
	return _mode


## 按种族加载图集。未知种族回退 human。可重复调用。
func set_race(race_id: String) -> void:
	var key := _normalize_race(race_id)
	if _active and key == _race_id and _sheet != null:
		return
	_race_id = key
	race = key
	if not enabled:
		_active = false
		return
	if not _load_sheet(key):
		_active = false
		_restore_system_cursor()
		return
	_active = true
	set_process(true)
	set_mode(Mode.IDLE)


func set_mode(mode: int) -> void:
	if not _active:
		return
	_mode = mode
	_frame = 0
	_accum = 0.0
	if mode == Mode.MOVE:
		if _move_sticky:
			_move_frames_left = 0
		else:
			_move_frames_left = maxi(move_flash_loops, 1) * _mode_frame_count(Mode.MOVE)
	else:
		_move_sticky = false
		_move_frames_left = 0
	_apply_frame()


## 行动面板「移动」瞄准：箭头循环直到 cancel / 下发命令。
func set_move_targeting(active: bool) -> void:
	_move_sticky = active
	if active:
		set_mode(Mode.MOVE)
	else:
		set_mode(Mode.IDLE)


## 攻击 / 技能瞄准：白圈，直到 cancel。
func set_attack_targeting(active: bool) -> void:
	_move_sticky = false
	if active:
		set_mode(Mode.TARGET)
	else:
		set_mode(Mode.IDLE)


## 右键下移动令时闪一下蓝色箭头，然后回到 IDLE。
func flash_move() -> void:
	_move_sticky = false
	set_mode(Mode.MOVE)


func _process(delta: float) -> void:
	if not _active or not enabled or _cursor_broken:
		return
	var n := _mode_frame_count(_mode)
	if n <= 1:
		return
	_accum += delta
	var step := 1.0 / maxf(fps, 1.0)
	while _accum >= step:
		_accum -= step
		_frame = (_frame + 1) % n
		if _mode == Mode.MOVE and not _move_sticky:
			_move_frames_left -= 1
			if _move_frames_left <= 0:
				set_mode(Mode.IDLE)
				return
		_apply_frame()


func _load_sheet(race_id: String) -> bool:
	var path := sheet_path_for_race(race_id)
	if path.is_empty() or not RuntimeAssets.file_exists(path):
		push_error("Wc3GameCursor: 缺少光标图集 %s（race=%s）" % [path, race_id])
		return false
	# asset-converted 有 .gdignore，不能 ResourceLoader.load；走磁盘 ImageTexture
	var src := RuntimeAssets.load_converted_texture(
		"%s/%s" % [CURSOR_DIR, str(RACE_SHEETS.get(_normalize_race(race_id), RACE_SHEETS["human"]))]
	)
	if src == null:
		push_error("Wc3GameCursor: 无法加载 %s" % path)
		return false
	# 转 ImageTexture，避免压缩贴图在系统光标上发糊
	var img: Image = src.get_image()
	if img == null:
		push_error("Wc3GameCursor: get_image() 失败 %s" % path)
		return false
	_sheet = ImageTexture.create_from_image(img)
	if _atlas == null:
		_atlas = AtlasTexture.new()
		_atlas.filter_clip = true
	_atlas.atlas = _sheet
	_cursor_broken = false
	_prebake_frames(img)
	return true


static func sheet_path_for_race(race_id: String) -> String:
	var key := _normalize_race(race_id)
	var file := str(RACE_SHEETS.get(key, RACE_SHEETS["human"]))
	return RuntimeAssets.converted_path("%s/%s" % [CURSOR_DIR, file])


static func _normalize_race(race_id: String) -> String:
	var key := race_id.strip_edges().to_lower()
	match key:
		"human", "h", "人族":
			return "human"
		"orc", "o", "兽族":
			return "orc"
		"undead", "u", "ud", "不死":
			return "undead"
		"nightelf", "night_elf", "ne", "e", "暗夜", "精灵":
			return "nightelf"
		_:
			return "human"


func _prebake_frames(sheet_img: Image) -> void:
	_frame_cache.clear()
	if sheet_img == null:
		return
	for mode in [
		Mode.IDLE, Mode.TARGET, Mode.ALLY, Mode.INVALID, Mode.SELECT,
		Mode.HAND_ALT_A, Mode.HAND_ALT_B, Mode.MOVE,
	]:
		var n := _mode_frame_count(mode)
		for f in range(maxi(n, 1)):
			var cell := _mode_cell(mode, f)
			var region := Rect2i(cell.x * CELL, cell.y * CELL, CELL, CELL)
			if region.position.x + CELL > sheet_img.get_width() or region.position.y + CELL > sheet_img.get_height():
				continue
			var sub := sheet_img.get_region(region)
			if sub == null or sub.is_empty():
				continue
			_frame_cache[_frame_key(mode, f)] = ImageTexture.create_from_image(sub)


func _frame_key(mode: int, frame: int) -> int:
	return mode * 100 + frame


func _apply_frame() -> void:
	if _cursor_broken or not _active:
		return
	var tex: Texture2D = _frame_cache.get(_frame_key(_mode, _frame)) as Texture2D
	if tex == null and _atlas != null:
		# 回退：旧路径（可能触发 GPU 读回）
		var cell := _mode_cell(_mode, _frame)
		_atlas.region = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
		tex = _atlas.duplicate() as AtlasTexture
	if tex == null:
		_fail_cursor("无可用光标帧")
		return
	var hotspot := _mode_hotspot(_mode)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, hotspot)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_POINTING_HAND, hotspot)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_MOVE, hotspot)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_CROSS, hotspot)


func _fail_cursor(reason: String) -> void:
	if _cursor_broken:
		return
	_cursor_broken = true
	push_warning("Wc3GameCursor: 停用自定义光标（%s）" % reason)
	_restore_system_cursor()
	set_process(false)


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
