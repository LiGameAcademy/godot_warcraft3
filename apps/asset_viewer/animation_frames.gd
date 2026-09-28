extends HBoxContainer
## Frame positions are preview samples, not source keyframe indices.
signal time_requested(seconds: float)
signal pause_requested

@export_range(1, 120) var preview_fps: int = 30
@onready var current: SpinBox = %CurrentFrame
@onready var maximum: Label = %MaximumFrame
@onready var rate: Label = %FrameRate
var _player: AnimationPlayer
var _length: float = 0.0

func _ready() -> void:
	current.value_changed.connect(_request_frame)
	current.get_line_edit().focus_entered.connect(func() -> void: pause_requested.emit())
	rate.text = "帧（%d FPS）" % preview_fps
	bind_animation(null)

func bind_animation(player: AnimationPlayer) -> void:
	_player = player
	_length = 0.0
	if is_instance_valid(player) and player.has_animation(player.assigned_animation):
		_length = player.get_animation(player.assigned_animation).length
	current.editable = _length > 0.0
	current.set_value_no_signal(0.0)
	current.max_value = ceilf(_length * preview_fps)
	maximum.text = "/ %d" % int(current.max_value)
	set_process(current.editable)
	_sync_position()

func _process(_delta: float) -> void:
	if not current.get_line_edit().has_focus():
		_sync_position()

func _sync_position() -> void:
	if not is_instance_valid(_player) or _length <= 0.0:
		return
	var seconds: float = _player.current_animation_position
	var frame: int = int(current.max_value) if seconds >= _length else floori(seconds * preview_fps + 0.00001)
	current.set_value_no_signal(clampi(frame, 0, int(current.max_value)))

func _request_frame(value: float) -> void:
	if not is_instance_valid(_player) or _length <= 0.0:
		return
	pause_requested.emit()
	time_requested.emit(minf(value / preview_fps, _length))
